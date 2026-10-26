import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/document_link_service.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'cross document return preserves dirty tabs and orders local jumps',
    (tester) async {
      final files = MemoryMarkdownFileService()
        ..files.addAll({
          '/notes/a.md': '# A\n\noriginal',
          '/notes/b.md': '# B\n\n## Target\n\nBody',
          '/notes/c.md': '# C',
        });
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      final a = (await workspace.openPath('/notes/a.md'))!;
      a.controller.text = '# A\n\nunsaved';
      a.controller.selection = const TextSelection(
        baseOffset: 5,
        extentOffset: 8,
      );
      a.controller.rememberViewport(
        IanvsMarkdownViewportAnchor(
          source: a.controller.text,
          sourceOffset: 5,
          viewportOffset: -12,
        ),
      );
      final links = DocumentLinkService(
        workspace: workspace,
        openImage: (_) async {},
      );
      await links.open(a, 'b.md#target');
      await tester.pump();
      final b = workspace.activeDocument!;
      expect(workspace.canNavigateBack, isTrue);
      b.controller.rememberViewport(
        IanvsMarkdownViewportAnchor(
          source: b.controller.text,
          sourceOffset: 5,
          viewportOffset: 4,
        ),
      );
      b.controller.revealHeading(0);
      expect(workspace.navigateBack(), isTrue);
      expect(workspace.activeDocument, same(b));
      await links.open(b, 'c.md');
      await tester.pump();
      expect(workspace.activeDocument!.path, '/notes/c.md');
      expect(workspace.navigateBack(), isTrue);
      expect(workspace.activeDocument, same(b));
      expect(workspace.navigateBack(), isTrue);
      expect(workspace.activeDocument, same(a));
      expect(a.controller.text, '# A\n\nunsaved');
      expect(a.controller.isDirty, isTrue);
      expect(
        a.controller.selection,
        const TextSelection(baseOffset: 5, extentOffset: 8),
      );
      expect(a.controller.sourceNavigation.value!.viewportOffset, -12);
      expect(files.files['/notes/a.md'], '# A\n\noriginal');
      await links.open(a, 'c.md');
      await tester.pump();
      workspace.removeDocument(a);
      expect(workspace.canNavigateBack, isFalse);
      expect(workspace.navigateBack(), isFalse);
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'footnote fragments reveal definitions and references with return history',
    (tester) async {
      final source =
          'Intro[^中文]\n\n${List.generate(80, (i) => 'Paragraph $i\n\n').join()}[^中文]: FOOTNOTE TARGET';
      final files = MemoryMarkdownFileService()
        ..files['/notes/doc.md'] = source;
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      final document = (await workspace.openPath('/notes/doc.md'))!;
      document.controller.mode = IanvsMarkdownEditorMode.preview;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: document.controller,
              scrollController: scroll,
              preserveViewport: true,
              showToolbar: false,
              showNavigationPane: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final links = DocumentLinkService(
        workspace: workspace,
        openImage: (_) async {},
      );
      await links.open(document, '#fn-${Uri.encodeComponent('中文')}');
      await tester.pumpAndSettle();
      expect(
        find
            .textContaining('FOOTNOTE TARGET', findRichText: true)
            .hitTestable(),
        findsOneWidget,
      );
      expect(scroll.offset, greaterThan(1000));
      expect(document.controller.navigateBack(), isTrue);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(0, 1));
      await links.open(document, '#fn-${Uri.encodeComponent('中文')}');
      await tester.pumpAndSettle();
      await links.open(document, '#fnref-${Uri.encodeComponent('中文')}');
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(0, 1));
      expect(document.controller.canUndo, isFalse);
      expect(document.controller.isDirty, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'inline footnote fragments reveal generated footer and return to marker',
    (tester) async {
      final source =
          'Intro^[FOOTNOTE TARGET]\n\n${List.generate(80, (i) => 'Paragraph $i\n\n').join()}';
      final files = MemoryMarkdownFileService()
        ..files['/notes/doc.md'] = source;
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      final document = (await workspace.openPath('/notes/doc.md'))!;
      document.controller.mode = IanvsMarkdownEditorMode.preview;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: document.controller,
              scrollController: scroll,
              preserveViewport: true,
              showToolbar: false,
              showNavigationPane: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final links = DocumentLinkService(
        workspace: workspace,
        openImage: (_) async {},
      );
      await links.open(document, '#fn-ianvs-inline-footnote-1');
      await tester.pumpAndSettle();
      expect(
        find
            .textContaining('FOOTNOTE TARGET', findRichText: true)
            .hitTestable(),
        findsOneWidget,
      );
      expect(scroll.offset, greaterThan(1000));
      expect(document.controller.navigateBack(), isTrue);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(0, 1));
      await links.open(document, '#fn-ianvs-inline-footnote-1');
      await tester.pumpAndSettle();
      await links.open(document, '#fnref-ianvs-inline-footnote-1');
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(0, 1));
      expect(document.controller.canUndo, isFalse);
      expect(document.controller.isDirty, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('SVG external-view action dispatches the local file URL', (
    tester,
  ) async {
    const channel = MethodChannel('work.ianvs.linefold/file_access');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await DocumentLinkService.openExternalUri(Uri.file('/series/图 1.svg'));
    expect(calls.single.method, 'openExternal');
    expect(calls.single.arguments, {
      'url': Uri.file('/series/图 1.svg').toString(),
    });
  });

  testWidgets('reading follows chapter links and preserves open dirty tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.menu,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.menu,
        null,
      ),
    );
    final files = MemoryMarkdownFileService()
      ..files.addAll({
        '/series/INDEX.md': '[Chapter](articles/chapter%20one.md)',
        '/series/articles/chapter one.md': '# Chapter one\n\nBody',
      });
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    addTearDown(() async {
      workspace.dispose();
      await files.dispose();
    });
    await workspace.initialize();
    final index = (await workspace.openPath('/series/INDEX.md'))!;
    index.controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter'));
    await tester.pumpAndSettle();
    final chapter = workspace.activeDocument!;
    expect(chapter.path, '/series/articles/chapter one.md');
    expect(chapter.controller.mode, IanvsMarkdownEditorMode.preview);
    expect(find.text('Body'), findsOneWidget);
    chapter.controller.text += '\n\nUnsaved edit';
    chapter.controller.mode = IanvsMarkdownEditorMode.source;
    final links = DocumentLinkService(
      workspace: workspace,
      openImage: (_) async {},
    );
    await links.open(index, 'articles/chapter%20one.md');
    expect(workspace.activeDocument, same(chapter));
    expect(chapter.controller.text, contains('Unsaved edit'));
    expect(chapter.controller.mode, IanvsMarkdownEditorMode.source);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    'resolves local images, sources, external links and heading fragments',
    (tester) async {
      final files = MemoryMarkdownFileService()
        ..files.addAll({
          '/series/articles/04.md': '# 标题\n\n## More detail\n\nEnd',
          '/series/assets/mermaid/04.mmd': 'flowchart LR\nA-->B',
        });
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(() async {
        workspace.dispose();
        await files.dispose();
      });
      await workspace.initialize();
      final origin = (await workspace.openPath('/series/articles/04.md'))!;
      final images = <String>[];
      final external = <Uri>[];
      final links = DocumentLinkService(
        workspace: workspace,
        openImage: (path) async => images.add(path),
        openExternal: (uri) async => external.add(uri),
      );
      await links.open(origin, '../assets/png/04.png');
      await links.open(origin, '../assets/svg/04.svg');
      expect(images, [
        '/series/assets/png/04.png',
        '/series/assets/svg/04.svg',
      ]);
      await links.open(origin, 'https://example.com/paper#section');
      await links.open(origin, '../preview/INDEX.html');
      expect(external.map((uri) => uri.scheme), ['https', 'file']);
      await links.open(origin, '#more-detail');
      await tester.pump();
      expect(
        origin.controller.headingNavigation.value!.sourceOffset,
        origin.controller.text.indexOf('## More detail'),
      );
      await links.open(origin, '../assets/mermaid/04.mmd');
      expect(
        workspace.activeDocument!.controller.text,
        startsWith('flowchart LR'),
      );
      await expectLater(
        links.open(origin, 'javascript:alert(1)'),
        throwsFormatException,
      );
      await expectLater(
        links.open(origin, '../run.command'),
        throwsFormatException,
      );
      expect(external, hasLength(2));
      await tester.pump(const Duration(milliseconds: 400));
    },
  );
}
