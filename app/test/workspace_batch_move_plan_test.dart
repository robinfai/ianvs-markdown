import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/services/attachment_resolver.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_move_namespace.dart';
import 'package:linefold/src/services/workspace_move_tree.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';

import 'workspace_note_move_plan_test.dart' show MovePlanSource;
import 'workspace_directory_move_plan_test.dart' show treeFor, images;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MovePlanSource source;
  late WorkspaceIndex index;
  late WorkspaceReferenceIndex references;
  setUp(() {
    source = MovePlanSource();
    index = WorkspaceIndex(source: source)..configure('/vault');
    references = WorkspaceReferenceIndex(
      index,
      normalize: (paths) async =>
          paths.map((s) => s.replaceAll('e\u0301', 'é').toLowerCase()).toList(),
    );
  });
  tearDown(() {
    references.dispose();
    index.dispose();
  });
  Future<WorkspaceNoteMovePlan> plan(
    List<String> paths, {
    String target = 'dest',
    AttachmentIndex? attachments,
    List<WorkspaceBatchMoveRoot>? roots,
    int maximumFiles = 128,
    int maximumBackupBytes = 32 * 1024 * 1024,
    bool Function()? isCancelled,
    Set<String> dirty = const {},
  }) async {
    final snapshot = await references.refresh(refreshMetadata: true);
    return WorkspaceNoteMovePlanner(
      references,
      maximumFiles: maximumFiles,
      maximumBackupBytes: maximumBackupBytes,
    ).buildBatch(
      snapshot: snapshot,
      roots:
          roots ??
          [
            for (final path in paths)
              WorkspaceBatchMoveRoot(
                source: path,
                destination: '$target/${path.split('/').last}',
                tree: source.folders.contains(path)
                    ? treeFor(source, path, images: attachments)
                    : null,
              ),
          ],
      dirtySessionIds: dirty,
      attachments: attachments,
      isCancelled: isCancelled,
    );
  }

  void complete(WorkspaceNoteMovePlan result) {
    expect(result.blockers.map((b) => '${b.code}:${b.path}').toList(), isEmpty);
    expect(result.kind, WorkspaceNoteMovePlanKind.batch);
    expect(result.complete, isTrue);
    expect(result.executionSupported, isTrue);
  }

  Set<String> codes(WorkspaceNoteMovePlan result) =>
      result.blockers.map((b) => b.code).toSet();

  test(
    'two notes use one final namespace and rewrite an external note once',
    () async {
      source.note('One.md', '\ufeff[other](Two.md#Heading "title")\r\n');
      source.note('Two.md', '[back](One.md)');
      source.note('Outside.md', '[first](One.md) [second](Two.md)');
      source.folders.add('dest');
      final result = await plan(['One.md', 'Two.md']);
      complete(result);
      expect(result.files.length, 3);
      expect(
        result.files.where((f) => f.path == 'Outside.md').single.contents,
        '[first](dest/One.md) [second](dest/Two.md)',
      );
      expect(
        result.files.where((f) => f.path == 'One.md').single.contents,
        '\ufeff[other](Two.md#Heading "title")\r\n',
      );
      expect(
        result.files.where((f) => f.path == 'Two.md').single.contents,
        '[back](One.md)',
      );
    },
  );
  test(
    'note plus directory preserves cross-root links and exact source spans',
    () async {
      source.note('One.md', '[two](a/Two.md)');
      source.note('a/Two.md', '[one](../One.md)');
      source.note('Outside.md', '[one](One.md) [two](a/Two.md)');
      source.folders.add('dest');
      final result = await plan(['One.md', 'a']);
      complete(result);
      expect(
        result.files.where((f) => f.path == 'One.md').single.contents,
        '[two](a/Two.md)',
      );
      expect(
        result.files.where((f) => f.path == 'a/Two.md').single.contents,
        '[one](../One.md)',
      );
      expect(
        result.files.where((f) => f.path == 'Outside.md').single.contents,
        '[one](dest/One.md) [two](dest/a/Two.md)',
      );
    },
  );
  test('two directories map Wiki aliases and image targets globally', () async {
    source.note('a/One.md', '[[../b/Two|label]] ![](../b/pic.png "caption")');
    source.note('b/Two.md', '---\naliases: [Stable]\n---\n[[../a/One]]');
    source.note('Outside.md', '[[Stable]] ![](b/pic.png)');
    source.folders.add('dest');
    final result = await plan(['a', 'b'], attachments: images(['b/pic.png']));
    complete(result);
    expect(
      result.files.where((f) => f.path == 'a/One.md').single.contents,
      '[[../b/Two|label]] ![](../b/pic.png "caption")',
    );
    expect(
      result.files.where((f) => f.path == 'Outside.md').single.contents,
      '[[Stable]] ![](./dest/b/pic.png)',
    );
  });
  test('empty and image-only directories need no fake text entries', () async {
    source.folders.addAll(['a', 'b', 'dest']);
    final result = await plan(['a', 'b'], attachments: images(['b/pic.png']));
    complete(result);
    expect(result.files, isEmpty);
    expect(result.attachmentRequirements.single.relativePath, 'b/pic.png');
  });
  test('root count 2 through 8 accepted, 0/1/9 rejected', () async {
    source.folders.add('dest');
    for (var i = 0; i < 9; i++) {
      source.note('N$i.md', 'text');
    }
    complete(await plan([for (var i = 0; i < 8; i++) 'N$i.md']));
    for (final count in [0, 1, 9]) {
      expect(
        codes(await plan([for (var i = 0; i < count; i++) 'N$i.md'])),
        contains('scope'),
      );
    }
  });
  test(
    'duplicate, ancestor/child, target inside source and chain mappings rejected',
    () async {
      source.note('a/One.md', 'text');
      source.note('b/Two.md', 'text');
      source.folders.add('dest');
      for (final paths in [
        ['a', 'a/One.md'],
        ['a', 'a'],
      ]) {
        expect(codes(await plan(paths)), contains('scope'));
      }
      expect(
        codes(await plan(['a', 'b'], target: 'a/inside')),
        contains('scope'),
      );
      expect(
        codes(
          await plan(
            [],
            roots: [
              const WorkspaceBatchMoveRoot(source: 'a', destination: 'b'),
              const WorkspaceBatchMoveRoot(source: 'b', destination: 'c'),
            ],
          ),
        ),
        contains('scope'),
      );
    },
  );
  test(
    'case and NFC equivalent selected roots and destination collisions block',
    () async {
      source.note('a/One.md', 'text');
      source.note('b/one.md', 'text');
      source.folders.add('dest');
      expect(
        codes(await plan(['a/One.md', 'b/one.md'])),
        contains('sameIdentitySpelling'),
      );
      source.note('a/é.md', 'text');
      source.note('b/e\u0301.md', 'text');
      expect(
        codes(await plan(['a/é.md', 'b/e\u0301.md'])),
        contains('sameIdentitySpelling'),
      );
      source.note('dest/One.md', 'existing');
      expect(
        codes(await plan(['a/One.md', 'b/one.md'])),
        contains('destinationExists'),
      );
    },
  );
  test(
    'shared affected-file and recovery-byte budgets cannot multiply per root',
    () async {
      source.note('One.md', '[two](Two.md)');
      source.note('Two.md', '[one](One.md)');
      source.folders.add('dest');
      expect(
        codes(await plan(['One.md', 'Two.md'], maximumFiles: 1)),
        contains('transactionBudget'),
      );
      expect(
        codes(await plan(['One.md', 'Two.md'], maximumBackupBytes: 40)),
        contains('transactionBudget'),
      );
    },
  );
  test(
    'shared directory/member budget, unknown members and old artifacts block',
    () async {
      source.folders.addAll(['a', 'b', 'dest']);
      for (var i = 0; i < 130; i++) {
        source.folders.add('a/f$i');
        source.folders.add('b/f$i');
      }
      expect(codes(await plan(['a', 'b'])), contains('treeBudget'));
      source.folders.clear();
      source.folders.addAll(['a', 'b', 'dest']);
      final bad = treeFor(
        source,
        'a',
        extra: [
          const WorkspaceMoveTreeMember(
            path: 'a/.linefold-note-move-old.md',
            kind: WorkspaceMoveTreeMemberKind.note,
            identity: '1:99',
            revision: 'old',
            local: true,
            size: 1,
          ),
        ],
      );
      expect(
        codes(
          await plan(
            [],
            roots: [
              WorkspaceBatchMoveRoot(
                source: 'a',
                destination: 'dest/a',
                tree: bad,
              ),
              WorkspaceBatchMoveRoot(
                source: 'b',
                destination: 'dest/b',
                tree: treeFor(source, 'b'),
              ),
            ],
          ),
        ),
        contains('retainedArtifacts'),
      );
    },
  );
  test('cancellation never produces complete or executable proposal', () async {
    source.note('One.md', 'text');
    source.note('Two.md', 'text');
    source.folders.add('dest');
    final result = await plan(['One.md', 'Two.md'], isCancelled: () => true);
    expect(codes(result), contains('cancelled'));
    expect(result.executionSupported, isFalse);
  });
  test('global missing-to-resolved references block a batch', () async {
    source.note('One.md', 'text');
    source.note('Two.md', 'text');
    source.note('Outside.md', '[[/dest/One]] [future](dest/Two.md)');
    source.folders.add('dest');
    expect(codes(await plan(['One.md', 'Two.md'])), contains('newResolution'));
  });
  test(
    'dirty zero-edit root and dirty external alias dependency block',
    () async {
      source.note('One.md', 'text');
      source.note('Two.md', 'text');
      source.note('Alias.md', '---\naliases: [Stable]\n---\n');
      source.folders.add('dest');
      index.updateBuffer(
        sessionId: 'open',
        path: '/vault/One.md',
        name: 'One.md',
        text: 'text',
      );
      index.updateBuffer(
        sessionId: 'alias',
        path: '/vault/Alias.md',
        name: 'Alias.md',
        text: source.files['Alias.md']!,
      );
      final result = await plan(['One.md', 'Two.md'], dirty: {'open', 'alias'});
      expect(
        result.blockers.where((b) => b.code == 'dirty').map((b) => b.path),
        containsAll(['One.md', 'Alias.md']),
      );
    },
  );
  test(
    'unknown image metadata and hidden destination notes remain explicit',
    () async {
      source.note('a/One.md', '![](pic.png)');
      source.note('Two.md', 'text');
      source.folders.add('dest');
      final result = await plan(['a', 'Two.md']);
      expect(result.complete, isFalse);
      expect(result.executionSupported, isFalse);
      // Arbitrary PDF/hidden destination objects are not in this catalog. A
      // complete impact preview never claims native destination vacancy.
    },
  );
  test(
    'per-root rename and differing target parents are not a batch move',
    () async {
      source.note('One.md', 'text');
      source.note('Two.md', 'text');
      source.folders.addAll(['dest', 'other']);
      expect(
        codes(
          await plan(
            [],
            roots: [
              const WorkspaceBatchMoveRoot(
                source: 'One.md',
                destination: 'dest/Renamed.md',
              ),
              const WorkspaceBatchMoveRoot(
                source: 'Two.md',
                destination: 'other/Two.md',
              ),
            ],
          ),
        ),
        contains('batchTarget'),
      );
    },
  );

  test(
    'native adapter sends complete batch only to v3 with one shared file list',
    () async {
      source.note('One.md', 'text');
      source.note('Two.md', 'text');
      source.folders.add('dest');
      final result = await plan(['One.md', 'Two.md']);
      complete(result);
      const channel = MethodChannel('batch-preview-native-boundary');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            expect(call.method, 'prepareWorkspaceBatchMove');
            final args = call.arguments as Map;
            expect(args['roots'], hasLength(2));
            expect(
              (args['roots'] as List).every(
                (r) => r['kind'] == 'note' && !r.containsKey('tree'),
              ),
              isTrue,
            );
            expect(args['files'], hasLength(2));
            return {
              'transactionId': args['transactionId'],
              'phase': 'blocked',
              'entries': [],
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final receipt = await const AppleWorkspaceNoteTransactionStore(
        channel: channel,
      ).prepare(result, '12345678-1234-4234-8234-123456789abc');
      expect(receipt.phase, 'blocked');
      expect(calls, 1);
    },
  );

  test('mapping is simultaneous and component-aware', () {
    final mapping = WorkspaceBatchMoveNamespace([
      WorkspaceMoveNamespace(source: 'a', destination: 'dest/a'),
      WorkspaceMoveNamespace(source: 'b', destination: 'dest/b'),
    ]);
    expect(mapping.map('a/One.md'), 'dest/a/One.md');
    expect(mapping.map('ab/One.md'), 'ab/One.md');
    expect(mapping.map('dest/a/One.md'), 'dest/a/One.md');
  });
}
