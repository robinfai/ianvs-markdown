import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/widgets/workspace_note_move_preview.dart';

void main() {
  testWidgets(
    'folder and multi-item move requires an explicit unmaintained choice',
    (tester) async {
      bool? result;
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
          'Folder and multi-item reference maintenance is not supported',
        ),
        findsOneWidget,
      );
      expect(result, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('move-without-updating-links')),
      );
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );

  testWidgets(
    'pending preview is cancellable and late failure never approves a move',
    (tester) async {
      final pending = Completer<WorkspaceNoteMovePlan>();
      bool? result;
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
      expect(result, isFalse);
      pending.completeError(StateError('source changed'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed preview states missing coverage before any manual-only approval',
    (tester) async {
      bool? result;
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
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
