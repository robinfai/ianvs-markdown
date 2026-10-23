import 'workspace_index_source.dart';
import 'workspace_move_receipt.dart';

/// Read-only observations of app-managed recovery storage, never a receipt or
/// permission to clean up. Null metrics are unknown, not zero or partial sums.
class WorkspaceNoteMoveStorage {
  WorkspaceNoteMoveStorage({
    this.observedComplete = false,
    this.currentRootKnown = false,
    this.globalJournalCount,
    this.globalRecordSlotCount,
    this.globalJournalBytes,
    this.pendingCount,
    this.pendingBytes,
    this.invalidJournalCount,
    this.unknownEntryCount,
    this.unavailableCount,
    this.artifactReservedBytes,
    this.availableBudgetBytes,
    this.currentRootJournalBytes,
    this.currentRootArtifactBytes,
    this.currentRootArtifactAllocatedBytes,
    this.artifactUnknownCount,
    this.recordLimit = 32,
    this.journalByteLimit = 192 * 1024 * 1024,
    this.artifactReservationLimit = 192 * 1024 * 1024,
    List<String> blockers = const [],
    List<WorkspaceNoteMoveStorageRecord> records = const [],
  }) : blockers = List.unmodifiable(blockers),
       records = List.unmodifiable(records);

  final bool observedComplete;
  final bool currentRootKnown;
  final int? globalJournalCount;
  final int? globalRecordSlotCount;
  final int? globalJournalBytes;
  final int? pendingCount;
  final int? pendingBytes;
  final int? invalidJournalCount;
  final int? unknownEntryCount;
  final int? unavailableCount;
  final int? artifactReservedBytes;
  final int? availableBudgetBytes;
  final int? currentRootJournalBytes;
  final int? currentRootArtifactBytes;
  final int? currentRootArtifactAllocatedBytes;
  final int? artifactUnknownCount;
  final int recordLimit;
  final int journalByteLimit;
  final int artifactReservationLimit;
  final List<String> blockers;
  final List<WorkspaceNoteMoveStorageRecord> records;

  bool get storageLimitReached => blockers.any(
    const {
      'journal_record_limit',
      'journal_byte_limit',
      'artifact_reservation_limit',
    }.contains,
  );

  bool get needsReview =>
      !observedComplete ||
      storageLimitReached ||
      (unavailableCount ?? 0) > 0 ||
      (pendingCount ?? 0) > 0 ||
      (invalidJournalCount ?? 0) > 0 ||
      (unknownEntryCount ?? 0) > 0 ||
      (artifactUnknownCount ?? 0) > 0 ||
      records.any(
        (record) =>
            !const {'completed', 'cancelled'}.contains(record.storedPhase) ||
            (record.artifactMissingCount ?? 0) > 0,
      );

  factory WorkspaceNoteMoveStorage.fromMap(Map<Object?, Object?> value) {
    final limits = value['limits'];
    final records = value['records'];
    if (value['observedComplete'] is! bool ||
        value['currentRootKnown'] is! bool ||
        limits is! Map ||
        records is! List ||
        records.length > 32) {
      throw const FormatException('Invalid recovery storage observation.');
    }
    final parsed = [
      for (final record in records)
        if (record is Map)
          WorkspaceNoteMoveStorageRecord.fromMap(record)
        else
          throw const FormatException('Invalid recovery storage record.'),
    ];
    if (parsed.map((record) => record.transactionId).toSet().length !=
        parsed.length) {
      throw const FormatException('Duplicate recovery storage record.');
    }
    return WorkspaceNoteMoveStorage(
      observedComplete: value['observedComplete'] as bool,
      currentRootKnown: value['currentRootKnown'] as bool,
      globalJournalCount: _count(value, 'globalJournalCount'),
      globalRecordSlotCount: _count(value, 'globalRecordSlotCount'),
      globalJournalBytes: _bytes(value, 'globalJournalBytes'),
      pendingCount: _count(value, 'pendingCount'),
      pendingBytes: _bytes(value, 'pendingBytes'),
      invalidJournalCount: _count(value, 'invalidJournalCount'),
      unknownEntryCount: _count(value, 'unknownEntryCount'),
      unavailableCount: _count(value, 'unavailableCount'),
      artifactReservedBytes: _bytes(value, 'artifactReservedBytes'),
      availableBudgetBytes: _bytes(value, 'availableBudgetBytes'),
      currentRootJournalBytes: _bytes(value, 'currentRootJournalBytes'),
      currentRootArtifactBytes: _bytes(value, 'currentRootArtifactBytes'),
      currentRootArtifactAllocatedBytes: _bytes(
        value,
        'currentRootArtifactAllocatedBytes',
      ),
      artifactUnknownCount: _count(value, 'artifactUnknownCount', max: 4096),
      recordLimit: _requiredLimit(limits, 'records', 32),
      journalByteLimit: _requiredLimit(
        limits,
        'journalBytes',
        192 * 1024 * 1024,
      ),
      artifactReservationLimit: _requiredLimit(
        limits,
        'artifactReservedBytes',
        192 * 1024 * 1024,
      ),
      blockers: _codes(value['blockers']),
      records: parsed,
    );
  }
}

class WorkspaceNoteMoveStorageRecord {
  WorkspaceNoteMoveStorageRecord({
    required this.transactionId,
    required this.sourcePath,
    required this.destinationPath,
    required this.entryCount,
    required this.storedPhase,
    this.storedCode,
    this.version = 1,
    this.namespace,
    List<WorkspaceBatchMoveReceipt> namespaces = const [],
    this.journalBytes,
    this.artifactBytes,
    this.allocatedBytes,
    this.artifactCount,
    this.artifactMissingCount,
    this.artifactUnknownCount,
    List<String> blockers = const [],
  }) : namespaces = List.unmodifiable(namespaces),
       blockers = List.unmodifiable(blockers);

  final int version;
  final WorkspaceDirectoryMoveReceipt? namespace;
  final List<WorkspaceBatchMoveReceipt> namespaces;
  final String transactionId;
  final String sourcePath;
  final String destinationPath;
  final int entryCount;
  final String storedPhase;
  final String? storedCode;
  final int? journalBytes;
  final int? artifactBytes;
  final int? allocatedBytes;
  final int? artifactCount;
  final int? artifactMissingCount;
  final int? artifactUnknownCount;
  final List<String> blockers;

  factory WorkspaceNoteMoveStorageRecord.fromMap(Map<Object?, Object?> value) {
    final id = value['transactionId'];
    final version = value['version'] ?? 1;
    final namespace = value['namespace'];
    final namespaces = value['namespaces'];
    final source = value['sourcePath'];
    final destination = value['destinationPath'];
    final phase = value['storedPhase'];
    final code = value['storedCode'];
    final count = _count(value, 'entryCount', max: 128);
    if ((version != 1 && version != 2 && version != 3) ||
        (version == 1 && namespace != null) ||
        (version == 2 && namespace is! Map) ||
        (version != 3 && namespaces != null) ||
        (version == 3 && (namespace != null || namespaces is! List)) ||
        id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        source is! String ||
        destination is! String ||
        !safeWorkspaceRelativePath(source) ||
        !safeWorkspaceRelativePath(destination) ||
        phase is! String ||
        phase.isEmpty ||
        phase.length > 128 ||
        (code != null && (code is! String || code.length > 256)) ||
        count == null ||
        (count == 0 && version == 1) ||
        value['historicalObservation'] != true ||
        value['cleanupSupported'] != false) {
      throw const FormatException(
        'Invalid historical recovery storage record.',
      );
    }
    return WorkspaceNoteMoveStorageRecord(
      transactionId: id,
      version: version as int,
      namespace: namespace is Map
          ? WorkspaceDirectoryMoveReceipt.fromMap(namespace)
          : null,
      namespaces: version == 3
          ? parseWorkspaceBatchReceipts(namespaces)
          : const [],
      sourcePath: source,
      destinationPath: destination,
      entryCount: count,
      storedPhase: phase,
      storedCode: code as String?,
      journalBytes: _bytes(value, 'journalBytes'),
      artifactBytes: _bytes(value, 'artifactBytes'),
      allocatedBytes: _bytes(value, 'allocatedBytes'),
      artifactCount: _count(value, 'artifactCount', max: 128),
      artifactMissingCount: _count(value, 'artifactMissingCount', max: 128),
      artifactUnknownCount: _count(value, 'artifactUnknownCount', max: 128),
      blockers: _codes(value['blockers']),
    );
  }
}

int? _count(Map<Object?, Object?> value, String key, {int max = 256}) =>
    _metric(value[key], max);
int? _bytes(Map<Object?, Object?> value, String key) =>
    _metric(value[key], 0x7fffffffffffffff);
int? _metric(Object? value, int max) {
  if (value == null) return null;
  if (value is! int || value < 0 || value > max) {
    throw const FormatException('Invalid recovery storage metric.');
  }
  return value;
}

int _requiredLimit(Map<Object?, Object?> value, String key, int max) {
  final result = _metric(value[key], max);
  if (result == null || result == 0) {
    throw const FormatException('Invalid recovery storage limit.');
  }
  return result;
}

List<String> _codes(Object? value) {
  if (value is! List ||
      value.length > 32 ||
      value.any(
        (code) =>
            code is! String ||
            !RegExp(r'^[a-z][a-z0-9_]{0,127}$').hasMatch(code),
      )) {
    throw const FormatException('Invalid recovery storage reasons.');
  }
  return value.cast<String>();
}
