import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';

import 'workspace_note_move_plan_test.dart' show MovePlanSource;

const _id = '12345678-1234-4234-8234-123456789abc';
const _otherId = '87654321-4321-4321-8321-cba987654321';

Map<String, Object?> _receipt({
  String path = 'Old.md',
  String destination = 'New.md',
  String state = 'moved',
  String? actualPath = 'New.md',
  String? revision = 'native-revision',
  bool verified = true,
}) => {
  'path': path,
  'destinationPath': destination,
  'state': state,
  'actualPath': actualPath,
  'revision': revision,
  'verified': verified,
};

Map<String, Object?> _record({
  String id = _id,
  String phase = 'completed',
  List<Object?>? entries,
}) => {
  'transactionId': id,
  'phase': phase,
  'entries': entries ?? [_receipt()],
};

WorkspaceReferenceSnapshot _withCatalog(
  WorkspaceReferenceSnapshot value,
  List<WorkspaceMetadata> entries,
) => WorkspaceReferenceSnapshot(
  epoch: value.epoch,
  contentRevision: value.contentRevision,
  catalogRevision: value.catalogRevision,
  catalog: WorkspaceCatalogSnapshot(
    epoch: value.catalog.epoch,
    entries: entries,
    complete: value.catalog.complete,
    issues: value.catalog.issues,
  ),
  notes: value.notes,
  edges: value.edges,
  tags: value.tags,
  aliases: value.aliases,
  wikiCandidates: value.wikiCandidates,
  noteCandidates: value.noteCandidates,
  issues: value.issues,
  knownDocuments: value.knownDocuments,
);

WorkspaceNoteMovePlan _copyPlan(
  WorkspaceNoteMovePlan value, {
  List<WorkspaceNoteMoveFile>? files,
  List<WorkspaceMetadata>? catalog,
  List<WorkspaceNoteMoveBlocker>? blockers,
}) => WorkspaceNoteMovePlan(
  root: value.root,
  snapshot: catalog == null
      ? value.snapshot
      : _withCatalog(value.snapshot, catalog),
  sourcePath: value.sourcePath,
  destinationPath: value.destinationPath,
  files: files ?? value.files,
  blockers: blockers ?? value.blockers,
  attachmentRequirements: value.attachmentRequirements,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native journal DTO validation', () {
    test('generated transaction IDs are unique RFC 4122 version 4 IDs', () {
      final ids = List.generate(100, (_) => newWorkspaceNoteTransactionId());
      expect(ids.toSet(), hasLength(ids.length));
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(ids.every(pattern.hasMatch), isTrue);
    });

    test('only verified final destination receipts complete a record', () {
      expect(WorkspaceNoteMoveRecord.fromMap(_record()).completed, isTrue);
      for (final entry in [
        _receipt(verified: false),
        _receipt(state: 'pending'),
        _receipt(actualPath: null),
        _receipt(actualPath: 'Old.md'),
        _receipt(revision: null),
        _receipt(revision: ''),
      ]) {
        expect(
          WorkspaceNoteMoveRecord.fromMap(_record(entries: [entry])).completed,
          isFalse,
          reason: '$entry must not claim completion',
        );
      }
      expect(
        WorkspaceNoteMoveRecord.fromMap(_record(entries: [])).completed,
        isFalse,
      );
      expect(
        WorkspaceNoteMoveRecord.fromMap(_record(phase: 'partial')).completed,
        isFalse,
      );
    });

    test('v2 empty namespace needs independent complete proof', () {
      final namespace = <String, Object?>{
        'sourcePath': 'Old',
        'destinationPath': 'New',
        'identity': '1:2',
        'memberCount': 1,
        'moved': true,
        'synced': true,
        'verified': true,
        'actualPath': 'New',
      };
      Map<String, Object?> envelope(Map<String, Object?> n) => {
        ..._record(entries: []),
        'version': 2,
        'namespace': n,
      };
      expect(
        WorkspaceNoteMoveRecord.fromMap(envelope(namespace)).completed,
        isTrue,
      );
      for (final patch in <Map<String, Object?>>[
        {'verified': false},
        {'synced': false},
        {'actualPath': 'Old'},
        {'actualPath': null},
      ]) {
        expect(
          WorkspaceNoteMoveRecord.fromMap(
            envelope({...namespace, ...patch}),
          ).completed,
          isFalse,
        );
      }
      for (final patch in <Map<String, Object?>>[
        {'memberCount': 0},
        {'memberCount': 257},
        {'identity': 'unknown'},
        {'actualPath': 'Other'},
        {'moved': false},
        {'verified': 'true'},
        {'sourcePath': '../Old'},
      ]) {
        expect(
          () => WorkspaceNoteMoveRecord.fromMap(
            envelope({...namespace, ...patch}),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => WorkspaceNoteMoveRecord.fromMap({..._record(), 'version': 2}),
        throwsFormatException,
      );
      expect(
        () => WorkspaceNoteMoveRecord.fromMap({
          ...envelope(namespace),
          'version': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => WorkspaceNoteMoveRecord.fromMap({..._record(), 'version': 3}),
        throwsFormatException,
      );
    });

    test('duplicate receipts cannot claim a completed manifest', () {
      expect(
        WorkspaceNoteMoveRecord.fromMap(
          _record(entries: [_receipt(), _receipt()]),
        ).completed,
        isFalse,
      );
    });

    test('all record lists are immutable', () {
      final entries = [_receipt()];
      final copies = ['Recovered.md'];
      final value = WorkspaceNoteMoveRecord.fromMap({
        ..._record(entries: entries),
        'recoveryPaths': copies,
      });
      entries.clear();
      copies.clear();
      expect(value.entries, hasLength(1));
      expect(value.recoveryPaths, ['Recovered.md']);
      expect(() => value.entries.clear(), throwsUnsupportedError);
      expect(() => value.recoveryPaths.clear(), throwsUnsupportedError);
      expect(() => value.retainedArtifacts.clear(), throwsUnsupportedError);
      expect(() => value.recoveryEntries.clear(), throwsUnsupportedError);
    });

    test('malformed journal envelopes fail closed', () {
      for (final patch in <Map<String, Object?>>[
        {'transactionId': 'not-a-uuid'},
        {'transactionId': '12345678-1234-1234-8234-123456789abc'},
        {'phase': 3},
        {'entries': null},
        {
          'entries': [3],
        },
        {'entries': List.generate(129, (_) => _receipt())},
        {
          'recoveryPaths': ['../outside.md'],
        },
        {'recoveryPaths': List.filled(129, 'Recovered.md')},
        {'token': false},
        {'code': 5},
        {'message': []},
        {'retryAllowed': 'yes'},
        {
          'retainedArtifacts': [{}],
        },
        {
          'recoveryEntries': [{}],
        },
      ]) {
        expect(
          () => WorkspaceNoteMoveRecord.fromMap({..._record(), ...patch}),
          throwsFormatException,
          reason: '$patch',
        );
      }
    });

    test('unsafe note and recovery paths never become trusted receipts', () {
      for (final path in [
        '/absolute.md',
        '../escape.md',
        'a/../escape.md',
        '.hidden.md',
        'a\\file.md',
        'a\u0000.md',
      ]) {
        for (final key in ['path', 'destinationPath', 'actualPath']) {
          expect(
            () => WorkspaceNoteMoveReceipt.fromMap({..._receipt(), key: path}),
            throwsFormatException,
            reason: '$key: $path',
          );
        }
      }
      expect(
        () => WorkspaceNoteMoveRecord.fromMap({
          ..._record(),
          'retainedArtifacts': [
            {
              'path': '.linefold-note-move-$_otherId-0.md',
              'state': 'retained',
              'verified': true,
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test(
      'retained artifact and recovery receipt preserve exact bounded paths',
      () {
        final record = WorkspaceNoteMoveRecord.fromMap({
          ..._record(phase: 'partial'),
          'retainedArtifacts': [
            {
              'path': 'folder/.linefold-note-move-$_id-0.md',
              'state': 'retained',
              'verified': true,
            },
          ],
          'recoveryPaths': ['Recovery/Old recovered.md'],
          'recoveryEntries': [
            {
              'sourcePath': 'Old.md',
              'path': 'Recovery/Old recovered.md',
              'state': 'created',
            },
          ],
        });
        expect(record.uncertain, isTrue);
        expect(record.retainedArtifacts.single.verified, isTrue);
        expect(record.recoveryEntries.single.sourcePath, 'Old.md');
        expect(record.recoveryEntries.single.path, 'Recovery/Old recovered.md');
      },
    );
  });

  group('typed native note transaction channel', () {
    const channel = MethodChannel('linefold/test-note-transactions');
    const store = AppleWorkspaceNoteTransactionStore(channel: channel);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late MovePlanSource source;
    late WorkspaceIndex index;
    late WorkspaceReferenceIndex references;
    late List<MethodCall> calls;
    late Object? Function(MethodCall) reply;

    setUp(() {
      source = MovePlanSource()..note('Old.md', '\ufeff# 中文 😀\r\nbody\r\n');
      index = WorkspaceIndex(source: source)..configure('/vault');
      references = WorkspaceReferenceIndex(index);
      calls = [];
      reply = (call) => _record(
        id: (call.arguments as Map)['transactionId'] as String? ?? _id,
        phase: 'prepared',
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply(call);
      });
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      references.dispose();
      index.dispose();
    });
    Future<WorkspaceNoteMovePlan> preview() async =>
        WorkspaceNoteMovePlanner(references).build(
          snapshot: await references.refresh(),
          sourcePath: 'Old.md',
          destinationPath: 'New.md',
          dirtySessionIds: {},
        );

    test(
      'prepare transports exact UTF-8 BOM CRLF bytes and native catalog revisions',
      () async {
        source.note('Origin.md', '\ufeff😀 [title](Old.md#h "keep")\r\n');
        index.updateBuffer(
          sessionId: 'clean-open-tab',
          path: '/vault/Origin.md',
          name: 'Origin.md',
          text: source.files['Origin.md']!,
        );
        final plan = await preview();
        expect(plan.complete, isTrue);
        final origin = plan.files.firstWhere(
          (file) => file.path == 'Origin.md',
        );
        expect(origin.source.fromBuffer, isTrue);
        expect(origin.source.revision, isNot('r:Origin.md'));
        await store.prepare(plan, _id);
        expect(calls.map((call) => call.method), ['prepareWorkspaceNoteMove']);
        final arguments = calls.single.arguments as Map;
        expect(arguments['path'], '/vault');
        expect(arguments['transactionId'], _id);
        final files = (arguments['files'] as List).cast<Map>();
        for (final file in plan.files) {
          final sent = files.singleWhere((entry) => entry['path'] == file.path);
          expect(sent['expectedRevision'], 'r:${file.path}');
          expect(sent['expectedBytes'], isA<Uint8List>());
          expect(sent['replacementBytes'], isA<Uint8List>());
          expect(
            sent['expectedBytes'],
            orderedEquals(utf8.encode(file.source.text)),
          );
          expect(
            sent['replacementBytes'],
            orderedEquals(utf8.encode(file.contents)),
          );
          expect((sent['expectedBytes'] as Uint8List).take(3), [
            0xef,
            0xbb,
            0xbf,
          ]);
        }
        expect(
          files.singleWhere(
            (f) => f['path'] == 'Origin.md',
          )['replacementBytes'],
          orderedEquals(utf8.encode('\ufeff😀 [title](New.md#h "keep")\r\n')),
        );
        expect(
          source.files['Origin.md'],
          '\ufeff😀 [title](Old.md#h "keep")\r\n',
        );
      },
    );

    test(
      'prepare rejects incomplete, invalid UUID and invalid file-count plans without invoking native',
      () async {
        final plan = await preview();
        for (final invalid in [
          _copyPlan(plan, files: []),
          _copyPlan(plan, files: List.filled(129, plan.files.single)),
          _copyPlan(plan, files: [plan.files.single, plan.files.single]),
          _copyPlan(
            plan,
            blockers: [
              const WorkspaceNoteMoveBlocker('offline', 'Unavailable'),
            ],
          ),
        ]) {
          await expectLater(store.prepare(invalid, _id), throwsStateError);
        }
        await expectLater(store.prepare(plan, 'invalid'), throwsStateError);
        expect(calls, isEmpty);
      },
    );

    test(
      'prepare rejects offline, missing, directory and revisionless catalog baselines',
      () async {
        final plan = await preview();
        for (final catalog in <List<WorkspaceMetadata>>[
          [],
          [
            const WorkspaceMetadata(
              relativePath: 'Old.md',
              isDirectory: false,
              revision: 'r:Old.md',
              local: false,
            ),
          ],
          [
            const WorkspaceMetadata(
              relativePath: 'Old.md',
              isDirectory: true,
              revision: 'r:Old.md',
            ),
          ],
          [
            const WorkspaceMetadata(
              relativePath: 'Old.md',
              isDirectory: false,
              revision: '',
            ),
          ],
        ]) {
          await expectLater(
            store.prepare(_copyPlan(plan, catalog: catalog), _id),
            throwsStateError,
          );
        }
        expect(calls, isEmpty);
      },
    );

    test(
      'prepare rejects a journal over 32 MiB before calling native',
      () async {
        final plan = await preview();
        final file = plan.files.single;
        final hugeText = 'x' * (17 * 1024 * 1024);
        final huge = WorkspaceNoteMoveFile(
          path: file.path,
          destination: file.destination,
          source: WorkspaceNoteSnapshot(
            key: file.source.key,
            path: file.source.path,
            name: file.source.name,
            text: hugeText,
            revision: file.source.revision,
          ),
          contents: hugeText,
          edits: [],
        );
        await expectLater(
          store.prepare(_copyPlan(plan, files: [huge]), _id),
          throwsStateError,
        );
        expect(calls, isEmpty);
      },
    );

    test(
      'prepare rejects excessive catalog and unsafe file destinations',
      () async {
        final plan = await preview();
        await expectLater(
          store.prepare(
            _copyPlan(
              plan,
              catalog: [
                for (var i = 0; i <= 50000; i++)
                  WorkspaceMetadata(
                    relativePath: '$i.md',
                    isDirectory: false,
                    revision: 'r:$i',
                  ),
              ],
            ),
            _id,
          ),
          throwsStateError,
        );
        final file = plan.files.single;
        await expectLater(
          store.prepare(
            _copyPlan(
              plan,
              files: [
                WorkspaceNoteMoveFile(
                  path: file.path,
                  destination: '../Outside.md',
                  source: file.source,
                  contents: file.contents,
                  edits: file.edits,
                ),
              ],
            ),
            _id,
          ),
          throwsStateError,
        );
        expect(calls, isEmpty);
      },
    );

    test(
      'null, malformed and mismatched transaction replies are rejected',
      () async {
        for (final response in <Object?>[
          null,
          {'transactionId': _id},
          _record(id: _otherId),
        ]) {
          reply = (_) => response;
          await expectLater(
            store.reconcile('/vault', _id),
            throwsFormatException,
          );
        }
        expect(calls, hasLength(3));
      },
    );

    test(
      'execute cancel reconcile and recovery use only their exact native entry point',
      () async {
        await store.execute('/vault', _id, 'confirmed-token');
        await store.cancelPrepared('/vault', _id, 'confirmed-token');
        await store.reconcile('/vault', _id);
        await store.recoverCopies('/vault', _id, 'Recovery');
        expect(calls.map((call) => call.method), [
          'executeWorkspaceNoteMove',
          'cancelPreparedWorkspaceNoteMove',
          'reconcileWorkspaceNoteMove',
          'recoverWorkspaceNoteMove',
        ]);
        expect(calls[0].arguments, {
          'path': '/vault',
          'transactionId': _id,
          'token': 'confirmed-token',
        });
        expect(calls[3].arguments, {
          'path': '/vault',
          'transactionId': _id,
          'relativeDirectory': 'Recovery',
        });
        expect((calls[3].arguments as Map).containsKey('overwrite'), isFalse);
        expect(
          (calls[3].arguments as Map).containsKey('replacementBytes'),
          isFalse,
        );
      },
    );

    test('recovery rejects traversal before invoking native', () async {
      for (final directory in ['../outside', '/outside', '.private', 'a\\b']) {
        expect(
          () => store.recoverCopies('/vault', _id, directory),
          throwsArgumentError,
        );
      }
      expect(calls, isEmpty);
    });

    test(
      'invalid UUIDs and relative roots never cross the native channel',
      () async {
        for (final operation in <Future<Object?> Function()>[
          () => store.execute('/vault', 'invalid', 'token'),
          () => store.cancelPrepared('/vault', 'invalid', 'token'),
          () => store.reconcile('/vault', 'invalid'),
          () => store.recoverCopies('/vault', 'invalid', ''),
          () => store.execute('relative/root', _id, 'token'),
          () => store.reconcile('/vault\u0000suffix', _id),
        ]) {
          await expectLater(operation(), throwsFormatException);
        }
        expect(calls, isEmpty);
      },
    );

    test(
      'journal list keeps valid records and exposes unavailable retained storage',
      () async {
        reply = (_) => {
          'transactions': [_record()],
          'unavailableRecords': 2,
          'retainedBytes': 4096,
          'storageBlocked': true,
        };
        final result = await store.list('/vault');
        expect(calls.single.method, 'listWorkspaceNoteMoves');
        expect(calls.single.arguments, {'path': '/vault'});
        expect(result.transactions.single.transactionId, _id);
        expect(result.unavailableRecords, 2);
        expect(result.retainedBytes, 4096);
        expect(result.storageBlocked, isTrue);
        expect(() => result.transactions.clear(), throwsUnsupportedError);
      },
    );

    test(
      'journal list rejects legacy lists, oversized arrays and malformed storage fields',
      () async {
        final envelope = <String, Object?>{
          'transactions': [_record()],
          'unavailableRecords': 0,
          'retainedBytes': 0,
          'storageBlocked': false,
        };
        for (final response in <Object?>[
          null,
          [_record()],
          {...envelope, 'transactions': List.generate(33, (_) => _record())},
          {
            ...envelope,
            'transactions': [7],
          },
          {...envelope, 'unavailableRecords': -1},
          {...envelope, 'unavailableRecords': '1'},
          {...envelope, 'retainedBytes': -1},
          {...envelope, 'retainedBytes': 1.5},
          {...envelope, 'storageBlocked': 'yes'},
        ]) {
          reply = (_) => response;
          await expectLater(
            store.list('/vault'),
            throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
          );
        }
      },
    );
  });
}
