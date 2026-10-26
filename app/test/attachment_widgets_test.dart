import 'preview_test_support.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/preview/preview_app.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_platform.dart';
import 'package:linefold/src/widgets/document_attachment_scope.dart';
import 'package:linefold/src/widgets/editor_shell.dart';

import 'attachment_test_support.dart';
import 'support/fakes.dart';

Future<void> settleImage(WidgetTester tester, {bool Function()? until}) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (until?.call() ?? find.byType(RawImage).evaluate().isNotEmpty) return;
  }
}

void main() {
  for (final mode in [
    IanvsMarkdownEditorMode.preview,
    IanvsMarkdownEditorMode.livePreview,
  ]) {
    testWidgets('$mode preserves viewport across delayed attachment completion', (
      tester,
    ) async {
      final gate = Completer<void>();
      final attachments = FakeAttachmentSource()..beforeRead = gate.future;
      final text =
          '# Attachment QA\n\n![Alt](assets/image.png)\n\n${List.generate(80, (i) => 'Paragraph $i identifies a stable reading position.').join('\n\n')}';
      final controller = IanvsMarkdownController(text: text, mode: mode);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentAttachmentScope(
              root: '/vault',
              documentPath: '/vault/note.md',
              source: attachments,
              builder: (_, images) => IanvsMarkdownLiveEditor(
                controller: controller,
                scrollController: scroll,
                preserveViewport: true,
                showToolbar: false,
                showNavigationPane: false,
                imageBuilder: images.image,
                wikiEmbedBuilder: images.wiki,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      scroll.jumpTo(180);
      await tester.pumpAndSettle();
      final anchor = controller.viewportAnchor.value!;
      final imageStillMounted = find
          .byType(DocumentAttachmentImage)
          .evaluate()
          .isNotEmpty;
      expect(imageStillMounted, mode == IanvsMarkdownEditorMode.preview);
      final paragraph = text.substring(anchor.sourceOffset).split('\n').first;
      expect(paragraph, startsWith('Paragraph '));
      final target = find.text(paragraph, findRichText: true);
      final top = tester.getTopLeft(target).dy;
      final oldScroll = scroll.offset;
      final value = controller.value;
      gate.complete();
      if (!imageStillMounted) {
        // Live removes the offscreen image. A late read must not move the reader.
        await settleImage(tester, until: () => false);
        expect(tester.getTopLeft(target).dy, closeTo(top, 1));
        expect(controller.value, value);
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
      }
      var decoded = false;
      await settleImage(
        tester,
        until: () => decoded = tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      await tester.pumpAndSettle();
      // Live may unmount the now smaller image once it is above the viewport.
      expect(decoded, isTrue);
      if (imageStillMounted) {
        expect((scroll.offset - oldScroll).abs(), greaterThan(1));
        expect(tester.getTopLeft(target).dy, closeTo(top, 1));
        expect(
          controller.viewportAnchor.value!.sourceOffset,
          anchor.sourceOffset,
        );
      }
      expect(controller.value, value);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'both Markdown and block Wiki embeds load through shared builders with dimensions',
    (tester) async {
      final source = FakeAttachmentSource();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentAttachmentScope(
              root: '/vault',
              documentPath: '/vault/note.md',
              source: source,
              builder: (_, images) => IanvsMarkdownView(
                data: '![Alt](assets/image.png)\n\n![[image.png|100x145]]',
                imageBuilder: images.image,
                wikiEmbedBuilder: images.wiki,
              ),
            ),
          ),
        ),
      );
      await settleImage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(DocumentAttachmentImage), findsNWidgets(2));
      expect(find.byType(RawImage), findsNWidgets(2));
      final sized = tester.widget<IanvsMarkdownSizedImage>(
        find.byType(IanvsMarkdownSizedImage),
      );
      expect(sized.dimensions.width, 100);
      expect(sized.dimensions.height, 145);
      expect(source.reads.where((p) => p.endsWith('.png')).length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'same Markdown source switching vault uses new scope, never captured old builders',
    (tester) async {
      final source = FakeAttachmentSource();
      Widget app(String root) => MaterialApp(
        home: Scaffold(
          body: DocumentAttachmentScope(
            root: root,
            documentPath: '$root/note.md',
            source: source,
            builder: (_, images) => IanvsMarkdownView(
              data: '![[image.png]]',
              imageBuilder: images.image,
              wikiEmbedBuilder: images.wiki,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app('/first'));
      await settleImage(tester);
      expect(find.byType(RawImage), findsOneWidget);
      await tester.pumpWidget(app('/second'));
      await settleImage(tester);
      expect(source.roots, ['/first', '/second']);
      expect(source.reads.where((p) => p.endsWith('.png')).length, 2);
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pending old document is discarded on tab/path change', (
    tester,
  ) async {
    final source = FakeAttachmentSource()..files['other.png'] = tinyPng;
    final gate = Completer<void>();
    source.beforeRead = gate.future;
    Widget app(String note, String image) => MaterialApp(
      home: Scaffold(
        body: DocumentAttachmentScope(
          root: '/vault',
          documentPath: '/vault/$note',
          source: source,
          builder: (_, images) => IanvsMarkdownView(
            data: '![[$image]]',
            wikiEmbedBuilder: images.wiki,
          ),
        ),
      ),
    );
    await tester.pumpWidget(app('first.md', 'image.png'));
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    source.beforeRead = null;
    await tester.pumpWidget(app('second.md', 'other.png'));
    gate.complete();
    await settleImage(tester);
    expect(
      tester
          .widget<DocumentAttachmentImage>(find.byType(DocumentAttachmentImage))
          .target,
      'other.png',
    );
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'external replacement refreshes metadata and malformed/missing images recover',
    (tester) async {
      final source = FakeAttachmentSource();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentAttachmentScope(
              root: '/vault',
              documentPath: '/vault/note.md',
              source: source,
              builder: (_, images) => IanvsMarkdownView(
                data: '![[image.png]]',
                wikiEmbedBuilder: images.wiki,
              ),
            ),
          ),
        ),
      );
      await settleImage(tester);
      final first = tester.widget<RawImage>(find.byType(RawImage)).image;
      source.revision++;
      await tester.pump(const Duration(seconds: 5));
      await settleImage(
        tester,
        until: () =>
            tester.widget<RawImage>(find.byType(RawImage)).image != first,
      );
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        isNot(same(first)),
      );
      source.files.clear();
      source.revision++;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('Image not found in the current folder.'),
        findsOneWidget,
      );
      expect(find.byType(RawImage), findsNothing);
      source.files['assets/image.png'] = tinyPng;
      await tester.tap(find.text('Retry'));
      await settleImage(tester);
      expect(find.byType(RawImage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'inline Wiki syntax remains explicitly outside this block-embed phase',
    (tester) async {
      final source = FakeAttachmentSource();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentAttachmentScope(
              root: '/vault',
              documentPath: '/vault/note.md',
              source: source,
              builder: (_, images) => IanvsMarkdownView(
                data: 'Before ![[image.png]] after',
                wikiEmbedBuilder: images.wiki,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DocumentAttachmentImage), findsNothing);
      expect(source.reads, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'desktop editor wires both builders and switching modes never dirties original source',
    (tester) async {
      const text =
          '# 原文\r\n\r\n![图](assets/image.png)\r\n\r\n![[image.png|250]]\r\n';
      final files = MemoryMarkdownFileService()
        ..selectedFolder = '/vault'
        ..files['/vault/note.md'] = text;
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      final source = FakeAttachmentSource();
      addTearDown(files.dispose);
      addTearDown(workspace.dispose);
      await workspace.initialize();
      await workspace.chooseWorkspaceFolder();
      await workspace.openPath('/vault/note.md');
      workspace.toggleSidebar();
      workspace.toggleOutline();
      workspace.setMode(IanvsMarkdownEditorMode.preview);
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(Brightness.light),
          home: EditorShell(
            workspace: workspace,
            dark: false,
            onToggleTheme: () {},
            enableFileDrop: false,
            attachmentSource: source,
          ),
        ),
      );
      await settleImage(tester);
      expect(find.byType(DocumentAttachmentImage), findsNWidgets(2));
      expect(find.byType(RawImage), findsNWidgets(2));
      for (final mode in [
        IanvsMarkdownEditorMode.source,
        IanvsMarkdownEditorMode.livePreview,
        IanvsMarkdownEditorMode.preview,
      ]) {
        workspace.setMode(mode);
        await tester.pumpAndSettle();
        expect(workspace.activeDocument!.controller.text, text);
        expect(workspace.activeDocument!.controller.isDirty, isFalse);
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(files.files['/vault/note.md'], text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'iOS preview wires both builders, single imported note never searches original parent',
    (tester) async {
      for (final hasVault in [true, false]) {
        final library = _ImageLibrary(hasVault);
        final controller = PreviewController(library: library);
        final source = FakeAttachmentSource();
        await tester.pumpWidget(
          LinefoldPreviewApp(
            readingPositions: memoryPreviewReadingPositions(),
            controller: controller,
            platform: _Platform(),
            attachmentSource: source,
          ),
        );
        await tester.pumpAndSettle();
        await controller.open('/vault/note.md');
        await tester.pump();
        if (hasVault) {
          await settleImage(tester);
          expect(find.byType(RawImage), findsNWidgets(2));
          expect(source.roots, ['/vault']);
        } else {
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Importing a single note'),
            findsNWidgets(2),
          );
          expect(source.listCalls, 0);
          expect(source.reads, isEmpty);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}

class _ImageLibrary extends PreviewLibrary {
  _ImageLibrary(this.hasVault);
  final bool hasVault;
  @override
  Future<void> useDefaultWorkspace() async {
    workspace = hasVault
        ? const PreviewWorkspace(
            path: '/vault',
            name: 'Fixture',
            isCloud: false,
          )
        : null;
  }

  @override
  Future<List<PreviewDocument>> list() async => [];
  @override
  Future<String> read(String path) async =>
      '![image](assets/image.png)\n\n![[image.png|250]]';
}

class _Platform extends PreviewPlatform {
  @override
  Future<void> start(
    PreviewDelivery onFiles,
    void Function(String) onError,
  ) async {}
  @override
  void dispose() {}
}
