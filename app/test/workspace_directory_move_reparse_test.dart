import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';

import 'workspace_directory_move_plan_test.dart' show treeFor;
import 'workspace_note_move_plan_test.dart' show MovePlanSource;

String definitions(int count) =>
    List.generate(count, (i) => '[r$i]: Target.md').join('\n');

void main() {
  late MovePlanSource source;
  late WorkspaceIndex index;
  late WorkspaceReferenceIndex references;
  setUp(() {
    source = MovePlanSource()
      ..folders.addAll(['a', 'dest'])
      ..note('Target.md', 'body');
    index = WorkspaceIndex(source: source)..configure('/vault');
    references = WorkspaceReferenceIndex(index);
  });
  tearDown(() {
    references.dispose();
    index.dispose();
  });
  Future<WorkspaceNoteMovePlan> plan({
    WorkspaceNoteMovePlanner? planner,
    bool Function()? isCancelled,
  }) async => (planner ?? WorkspaceNoteMovePlanner(references)).buildDirectory(
    snapshot: await references.refresh(),
    sourcePath: 'a',
    destinationPath: 'dest/a',
    dirtySessionIds: {},
    tree: treeFor(source, 'a'),
    isCancelled: isCancelled,
  );
  List<String> codes(WorkspaceNoteMovePlan p) =>
      p.blockers.map((b) => b.code).toList();

  test(
    '1500 unchanged definitions skip reparse but keep complete identity proof',
    () async {
      source.note('Outside.md', definitions(1500));
      source.note('a/Move.md', 'body');
      final result = await plan(
        planner: WorkspaceNoteMovePlanner(
          references,
          maximumDirectoryReparseCodeUnits: 0,
          maximumDirectoryReparseReferences: 0,
          maximumDirectoryReparseLineCodeUnits: 0,
        ),
      );
      expect(result.complete, isTrue, reason: codes(result).join(','));
      expect(result.editCount, 0);
      expect(result.files.single.path, 'a/Move.md');
    },
  );

  test(
    'unchanged complex notes still detect missing-to-resolved semantic changes',
    () async {
      source.note(
        'Outside.md',
        '[future](dest/a/Move.md)\n\n${definitions(1500)}',
      );
      source.note('a/Move.md', 'body');
      final result = await plan(
        planner: WorkspaceNoteMovePlanner(
          references,
          maximumDirectoryReparseCodeUnits: 0,
          maximumDirectoryReparseReferences: 0,
        ),
      );
      expect(result.complete, isFalse);
      expect(codes(result), contains('newResolution'));
      expect(codes(result), isNot(contains('reparseComplexity')));
    },
  );

  test(
    'one real edit plus 1500 definitions is fully verified by default',
    () async {
      source.note('Outside.md', '[touch](a/Move.md)\n\n${definitions(1500)}');
      source.note('a/Move.md', 'body');
      final result = await plan();
      expect(result.complete, isTrue, reason: codes(result).join(','));
      expect(result.editCount, 1);
      expect(
        result.files.firstWhere((f) => f.path == 'Outside.md').contents,
        startsWith('[touch](dest/a/Move.md)'),
      );
    },
  );

  test('custom 128-reference budget includes changed occurrences', () async {
    source.note('a/Move.md', 'body');
    for (final count in [127, 128]) {
      source.note('Outside.md', '[touch](a/Move.md)\n\n${definitions(count)}');
      // Give each synthetic source revision a fresh index; the fake revision is
      // path-based, so changing its text alone is not a production invalidation.
      references.dispose();
      index.dispose();
      index = WorkspaceIndex(source: source)..configure('/vault');
      references = WorkspaceReferenceIndex(index);
      final result = await plan(
        planner: WorkspaceNoteMovePlanner(
          references,
          maximumDirectoryReparseReferences: 128,
        ),
      );
      expect(result.complete, count == 127, reason: codes(result).join(','));
      expect(codes(result).contains('reparseComplexity'), count == 128);
    }
  });

  test('custom source limit rejects an oversized changed note', () async {
    source.note(
      'Outside.md',
      '[touch](a/Move.md)\n\n${List.filled(140, 'x' * 127).join('\n')}',
    );
    source.note('a/Move.md', 'body');
    final result = await plan(
      planner: WorkspaceNoteMovePlanner(
        references,
        maximumDirectoryReparseCodeUnits: 16 * 1024,
      ),
    );
    expect(result.complete, isFalse);
    expect(
      result.blockers.firstWhere((b) => b.code == 'reparseComplexity').message,
      contains('source length'),
    );
  });

  test(
    'custom line limit rejects a changed note before sync reparse',
    () async {
      const prefix = '[touch](a/Move.md) ';
      source.note('Outside.md', '$prefix${'x' * (4096 - prefix.length)}');
      source.note('a/Move.md', 'body');
      final result = await plan(
        planner: WorkspaceNoteMovePlanner(
          references,
          maximumDirectoryReparseLineCodeUnits: 512,
        ),
      );
      expect(
        result.snapshot.notes['/vault/Outside.md']!.semantics.complete,
        isTrue,
      );
      expect(result.complete, isFalse);
      expect(
        result.blockers
            .firstWhere((b) => b.code == 'reparseComplexity')
            .message,
        contains('line length'),
      );
    },
  );

  test(
    'unchanged legal long line is not rejected by changed-text limits',
    () async {
      source.note('Outside.md', 'x' * 4096);
      source.note('a/Move.md', 'body');
      final result = await plan();
      expect(result.complete, isTrue, reason: codes(result).join(','));
      expect(result.editCount, 0);
    },
  );

  test(
    'destination growth cannot bypass projected source or line bounds',
    () async {
      source.note('Outside.md', '[touch](a/Move.md)');
      source.note('a/Move.md', 'body');
      final length = source.files['Outside.md']!.length;
      for (final planner in [
        WorkspaceNoteMovePlanner(
          references,
          maximumDirectoryReparseCodeUnits: length,
        ),
        WorkspaceNoteMovePlanner(
          references,
          maximumDirectoryReparseLineCodeUnits: length,
        ),
      ]) {
        final result = await plan(planner: planner);
        expect(result.complete, isFalse);
        expect(codes(result), contains('reparseComplexity'));
      }
    },
  );

  test(
    'moved unedited notes retain dirty local and disk-baseline checks',
    () async {
      source.note('a/Move.md', 'body');
      index.updateBuffer(
        sessionId: 'open',
        path: '/vault/a/Move.md',
        name: 'Move.md',
        text: 'body',
      );
      final planner = WorkspaceNoteMovePlanner(
        references,
        maximumDirectoryReparseCodeUnits: 0,
        maximumDirectoryReparseReferences: 0,
      );
      Future<WorkspaceNoteMovePlan> build(Set<String> dirty) async =>
          planner.buildDirectory(
            snapshot: await references.refresh(refreshMetadata: true),
            sourcePath: 'a',
            destinationPath: 'dest/a',
            dirtySessionIds: dirty,
            tree: treeFor(source, 'a'),
          );
      expect(codes(await build({'open'})), contains('dirty'));
      source.offline.add('a/Move.md');
      expect(codes(await build({})), contains('offline'));
      source.files.remove('a/Move.md');
      source.offline.clear();
      final ghost = await build({});
      expect(codes(ghost), containsAll(['sourceGhost', 'sourceUnavailable']));
      expect(codes(ghost), isNot(contains('reparseComplexity')));
    },
  );

  test(
    'large unchanged semantic proof remains cooperatively cancellable',
    () async {
      source.note('Outside.md', definitions(1500));
      source.note('a/Move.md', 'body');
      final snapshot = await references.refresh();
      var checks = 0;
      var cancelled = false;
      final result = await WorkspaceNoteMovePlanner(references).buildDirectory(
        snapshot: snapshot,
        sourcePath: 'a',
        destinationPath: 'dest/a',
        dirtySessionIds: {},
        tree: treeFor(source, 'a'),
        isCancelled: () {
          if (++checks == 500) Timer.run(() => cancelled = true);
          return cancelled;
        },
      );
      expect(result.complete, isFalse);
      expect(codes(result), contains('cancelled'));
    },
  );
}
