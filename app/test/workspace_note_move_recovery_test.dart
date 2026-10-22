import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/widgets/workspace_note_move_recovery.dart';

import 'support/fakes.dart';

class RecoveryStore implements WorkspaceNoteTransactionStore {
  var listing = const WorkspaceNoteMoveJournalList();
  final copies = <String>[];
  int inspections = 0;
  int lists = 0;
  Completer<WorkspaceNoteMoveStorage>? gate;
  Object? inspectionError;
  WorkspaceNoteMoveStorage? storageOverride;
  @override
  Future<WorkspaceNoteMoveStorage> inspectStorage(String root) async {
    inspections++;
    if (inspectionError case final error?) throw error;
    if (gate case final pending?) return pending.future;
    if (storageOverride case final value?) return value;
    return WorkspaceNoteMoveStorage(
      observedComplete: false,
      currentRootKnown: true,
      globalJournalCount: listing.transactions.length,
      globalRecordSlotCount: listing.storageBlocked
          ? 32
          : listing.transactions.length,
      pendingCount: 3,
      pendingBytes: 1024,
      unavailableCount: listing.unavailableRecords,
      blockers: [
        'cleanup_not_implemented',
        if (listing.storageBlocked) 'journal_record_limit',
      ],
      records: [
        for (final record in listing.transactions)
          WorkspaceNoteMoveStorageRecord(
            transactionId: record.transactionId,
            sourcePath: record.entries.first.path,
            destinationPath: record.entries.first.destinationPath,
            entryCount: record.entries.length,
            storedPhase: record.phase,
            artifactUnknownCount: record.retainedArtifacts.length,
            blockers: ['partial_unverified'],
          ),
      ],
    );
  }

  @override
  Future<WorkspaceNoteMoveJournalList> list(String root) async {
    lists++;
    return listing;
  }

  @override
  Future<WorkspaceNoteMoveRecord> recoverCopies(
    String root,
    String id,
    String directory,
  ) async {
    copies.add('$root:$id:$directory');
    return listing.transactions.single;
  }

  @override
  Future<WorkspaceNoteMoveRecord> prepare(
    WorkspaceNoteMovePlan plan,
    String id,
  ) => throw UnimplementedError();
  @override
  Future<WorkspaceNoteMoveRecord> execute(
    String root,
    String id,
    String token,
  ) => throw UnimplementedError();
  @override
  Future<WorkspaceNoteMoveRecord> cancelPrepared(
    String root,
    String id,
    String token,
  ) => throw UnimplementedError();
  @override
  Future<WorkspaceNoteMoveRecord> reconcile(String root, String id) =>
      throw UnimplementedError();
}

void main() {
  testWidgets(
    'restart recovery exposes unknown artifacts and copies only after explicit approval',
    (tester) async {
      const id = '12345678-1234-4234-8234-123456789abc';
      final store = RecoveryStore()
        ..listing = WorkspaceNoteMoveJournalList(
          transactions: [
            WorkspaceNoteMoveRecord(
              transactionId: id,
              phase: 'uncertain',
              entries: const [
                WorkspaceNoteMoveReceipt(
                  path: 'Old.md',
                  destinationPath: 'New.md',
                  state: 'uncertain',
                ),
              ],
              retainedArtifacts: const [
                WorkspaceNoteMoveArtifact(
                  '.linefold-note-move-$id-0.md',
                  'uncertain',
                  false,
                ),
              ],
            ),
          ],
          unavailableRecords: 1,
          storageBlocked: true,
        );
      final files = MemoryMarkdownFileService()..selectedFolder = '/vault';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
        noteTransactions: store,
      );
      addTearDown(workspace.dispose);
      await tester.runAsync(workspace.chooseWorkspaceFolder);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showWorkspaceNoteMoveRecovery(context, workspace),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(workspace.noteMoveRecoveryNotice, isNotNull);
      expect(find.textContaining('Unavailable records: 1'), findsOneWidget);
      expect(find.textContaining('storage limit reached'), findsOneWidget);
      expect(find.text('Saved state: uncertain (historical)'), findsOneWidget);
      expect(store.lists, 0);
      expect(
        find.textContaining('Retained artifacts: Unknown'),
        findsOneWidget,
      );
      expect(
        find.textContaining('consume bytes, not record slots'),
        findsOneWidget,
      );
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(store.lists, 0);
      expect(store.copies, isEmpty);
      final recover = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Recover originals as new copies'),
      );
      recover.onPressed!();
      recover.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Create original recovery copies?'), findsOneWidget);
      expect(
        find.textContaining('Existing notes are never replaced or deleted'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.copies, isEmpty);
      await tester.ensureVisible(find.text('Recover originals as new copies'));
      await tester.tap(find.text('Recover originals as new copies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create original copies'));
      await tester.pumpAndSettle();
      expect(store.copies, ['/vault:$id:']);
      expect(
        store.lists,
        1,
        reason: 'Only explicit recovery may use the existing reconcile flow',
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'workspace switch away and back invalidates displayed original-copy consent',
    (tester) async {
      const id = '12345678-1234-4234-8234-123456789abc';
      final store = RecoveryStore()
        ..listing = WorkspaceNoteMoveJournalList(
          transactions: [
            WorkspaceNoteMoveRecord(
              transactionId: id,
              phase: 'partial',
              entries: const [
                WorkspaceNoteMoveReceipt(
                  path: 'Old.md',
                  destinationPath: 'New.md',
                  state: 'pending',
                  verified: true,
                ),
              ],
            ),
          ],
        );
      final files = MemoryMarkdownFileService()..selectedFolder = '/vault';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
        noteTransactions: store,
      );
      addTearDown(workspace.dispose);
      await tester.runAsync(workspace.chooseWorkspaceFolder);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showWorkspaceNoteMoveRecovery(context, workspace),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Recover originals as new copies'));
      await tester.tap(find.text('Recover originals as new copies'));
      await tester.pumpAndSettle();
      files.selectedFolder = '/different';
      await tester.runAsync(workspace.chooseWorkspaceFolder);
      files.selectedFolder = '/vault';
      await tester.runAsync(workspace.chooseWorkspaceFolder);
      await tester.tap(find.text('Create original copies'));
      await tester.pumpAndSettle();
      expect(store.copies, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );
  Future<WorkspaceController> openEmpty(
    WidgetTester tester,
    RecoveryStore store,
    MemoryMarkdownFileService files,
  ) async {
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
      noteTransactions: store,
    );
    addTearDown(workspace.dispose);
    await tester.runAsync(workspace.chooseWorkspaceFolder);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWorkspaceNoteMoveRecovery(context, workspace),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return workspace;
  }

  testWidgets(
    'pending observation is dismissible and late response is ignored',
    (tester) async {
      final store = RecoveryStore();
      await openEmpty(
        tester,
        store,
        MemoryMarkdownFileService()..selectedFolder = '/vault',
      );
      store.gate = Completer();
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Refresh'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      store.gate!.complete(WorkspaceNoteMoveStorage());
      await tester.pumpAndSettle();
      expect(find.text('Note move recovery'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(store.lists, 0);
      expect(store.copies, isEmpty);
    },
  );

  testWidgets('late scope observation cannot repopulate an obsolete view', (
    tester,
  ) async {
    final store = RecoveryStore();
    final files = MemoryMarkdownFileService()..selectedFolder = '/vault';
    final workspace = await openEmpty(tester, store, files);
    store.gate = Completer();
    await tester.tap(find.text('Refresh'));
    await tester.pump();
    files.selectedFolder = '/other';
    await tester.runAsync(workspace.chooseWorkspaceFolder);
    store.gate!.complete(WorkspaceNoteMoveStorage());
    await tester.pumpAndSettle();
    expect(find.textContaining('Record slots:'), findsNothing);
    expect(find.textContaining('The workspace changed.'), findsOneWidget);
    expect(store.lists, 0);
    expect(store.copies, isEmpty);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('read failure removes stale totals instead of showing zero', (
    tester,
  ) async {
    final store = RecoveryStore();
    await openEmpty(
      tester,
      store,
      MemoryMarkdownFileService()..selectedFolder = '/vault',
    );
    store.inspectionError = StateError('Storage unavailable');
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Storage unavailable'), findsOneWidget);
    expect(find.textContaining('Record slots:'), findsNothing);
    expect(find.text('Recover originals as new copies'), findsNothing);
    expect(store.lists, 0);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
  testWidgets('unverified native scope disables copy and cached callbacks', (
    tester,
  ) async {
    const id = '12345678-1234-4234-8234-123456789abc';
    final store = RecoveryStore()
      ..listing = WorkspaceNoteMoveJournalList(
        transactions: [
          WorkspaceNoteMoveRecord(
            transactionId: id,
            phase: 'completed',
            entries: const [
              WorkspaceNoteMoveReceipt(
                path: 'Old.md',
                destinationPath: 'New.md',
                state: 'moved',
              ),
            ],
          ),
        ],
      );
    await openEmpty(
      tester,
      store,
      MemoryMarkdownFileService()..selectedFolder = '/vault',
    );
    final oldCallback = tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Recover originals as new copies'),
        )
        .onPressed!;
    final previous = await store.inspectStorage('/vault');
    store.storageOverride = WorkspaceNoteMoveStorage(
      currentRootKnown: false,
      records: previous.records,
      blockers: ['scope_changed_during_observation'],
    );
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Recover originals as new copies'),
          )
          .onPressed,
      isNull,
    );
    oldCallback();
    await tester.pumpAndSettle();
    expect(find.text('Create original recovery copies?'), findsNothing);
    expect(find.text('Saved state: completed (historical)'), findsOneWidget);
    expect(store.copies, isEmpty);
    expect(store.lists, 0);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'platform disclosure concerns recovery visibility not API absence',
    (tester) async {
      final store = RecoveryStore()
        ..storageOverride = WorkspaceNoteMoveStorage(
          observedComplete: true,
          currentRootKnown: true,
          blockers: ['platform_recovery_surface_unverified'],
        );
      await openEmpty(
        tester,
        store,
        MemoryMarkdownFileService()..selectedFolder = '/vault',
      );
      expect(
        find.textContaining(
          'a user-visible recovery location has not been verified',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('API unavailable'), findsNothing);
      expect(find.text('Recover originals as new copies'), findsNothing);
      expect(store.lists, 0);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  for (final scale in [2.0, 3.0]) {
    testWidgets('compact recovery controls stay reachable at ${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RecoveryStore()
        ..storageOverride = WorkspaceNoteMoveStorage(
          observedComplete: false,
          currentRootKnown: true,
          records: [
            WorkspaceNoteMoveStorageRecord(
              transactionId: '12345678-1234-4234-8234-123456789abc',
              sourcePath: 'folder/Old.md',
              destinationPath: 'archive/New.md',
              entryCount: 128,
              storedPhase: 'partial',
              blockers: ['artifact_changed', 'partial_unverified'],
            ),
          ],
          blockers: [
            'journal_read_limit',
            'journal_pending_remnants',
            'admission_not_evaluated',
          ],
        );
      final workspace = WorkspaceController(
        fileService: MemoryMarkdownFileService()..selectedFolder = '/vault',
        sessionStore: MemoryWorkspaceSessionStore(),
        noteTransactions: store,
      );
      addTearDown(workspace.dispose);
      await tester.runAsync(workspace.chooseWorkspaceFolder);
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
              onPressed: () =>
                  showWorkspaceNoteMoveRecovery(context, workspace),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'inventory layout');
      final before = store.inspections;
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(store.inspections, before + 1);
      await tester.ensureVisible(find.text('Recover originals as new copies'));
      await tester.pumpAndSettle();
      // Use a real hit-tested tap, not the callback: a tiny content viewport
      // could otherwise place this button underneath the fixed dialog actions.
      await tester.tap(find.text('Recover originals as new copies'));
      await tester.pumpAndSettle();
      expect(find.text('Create original copies'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'confirmation layout');
      expect(find.textContaining('Copies consume disk space'), findsOneWidget);
      expect(find.textContaining('Copied aliases'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.copies, isEmpty);
      expect(store.lists, 0);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Note move recovery'), findsNothing);
    });
  }
}
