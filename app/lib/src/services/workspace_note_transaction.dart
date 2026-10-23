import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'apple_workspace_service.dart';
import 'workspace_index_source.dart';
import 'workspace_note_move_plan.dart';
import 'workspace_note_move_storage.dart';
import 'workspace_move_receipt.dart';

export 'workspace_note_move_storage.dart';
export 'workspace_move_receipt.dart';

/// A receipt is evidence about one native observation, not an ACID guarantee.
class WorkspaceNoteMoveReceipt {
  const WorkspaceNoteMoveReceipt({
    required this.path,
    required this.destinationPath,
    required this.state,
    this.actualPath,
    this.revision,
    this.verified = false,
  });
  final String path;
  final String destinationPath;
  final String state;
  final String? actualPath;
  final String? revision;
  final bool verified;

  bool get applied => verified && const {'applied', 'moved'}.contains(state);
  bool get unchanged =>
      verified &&
      (state == 'pending' || state == 'original') &&
      actualPath == path &&
      revision != null &&
      revision!.isNotEmpty;

  factory WorkspaceNoteMoveReceipt.fromMap(Map<Object?, Object?> value) {
    final path = value['path'];
    final destination = value['destinationPath'];
    final state = value['state'];
    final actual = value['actualPath'];
    final revision = value['revision'];
    if (path is! String ||
        destination is! String ||
        state is! String ||
        !safeWorkspaceRelativePath(path) ||
        !safeWorkspaceRelativePath(destination) ||
        (actual != null &&
            (actual is! String || !safeWorkspaceRelativePath(actual))) ||
        (revision != null && revision is! String)) {
      throw const FormatException('Invalid note move receipt.');
    }
    return WorkspaceNoteMoveReceipt(
      path: path,
      destinationPath: destination,
      state: state,
      actualPath: actual as String?,
      revision: revision as String?,
      verified: value['verified'] == true,
    );
  }
}

class WorkspaceNoteMoveArtifact {
  const WorkspaceNoteMoveArtifact(this.path, this.state, this.verified);
  final String path;
  final String state;
  final bool verified;
}

class WorkspaceNoteRecoveryReceipt {
  const WorkspaceNoteRecoveryReceipt(this.sourcePath, this.path, this.state);
  final String sourcePath;
  final String path;
  final String state;
}

class WorkspaceNoteMoveRecord {
  WorkspaceNoteMoveRecord({
    required this.transactionId,
    required this.phase,
    required List<WorkspaceNoteMoveReceipt> entries,
    this.token,
    this.version = 1,
    this.namespace,
    List<WorkspaceBatchMoveReceipt> namespaces = const [],
    this.code,
    this.message,
    this.retryAllowed = false,
    List<String> recoveryPaths = const [],
    List<WorkspaceNoteMoveArtifact> retainedArtifacts = const [],
    List<WorkspaceNoteRecoveryReceipt> recoveryEntries = const [],
  }) : namespaces = List.unmodifiable(namespaces),
       entries = List.unmodifiable(entries),
       recoveryPaths = List.unmodifiable(recoveryPaths),
       retainedArtifacts = List.unmodifiable(retainedArtifacts),
       recoveryEntries = List.unmodifiable(recoveryEntries);

  final String transactionId;
  final int version;
  final WorkspaceDirectoryMoveReceipt? namespace;
  final List<WorkspaceBatchMoveReceipt> namespaces;
  final String phase;
  final String? token;
  final String? code;
  final String? message;
  final bool retryAllowed;
  final List<WorkspaceNoteMoveReceipt> entries;
  final List<String> recoveryPaths;
  final List<WorkspaceNoteMoveArtifact> retainedArtifacts;
  final List<WorkspaceNoteRecoveryReceipt> recoveryEntries;
  bool get completed =>
      phase == 'completed' &&
      ((version == 1 &&
              namespace == null &&
              namespaces.isEmpty &&
              entries.isNotEmpty) ||
          (version == 2 &&
              namespaces.isEmpty &&
              namespace?.completed == true) ||
          (version == 3 &&
              namespace == null &&
              namespaces.length >= 2 &&
              namespaces.length <= 8 &&
              namespaces.map((r) => r.sourcePath).toSet().length ==
                  namespaces.length &&
              namespaces.map((r) => r.destinationPath).toSet().length ==
                  namespaces.length &&
              namespaces.every((r) => r.completed))) &&
      entries.map((entry) => entry.path).toSet().length == entries.length &&
      entries.every(
        (entry) =>
            entry.applied &&
            entry.actualPath == entry.destinationPath &&
            entry.revision != null &&
            entry.revision!.isNotEmpty,
      );
  bool get uncertain => phase == 'uncertain' || phase == 'partial';

  factory WorkspaceNoteMoveRecord.fromMap(Map<Object?, Object?> value) {
    final id = value['transactionId'];
    final version = value['version'] ?? 1;
    final namespace = value['namespace'];
    final namespaces = value['namespaces'];
    final phase = value['phase'];
    final entries = value['entries'];
    final copies = value['recoveryPaths'] ?? const <Object?>[];
    final artifacts = value['retainedArtifacts'] ?? const <Object?>[];
    final recoveryEntries = value['recoveryEntries'] ?? const <Object?>[];
    if ((version != 1 && version != 2 && version != 3) ||
        (version != 3 && namespaces != null) ||
        (version == 3 && (namespace != null || namespaces is! List)) ||
        (version == 1 && namespace != null) ||
        (version == 2 && namespace is! Map) ||
        id is! String ||
        !_validId(id) ||
        phase is! String ||
        entries is! List ||
        entries.length > 128 ||
        copies is! List ||
        copies.length > 128 ||
        artifacts is! List ||
        artifacts.length > 128 ||
        recoveryEntries is! List ||
        recoveryEntries.length > 128 ||
        copies.any((p) => p is! String || !safeWorkspaceRelativePath(p)) ||
        value['token'] != null && value['token'] is! String ||
        value['code'] != null && value['code'] is! String ||
        value['message'] != null && value['message'] is! String ||
        value['retryAllowed'] != null && value['retryAllowed'] is! bool) {
      throw const FormatException('Invalid note move journal response.');
    }
    return WorkspaceNoteMoveRecord(
      transactionId: id,
      version: version as int,
      namespace: namespace is Map
          ? WorkspaceDirectoryMoveReceipt.fromMap(namespace)
          : null,
      namespaces: version == 3
          ? parseWorkspaceBatchReceipts(namespaces)
          : const [],
      phase: phase,
      entries: [
        for (final entry in entries)
          if (entry is Map)
            WorkspaceNoteMoveReceipt.fromMap(entry)
          else
            throw const FormatException('Invalid note move journal entry.'),
      ],
      token: value['token'] as String?,
      code: value['code'] as String?,
      message: value['message'] as String?,
      retryAllowed: value['retryAllowed'] == true,
      recoveryPaths: copies.cast<String>(),
      retainedArtifacts: [
        for (final artifact in artifacts)
          if (artifact is Map &&
              artifact['path'] is String &&
              _validArtifactPath(artifact['path'] as String, id) &&
              artifact['state'] is String)
            WorkspaceNoteMoveArtifact(
              artifact['path'] as String,
              artifact['state'] as String,
              artifact['verified'] == true,
            )
          else
            throw const FormatException('Invalid retained recovery artifact.'),
      ],
      recoveryEntries: [
        for (final entry in recoveryEntries)
          if (entry is Map &&
              entry['path'] is String &&
              entry['sourcePath'] is String &&
              entry['state'] is String &&
              safeWorkspaceRelativePath(entry['path'] as String) &&
              safeWorkspaceRelativePath(entry['sourcePath'] as String))
            WorkspaceNoteRecoveryReceipt(
              entry['sourcePath'] as String,
              entry['path'] as String,
              entry['state'] as String,
            )
          else
            throw const FormatException(
              'Invalid original-copy recovery receipt.',
            ),
      ],
    );
  }
}

/// A missing/lost platform reply never means that a mutation did not happen.
class WorkspaceNoteMoveJournalList {
  const WorkspaceNoteMoveJournalList({
    this.transactions = const [],
    this.unavailableRecords = 0,
    this.retainedBytes = 0,
    this.storageBlocked = false,
  });
  final List<WorkspaceNoteMoveRecord> transactions;
  final int unavailableRecords;
  final int retainedBytes;
  final bool storageBlocked;
}

class WorkspaceNoteMoveUncertain implements Exception {
  const WorkspaceNoteMoveUncertain(this.transactionId, this.cause);
  final String transactionId;
  final Object cause;
  @override
  String toString() =>
      'The note move outcome is unknown. Review journal $transactionId before retrying.';
}

abstract interface class WorkspaceNoteTransactionStore {
  Future<WorkspaceNoteMoveRecord> prepare(
    WorkspaceNoteMovePlan plan,
    String transactionId,
  );
  Future<WorkspaceNoteMoveRecord> execute(
    String root,
    String transactionId,
    String token,
  );
  Future<WorkspaceNoteMoveRecord> cancelPrepared(
    String root,
    String transactionId,
    String token,
  );
  Future<WorkspaceNoteMoveStorage> inspectStorage(String root);
  Future<WorkspaceNoteMoveJournalList> list(String root);
  Future<WorkspaceNoteMoveRecord> reconcile(String root, String transactionId);
  Future<WorkspaceNoteMoveRecord> recoverCopies(
    String root,
    String transactionId,
    String relativeDirectory,
  );
}

class AppleWorkspaceNoteTransactionStore
    implements WorkspaceNoteTransactionStore {
  const AppleWorkspaceNoteTransactionStore({
    this.channel = AppleWorkspaceService.channel,
  });
  final MethodChannel channel;

  @override
  Future<WorkspaceNoteMoveRecord> prepare(
    WorkspaceNoteMovePlan plan,
    String transactionId,
  ) async {
    if (!plan.executionSupported ||
        !plan.complete ||
        plan.root == null ||
        !_validId(transactionId)) {
      throw StateError('Only a complete exact preview can be prepared.');
    }
    final metadata = {
      for (final entry in plan.snapshot.catalog.entries)
        entry.relativePath: entry,
    };
    if ((plan.files.isEmpty &&
            plan.kind == WorkspaceNoteMovePlanKind.singleNote) ||
        plan.files.length > 128 ||
        metadata.length > 50000) {
      throw StateError('The note move exceeds its bounded journal limits.');
    }
    var bytes = 0;
    final files = <Map<String, Object>>[];
    final paths = <String>{};
    for (final file in plan.files) {
      final before = Uint8List.fromList(utf8.encode(file.source.text));
      final after = Uint8List.fromList(utf8.encode(file.contents));
      bytes += before.length + after.length;
      final disk = metadata[file.path];
      if (bytes > 32 * 1024 * 1024 ||
          !paths.add(file.path) ||
          !safeWorkspaceRelativePath(file.path) ||
          !safeWorkspaceRelativePath(file.destination) ||
          disk == null ||
          disk.isDirectory ||
          !disk.local ||
          disk.revision.isEmpty) {
        throw StateError(
          'The affected note lacks a bounded local disk baseline.',
        );
      }
      files.add({
        'path': file.path,
        'destinationPath': file.destination,
        'expectedRevision': disk.revision,
        'expectedBytes': before,
        'replacementBytes': after,
      });
    }
    final directory = plan.kind == WorkspaceNoteMovePlanKind.directory;
    final batch = plan.kind == WorkspaceNoteMovePlanKind.batch;
    final roots = [...plan.batchRoots]
      ..sort((a, b) => a.source.compareTo(b.source));
    return _call(
      batch
          ? 'prepareWorkspaceBatchMove'
          : directory
          ? 'prepareWorkspaceDirectoryMove'
          : 'prepareWorkspaceNoteMove',
      {
        if (directory) 'tree': plan.treeSnapshot!.toNative(),
        if (batch)
          'roots': [
            for (final root in roots)
              {
                'sourcePath': root.source,
                'destinationPath': root.destination,
                'kind': root.isDirectory ? 'directory' : 'note',
                if (root.tree != null) 'tree': root.tree!.toNative(),
              },
          ],
        'path': plan.root!,
        'transactionId': transactionId,
        'sourcePath': plan.sourcePath,
        'destinationPath': plan.destinationPath,
        'files': files,
        'assets': [
          for (final asset in plan.attachmentRequirements)
            {'path': asset.relativePath, 'revision': asset.revision},
        ],
        'catalog': [
          for (final entry in metadata.values)
            {
              'path': entry.relativePath,
              'revision': entry.revision,
              'isDirectory': entry.isDirectory,
              'local': entry.local,
            },
        ],
      },
    );
  }

  @override
  Future<WorkspaceNoteMoveRecord> execute(
    String root,
    String transactionId,
    String token,
  ) => _call('executeWorkspaceNoteMove', {
    'path': root,
    'transactionId': transactionId,
    'token': token,
  });

  @override
  Future<WorkspaceNoteMoveRecord> cancelPrepared(
    String root,
    String transactionId,
    String token,
  ) => _call('cancelPreparedWorkspaceNoteMove', {
    'path': root,
    'transactionId': transactionId,
    'token': token,
  });

  @override
  Future<WorkspaceNoteMoveStorage> inspectStorage(String root) async {
    if (!root.startsWith('/') || root.contains('\u0000')) {
      throw const FormatException('Invalid recovery storage scope.');
    }
    final result = await channel.invokeMapMethod<Object?, Object?>(
      'inspectWorkspaceNoteMoveStorage',
      {'path': root},
    );
    if (result == null) {
      throw const FormatException('Recovery storage could not be observed.');
    }
    return WorkspaceNoteMoveStorage.fromMap(result);
  }

  @override
  Future<WorkspaceNoteMoveJournalList> list(String root) async {
    final result = await channel.invokeMapMethod<Object?, Object?>(
      'listWorkspaceNoteMoves',
      {'path': root},
    );
    final values = result?['transactions'];
    final unavailable = result?['unavailableRecords'];
    final retained = result?['retainedBytes'];
    if (values is! List ||
        values.length > 32 ||
        unavailable is! int ||
        unavailable < 0 ||
        retained is! int ||
        retained < 0 ||
        result?['storageBlocked'] is! bool) {
      throw const FormatException(
        'The retained note-move journals could not be verified. No recovery data was discarded.',
      );
    }
    return WorkspaceNoteMoveJournalList(
      transactions: List.unmodifiable([
        for (final value in values)
          if (value is Map)
            WorkspaceNoteMoveRecord.fromMap(value)
          else
            throw const FormatException('Invalid note move journal summary.'),
      ]),
      unavailableRecords: unavailable,
      retainedBytes: retained,
      storageBlocked: result!['storageBlocked'] as bool,
    );
  }

  @override
  Future<WorkspaceNoteMoveRecord> reconcile(
    String root,
    String transactionId,
  ) => _call('reconcileWorkspaceNoteMove', {
    'path': root,
    'transactionId': transactionId,
  });

  @override
  Future<WorkspaceNoteMoveRecord> recoverCopies(
    String root,
    String transactionId,
    String relativeDirectory,
  ) {
    if (!safeWorkspaceRelativePath(relativeDirectory, directory: true)) {
      throw ArgumentError.value(relativeDirectory, 'relativeDirectory');
    }
    return _call('recoverWorkspaceNoteMove', {
      'path': root,
      'transactionId': transactionId,
      'relativeDirectory': relativeDirectory,
    });
  }

  Future<WorkspaceNoteMoveRecord> _call(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final id = arguments['transactionId'];
    final root = arguments['path'];
    if (id is! String ||
        !_validId(id) ||
        root is! String ||
        !root.startsWith('/') ||
        root.contains('\u0000')) {
      throw const FormatException(
        'Invalid note-move scope or journal identity.',
      );
    }
    final result = await channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    if (result == null) {
      throw const FormatException(
        'The note move journal reply is unavailable.',
      );
    }
    final record = WorkspaceNoteMoveRecord.fromMap(result);
    if (record.transactionId != arguments['transactionId']) {
      throw const FormatException('The note move journal identity changed.');
    }
    return record;
  }
}

bool _validId(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

String newWorkspaceNoteTransactionId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final text = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
      '${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
}

bool _validArtifactPath(String path, String transactionId) {
  final parts = path.split('/');
  if (parts.isEmpty || path.length > 4096) return false;
  final parent = parts.take(parts.length - 1).join('/');
  return safeWorkspaceRelativePath(parent, directory: true) &&
      RegExp(
        '^\\.linefold-note-move-${RegExp.escape(transactionId)}-[0-9]{1,3}\\.md\$',
      ).hasMatch(parts.last);
}
