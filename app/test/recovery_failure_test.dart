import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/workspace_session_store.dart';
import 'package:linefold/src/widgets/editor_shell.dart';

import 'support/fakes.dart';

class _FailingStore extends MemoryWorkspaceSessionStore {
  bool failLoad = false;
  bool failSave = false;
  int writes = 0;

  @override
  Future<WorkspaceSnapshot?> load() async {
    if (failLoad) throw const FormatException('Corrupt recovery file');
    return super.load();
  }

  @override
  Future<void> save(WorkspaceSnapshot snapshot) async {
    writes++;
    if (failSave) throw StateError('Disk full');
    return super.save(snapshot);
  }
}

void main() {
  late MemoryMarkdownFileService files;
  late _FailingStore store;
  late WorkspaceController workspace;

  setUp(() {
    files = MemoryMarkdownFileService();
    store = _FailingStore();
    workspace = WorkspaceController(fileService: files, sessionStore: store);
  });
  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });

  testWidgets('load failure cannot persist Welcome over the failed session', (
    tester,
  ) async {
    store.failLoad = true;
    await workspace.initialize();
    expect(workspace.initialized, isFalse);
    expect(workspace.documents, isEmpty);
    expect(workspace.recoveryError, contains('not been replaced'));
    await tester.pump(const Duration(seconds: 1));
    await workspace.flushSession();
    expect(store.writes, 0);

    store.failLoad = false;
    await workspace.retryRecovery();
    expect(workspace.initialized, isTrue);
    expect(workspace.recoveryError, isNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.writes, 1);
  });

  testWidgets(
    'background save failure is visible and retry includes latest edits',
    (tester) async {
      await workspace.initialize();
      store.failSave = true;
      final draft = workspace.newDocument();
      draft.controller.text = 'First unsaved draft';
      await tester.pump(const Duration(milliseconds: 400));
      expect(workspace.recoveryError, contains('Disk full'));
      expect(store.snapshot, isNull);
      draft.controller.text = 'Latest draft 中文😀\r\n';
      store.failSave = false;
      await workspace.retryRecovery();
      expect(workspace.recoveryError, isNull);
      expect(store.snapshot!.documents.last['text'], 'Latest draft 中文😀\r\n');
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'recovery screen offers working Retry instead of an endless spinner',
    (tester) async {
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
      store.failLoad = true;
      await workspace.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShell(
            workspace: workspace,
            dark: false,
            onToggleTheme: () {},
            enableFileDrop: false,
          ),
        ),
      );
      expect(find.text('Recovery needs attention'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      store.failLoad = false;
      await tester.tap(find.text('Retry recovery'));
      await tester.pumpAndSettle();
      expect(workspace.initialized, isTrue);
      expect(find.text('Recovery needs attention'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  test('successful backup recovery retains a visible notice', () async {
    store.snapshot = const WorkspaceSnapshot(
      documents: [],
      activeDocumentId: null,
      workspaceRoot: null,
      workspaceAccessToken: null,
      sidebarVisible: true,
      outlineVisible: true,
      recoveryNotice: 'Recovered from the previous valid backup.',
    );
    await workspace.initialize();
    expect(workspace.recoveryNotice, contains('previous valid backup'));
    await workspace.flushSession();
    expect(workspace.recoveryNotice, isNotNull);
    workspace.dismissRecoveryNotice();
    expect(workspace.recoveryNotice, isNull);
  });
}
