import 'dart:async';

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
  Object? failure;
  Future<void>? beforeOutput;
  @override
  Future<bool> output({
    required DocumentExportAction action,
    required ExportedDocument document,
    required DocumentExportSnapshot snapshot,
  }) async {
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

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              flow.run(
                context,
                workspace,
                DocumentExportAction.html,
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
      expect(platform.outputs.single.html, contains('Dirty snapshot 中文'));
      expect(
        platform.snapshots.single.protectedPaths,
        contains('/vault/Origin.md'),
      );
      expect(platform.outputs.single.html, isNot(contains('Later edits')));
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
