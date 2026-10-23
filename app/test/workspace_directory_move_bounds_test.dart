import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_move_namespace.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';

import 'workspace_directory_move_plan_test.dart' show images, treeFor;
import 'workspace_note_move_plan_test.dart' show MovePlanSource;

void addAncestors(MovePlanSource source, String path) {
  var current = '';
  for (final part in path.split('/')) {
    current = current.isEmpty ? part : '$current/$part';
    source.folders.add(current);
  }
}

void main() {
  test('mapped notes must fit the 65-component file protocol', () async {
    final source = MovePlanSource()..note('a/nested/Note.md', 'body');
    final parent = List.generate(63, (i) => 'd$i').join('/');
    addAncestors(source, parent);
    final index = WorkspaceIndex(source: source)..configure('/vault');
    final references = WorkspaceReferenceIndex(index);
    addTearDown(references.dispose);
    addTearDown(index.dispose);
    final result = await WorkspaceNoteMovePlanner(references).buildDirectory(
      snapshot: await references.refresh(),
      sourcePath: 'a',
      destinationPath: '$parent/a',
      dirtySessionIds: {},
      tree: treeFor(source, 'a'),
    );
    expect(result.files.single.destination.split('/'), hasLength(66));
    expect(result.complete, isFalse);
    expect(result.blockers.map((b) => b.code), contains('mappedPath'));
  });

  test(
    'mapped empty directories and images receive their own depth checks',
    () async {
      final source = MovePlanSource()..folders.addAll(['a', 'a/nested']);
      final parent = List.generate(63, (i) => 'd$i').join('/');
      addAncestors(source, parent);
      final index = WorkspaceIndex(source: source)..configure('/vault');
      final references = WorkspaceReferenceIndex(index);
      addTearDown(references.dispose);
      addTearDown(index.dispose);
      final attachments = images(['a/nested/photo.png']);
      final result = await WorkspaceNoteMovePlanner(references).buildDirectory(
        snapshot: await references.refresh(),
        sourcePath: 'a',
        destinationPath: '$parent/a',
        dirtySessionIds: {},
        tree: treeFor(source, 'a', images: attachments),
        attachments: attachments,
      );
      expect(result.complete, isFalse);
      expect(result.files, isEmpty);
      final blocked = result.blockers
          .where((b) => b.code == 'mappedPath')
          .map((b) => b.path)
          .toSet();
      expect(
        blocked,
        containsAll(['$parent/a/nested', '$parent/a/nested/photo.png']),
      );
    },
  );

  test(
    'mapped UTF-8 byte limit is checked even when UTF-16 length fits',
    () async {
      final source = MovePlanSource()..note('a/${'n' * 200}.md', 'body');
      final parent = List.generate(22, (_) => 'é' * 90).join('/');
      addAncestors(source, parent);
      final index = WorkspaceIndex(source: source)..configure('/vault');
      final references = WorkspaceReferenceIndex(
        index,
        normalize: (paths) async => paths.map((p) => p.toLowerCase()).toList(),
      );
      addTearDown(references.dispose);
      addTearDown(index.dispose);
      expect(
        isSupportedWorkspaceMovePath('$parent/a', directory: true),
        isTrue,
      );
      final result = await WorkspaceNoteMovePlanner(references).buildDirectory(
        snapshot: await references.refresh(),
        sourcePath: 'a',
        destinationPath: '$parent/a',
        dirtySessionIds: {},
        tree: treeFor(source, 'a'),
      );
      expect(result.files.single.destination.length, lessThan(4096));
      expect(
        utf8.encode(result.files.single.destination).length,
        greaterThan(4096),
      );
      expect(result.complete, isFalse);
      expect(result.blockers.map((b) => b.code), contains('mappedPath'));
    },
  );

  test(
    'directory preview component bounds are conservative and scalar-safe',
    () {
      expect(
        isSupportedWorkspaceMovePath('a/${'é' * 126}.md', directory: false),
        isTrue,
      );
      expect(
        isSupportedWorkspaceMovePath('a/${'é' * 127}.md', directory: false),
        isFalse,
      );
      expect(
        isSupportedWorkspaceMovePath('a/\ud800.md', directory: false),
        isFalse,
      );
      expect(
        () => WorkspaceMoveNamespace(source: 'a', destination: 'é' * 128),
        throwsFormatException,
      );
      expect(
        isSupportedWorkspaceMovePath(
          List.filled(64, 'a').join('/'),
          directory: true,
        ),
        isTrue,
      );
      expect(
        isSupportedWorkspaceMovePath(
          List.filled(65, 'a').join('/'),
          directory: true,
        ),
        isFalse,
      );
      expect(
        isSupportedWorkspaceMovePath(
          List.filled(65, 'a').join('/'),
          directory: false,
        ),
        isTrue,
      );
    },
  );

  test(
    'missing Wiki cancellation stops before alias or parent normalization',
    () async {
      final source = MovePlanSource()
        ..folders.addAll(['a', 'dest', for (var i = 0; i < 160; i++) 'é$i'])
        ..note('Outside.md', '[[Missingé]]');
      final index = WorkspaceIndex(source: source)..configure('/vault');
      var armed = false;
      var cancelled = false;
      var callsAfterCancel = 0;
      final references = WorkspaceReferenceIndex(
        index,
        normalize: (paths) async {
          if (cancelled) callsAfterCancel++;
          if (armed && paths.length == 1 && paths.single == 'Missingé.md') {
            cancelled = true;
          }
          return paths.map((p) => p.toLowerCase()).toList();
        },
      );
      addTearDown(references.dispose);
      addTearDown(index.dispose);
      final snapshot = await references.refresh();
      armed = true;
      final result = await WorkspaceNoteMovePlanner(references).buildDirectory(
        snapshot: snapshot,
        sourcePath: 'a',
        destinationPath: 'dest/a',
        dirtySessionIds: {},
        tree: treeFor(source, 'a'),
        isCancelled: () => cancelled,
      );
      expect(result.complete, isFalse);
      expect(result.blockers.map((b) => b.code), contains('cancelled'));
      expect(callsAfterCancel, 0);
    },
  );

  test(
    'missing Wiki normalization is charged without repeated parent scans',
    () async {
      final source = MovePlanSource()
        ..folders.addAll(['a', 'dest', for (var i = 0; i < 160; i++) 'é$i'])
        ..note('Outside.md', List.filled(20, '[[Missingé]]').join('\n'));
      final index = WorkspaceIndex(source: source)..configure('/vault');
      var normalizedPaths = 0;
      final references = WorkspaceReferenceIndex(
        index,
        normalize: (paths) async {
          normalizedPaths += paths.length;
          return paths.map((p) => p.toLowerCase()).toList();
        },
      );
      addTearDown(references.dispose);
      addTearDown(index.dispose);
      final snapshot = await references.refresh();
      for (final budget in [1000, 600]) {
        normalizedPaths = 0;
        final result =
            await WorkspaceNoteMovePlanner(
              references,
              maximumDirectoryOperations: budget,
            ).buildDirectory(
              snapshot: snapshot,
              sourcePath: 'a',
              destinationPath: 'dest/a',
              dirtySessionIds: {},
              tree: treeFor(source, 'a'),
            );
        expect(normalizedPaths, lessThanOrEqualTo(budget));
        if (budget == 1000) {
          expect(
            result.complete,
            isTrue,
            reason: result.blockers.map((b) => b.code).join(','),
          );
        } else {
          expect(result.complete, isFalse);
          expect(
            result.blockers.map((b) => b.code),
            contains('planningBudget'),
          );
        }
      }
    },
  );
}
