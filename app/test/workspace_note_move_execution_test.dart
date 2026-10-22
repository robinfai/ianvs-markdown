import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/document_session.dart';
import 'package:linefold/src/models/document_sync_status.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/services/workspace_session_store.dart';
import 'package:linefold/src/widgets/workspace_note_move_preview.dart';
import 'package:path/path.dart' as p;

import 'support/fakes.dart';

/// Entirely synthetic files and journal observations. These tests do not run
/// native code and deliberately make no filesystem/provider/CAS guarantees.
class _Files extends MemoryMarkdownFileService {
  final writes = <(String, String)>[];
  Completer<void>? writeGate;
  Completer<void>? writeStarted;
  Completer<String?>? savePathChoice;
  final savePathStarted = Completer<void>();
  final tokenCalls = <String>[];
  String? tokenGatePath;
  Completer<String?>? tokenGate;
  final tokenStarted = Completer<void>();
  bool tokenFailure = false;
  bool tokensSupported = true;
  final restoredTokenPaths = <String, String>{};

  @override
  Future<String?> createPersistentAccessToken(String path) async {
    tokenCalls.add(path);
    if (tokenFailure) throw StateError('Bookmark unavailable');
    if (!tokensSupported) return null;
    if (path == tokenGatePath && tokenGate != null) {
      if (!tokenStarted.isCompleted) tokenStarted.complete();
      return tokenGate!.future;
    }
    return super.createPersistentAccessToken(path);
  }

  @override
  Future<String?> restorePersistentAccess(String token) async =>
      restoredTokenPaths[token] ?? await super.restorePersistentAccess(token);

  @override
  Future<String?> chooseSavePath(String suggestedName) async {
    if (savePathChoice case final choice?) {
      if (!savePathStarted.isCompleted) savePathStarted.complete();
      return choice.future;
    }
    return super.chooseSavePath(suggestedName);
  }

  @override
  Future<List<WorkspaceEntry>> listDirectory(String directory) async {
    final entries = <String, bool>{};
    for (final path in files.keys) {
      if (!p.posix.isWithin(directory, path)) continue;
      final components = p.posix.relative(path, from: directory).split('/');
      entries[p.posix.join(directory, components.first)] =
          components.length > 1;
    }
    return [
      for (final entry in entries.entries)
        WorkspaceEntry(
          path: entry.key,
          name: p.posix.basename(entry.key),
          isDirectory: entry.value,
        ),
    ];
  }

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    writes.add((path, contents));
    if (writeStarted case final started?) {
      if (!started.isCompleted) started.complete();
    }
    if (writeGate case final gate?) await gate.future;
    await super.writeMarkdownFileAtomic(path, contents);
  }
}

class _ScopeFiles extends _Files {
  bool requireRestoredScope = false;
  final restoredScopes = <String>{};
  @override
  bool fileExists(String path) =>
      super.fileExists(path) &&
      (!requireRestoredScope ||
          restoredScopes.any(
            (scope) => path == scope || p.posix.isWithin(scope, path),
          ));
  @override
  Future<String?> restorePersistentAccess(String token) async {
    final path = await super.restorePersistentAccess(token);
    if (path != null) restoredScopes.add(path);
    return path;
  }
}

class _Sessions extends MemoryWorkspaceSessionStore {
  bool fail = false;
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<void> save(WorkspaceSnapshot snapshot) async {
    if (fail) throw StateError('Recovery storage unavailable');
    if (gate case final pending?) {
      if (!started.isCompleted) started.complete();
      await pending.future;
    }
    await super.save(snapshot);
  }
}

class _Metadata implements DocumentSyncSource {
  final paths = <String>[];
  CloudSyncState state = CloudSyncState.uploaded;
  Future<DocumentSyncMetadata> Function(String)? onRead;
  @override
  Future<DocumentSyncMetadata> readSyncMetadata(String path) async {
    paths.add(path);
    if (onRead case final callback?) return callback(path);
    return DocumentSyncMetadata(state: state, observedAt: DateTime.now());
  }
}

class _Transactions implements WorkspaceNoteTransactionStore {
  _Transactions(this.files);
  final _Files files;
  final calls = <String>[];
  List<String> get operations => calls.where((call) => call != 'list').toList();
  final recoverRequests = <(String, String, String)>[];
  WorkspaceNoteMovePlan? plan;
  String? transactionId;
  Object? prepareError;
  Object? executeError;
  Object? reconcileError;
  Completer<void>? prepareGate;
  Completer<void>? executeGate;
  final preparedStarted = Completer<void>();
  final executeStarted = Completer<void>();
  bool applyOnExecute = true;
  bool applied = false;
  WorkspaceNoteMoveRecord Function(WorkspaceNoteMoveRecord)? prepareResult;
  WorkspaceNoteMoveRecord Function(WorkspaceNoteMoveRecord)? executeResult;
  WorkspaceNoteMoveRecord Function(WorkspaceNoteMoveRecord)? reconcileResult;
  WorkspaceNoteMoveJournalList journal = const WorkspaceNoteMoveJournalList();

  WorkspaceNoteMoveRecord record({bool completed = false}) =>
      WorkspaceNoteMoveRecord(
        transactionId: transactionId!,
        phase: completed ? 'completed' : 'prepared',
        token: completed ? null : 'native-preflight-token',
        entries: [
          for (final file in plan!.files)
            WorkspaceNoteMoveReceipt(
              path: file.path,
              destinationPath: file.destination,
              state: completed
                  ? (file.path == file.destination ? 'applied' : 'moved')
                  : 'pending',
              actualPath: completed ? file.destination : file.path,
              revision: completed ? file.contents : file.source.text,
              verified: true,
            ),
        ],
      );

  @override
  Future<WorkspaceNoteMoveRecord> prepare(
    WorkspaceNoteMovePlan value,
    String id,
  ) async {
    calls.add('prepare');
    plan = value;
    transactionId = id;
    if (!preparedStarted.isCompleted) preparedStarted.complete();
    if (prepareGate case final gate?) await gate.future;
    if (prepareError case final error?) throw error;
    final result = record();
    return prepareResult?.call(result) ?? result;
  }

  @override
  Future<WorkspaceNoteMoveRecord> execute(
    String root,
    String id,
    String token,
  ) async {
    calls.add('execute');
    expectSync(id, transactionId);
    expectSync(token, 'native-preflight-token');
    if (!executeStarted.isCompleted) executeStarted.complete();
    if (executeGate case final gate?) await gate.future;
    if (applyOnExecute) {
      for (final file in plan!.files) {
        files.files.remove(p.posix.join(root, file.path));
        files.files[p.posix.join(root, file.destination)] = file.contents;
      }
      applied = true;
    }
    if (executeError case final error?) throw error;
    final result = record(completed: applied);
    return executeResult?.call(result) ?? result;
  }

  @override
  Future<WorkspaceNoteMoveRecord> reconcile(String root, String id) async {
    calls.add('reconcile');
    expectSync(id, transactionId);
    if (reconcileError case final error?) throw error;
    final result = record(completed: applied);
    return reconcileResult?.call(result) ?? result;
  }

  @override
  Future<WorkspaceNoteMoveRecord> cancelPrepared(
    String root,
    String id,
    String token,
  ) async {
    calls.add('cancelPrepared');
    return WorkspaceNoteMoveRecord(
      transactionId: id,
      phase: 'cancelled',
      entries: record().entries,
    );
  }

  @override
  Future<WorkspaceNoteMoveJournalList> list(String root) async {
    calls.add('list');
    return journal;
  }

  @override
  Future<WorkspaceNoteMoveRecord> recoverCopies(
    String root,
    String id,
    String directory,
  ) async {
    calls.add('recoverCopies');
    recoverRequests.add((root, id, directory));
    final paths = <String>[];
    for (final file in plan!.files) {
      final stem = p.posix.basenameWithoutExtension(file.path);
      var number = 1;
      String path;
      do {
        path = p.posix.join(directory, '$stem recovered $number.md');
        number++;
      } while (files.files.containsKey(p.posix.join(root, path)));
      files.files[p.posix.join(root, path)] = file.source.text;
      paths.add(path);
    }
    return WorkspaceNoteMoveRecord(
      transactionId: id,
      phase: 'recovered',
      entries: record(completed: applied).entries,
      recoveryPaths: paths,
    );
  }
}

WorkspaceNoteMoveRecord _withEntries(
  WorkspaceNoteMoveRecord value,
  List<WorkspaceNoteMoveReceipt> entries, {
  String? phase,
}) => WorkspaceNoteMoveRecord(
  transactionId: value.transactionId,
  phase: phase ?? value.phase,
  token: value.token,
  entries: entries,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Files files;
  late _Transactions transactions;
  late WorkspaceController workspace;
  late _Sessions sessions;
  late DocumentSession old;
  late DocumentSession origin;

  setUp(() async {
    files = _Files()
      ..selectedFolder = '/vault'
      ..files['/vault/Old.md'] = '\ufeff# Old 😀\r\nbody\r\n'
      ..files['/vault/Origin.md'] = '\ufeff[old](Old.md#h "keep")\r\n';
    transactions = _Transactions(files);
    sessions = _Sessions();
    workspace = WorkspaceController(
      fileService: files,
      sessionStore: sessions,
      noteTransactions: transactions,
    );
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
    old = (await workspace.openPath('/vault/Old.md'))!;
    origin = (await workspace.openPath('/vault/Origin.md'))!;
  });
  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });
  Future<WorkspaceNoteMovePlan> preview() =>
      workspace.previewNoteMove('/vault/Old.md', '/vault/New.md');

  Future<_Metadata> enableMetadata() async {
    workspace.dispose();
    await Future<void>.delayed(Duration.zero);
    final metadata = _Metadata();
    sessions = _Sessions();
    workspace = WorkspaceController(
      fileService: files,
      sessionStore: sessions,
      noteTransactions: transactions,
      syncSource: metadata,
    );
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
    old = (await workspace.openPath('/vault/Old.md'))!;
    origin = (await workspace.openPath('/vault/Origin.md'))!;
    await workspace.sync.refresh();
    return metadata;
  }

  test(
    'same-path active backlink refreshes only its cloud observation',
    () async {
      final metadata = await enableMetadata();
      expect(workspace.sync.metadata.state, CloudSyncState.uploaded);
      final plan = await preview();
      transactions.executeGate = Completer<void>();
      final moving = workspace.executeNoteMove(plan);
      await transactions.executeStarted.future;
      expect(workspace.sync.metadata.state, CloudSyncState.unknown);
      metadata.paths.clear();
      metadata.state = CloudSyncState.uploadPending;
      transactions.executeGate!.complete();
      expect((await moving).completed, isTrue);
      expect(workspace.activeDocument, origin);
      expect(origin.path, '/vault/Origin.md');
      expect(workspace.sync.metadata.state, CloudSyncState.unknown);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(workspace.sync.metadata.state, CloudSyncState.uploadPending);
      expect(metadata.paths, ['/vault/Origin.md']);
    },
  );

  test('note move does not revive old metadata after switching tabs', () async {
    final metadata = await enableMetadata();
    final stale = Completer<DocumentSyncMetadata>();
    metadata.onRead = (_) => stale.future;
    final oldRead = workspace.sync.refresh();
    await Future<void>.delayed(Duration.zero);
    final plan = await preview();
    transactions.executeGate = Completer<void>();
    final moving = workspace.executeNoteMove(plan);
    await transactions.executeStarted.future;
    metadata.onRead = null;
    metadata.state = CloudSyncState.uploadPending;
    workspace.selectDocument(workspace.documents.indexOf(old));
    transactions.executeGate!.complete();
    expect((await moving).completed, isTrue);
    stale.complete(
      DocumentSyncMetadata(
        state: CloudSyncState.uploaded,
        observedAt: DateTime.now(),
      ),
    );
    await oldRead;
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(workspace.activeDocument, old);
    expect(workspace.sync.path, '/vault/New.md');
    expect(workspace.sync.metadata.state, CloudSyncState.uploadPending);
    expect(metadata.paths.last, '/vault/New.md');
  });

  test(
    'note move completion cannot refresh a replacement workspace scope',
    () async {
      final metadata = await enableMetadata();
      final stale = Completer<DocumentSyncMetadata>();
      metadata.onRead = (_) => stale.future;
      final oldRead = workspace.sync.refresh();
      await Future<void>.delayed(Duration.zero);
      final plan = await preview();
      transactions.executeGate = Completer<void>();
      final moving = workspace.executeNoteMove(plan);
      await transactions.executeStarted.future;
      metadata.onRead = null;
      metadata.state = CloudSyncState.uploadPending;
      files.selectedFolder = '/other';
      await workspace.chooseWorkspaceFolder();
      await workspace.sync.refresh();
      final before = List.of(metadata.paths);
      transactions.executeGate!.complete();
      expect((await moving).completed, isFalse);
      stale.complete(
        DocumentSyncMetadata(
          state: CloudSyncState.uploaded,
          observedAt: DateTime.now(),
        ),
      );
      await oldRead;
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(workspace.workspaceRoot, '/other');
      expect(workspace.sync.metadata.state, CloudSyncState.uploadPending);
      expect(metadata.paths, before);
    },
  );

  test(
    'preview is read-only and explicit execution reconciles exact clean buffers',
    () async {
      final before = Map.of(files.files);
      final plan = await preview();
      expect(
        plan.complete,
        isTrue,
        reason: '${plan.blockers.map((b) => b.code)}',
      );
      expect(transactions.operations, isEmpty);
      expect(files.files, before);
      final result = await workspace.executeNoteMove(plan);
      expect(result.completed, isTrue);
      expect(transactions.operations, ['prepare', 'execute']);
      expect(old.path, '/vault/New.md');
      expect(old.accessToken, 'access:/vault/New.md');
      expect(origin.accessToken, 'access:/vault/Origin.md');
      expect(origin.controller.text, '\ufeff[old](New.md#h "keep")\r\n');
      expect(old.controller.isDirty, isFalse);
      expect(origin.controller.isDirty, isFalse);
      expect(origin.persistedText, origin.controller.text);
      expect(
        files.writes,
        isEmpty,
        reason: 'No ordinary save may implement a note transaction.',
      );
    },
  );

  test(
    'lost prepare reply reconciles once and never executes or prepares twice',
    () async {
      final plan = await preview();
      transactions.prepareError = PlatformException(code: 'lost_prepare_reply');
      final result = await workspace.executeNoteMove(plan);
      expect(result.phase, 'prepared');
      expect(result.completed, isFalse);
      expect(transactions.operations, ['prepare', 'reconcile']);
      expect(old.path, '/vault/Old.md');
      expect(origin.controller.text, contains('(Old.md#h'));
      expect(files.files.containsKey('/vault/New.md'), isFalse);
    },
  );

  test(
    'lost prepare and reconciliation replies report an uncertain transaction ID',
    () async {
      final plan = await preview();
      transactions
        ..prepareError = PlatformException(code: 'lost_prepare_reply')
        ..reconcileError = PlatformException(code: 'journal_unavailable');
      await expectLater(
        workspace.executeNoteMove(plan),
        throwsA(
          isA<WorkspaceNoteMoveUncertain>().having(
            (error) => error.transactionId,
            'transaction ID',
            isNotEmpty,
          ),
        ),
      );
      expect(transactions.operations, ['prepare', 'reconcile']);
      expect(files.files.containsKey('/vault/New.md'), isFalse);
    },
  );

  test(
    'lost execute reply reconciles verified disk state without retrying execution',
    () async {
      final plan = await preview();
      transactions.executeError = PlatformException(code: 'lost_execute_reply');
      final result = await workspace.executeNoteMove(plan);
      expect(result.completed, isTrue);
      expect(transactions.operations, ['prepare', 'execute', 'reconcile']);
      expect(old.path, '/vault/New.md');
      expect(origin.controller.text, contains('(New.md#h'));
      expect(origin.hasExternalChanges, isFalse);
    },
  );

  test(
    'lost execute and reconcile replies preserve buffers and never blind retry',
    () async {
      final plan = await preview();
      transactions
        ..executeError = PlatformException(code: 'lost_execute_reply')
        ..reconcileError = PlatformException(code: 'journal_unavailable');
      await expectLater(
        workspace.executeNoteMove(plan),
        throwsA(isA<WorkspaceNoteMoveUncertain>()),
      );
      expect(transactions.operations, ['prepare', 'execute', 'reconcile']);
      expect(old.path, '/vault/Old.md');
      expect(origin.controller.text, contains('(Old.md#h'));
      expect(files.files['/vault/Origin.md'], contains('(New.md#h'));
    },
  );

  test(
    'blocked native prepare with no entries is not an ambiguous mutation',
    () async {
      final plan = await preview();
      transactions.prepareResult = (value) => WorkspaceNoteMoveRecord(
        transactionId: value.transactionId,
        phase: 'blocked',
        code: 'destination_exists',
        message: 'Destination already exists.',
        entries: [],
      );
      final record = await workspace.executeNoteMove(plan);
      expect(record.phase, 'blocked');
      expect(record.completed, isFalse);
      expect(transactions.operations, ['prepare']);
      expect(old.path, '/vault/Old.md');
    },
  );

  test(
    'unverified receipts preserve original text and mark external changes',
    () async {
      final plan = await preview();
      transactions.executeResult = (value) => _withEntries(value, [
        for (final entry in value.entries)
          WorkspaceNoteMoveReceipt(
            path: entry.path,
            destinationPath: entry.destinationPath,
            state: entry.state,
            actualPath: entry.actualPath,
            revision: entry.revision,
            verified: false,
          ),
      ], phase: 'partial');
      final result = await workspace.executeNoteMove(plan);
      expect(result.completed, isFalse);
      expect(old.path, '/vault/Old.md');
      expect(origin.controller.text, contains('(Old.md#h'));
      expect(old.hasExternalChanges, isTrue);
      expect(origin.hasExternalChanges, isTrue);
    },
  );

  test(
    'receipt revision mismatch cannot update open buffer baselines',
    () async {
      final plan = await preview();
      transactions.executeResult = (value) => _withEntries(value, [
        for (final entry in value.entries)
          WorkspaceNoteMoveReceipt(
            path: entry.path,
            destinationPath: entry.destinationPath,
            state: entry.state,
            actualPath: entry.actualPath,
            revision: 'not-the-reread-native-revision',
            verified: true,
          ),
      ]);
      final result = await workspace.executeNoteMove(plan);
      expect(result.completed, isFalse);
      expect(result.code, 'client_verification_failed');
      expect(result.entries.every((entry) => !entry.verified), isTrue);
      expect(old.path, '/vault/Old.md');
      expect(origin.controller.text, contains('(Old.md#h'));
      expect(origin.persistedText, contains('(Old.md#h'));
      expect(old.hasExternalChanges, isTrue);
      expect(origin.hasExternalChanges, isTrue);
    },
  );

  test('receipt exact-byte mismatch cannot overwrite an open buffer', () async {
    final plan = await preview();
    transactions.executeResult = (value) {
      files.files['/vault/Origin.md'] = 'External concurrent contents';
      return value;
    };
    await workspace.executeNoteMove(plan);
    expect(old.path, '/vault/New.md');
    expect(origin.controller.text, contains('(Old.md#h'));
    expect(origin.hasExternalChanges, isTrue);
    expect(files.files['/vault/Origin.md'], 'External concurrent contents');
  });

  test(
    'partial receipts reconcile only verified applied entries, not unchanged notes',
    () async {
      final plan = await preview();
      transactions.applyOnExecute = false;
      transactions.executeResult = (value) {
        final changed = plan.files.singleWhere(
          (file) => file.path == 'Origin.md',
        );
        files.files['/vault/Origin.md'] = changed.contents;
        return _withEntries(value, [
          for (final entry in value.entries)
            if (entry.path == 'Origin.md')
              WorkspaceNoteMoveReceipt(
                path: entry.path,
                destinationPath: entry.destinationPath,
                actualPath: entry.path,
                state: 'applied',
                revision: changed.contents,
                verified: true,
              )
            else
              entry,
        ], phase: 'partial');
      };
      final result = await workspace.executeNoteMove(plan);
      expect(result.completed, isFalse);
      expect(result.uncertain, isTrue);
      expect(origin.controller.text, contains('(New.md#h'));
      expect(origin.controller.isDirty, isFalse);
      expect(old.path, '/vault/Old.md');
      expect(old.hasExternalChanges, isFalse);
      expect(files.files.containsKey('/vault/New.md'), isFalse);
    },
  );

  for (final badBaseline in [
    'unverified',
    'missing location',
    'changed revision',
  ]) {
    test('invalid prepared baseline ($badBaseline) never executes', () async {
      final plan = await preview();
      transactions.prepareResult = (value) => _withEntries(value, [
        for (final entry in value.entries)
          WorkspaceNoteMoveReceipt(
            path: entry.path,
            destinationPath: entry.destinationPath,
            state: 'pending',
            actualPath: badBaseline == 'missing location' ? null : entry.path,
            revision: badBaseline == 'changed revision'
                ? 'unexpected'
                : entry.revision,
            verified: badBaseline != 'unverified',
          ),
      ]);
      await expectLater(
        workspace.executeNoteMove(plan),
        throwsA(isA<WorkspaceNoteMoveUncertain>()),
      );
      expect(transactions.operations, ['prepare']);
      expect(old.path, '/vault/Old.md');
      expect(origin.controller.text, contains('(Old.md#h'));
      expect(workspace.noteMoveRecords, isEmpty);
    });
  }

  for (final lostStage in ['prepare', 'execute']) {
    test(
      'lost $lostStage reply cannot accept a malformed reconciliation manifest',
      () async {
        final plan = await preview();
        if (lostStage == 'prepare') {
          transactions.prepareError = PlatformException(code: 'lost_reply');
        } else {
          transactions.executeError = PlatformException(code: 'lost_reply');
        }
        transactions.reconcileResult = (value) => _withEntries(value, []);
        await expectLater(
          workspace.executeNoteMove(plan),
          throwsA(isA<WorkspaceNoteMoveUncertain>()),
        );
        expect(transactions.operations, [
          'prepare',
          if (lostStage == 'execute') 'execute',
          'reconcile',
        ]);
        expect(old.path, '/vault/Old.md');
        expect(origin.controller.text, contains('(Old.md#h'));
        expect(workspace.noteMoveRecords, isEmpty);
      },
    );
  }

  for (final malformed in [
    'missing entry',
    'duplicate entry',
    'wrong destination',
    'unexpected actual path',
    'missing revision',
    'empty revision',
    'unverified completion',
  ]) {
    test(
      'malformed execute manifest ($malformed) cannot complete buffer reconciliation',
      () async {
        final plan = await preview();
        transactions.executeResult = (value) {
          final first = value.entries.first;
          final entries = switch (malformed) {
            'missing entry' => value.entries.skip(1).toList(),
            'duplicate entry' => [...value.entries, first],
            'wrong destination' => [
              WorkspaceNoteMoveReceipt(
                path: first.path,
                destinationPath: 'Other.md',
                state: 'moved',
                actualPath: 'Other.md',
                revision: first.revision,
                verified: true,
              ),
              ...value.entries.skip(1),
            ],
            'missing revision' ||
            'empty revision' ||
            'unverified completion' => [
              WorkspaceNoteMoveReceipt(
                path: first.path,
                destinationPath: first.destinationPath,
                state: first.state,
                actualPath: first.actualPath,
                revision: malformed == 'missing revision'
                    ? null
                    : malformed == 'empty revision'
                    ? ''
                    : first.revision,
                verified: malformed != 'unverified completion',
              ),
              ...value.entries.skip(1),
            ],
            _ => [
              WorkspaceNoteMoveReceipt(
                path: first.path,
                destinationPath: first.destinationPath,
                state: 'moved',
                actualPath: 'Other.md',
                revision: first.revision,
                verified: true,
              ),
              ...value.entries.skip(1),
            ],
          };
          return _withEntries(value, entries);
        };
        await expectLater(
          workspace.executeNoteMove(plan),
          throwsA(isA<WorkspaceNoteMoveUncertain>()),
        );
        expect(old.path, '/vault/Old.md');
        expect(origin.controller.text, contains('(Old.md#h'));
        expect(transactions.operations, ['prepare', 'execute']);
        expect(workspace.noteMoveRecords, isEmpty);
      },
    );
  }

  test(
    'dirty and external-conflict buffers reject before native prepare',
    () async {
      final plan = await preview();
      origin.controller.text = 'Unsaved [[Old]]';
      await expectLater(workspace.executeNoteMove(plan), throwsStateError);
      expect(transactions.operations, isEmpty);
      origin.replaceFromDisk(files.files['/vault/Origin.md']!);
      final cleanPlan = await preview();
      origin.hasExternalChanges = true;
      await expectLater(workspace.executeNoteMove(cleanPlan), throwsStateError);
      expect(transactions.operations, isEmpty);
    },
  );

  test(
    'stale catalog and changed root epoch reject before native prepare',
    () async {
      final plan = await preview();
      files.files['/vault/Added.md'] = 'New catalog member';
      await workspace.references.refresh(refreshMetadata: true);
      await expectLater(workspace.executeNoteMove(plan), throwsStateError);
      final refreshed = await preview();
      files.selectedFolder = '/other';
      await workspace.chooseWorkspaceFolder();
      await expectLater(workspace.executeNoteMove(refreshed), throwsStateError);
      expect(transactions.operations, isEmpty);
    },
  );

  test(
    'typing while prepare is pending cancels native preparation without executing',
    () async {
      final plan = await preview();
      transactions.prepareGate = Completer<void>();
      final execution = workspace.executeNoteMove(plan);
      final checked = expectLater(execution, throwsStateError);
      await transactions.preparedStarted.future;
      origin.controller.text = 'Typed during prepare [[Old]]';
      transactions.prepareGate!.complete();
      await checked;
      expect(transactions.operations, ['prepare', 'cancelPrepared']);
      expect(origin.controller.text, 'Typed during prepare [[Old]]');
      expect(origin.controller.isDirty, isTrue);
      expect(files.files.containsKey('/vault/New.md'), isFalse);
    },
  );

  test(
    'changing root while prepare is pending cancels instead of executing old approval',
    () async {
      final plan = await preview();
      transactions.prepareGate = Completer<void>();
      final checked = expectLater(
        workspace.executeNoteMove(plan),
        throwsStateError,
      );
      await transactions.preparedStarted.future;
      files.selectedFolder = '/other';
      await workspace.chooseWorkspaceFolder();
      transactions.prepareGate!.complete();
      await checked;
      expect(transactions.operations, ['prepare', 'cancelPrepared']);
      expect(old.path, '/vault/Old.md');
    },
  );

  test(
    'typing while execution is pending keeps dirty text and updates only verified identity',
    () async {
      final plan = await preview();
      transactions.executeGate = Completer<void>();
      final execution = workspace.executeNoteMove(plan);
      await transactions.executeStarted.future;
      old.controller.text = 'New unsaved keystrokes';
      transactions.executeGate!.complete();
      await execution;
      expect(old.path, '/vault/New.md');
      expect(old.controller.text, 'New unsaved keystrokes');
      expect(old.controller.isDirty, isTrue);
      expect(old.hasExternalChanges, isTrue);
      expect(old.persistedText, '\ufeff# Old 😀\r\nbody\r\n');
    },
  );

  test(
    'changing root while execution is pending never remaps old workspace buffers',
    () async {
      final plan = await preview();
      transactions.executeGate = Completer<void>();
      final execution = workspace.executeNoteMove(plan);
      await transactions.executeStarted.future;
      files.selectedFolder = '/other';
      await workspace.chooseWorkspaceFolder();
      transactions.executeGate!.complete();
      await execution;
      expect(workspace.workspaceRoot, '/other');
      expect(old.path, '/vault/Old.md');
      expect(origin.controller.text, contains('(Old.md#h'));
      expect(workspace.noteMoveRecords, isEmpty);
    },
  );

  test(
    'save while a note transaction is active is refused without ordinary writes',
    () async {
      final plan = await preview();
      transactions.executeGate = Completer<void>();
      final execution = workspace.executeNoteMove(plan);
      await transactions.executeStarted.future;
      await expectLater(workspace.saveDocument(origin), throwsStateError);
      expect(files.writes, isEmpty);
      transactions.executeGate!.complete();
      await execution;
      expect(origin.controller.text, contains('(New.md#h'));
    },
  );

  test(
    'a save queued before execution cannot restore captured pre-move links',
    () async {
      final plan = await preview();
      files.savePathChoice = Completer<String?>();
      final firstSave = workspace.saveDocument(origin, saveAs: true);
      await files.savePathStarted.future;
      final execution = workspace.executeNoteMove(plan);
      final queuedSave = workspace.saveDocument(origin);
      final rejected = expectLater(queuedSave, throwsStateError);
      // Cancelling this earlier Save As releases the file-operation queue
      // without changing the approved preview or writing a note.
      files.savePathChoice!.complete(null);
      expect(await firstSave, isFalse);
      expect((await execution).completed, isTrue);
      await rejected;
      expect(files.writes, isEmpty);
      expect(files.files['/vault/Origin.md'], contains('(New.md#h'));
      expect(origin.controller.text, contains('(New.md#h'));
    },
  );

  test(
    'recovery requests only new original copies and leaves current files and buffers untouched',
    () async {
      final plan = await preview();
      final moved = await workspace.executeNoteMove(plan);
      files.files['/vault/Recovery/Old recovered 1.md'] =
          'Existing recovery copy';
      final before = Map.of(files.files);
      final currentOldText = old.controller.text;
      final currentOriginText = origin.controller.text;
      final result = await workspace.recoverNoteMoveCopies(
        moved.transactionId,
        relativeDirectory: 'Recovery',
      );
      expect(transactions.recoverRequests, [
        ('/vault', moved.transactionId, 'Recovery'),
      ]);
      expect(transactions.operations, ['prepare', 'execute', 'recoverCopies']);
      for (final entry in before.entries) {
        expect(files.files[entry.key], entry.value);
      }
      expect(result.recoveryPaths, contains('Recovery/Old recovered 2.md'));
      expect(
        files.files['/vault/Recovery/Origin recovered 1.md'],
        contains('(Old.md#h'),
      );
      expect(old.path, '/vault/New.md');
      expect(old.controller.text, currentOldText);
      expect(origin.controller.text, currentOriginText);
      expect(files.writes, isEmpty);
    },
  );

  testWidgets(
    'preview cancellation never prepares and explicit maintain is single-shot',
    (tester) async {
      final plan = (await tester.runAsync(preview))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWorkspaceNoteMovePreview(
                context: context,
                sources: ['Old.md'],
                destinations: ['New.md'],
                preview: Future.value(plan),
                onMaintain: workspace.executeNoteMove,
              ),
              child: const Text('Open preview'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open preview'));
      await tester.pumpAndSettle();
      expect(transactions.operations, isEmpty);
      expect(
        find.textContaining('retains original recovery copies'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(transactions.operations, isEmpty);
      await tester.tap(find.text('Open preview'));
      await tester.pumpAndSettle();
      transactions.executeGate = Completer<void>();
      final press = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('move-and-update-links')),
          )
          .onPressed!;
      press();
      press();
      await tester.pump();
      expect(transactions.operations, ['prepare', 'execute']);
      expect(find.byKey(const ValueKey('move-and-update-links')), findsNothing);
      expect(
        find.byKey(const ValueKey('move-without-updating-links')),
        findsNothing,
      );
      transactions.executeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Move and reference updates verified.'), findsOneWidget);
      expect(transactions.operations, ['prepare', 'execute']);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'old inode bookmarks are persisted absent before native execution',
    () async {
      final plan = await preview();
      transactions.executeGate = Completer<void>();
      final execution = workspace.executeNoteMove(plan);
      await transactions.executeStarted.future;
      final saved = sessions.snapshot!.documents.where(
        (entry) =>
            entry['path'] == '/vault/Old.md' ||
            entry['path'] == '/vault/Origin.md',
      );
      expect(saved.length, 2);
      expect(saved.every((entry) => entry['accessToken'] == null), isTrue);
      expect(old.accessToken, isNull);
      expect(origin.accessToken, isNull);
      transactions.executeGate!.complete();
      expect((await execution).completed, isTrue);
      expect(old.accessToken, 'access:/vault/New.md');
      expect(origin.accessToken, 'access:/vault/Origin.md');
    },
  );

  test(
    'failed bookmark invalidation persistence cancels before native execute',
    () async {
      final plan = await preview();
      final before = Map.of(files.files);
      sessions.fail = true;
      await expectLater(workspace.executeNoteMove(plan), throwsStateError);
      sessions.fail = false;
      expect(transactions.operations, ['prepare', 'cancelPrepared']);
      expect(old.accessToken, 'access:/vault/Old.md');
      expect(origin.accessToken, 'access:/vault/Origin.md');
      expect(files.files, before);
      expect(files.writes, isEmpty);
    },
  );

  test(
    'bookmark failure keeps verified new path and reports persistent access warning',
    () async {
      final plan = await preview();
      files.tokenFailure = true;
      final result = await workspace.executeNoteMove(plan);
      expect(result.completed, isTrue);
      expect(result.code, 'persistent_access_unavailable');
      expect(old.path, '/vault/New.md');
      expect(old.accessToken, isNull);
      expect(origin.accessToken, isNull);
    },
  );

  test(
    'closing a document during bookmark creation never mutates the closed document',
    () async {
      final plan = await preview();
      files.tokenGatePath = '/vault/New.md';
      files.tokenGate = Completer<String?>();
      final execution = workspace.executeNoteMove(plan);
      await files.tokenStarted.future;
      workspace.removeDocument(old);
      files.tokenGate!.complete('new-token');
      expect((await execution).completed, isTrue);
      expect(workspace.documents, isNot(contains(old)));
      expect(old.accessToken, isNull);
    },
  );

  test(
    'changing scope during bookmark creation does not publish stale token or completion',
    () async {
      final plan = await preview();
      files.tokenGatePath = '/vault/New.md';
      files.tokenGate = Completer<String?>();
      final execution = workspace.executeNoteMove(plan);
      await files.tokenStarted.future;
      files.selectedFolder = '/other';
      await workspace.chooseWorkspaceFolder();
      files.tokenGate!.complete('stale-token');
      final result = await execution;
      expect(result.completed, isFalse);
      expect(result.code, 'client_verification_failed');
      expect(old.accessToken, isNull);
      expect(workspace.noteMoveRecords, isEmpty);
    },
  );

  test('queued recovery keeps the workspace that the user confirmed', () async {
    final plan = await preview();
    transactions.executeGate = Completer<void>();
    final execution = workspace.executeNoteMove(plan);
    await transactions.executeStarted.future;
    final recovery = workspace.recoverNoteMoveCopies(
      transactions.transactionId!,
    );
    final rejected = expectLater(recovery, throwsStateError);
    files.selectedFolder = '/other';
    await workspace.chooseWorkspaceFolder();
    transactions.executeGate!.complete();
    expect((await execution).completed, isFalse);
    await rejected;
    expect(transactions.recoverRequests, isEmpty);
  });

  test(
    'stale snapshot bookmarks cannot redirect restored notes or favorites to retained originals',
    () async {
      await workspace.flushSession();
      final prior = sessions.snapshot!;
      final plan = await preview();
      await workspace.executeNoteMove(plan);
      const artifact =
          '/vault/.linefold-note-move-00000000-0000-4000-8000-000000000000-0.md';
      files.files[artifact] = 'Retained old inode, not the live note';
      files.restoredTokenPaths['access:/vault/Old.md'] = artifact;
      files.restoredTokenPaths['access:/vault/Origin.md'] = artifact;
      final stale = _Sessions()
        ..snapshot = WorkspaceSnapshot(
          documents: prior.documents,
          activeDocumentId: prior.activeDocumentId,
          workspaceRoot: prior.workspaceRoot,
          workspaceAccessToken: prior.workspaceAccessToken,
          sidebarVisible: prior.sidebarVisible,
          outlineVisible: prior.outlineVisible,
          browserState: {
            'favorites': {'/vault/Old.md': false},
          },
          favoriteAccessTokens: {'/vault/Old.md': 'access:/vault/Old.md'},
        );
      final restored = WorkspaceController(
        fileService: files,
        sessionStore: stale,
        noteTransactions: transactions,
      );
      try {
        await restored.initialize();
        expect(
          restored.documents.any((document) => document.path == artifact),
          isFalse,
        );
        expect(
          restored.browser.preferences.favorites.containsKey(artifact),
          isFalse,
        );
        final liveOrigin = restored.documents.singleWhere(
          (document) => document.path == '/vault/Origin.md',
        );
        expect(liveOrigin.controller.text, contains('(New.md#h'));
        expect(liveOrigin.accessToken, isNull);
        expect(
          restored.recoveryNotice,
          contains('retained note-move original'),
        );
      } finally {
        restored.dispose();
      }
    },
  );

  test(
    'typing during persisted token invalidation cancels and restores original scope',
    () async {
      final plan = await preview();
      sessions.gate = Completer<void>();
      final execution = workspace.executeNoteMove(plan);
      final rejected = expectLater(execution, throwsStateError);
      await sessions.started.future;
      expect(old.accessToken, isNull);
      origin.controller.text = 'Typed while preparing [[Old]]';
      sessions.gate!.complete();
      await rejected;
      expect(transactions.operations, ['prepare', 'cancelPrepared']);
      expect(old.accessToken, 'access:/vault/Old.md');
      expect(origin.accessToken, 'access:/vault/Origin.md');
      expect(files.files.containsKey('/vault/New.md'), isFalse);
      expect(
        sessions.snapshot!.documents.singleWhere(
          (entry) => entry['path'] == '/vault/Old.md',
        )['accessToken'],
        'access:/vault/Old.md',
      );
    },
  );

  test(
    'null bookmarks only warn where persistent access was expected',
    () async {
      final plan = await preview();
      old.accessToken = null;
      origin.accessToken = null;
      files.tokensSupported = false;
      final result = await workspace.executeNoteMove(plan);
      expect(result.completed, isTrue);
      expect(
        result.code,
        Platform.isMacOS ? 'persistent_access_unavailable' : null,
      );
    },
  );

  test(
    'bookmark failure preserves native partial failure explanation',
    () async {
      final plan = await preview();
      files.tokenFailure = true;
      transactions.executeResult = (value) => WorkspaceNoteMoveRecord(
        transactionId: value.transactionId,
        phase: 'partial',
        code: 'dependency_conflict',
        message: 'A new inbound note appeared.',
        entries: value.entries,
      );
      final result = await workspace.executeNoteMove(plan);
      expect(result.completed, isFalse);
      expect(result.code, 'dependency_conflict');
      expect(result.message, contains('A new inbound note appeared.'));
      expect(result.message, contains('some verified entries'));
    },
  );
  test(
    'moved and rewritten tabs survive root switch plus scoped restart',
    () async {
      final scopedFiles = _ScopeFiles()
        ..selectedFolder = '/vault'
        ..files['/vault/Old.md'] = '# Old'
        ..files['/vault/Origin.md'] = '[old](Old.md)';
      final sessions = MemoryWorkspaceSessionStore();
      final tx = _Transactions(scopedFiles);
      final first = WorkspaceController(
        fileService: scopedFiles,
        sessionStore: sessions,
        noteTransactions: tx,
      );
      await first.initialize();
      await first.chooseWorkspaceFolder();
      await first.openPath('/vault/Old.md');
      await first.openPath('/vault/Origin.md');
      final plan = await first.previewNoteMove(
        '/vault/Old.md',
        '/vault/New.md',
      );
      expect((await first.executeNoteMove(plan)).completed, isTrue);
      scopedFiles.selectedFolder = '/other';
      await first.chooseWorkspaceFolder();
      await first.flushSession();
      first.dispose();
      scopedFiles.requireRestoredScope = true;
      final restarted = WorkspaceController(
        fileService: scopedFiles,
        sessionStore: sessions,
        noteTransactions: tx,
      );
      addTearDown(restarted.dispose);
      addTearDown(scopedFiles.dispose);
      await restarted.initialize();
      expect(restarted.workspaceRoot, '/other');
      expect(
        restarted.documents.map((doc) => doc.path),
        containsAll(['/vault/New.md', '/vault/Origin.md']),
        reason:
            'Each rewritten inode must retain independently restorable access after another workspace is selected.',
      );
    },
  );

  test(
    'cross-workspace external favorite renews token even when note is closed',
    () async {
      files.selectedFolder = '/other';
      await workspace.chooseWorkspaceFolder();
      await workspace.toggleFileFavorite(
        WorkspaceEntry(
          path: '/vault/Old.md',
          name: 'Old.md',
          isDirectory: false,
        ),
      );
      workspace.removeDocument(old);
      workspace.removeDocument(origin);
      files.selectedFolder = '/vault';
      await workspace.chooseWorkspaceFolder();
      final plan = await preview();
      expect((await workspace.executeNoteMove(plan)).completed, isTrue);
      files.selectedFolder = '/other';
      await workspace.chooseWorkspaceFolder();
      await workspace.flushSession();
      expect(
        workspace.browser.preferences.favorites,
        contains('/vault/New.md'),
      );
      final snapshot =
          (workspace.sessionStore as MemoryWorkspaceSessionStore).snapshot!;
      expect(
        snapshot.favoriteAccessTokens['/vault/New.md'],
        'access:/vault/New.md',
      );
      expect(snapshot.favoriteAccessTokens, isNot(contains('/vault/Old.md')));
    },
  );
}
