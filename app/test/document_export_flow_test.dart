import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/document_export_service.dart';
import 'package:linefold/src/widgets/document_export_dialog.dart';

import 'attachment_test_support.dart';
import 'wiki_note_navigation_test.dart' show WikiFiles, wikiWorkspace;

class FakeExportPlatform implements DocumentExportPlatform {
  final snapshots = <DocumentExportSnapshot>[];
  final outputs = <ExportedDocument>[];
  final actions = <DocumentExportAction>[];
  int cancellations = 0;
  bool Function()? approval;
  @override
  Future<void> cancel(DocumentExportSnapshot snapshot) async {
    cancellations++;
  }

  Object? failure;
  Future<void>? beforeOutput;
  @override
  Future<bool> output({
    required DocumentExportAction action,
    required ExportedDocument document,
    required DocumentExportSnapshot snapshot,
    required bool Function() isCurrent,
  }) async {
    approval = isCurrent;
    actions.add(action);
    snapshots.add(snapshot);
    outputs.add(document);
    await beforeOutput;
    if (failure != null) throw failure!;
    return false;
  }
}

void main() {
  late WikiFiles files;
  late WorkspaceController workspace;
  late FakeExportPlatform platform;
  late FakeAttachmentSource attachments;
  late DocumentExportFlow flow;

  setUp(() async {
    files = WikiFiles()..files['/vault/Origin.md'] = '# Saved';
    workspace = await wikiWorkspace(files);
    platform = FakeExportPlatform();
    attachments = FakeAttachmentSource();
    flow = DocumentExportFlow();
  });
  tearDown(() async {
    flow.dispose();
    workspace.dispose();
    await files.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    DocumentExportAction action = DocumentExportAction.html,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              flow.run(
                context,
                workspace,
                action,
                attachmentSource: attachments,
                platform: platform,
              ),
            ),
            child: const Text('Export'),
          ),
        ),
      ),
    ),
  );
  Future<void> begin(WidgetTester tester) async {
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Basic offline export'), findsOneWidget);
  }

  testWidgets('ZIP exports the command-time unsaved snapshot and image bytes', (
    tester,
  ) async {
    workspace.activeDocument!.controller.text =
        '# Unsaved\n![x](assets/image.png)';
    await mount(tester, action: DocumentExportAction.bundle);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Creates a ZIP'), findsOneWidget);
    workspace.activeDocument!.controller.text = '# Later';
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(platform.actions, [DocumentExportAction.bundle]);
    final zip = ZipDecoder().decodeBytes(
      platform.outputs.single.bytes!,
      verify: true,
    );
    expect(
      utf8.decode(zip.findFile('document.md')!.content),
      '# Unsaved\n![x](./assets/1.png)',
    );
    expect(zip.findFile('assets/1.png')!.content, tinyPng);
    expect(workspace.activeDocument!.controller.text, '# Later');
    await tester.pump(const Duration(seconds: 1));
    expect(files.files['/vault/Origin.md'], '# Saved');
  });

  for (final continuePartial in [false, true]) {
    testWidgets('ZIP missing resource disclosure: continue=$continuePartial', (
      tester,
    ) async {
      workspace.activeDocument!.controller.text = '![x](missing.png)';
      await mount(tester, action: DocumentExportAction.bundle);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Some resources were not included'), findsOneWidget);
      expect(platform.outputs, isEmpty);
      await tester.tap(
        find.text(continuePartial ? 'Export available resources' : 'Cancel'),
      );
      await tester.pumpAndSettle();
      expect(platform.outputs.length, continuePartial ? 1 : 0);
    });
  }

  testWidgets(
    'Markdown copy snapshot is verbatim, visible attachment caveat and no image I/O',
    (tester) async {
      const dirty = '# 中文😀\r\n![image](assets/image.png)\r\n';
      workspace.activeDocument!.controller.text = dirty;
      final captured = workspace.activeDocument!.controller.text;
      await mount(tester, action: DocumentExportAction.markdown);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Attachments are not copied.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('may not resolve in the destination folder'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Cancelling the Save dialog writes nothing.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'the copy may be committed even if you switch tabs.',
        ),
        findsOneWidget,
      );
      workspace.activeDocument!.controller.text = '# Later edit';
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(platform.outputs.single.content, captured);
      expect(attachments.reads, isEmpty);
      expect(files.files['/vault/Origin.md'], '# Saved');
      expect(workspace.activeDocument!.controller.text, '# Later edit');
      expect(workspace.activeDocument!.controller.isDirty, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(files.files['/vault/Origin.md'], '# Saved');
    },
  );

  testWidgets(
    'PDF discloses practical fidelity and exports the dirty snapshot without saving',
    (tester) async {
      final document = workspace.activeDocument!;
      document.controller.text = '# PDF snapshot 中文😀';
      await mount(tester, action: DocumentExportAction.pdf);
      await begin(tester);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.textContaining('not a pixel-perfect copy'), findsOneWidget);
      expect(
        find.textContaining(
          'Copy/search text and reading order vary by PDF viewer',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('row taller than a page'), findsOneWidget);
      expect(
        find.textContaining('PDF preparation is still cancelled'),
        findsOneWidget,
      );
      document.controller.text = '# Later PDF edits';
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(platform.actions, [DocumentExportAction.pdf]);
      expect(platform.outputs.single.content, contains('PDF snapshot 中文😀'));
      expect(
        platform.outputs.single.content,
        contains('not a pixel-perfect copy'),
      );
      expect(
        platform.outputs.single.content,
        isNot(contains('Later PDF edits')),
      );
      expect(document.controller.text, '# Later PDF edits');
      expect(document.controller.isDirty, isTrue);
      expect(files.files['/vault/Origin.md'], '# Saved');
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'cancel PDF before confirmation performs no output or asset I/O',
    (tester) async {
      workspace.activeDocument!.controller.text =
          '![private](assets/image.png)';
      await mount(tester, action: DocumentExportAction.pdf);
      await begin(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(platform.outputs, isEmpty);
      expect(attachments.reads, isEmpty);
      expect(files.files['/vault/Origin.md'], '# Saved');
      expect(workspace.activeDocument!.controller.isDirty, isTrue);
    },
  );

  testWidgets('cancel Markdown copy performs no output or attachment I/O', (
    tester,
  ) async {
    workspace.activeDocument!.controller.text = '![image](assets/image.png)';
    await mount(tester, action: DocumentExportAction.markdown);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(platform.outputs, isEmpty);
    expect(attachments.reads, isEmpty);
    expect(files.files['/vault/Origin.md'], '# Saved');
    expect(workspace.activeDocument!.controller.isDirty, isTrue);
  });

  testWidgets(
    'cancel never reads images, invokes native output or saves source',
    (tester) async {
      workspace.activeDocument!.controller.text =
          '![private](assets/image.png)';
      await mount(tester);
      await begin(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(platform.outputs, isEmpty);
      expect(attachments.reads, isEmpty);
      expect(files.files['/vault/Origin.md'], '# Saved');
      expect(workspace.activeDocument!.controller.isDirty, isTrue);
    },
  );

  testWidgets(
    'exports command-time dirty buffer, later edits never mix into snapshot',
    (tester) async {
      final document = workspace.activeDocument!;
      document.controller.text = '# Dirty snapshot 中文';
      await mount(tester);
      await begin(tester);
      document.controller.text = '# Later edits';
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(platform.outputs, hasLength(1));
      expect(platform.outputs.single.content, contains('Dirty snapshot 中文'));
      expect(
        platform.snapshots.single.protectedPaths,
        contains('/vault/Origin.md'),
      );
      expect(platform.outputs.single.content, isNot(contains('Later edits')));
      expect(document.controller.text, '# Later edits');
      expect(document.persistedText, '# Saved');
      expect(files.files['/vault/Origin.md'], '# Saved');
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'switching away and back while confirmation is open invalidates export',
    (tester) async {
      final original = workspace.activeDocument!;
      await mount(tester);
      await begin(tester);
      workspace.newDocument();
      workspace.selectDocument(workspace.documents.indexOf(original));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(platform.outputs, isEmpty);
    },
  );

  testWidgets(
    'tab change during image read stops before native destination UI',
    (tester) async {
      final blocked = Completer<void>();
      attachments.beforeRead = blocked.future;
      workspace.activeDocument!.controller.text =
          '![private](assets/image.png)';
      await mount(tester);
      await begin(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      workspace.newDocument();
      await tester.runAsync(() async {
        blocked.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(platform.outputs, isEmpty);
      expect(find.text('Export was not completed'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    },
  );

  for (final action in [
    DocumentExportAction.markdown,
    DocumentExportAction.pdf,
    DocumentExportAction.bundle,
  ]) {
    testWidgets(
      'new opened dirty source during native ${action.name} preparation invalidates final approval',
      (tester) async {
        files.files['/vault/Other.md'] = '# Other persisted';
        final original = workspace.activeDocument!;
        final pending = Completer<void>();
        platform.beforeOutput = pending.future;
        await mount(tester, action: action);
        await tester.tap(find.text('Export'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(platform.approval!(), isTrue);
        final other = await workspace.openPath('/vault/Other.md');
        other!.controller.text = '# Other dirty';
        workspace.selectDocument(workspace.documents.indexOf(original));
        expect(platform.approval!(), isFalse);
        expect(platform.cancellations, 1);
        expect(
          platform.snapshots.single.protectedPaths,
          isNot(contains('/vault/Other.md')),
        );
        pending.complete();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(other.controller.text, '# Other dirty');
        expect(other.controller.isDirty, isTrue);
        expect(files.files['/vault/Other.md'], '# Other persisted');
        expect(files.files['/vault/Origin.md'], '# Saved');
      },
    );
  }

  for (final action in [DocumentExportAction.html, DocumentExportAction.pdf]) {
    for (final dispose in [false, true]) {
      testWidgets(
        'native pending ${action.name} loses final approval on ${dispose ? 'dispose' : 'tab change'}',
        (tester) async {
          final pending = Completer<void>();
          platform.beforeOutput = pending.future;
          await mount(tester, action: action);
          await begin(tester);
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          expect(platform.approval!(), isTrue);
          if (dispose) {
            flow.dispose();
          } else {
            final original = workspace.activeDocument!;
            workspace.newDocument();
            workspace.selectDocument(workspace.documents.indexOf(original));
          }
          expect(platform.approval!(), isFalse);
          expect(platform.cancellations, 1);
          pending.complete();
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 1));
          expect(files.files['/vault/Origin.md'], '# Saved');
        },
      );
    }
  }

  testWidgets('native permission failure leaves source dirty and retryable', (
    tester,
  ) async {
    platform.failure = const DocumentExportFailure('Output permission denied.');
    workspace.activeDocument!.controller.text = '# Dirty';
    await mount(tester);
    await begin(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Output permission denied.'), findsOneWidget);
    expect(files.files['/vault/Origin.md'], '# Saved');
    expect(workspace.activeDocument!.controller.isDirty, isTrue);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    platform.failure = null;
    await begin(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(platform.outputs, hasLength(2));
  });
}
