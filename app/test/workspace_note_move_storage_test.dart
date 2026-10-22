import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';

const _id = '12345678-1234-4234-8234-123456789abc';
Map<String, Object?> _record() => {
  'transactionId': _id,
  'sourcePath': 'Old.md',
  'destinationPath': 'folder/New.md',
  'entryCount': 1,
  'storedPhase': 'completed',
  'journalBytes': 1024,
  'artifactBytes': 512,
  'allocatedBytes': 4096,
  'artifactCount': 1,
  'artifactMissingCount': 0,
  'artifactUnknownCount': 0,
  'historicalObservation': true,
  'cleanupSupported': false,
  'blockers': ['cleanup_not_implemented'],
};
Map<String, Object?> _storage() => {
  'observedComplete': false,
  'currentRootKnown': true,
  'globalJournalCount': 1,
  'globalRecordSlotCount': 2,
  'globalJournalBytes': 2048,
  'pendingCount': 1,
  'pendingBytes': 512,
  'invalidJournalCount': 1,
  'unknownEntryCount': 0,
  'unavailableCount': 1,
  'artifactReservedBytes': 1024,
  'availableBudgetBytes': 201324544,
  'currentRootJournalBytes': 1024,
  'currentRootArtifactBytes': 512,
  'currentRootArtifactAllocatedBytes': 4096,
  'artifactUnknownCount': 0,
  'limits': {
    'records': 32,
    'journalBytes': 201326592,
    'artifactReservedBytes': 201326592,
  },
  'blockers': ['cleanup_not_implemented', 'admission_not_evaluated'],
  'records': [_record()],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'DTO preserves separate counts, historical state, and immutable lists',
    () {
      final value = _storage();
      final result = WorkspaceNoteMoveStorage.fromMap(value);
      expect(result.globalRecordSlotCount, 2);
      expect(result.globalJournalCount, 1);
      expect(result.pendingCount, 1);
      expect(result.records.single.storedPhase, 'completed');
      (value['records'] as List).clear();
      (value['blockers'] as List).clear();
      expect(result.records, hasLength(1));
      expect(result.blockers, hasLength(2));
      expect(() => result.records.clear(), throwsUnsupportedError);
      expect(() => result.blockers.clear(), throwsUnsupportedError);
      expect(
        () => result.records.single.blockers.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test('unknown totals stay null and never imply zero', () {
    final value = _storage();
    for (final key in [
      'globalJournalBytes',
      'globalRecordSlotCount',
      'artifactReservedBytes',
      'currentRootArtifactBytes',
    ]) {
      value[key] = null;
    }
    final result = WorkspaceNoteMoveStorage.fromMap(value);
    expect(result.globalJournalBytes, isNull);
    expect(result.globalRecordSlotCount, isNull);
    expect(result.artifactReservedBytes, isNull);
    expect(result.currentRootArtifactBytes, isNull);
    expect(result.needsReview, isTrue);
  });
  test(
    'malformed metrics, bounds, identities and action flags fail closed',
    () {
      for (final patch in <Map<String, Object?>>[
        {'observedComplete': 'yes'},
        {'currentRootKnown': 1},
        {'globalJournalBytes': -1},
        {'pendingCount': 257},
        {'currentRootArtifactBytes': 1.5},
        {'artifactUnknownCount': 4097},
        {
          'blockers': ['/outside/private.md'],
        },
        {
          'records': [null],
        },
        {
          'records': [_record(), _record()],
        },
        {'records': List.generate(33, (_) => _record())},
        {
          'limits': {
            'records': 33,
            'journalBytes': 1,
            'artifactReservedBytes': 1,
          },
        },
        {
          'limits': {
            'records': 0,
            'journalBytes': 1,
            'artifactReservedBytes': 1,
          },
        },
      ]) {
        expect(
          () => WorkspaceNoteMoveStorage.fromMap({..._storage(), ...patch}),
          throwsFormatException,
          reason: '$patch',
        );
      }
      for (final patch in <Map<String, Object?>>[
        {'transactionId': '../outside'},
        {'sourcePath': '../Old.md'},
        {'destinationPath': '/outside/New.md'},
        {'entryCount': 0},
        {'entryCount': 129},
        {'storedPhase': ''},
        {'storedCode': 1},
        {'historicalObservation': false},
        {'cleanupSupported': true},
        {'artifactCount': 129},
        {
          'blockers': ['Trash this'],
        },
      ]) {
        expect(
          () =>
              WorkspaceNoteMoveStorageRecord.fromMap({..._record(), ...patch}),
          throwsFormatException,
          reason: '$patch',
        );
      }
    },
  );
  test('only definite limit codes report a reached storage limit', () {
    for (final code in [
      'journal_record_limit',
      'journal_byte_limit',
      'artifact_reservation_limit',
    ]) {
      final result = WorkspaceNoteMoveStorage.fromMap({
        ..._storage(),
        'blockers': [code],
      });
      expect(result.storageLimitReached, isTrue);
    }
    expect(
      WorkspaceNoteMoveStorage.fromMap({
        ..._storage(),
        'blockers': ['journal_unavailable'],
      }).storageLimitReached,
      isFalse,
    );
  });
  test('platform storage request only invokes the read-only method', () async {
    const channel = MethodChannel('test/storage-observation');
    final calls = <MethodCall>[];
    Object? response = _storage();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return response;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final store = AppleWorkspaceNoteTransactionStore(channel: channel);
    final result = await store.inspectStorage('/vault');
    expect(calls.single.method, 'inspectWorkspaceNoteMoveStorage');
    expect(calls.single.arguments, {'path': '/vault'});
    expect(result.records.single.transactionId, _id);
    await expectLater(store.inspectStorage('relative'), throwsFormatException);
    await expectLater(
      store.inspectStorage('/bad\u0000path'),
      throwsFormatException,
    );
    expect(calls, hasLength(1));
    response = null;
    await expectLater(store.inspectStorage('/vault'), throwsFormatException);
    response = <String, Object?>{};
    await expectLater(store.inspectStorage('/vault'), throwsFormatException);
  });
}
