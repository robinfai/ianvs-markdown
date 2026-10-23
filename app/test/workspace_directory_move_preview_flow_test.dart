import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/attachment_repository.dart';
import 'package:linefold/src/services/attachment_resolver.dart';
import 'package:linefold/src/services/workspace_move_tree.dart';
import 'package:linefold/src/services/workspace_move_tree_inspector.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/widgets/workspace_note_move_preview.dart';

import 'support/fakes.dart';
import 'workspace_note_move_plan_test.dart' show MovePlanSource;

class _Images implements AttachmentSource {
  int lists = 0;
  int reads = 0;
  @override
  Future<List<AttachmentMetadata>> list(String root) async {
    lists++;
    return [];
  }

  @override
  Future<List<String>> normalize(List<String> paths) async => paths;
  @override
  Future<Uint8List> read(
    String root,
    String relativePath,
    int maximumBytes,
  ) async {
    reads++;
    throw StateError('Preview must not read image bytes.');
  }

  @override
  Future<Uint8List> readImportSettings(String root) async =>
      throw StateError('Preview must not read import settings.');
}

class _Trees implements WorkspaceMoveTreeInspector {
  _Trees(this.source);
  final MovePlanSource source;
  final started = Completer<void>();
  Completer<void>? gate;
  final calls = <(String, String, String)>[];
  final cancellations = <String>[];
  bool unsupported = false;

  @override
  Future<WorkspaceMoveTreeSnapshot> inspect(
    String root,
    String relativePath,
    String requestId,
  ) async {
    calls.add((root, relativePath, requestId));
    if (!started.isCompleted) started.complete();
    if (gate case final pending?) await pending.future;
    final paths =
        [...source.folders, ...source.files.keys]
            .where((p) => p == relativePath || p.startsWith('$relativePath/'))
            .toList()
          ..sort();
    return WorkspaceMoveTreeSnapshot(
      root: root,
      sourcePath: relativePath,
      requestId: requestId,
      rootIdentity: '1:1',
      sourceIdentity: '1:2',
      sourceState: WorkspaceMoveTreeSourceState.directory,
      complete: true,
      members: [
        for (var i = 0; i < paths.length; i++)
          WorkspaceMoveTreeMember(
            path: paths[i],
            kind: source.folders.contains(paths[i])
                ? WorkspaceMoveTreeMemberKind.directory
                : WorkspaceMoveTreeMemberKind.note,
            identity: '1:${i + 2}',
            revision: 'r:${paths[i]}',
            local: true,
          ),
        if (unsupported)
          WorkspaceMoveTreeMember(
            path: '$relativePath/Guide.pdf',
            kind: WorkspaceMoveTreeMemberKind.unsupported,
            identity: '1:99',
            revision: 'pdf-revision',
            local: true,
          ),
      ],
      issues: [
        if (unsupported)
          WorkspaceMoveTreeIssue(
            'unsupported_member',
            path: '$relativePath/Guide.pdf',
          ),
      ],
      observedEntryCount: paths.length + (unsupported ? 1 : 0),
    );
  }

  @override
  Future<void> cancel(String requestId) async => cancellations.add(requestId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryMarkdownFileService files;
  late MovePlanSource source;
  late _Trees trees;
  late _Images images;
  late WorkspaceController workspace;
  var disposed = false;

  setUp(() async {
    disposed = false;
    files = MemoryMarkdownFileService()..selectedFolder = '/vault';
    source = MovePlanSource()
      ..note('Old/A.md', '# A')
      ..note('Incoming.md', '[A](Old/A.md)');
    trees = _Trees(source);
    images = _Images();
    workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
      indexSource: source,
      moveTreeInspector: trees,
      movePreviewAttachments: images,
    );
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
  });
  tearDown(() async {
    if (!disposed) workspace.dispose();
    await files.dispose();
  });

  Future<WorkspaceNoteMovePlan> preview({
    WorkspaceMovePreviewCancellation? cancellation,
  }) => workspace.previewNoteMove(
    '/vault/Old',
    '/vault/New',
    cancellation: cancellation,
  );

  test(
    'directory impact uses complete tree metadata but never executes v1',
    () async {
      final plan = await preview();
      expect(plan.kind, WorkspaceNoteMovePlanKind.directory);
      expect(
        plan.complete,
        isTrue,
        reason: plan.blockers.map((b) => b.message).join('\n'),
      );
      expect(plan.executionSupported, isFalse);
      expect(trees.calls.single.$1, '/vault');
      expect(trees.calls.single.$2, 'Old');
      expect(images.lists, 1);
      expect(images.reads, 0);
      expect(
        plan.files.singleWhere((f) => f.path == 'Incoming.md').contents,
        '[A](New/A.md)',
      );
      expect(source.files['Incoming.md'], '[A](Old/A.md)');
      await expectLater(workspace.executeNoteMove(plan), throwsStateError);

      const channel = MethodChannel('directory-preview-v1-forbidden');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            calls++;
            throw StateError('The v1 channel must not be called.');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await expectLater(
        const AppleWorkspaceNoteTransactionStore(
          channel: channel,
        ).prepare(plan, newWorkspaceNoteTransactionId()),
        throwsStateError,
      );
      expect(calls, 0);
      expect(files.files, isEmpty);
    },
  );

  test(
    'PDF member retains directory existence and a specific blocked reason',
    () async {
      trees.unsupported = true;
      final plan = await preview();
      expect(plan.kind, WorkspaceNoteMovePlanKind.directory);
      expect(
        plan.treeSnapshot!.sourceState,
        WorkspaceMoveTreeSourceState.directory,
      );
      expect(plan.complete, isFalse);
      expect(plan.blockers.any((b) => b.path == 'Old/Guide.pdf'), isTrue);
      expect(plan.blockers.any((b) => b.code == 'sourceUnavailable'), isFalse);
      expect(plan.executionSupported, isFalse);
    },
  );

  test(
    'already cancelled preview never starts a directory inspection',
    () async {
      final cancellation = WorkspaceMovePreviewCancellation()..cancel();
      await expectLater(
        preview(cancellation: cancellation),
        throwsA(isA<WorkspaceMovePreviewCancelled>()),
      );
      expect(trees.calls, isEmpty);
      expect(images.lists, 0);
      expect(source.files['Incoming.md'], '[A](Old/A.md)');
    },
  );

  test(
    'cancellation requests cooperative stop and discards a late tree',
    () async {
      trees.gate = Completer<void>();
      final cancellation = WorkspaceMovePreviewCancellation();
      final pending = preview(cancellation: cancellation);
      final assertion = expectLater(
        pending,
        throwsA(isA<WorkspaceMovePreviewCancelled>()),
      );
      await trees.started.future;
      cancellation.cancel();
      cancellation.cancel();
      expect(trees.cancellations, [trees.calls.single.$3]);
      trees.gate!.complete();
      await assertion;
      expect(source.files['Incoming.md'], '[A](Old/A.md)');
    },
  );

  test(
    'workspace switch cancels an old inspection even without UI dismissal',
    () async {
      trees.gate = Completer<void>();
      final pending = preview();
      final assertion = expectLater(
        pending,
        throwsA(isA<WorkspaceMovePreviewCancelled>()),
      );
      await trees.started.future;
      files.selectedFolder = '/other';
      await workspace.chooseWorkspaceFolder();
      expect(trees.cancellations, [trees.calls.single.$3]);
      trees.gate!.complete();
      await assertion;
      expect(workspace.workspaceRoot, '/other');
    },
  );

  test(
    'disposing cancels active observation and rejects its late result',
    () async {
      trees.gate = Completer<void>();
      final pending = preview();
      final assertion = expectLater(
        pending,
        throwsA(isA<WorkspaceMovePreviewCancelled>()),
      );
      await trees.started.future;
      workspace.dispose();
      disposed = true;
      expect(trees.cancellations, [trees.calls.single.$3]);
      trees.gate!.complete();
      await assertion;
      expect(source.files['Incoming.md'], '[A](Old/A.md)');
    },
  );

  testWidgets('closing a pending preview cancels observation once', (
    tester,
  ) async {
    final pending = Completer<WorkspaceNoteMovePlan>();
    var cancelled = 0;
    WorkspaceNoteMoveDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              child: const Text('Open'),
              onPressed: () async =>
                  decision = await showWorkspaceNoteMovePreview(
                    context: context,
                    sources: ['/vault/Old'],
                    destinations: ['/vault/New'],
                    preview: pending.future,
                    onCancelPreview: () => cancelled++,
                  ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cancelled, 1);
    expect(decision?.cancelled, isTrue);
    pending.completeError(StateError('Late cancelled inspection'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(cancelled, 1);
  });

  testWidgets('unsupported directory members remain visible in the manifest', (
    tester,
  ) async {
    trees.unsupported = true;
    final plan = (await tester.runAsync(() => preview()))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              child: const Text('Open'),
              onPressed: () {
                unawaited(
                  showWorkspaceNoteMovePreview(
                    context: context,
                    sources: ['/vault/Old'],
                    destinations: ['/vault/New'],
                    preview: Future.value(plan),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final manifest = find.byKey(const ValueKey('directory-move-manifest'));
    await tester.ensureVisible(manifest);
    await tester.tap(find.text('Observed directory members'));
    await tester.pumpAndSettle();
    expect(find.text('Old/Guide.pdf · unsupported · local'), findsOneWidget);
    expect(find.byKey(const ValueKey('move-and-update-links')), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('directory preview stays manual-only at text scale $scale', (
      tester,
    ) async {
      final plan = (await tester.runAsync(() => preview()))!;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var maintenanceCalls = 0;
      var cancelled = 0;
      WorkspaceNoteMoveDecision? decision;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  decision = await showWorkspaceNoteMovePreview(
                    context: context,
                    sources: ['/vault/Old'],
                    destinations: ['/vault/New'],
                    preview: Future.value(plan),
                    onMaintain: (_) async {
                      maintenanceCalls++;
                      throw StateError('Directory execution is not available.');
                    },
                    onCancelPreview: () => cancelled++,
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Directory impact preview only'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('move-and-update-links')), findsNothing);
      expect(
        find.textContaining('Destination vacancy and conflicts'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final manual = find.byKey(const ValueKey('move-without-updating-links'));
      await tester.ensureVisible(manual);
      await tester.tap(manual);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(decision?.manual, isTrue);
      expect(maintenanceCalls, 0);
      expect(cancelled, 1);
    });
  }
}
