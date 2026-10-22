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
  @override
  Future<WorkspaceNoteMoveJournalList> list(String root) async => listing;
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
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.textContaining('storage is full'), findsOneWidget);
      expect(find.textContaining('unverified)'), findsNWidgets(2));
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
      await tester.tap(find.text('Recover originals as new copies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create original copies'));
      await tester.pumpAndSettle();
      expect(store.copies, ['/vault:$id:']);
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
}
