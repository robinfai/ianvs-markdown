import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/widgets/workspace_note_move_recovery.dart';

const _id = '12345678-1234-4234-8234-123456789abc';
Map<String, Object?> _root(
  String path, {
  bool moved = true,
  bool synced = true,
  bool verified = true,
  String kind = 'directory',
  int count = 1,
}) => {
  'sourcePath': path,
  'destinationPath': 'dest/$path',
  'identity': '1:2',
  'kind': kind,
  'memberCount': count,
  'moved': moved,
  'synced': synced,
  'verified': verified,
  'actualPath': moved ? 'dest/$path' : path,
};
Map<String, Object?> _record() => {
  'transactionId': _id,
  'version': 3,
  'phase': 'completed',
  'entries': [],
  'namespaces': [_root('One'), _root('Two')],
};
Map<String, Object?> _storage() => {
  'transactionId': _id,
  'version': 3,
  'sourcePath': 'One',
  'destinationPath': 'dest/One',
  'entryCount': 0,
  'storedPhase': 'completed',
  'historicalObservation': true,
  'cleanupSupported': false,
  'blockers': <String>[],
  'namespaces': [_root('One'), _root('Two')],
};
void main() {
  test(
    'empty batch completes only with every independent namespace receipt',
    () {
      final record = WorkspaceNoteMoveRecord.fromMap(_record());
      expect(record.completed, isTrue);
      expect(record.namespaces, hasLength(2));
      expect(() => record.namespaces.clear(), throwsUnsupportedError);
      for (final partial in [
        _root('Two', moved: false, synced: false),
        _root('Two', synced: false),
        _root('Two', verified: false),
      ]) {
        final value = _record()..['namespaces'] = [_root('One'), partial];
        expect(WorkspaceNoteMoveRecord.fromMap(value).completed, isFalse);
      }
    },
  );
  test('malformed mixed or incomplete v3 schemas reject', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (r) => r.remove('namespaces'),
      (r) => r['namespaces'] = [],
      (r) => r['namespaces'] = [_root('One')],
      (r) => r['namespaces'] = List.generate(9, (i) => _root('R$i')),
      (r) => r['namespaces'] = [_root('One'), _root('One')],
      (r) => r['namespaces'] = [_root('One'), _root('Two', kind: 'unknown')],
      (r) => r['namespaces'] = [
        _root('One'),
        _root('Two', kind: 'note', count: 2),
      ],
      (r) => r['namespaces'] = [
        _root('One', count: 200),
        _root('Two', count: 200),
      ],
      (r) => r['namespaces'] = [
        _root('One'),
        _root('Two')..['actualPath'] = 'elsewhere',
      ],
      (r) => r['namespaces'] = [
        _root('One'),
        _root('Two')..['identity'] = 'invalid',
      ],
      (r) => r['namespace'] = _root('One'),
      (r) => r['version'] = 2,
      (r) => r['version'] = 1,
    ];
    for (final mutate in mutations) {
      final value = _record();
      mutate(value);
      expect(
        () => WorkspaceNoteMoveRecord.fromMap(value),
        throwsFormatException,
        reason: '$value',
      );
    }
  });
  test('file evidence is still required after all roots complete', () {
    final value = _record()
      ..['entries'] = [
        {
          'path': 'One/A.md',
          'destinationPath': 'dest/One/A.md',
          'state': 'applied',
          'actualPath': 'One/A.md',
          'revision': 'r',
          'verified': true,
        },
      ];
    expect(WorkspaceNoteMoveRecord.fromMap(value).completed, isFalse);
    (value['entries'] as List).first['actualPath'] = 'dest/One/A.md';
    expect(WorkspaceNoteMoveRecord.fromMap(value).completed, isTrue);
  });
  test('source and uncertain root outcomes have explicit UI labels', () {
    final source = WorkspaceBatchMoveReceipt.fromMap(
      _root('Two', moved: false, synced: false),
    );
    expect(source.atSource, isTrue);
    expect(workspaceBatchRootStatus(source), contains('verified source'));
    final uncertain = WorkspaceBatchMoveReceipt.fromMap(
      _root('Two', synced: false),
    );
    expect(workspaceBatchRootStatus(uncertain), contains('uncertain'));
    expect(
      workspaceBatchRootStatus(source, historical: true),
      contains('historical, not a current observation'),
    );
  });
  test(
    'historical v3 storage allows no-text roots but does not assert current state',
    () {
      final record = WorkspaceNoteMoveStorageRecord.fromMap(_storage());
      expect(record.entryCount, 0);
      expect(record.namespaces, hasLength(2));
      expect(() => record.namespaces.clear(), throwsUnsupportedError);
      expect(
        () => WorkspaceNoteMoveStorageRecord.fromMap(
          _storage()..remove('namespaces'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'historical v2 empty directory is accepted with namespace evidence only',
    () {
      final value = _storage()
        ..['version'] = 2
        ..remove('namespaces')
        ..['namespace'] = _root('One');
      expect(WorkspaceNoteMoveStorageRecord.fromMap(value).entryCount, 0);
      value.remove('namespace');
      expect(
        () => WorkspaceNoteMoveStorageRecord.fromMap(value),
        throwsFormatException,
      );
      value['version'] = 1;
      expect(
        () => WorkspaceNoteMoveStorageRecord.fromMap(value),
        throwsFormatException,
      );
    },
  );
}
