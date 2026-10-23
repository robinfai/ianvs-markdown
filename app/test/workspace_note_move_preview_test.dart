import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';
import 'workspace_note_move_plan_test.dart' show MovePlanSource;
import 'package:linefold/src/widgets/workspace_note_move_preview.dart';

void main() {
  testWidgets(
    'selection without a complete preview requires an explicit unmaintained choice',
    (tester) async {
      WorkspaceNoteMoveDecision? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showWorkspaceNoteMovePreview(
                    context: context,
                    sources: ['folder', 'Other.md'],
                    destinations: ['moved/folder', 'moved/Other.md'],
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('will NOT be updated'), findsOneWidget);
      expect(
        find.textContaining(
          'No complete reference preview is available for this selection',
        ),
        findsOneWidget,
      );
      expect(result, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result?.cancelled, isTrue);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('move-without-updating-links')),
      );
      await tester.pumpAndSettle();
      expect(result?.manual, isTrue);
    },
  );

  testWidgets(
    'pending preview is cancellable and late failure never approves a move',
    (tester) async {
      final pending = Completer<WorkspaceNoteMovePlan>();
      WorkspaceNoteMoveDecision? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showWorkspaceNoteMovePreview(
                    context: context,
                    sources: ['Old.md'],
                    destinations: ['New.md'],
                    preview: pending.future,
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('move-without-updating-links')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result?.cancelled, isTrue);
      pending.completeError(StateError('source changed'));
      await tester.pumpAndSettle();
      expect(result?.cancelled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed preview states missing coverage before any manual-only approval',
    (tester) async {
      WorkspaceNoteMoveDecision? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showWorkspaceNoteMovePreview(
                    context: context,
                    sources: ['Old.md'],
                    destinations: ['New.md'],
                    preview: Future.error(StateError('offline')),
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No complete maintenance plan could be verified'),
        findsOneWidget,
      );
      expect(find.textContaining('will NOT be updated'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result?.cancelled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  Future<WorkspaceNoteMovePlan> completePlan() async {
    final source = MovePlanSource()
      ..note('Old.md', '# original')
      ..note('Origin.md', '[[Old]]');
    final index = WorkspaceIndex(source: source)..configure('/vault');
    final references = WorkspaceReferenceIndex(index);
    addTearDown(() {
      references.dispose();
      index.dispose();
    });
    final plan = await WorkspaceNoteMovePlanner(references).build(
      snapshot: await references.refresh(),
      sourcePath: 'Old.md',
      destinationPath: 'New.md',
      dirtySessionIds: {},
    );
    expect(plan.complete, isTrue);
    return plan;
  }

  testWidgets(
    'automatic execution needs the explicit inspected plan choice and cannot fall back after failure',
    (tester) async {
      final plan = (await tester.runAsync(completePlan))!;
      final pending = Completer<WorkspaceNoteMoveRecord>();
      var calls = 0;
      WorkspaceNoteMoveDecision? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showWorkspaceNoteMovePreview(
                    context: context,
                    sources: ['Old.md'],
                    destinations: ['New.md'],
                    preview: Future.value(plan),
                    onMaintain: (approved) {
                      expect(identical(approved, plan), isTrue);
                      calls++;
                      return pending.future;
                    },
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.textContaining('may sync with your vault'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('note-move-diff-Origin.md')),
      );
      await tester.tap(find.byKey(const ValueKey('note-move-diff-Origin.md')));
      await tester.pumpAndSettle();
      final edit = plan.files
          .firstWhere((file) => file.path == 'Origin.md')
          .edits
          .single;
      expect(
        find.textContaining('${edit.before} → ${edit.after}'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('move-and-update-links')));
      await tester.pump();
      expect(calls, 1);
      expect(
        find.byKey(const ValueKey('move-without-updating-links')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNull,
      );
      pending.completeError(StateError('Native reply lost; review recovery'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Native reply lost'), findsOneWidget);
      expect(find.byKey(const ValueKey('move-and-update-links')), findsNothing);
      expect(calls, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(result?.manual, isFalse);
    },
  );

  testWidgets(
    'verified completion shows receipts and retained artifacts, never automatic copies',
    (tester) async {
      final plan = (await tester.runAsync(completePlan))!;
      const id = '12345678-1234-4234-8234-123456789abc';
      final completed = WorkspaceNoteMoveRecord(
        transactionId: id,
        phase: 'completed',
        entries: [
          for (final file in plan.files)
            WorkspaceNoteMoveReceipt(
              path: file.path,
              destinationPath: file.destination,
              state: 'applied',
              verified: true,
              actualPath: file.destination,
              revision: 'new',
            ),
        ],
        retainedArtifacts: const [
          WorkspaceNoteMoveArtifact(
            '.linefold-note-move-$id-0.md',
            'retained',
            true,
          ),
        ],
      );
      var copies = 0;
      WorkspaceNoteMoveDecision? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showWorkspaceNoteMovePreview(
                    context: context,
                    sources: ['Old.md'],
                    destinations: ['New.md'],
                    preview: Future.value(plan),
                    onMaintain: (_) async => completed,
                    onRecoverCopies: (_) async {
                      copies++;
                      return completed;
                    },
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('move-and-update-links')));
      await tester.pumpAndSettle();
      expect(find.text('Move and reference updates verified.'), findsOneWidget);
      expect(find.textContaining('Retained artifact:'), findsOneWidget);
      expect(copies, 0);
      final recover = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Recover originals as new copies'),
      );
      recover.onPressed!();
      recover.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Create original recovery copies?'), findsOneWidget);
      expect(find.textContaining('Copied aliases'), findsOneWidget);
      expect(find.textContaining('consume disk space'), findsOneWidget);
      expect(copies, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(copies, 0);
      await tester.tap(find.text('Recover originals as new copies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create original copies'));
      await tester.pumpAndSettle();
      expect(copies, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(result?.automatic, completed);
      expect(result?.manual, isFalse);
    },
  );
}
