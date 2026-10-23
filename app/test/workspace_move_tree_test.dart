import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_move_namespace.dart';
import 'package:linefold/src/services/workspace_move_tree.dart';

Map<String, Object?> member(String path, {String kind = 'directory'}) => {
  'path': path,
  'kind': kind,
  'revision': 'native-revision',
  'identity': '1:20',
  'local': true,
  'size': 0,
};
Map<String, Object?> manifest() => {
  'root': '/vault',
  'canonicalRoot': '/vault',
  'sourcePath': 'a',
  'requestId': '00000000-0000-4000-8000-000000000000',
  'sourceState': 'directory',
  'rootIdentity': '1:1',
  'sourceIdentity': '1:20',
  'complete': true,
  'members': [member('a')],
  'issues': <Object?>[],
  'observedEntryCount': 1,
};
void main() {
  test('inspection blockers provide actionable human-readable reasons', () {
    expect(
      const WorkspaceMoveTreeIssue('unsupportedMember').message,
      contains('PDF'),
    );
    expect(const WorkspaceMoveTreeIssue('entryLimit').message, contains('256'));
    expect(
      const WorkspaceMoveTreeIssue('treeChanged').message,
      contains('Refresh'),
    );
    expect(
      const WorkspaceMoveTreeIssue('deadlineExceeded').message,
      contains('time limit'),
    );
    expect(
      const WorkspaceMoveTreeIssue('cancelled').message,
      contains('no files were changed'),
    );
  });

  test(
    'one-shot component mapping never chains or matches sibling prefixes',
    () {
      final map = WorkspaceMoveNamespace(source: 'a', destination: 'b/a');
      expect(map.map('a/nested/note.md'), 'b/a/nested/note.md');
      expect(map.map('ab/note.md'), 'ab/note.md');
      expect(map.map('b/a/note.md'), 'b/a/note.md');
      for (final destination in [
        'a',
        'a/nested',
        '.',
        '../a',
        '/a',
        'a//b',
        '.hidden',
      ]) {
        expect(
          () => WorkspaceMoveNamespace(source: 'a', destination: destination),
          throwsFormatException,
        );
      }
      expect(
        () => WorkspaceMoveNamespace(source: 'a/sub', destination: 'a'),
        throwsFormatException,
      );
    },
  );
  test(
    'directory existence is independent of eligibility and unsupported diagnostics',
    () {
      final raw = manifest()
        ..['members'] = [
          member('a'),
          member('a/file.pdf', kind: 'unsupported'),
          member('a/.hidden', kind: 'unsupported'),
        ]
        ..['issues'] = [
          {'code': 'unsupportedMember', 'path': 'a/file.pdf'},
          {'code': 'hiddenMember', 'path': 'a/.hidden'},
        ]
        ..['observedEntryCount'] = 3;
      final tree = WorkspaceMoveTreeSnapshot.fromNative(raw);
      expect(tree.sourceState, WorkspaceMoveTreeSourceState.directory);
      expect(tree.complete, isTrue);
      expect(tree.issues, hasLength(2));
      expect(
        () => tree.members.add(tree.members.first),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'bounded diagnostic filenames are not interpreted as executable paths',
    () {
      final raw = manifest()
        ..['members'] = [
          member('a'),
          member('a/invalid:\\name\n.md', kind: 'unsupported'),
        ]
        ..['issues'] = [
          {'code': 'unsupportedPath', 'path': 'a/invalid:\\name\n.md'},
          {'code': 'invalidAncestor', 'path': 'parent'},
        ]
        ..['observedEntryCount'] = 2;
      final tree = WorkspaceMoveTreeSnapshot.fromNative(raw);
      expect(tree.members.last.path, 'a/invalid:\\name\n.md');
      expect(tree.issues.last.path, 'parent');
    },
  );
  test(
    'missing locality revision identity stay unknown, never assumed safe',
    () {
      final raw = manifest()
        ..remove('rootIdentity')
        ..remove('sourceIdentity');
      raw['members'] = [
        {'path': 'a', 'kind': 'directory'},
      ];
      final tree = WorkspaceMoveTreeSnapshot.fromNative(raw);
      expect(tree.rootIdentity, isNull);
      expect(tree.members.single.identity, isNull);
      expect(tree.members.single.local, isNull);
      expect(tree.members.single.revision, isNull);
    },
  );
  test(
    'failed partial scan retains directory state and over-budget observation',
    () {
      final raw = manifest()
        ..['complete'] = false
        ..['observedEntryCount'] = 257
        ..['issues'] = [
          {'code': 'entryLimit'},
        ];
      final tree = WorkspaceMoveTreeSnapshot.fromNative(raw);
      expect(tree.sourceState, WorkspaceMoveTreeSourceState.directory);
      expect(tree.complete, isFalse);
      expect(tree.observedEntryCount, 257);
      expect(tree.members, hasLength(1));
    },
  );
  test(
    'strict bounded decode rejects malformed types identities paths and counts',
    () {
      final invalid = <Map<String, Object?>>[
        manifest()..['complete'] = 'true',
        manifest()..['sourceState'] = 'other',
        manifest()..['observedEntryCount'] = -1,
        manifest()..['observedEntryCount'] = 2,
        manifest()..['rootIdentity'] = 'inode',
        manifest()..['root'] = '/vault/../elsewhere',
        manifest()..['sourcePath'] = '../a',
        manifest()..['members'] = [member('ab')],
        manifest()
          ..['members'] = [member('a'), member('a')]
          ..['observedEntryCount'] = 2,
        manifest()..['members'] = [member('a')..['local'] = 1],
        manifest()..['members'] = [member('a')..['size'] = -1],
        manifest()..['members'] = [member('a')..['kind'] = 'unknown'],
        manifest()..['members'] = [member('a/../x')],
        manifest()..['members'] = [member('a/x\u0000y')],
        manifest()
          ..['members'] = [
            member('a')..['revision'] = {'nested': true},
          ],
        manifest()
          ..['members'] = [
            for (var i = 0; i < 257; i++) member('a/$i', kind: 'note'),
          ]
          ..['observedEntryCount'] = 257,
        manifest()
          ..['members'] = [for (var i = 0; i < 65; i++) member('a/$i')]
          ..['observedEntryCount'] = 65,
        manifest()
          ..['issues'] = [
            for (var i = 0; i < 1025; i++) {'code': 'issue'},
          ],
        manifest()..['requestId'] = 'x' * 4097,
      ];
      for (var i = 0; i < invalid.length; i++) {
        expect(
          () => WorkspaceMoveTreeSnapshot.fromNative(invalid[i]),
          throwsFormatException,
          reason: 'fixture $i',
        );
      }
    },
  );
  test(
    'metadata byte ceiling fails closed without accepting a prefix manifest',
    () {
      final raw = manifest()
        ..['members'] = [
          for (var i = 0; i < 256; i++)
            member('a/${'x' * 4080}$i', kind: 'note')
              ..['revision'] = 'r' * 4096,
        ]
        ..['observedEntryCount'] = 256;
      expect(
        () => WorkspaceMoveTreeSnapshot.fromNative(raw),
        throwsFormatException,
      );
    },
  );
}
