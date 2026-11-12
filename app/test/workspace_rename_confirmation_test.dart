import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';
import 'package:linefold/src/widgets/workspace_note_move_preview.dart';

import 'workspace_directory_move_plan_test.dart' show treeFor;
import 'workspace_note_move_plan_test.dart' show MovePlanSource;

void main() {
  Future<WorkspaceNoteMovePlan> plan({
    bool inbound = false,
    bool partial = false,
    bool blocked = false,
    bool move = false,
  }) async {
    final source = MovePlanSource()..note('Old/Note.md', '# Note');
    if (inbound) source.note('Incoming.md', '[note](Old/Note.md)');
    if (partial) {
      source.note('Offline.md', 'unknown');
      source.offline.add('Offline.md');
    }
    if (blocked) source.offline.add('Old/Note.md');
    if (move) source.folders.add('dest');
    final index = WorkspaceIndex(source: source)..configure('/vault');
    final references = WorkspaceReferenceIndex(index);
    addTearDown(references.dispose);
    addTearDown(index.dispose);
    return WorkspaceNoteMovePlanner(references).buildDirectory(
      snapshot: await references.refresh(),
      sourcePath: 'Old',
      destinationPath: move ? 'dest/Old' : 'New',
      dirtySessionIds: {},
      tree: treeFor(source, 'Old'),
    );
  }

  WorkspaceNoteMoveRecord completed(WorkspaceNoteMovePlan plan) =>
      WorkspaceNoteMoveRecord(
        transactionId: 'result',
        phase: 'completed',
        version: 2,
        namespace: WorkspaceDirectoryMoveReceipt(
          sourcePath: plan.sourcePath,
          destinationPath: plan.destinationPath,
          identity: plan.treeSnapshot!.sourceIdentity!,
          memberCount: plan.treeSnapshot!.members.length,
          actualPath: plan.destinationPath,
          moved: true,
          synced: true,
          verified: true,
        ),
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
      );

  Future<void> open(
    WidgetTester tester, {
    required Future<WorkspaceNoteMovePlan> preview,
    required Future<WorkspaceNoteMoveRecord> Function(WorkspaceNoteMovePlan)
    execute,
    required void Function(WorkspaceNoteMoveDecision) onResult,
    VoidCallback? onCancel,
    bool Function()? current,
    String destination = '/vault/New',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Submit rename'),
              onPressed: () async => onResult(
                await showWorkspaceNoteMovePreview(
                  context: context,
                  sources: ['/vault/Old'],
                  destinations: [destination],
                  preview: preview,
                  onlyConfirmRisks: true,
                  isCurrent: current,
                  onMaintain: execute,
                  onCancelPreview: onCancel,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Submit rename'));
    await tester.pumpAndSettle();
  }

  for (final inbound in [false, true]) {
    testWidgets(
      'fully checked rename executes without another dialog; inbound=$inbound',
      (tester) async {
        final value = (await tester.runAsync(() => plan(inbound: inbound)))!;
        var calls = 0;
        var cancelled = 0;
        WorkspaceNoteMoveDecision? decision;
        await open(
          tester,
          preview: Future.value(value),
          execute: (approved) async {
            calls++;
            expect(identical(approved, value), isTrue);
            return completed(value);
          },
          onResult: (result) => decision = result,
          onCancel: () => cancelled++,
        );
        expect(calls, 1);
        expect(cancelled, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(decision?.automatic?.completed, isTrue);
        expect(decision?.plan?.editCount, inbound ? 1 : 0);
        expect(decision?.manual, isFalse);
      },
    );
  }

  for (final proceed in [false, true]) {
    testWidgets(
      'partial coverage requires one concise decision; proceed=$proceed',
      (tester) async {
        final value = (await tester.runAsync(() => plan(partial: true)))!;
        var calls = 0;
        WorkspaceNoteMoveDecision? decision;
        await open(
          tester,
          preview: Future.value(value),
          execute: (_) async {
            calls++;
            return completed(value);
          },
          onResult: (result) => decision = result,
        );
        expect(calls, 0);
        expect(
          find.text(
            'Some notes could not be checked. Renaming may leave links that need manual repair.',
          ),
          findsOneWidget,
        );
        expect(find.text('Rename anyway'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('directory-move-manifest')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('move-link-details')), findsNothing);
        expect(
          find.byKey(const ValueKey('move-without-updating-links')),
          findsNothing,
        );
        expect(find.textContaining('0 link replacements'), findsNothing);
        await tester.tap(find.text(proceed ? 'Rename anyway' : 'Back'));
        await tester.pumpAndSettle();
        expect(calls, proceed ? 1 : 0);
        expect(find.byType(AlertDialog), findsNothing);
        expect(decision?.cancelled, !proceed);
        expect(decision?.plan?.warnings.isNotEmpty, proceed ? isTrue : isNull);
      },
    );
  }

  testWidgets(
    'known source blocker explains issue without a raw rename bypass',
    (tester) async {
      final value = (await tester.runAsync(() => plan(blocked: true)))!;
      var calls = 0;
      await open(
        tester,
        preview: Future.value(value),
        execute: (_) async {
          calls++;
          return completed(value);
        },
        onResult: (_) {},
      );
      expect(
        find.text('Some affected files are not available locally.'),
        findsOneWidget,
      );
      expect(find.text('Back'), findsOneWidget);
      expect(find.byKey(const ValueKey('move-and-update-links')), findsNothing);
      expect(
        find.byKey(const ValueKey('move-without-updating-links')),
        findsNothing,
      );
      expect(calls, 0);
    },
  );

  testWidgets(
    'failed automatic execution is single shot and never falls back',
    (tester) async {
      final value = (await tester.runAsync(() => plan()))!;
      var calls = 0;
      await open(
        tester,
        preview: Future.value(value),
        execute: (_) async {
          calls++;
          throw StateError('Native reply lost');
        },
        onResult: (_) {},
      );
      expect(calls, 1);
      expect(find.textContaining('Native reply lost'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.byKey(const ValueKey('move-and-update-links')), findsNothing);
      expect(
        find.byKey(const ValueKey('move-without-updating-links')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'cancelled or changed rename intent cannot execute after planning',
    (tester) async {
      final value = (await tester.runAsync(() => plan()))!;
      final pending = Completer<WorkspaceNoteMovePlan>();
      var current = true;
      var calls = 0;
      var cancellations = 0;
      WorkspaceNoteMoveDecision? decision;
      await open(
        tester,
        preview: pending.future,
        current: () => current,
        execute: (_) async {
          calls++;
          return completed(value);
        },
        onResult: (result) => decision = result,
        onCancel: () => cancellations++,
      );
      expect(find.byType(AlertDialog), findsNothing);
      current = false;
      pending.complete(value);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(decision?.cancelled, isTrue);
      expect(cancellations, 1);
    },
  );

  testWidgets('a plan for another destination cannot execute automatically', (
    tester,
  ) async {
    final value = (await tester.runAsync(() => plan()))!;
    var calls = 0;
    WorkspaceNoteMoveDecision? decision;
    await open(
      tester,
      destination: '/vault/Different',
      preview: Future.value(value),
      execute: (_) async {
        calls++;
        return completed(value);
      },
      onResult: (result) => decision = result,
    );
    expect(calls, 0);
    expect(decision?.cancelled, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cross-parent move still requires its existing explicit review', (
    tester,
  ) async {
    final value = (await tester.runAsync(() => plan(move: true)))!;
    var calls = 0;
    await open(
      tester,
      destination: '/vault/dest/Old',
      preview: Future.value(value),
      execute: (_) async {
        calls++;
        return completed(value);
      },
      onResult: (_) {},
    );
    expect(calls, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Move and update links'), findsOneWidget);
  });
  testWidgets(
    'opening completed details cannot execute or offer a raw rename again',
    (tester) async {
      final value = (await tester.runAsync(() => plan()))!;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              child: const Text('Details'),
              onPressed: () => showWorkspaceNoteMovePreview(
                context: context,
                sources: ['/vault/Old'],
                destinations: ['/vault/New'],
                preview: Future.value(value),
                initialRecord: completed(value),
                onlyConfirmRisks: true,
                onMaintain: (_) async {
                  calls++;
                  return completed(value);
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Close'), findsOneWidget);
      expect(find.byKey(const ValueKey('move-and-update-links')), findsNothing);
      expect(
        find.byKey(const ValueKey('move-without-updating-links')),
        findsNothing,
      );
    },
  );
}
