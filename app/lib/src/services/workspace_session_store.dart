import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/workspace_layout.dart';
import '../models/reading_preferences.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.documents,
    required this.activeDocumentId,
    required this.workspaceRoot,
    required this.workspaceAccessToken,
    required this.sidebarVisible,
    required this.outlineVisible,
    this.sidebarWidth = WorkspaceLayout.defaultSidebarWidth,
    this.readingPreferences = ReadingPreferences.defaults,
    this.browserState = const {},
    this.collectionViews = const [],
    this.operationGrants = const {},
    this.favoriteAccessTokens = const {},
    this.recoveryNotice,
  });

  factory WorkspaceSnapshot.fromJson(
    Map<String, Object?> json, {
    String? recoveryNotice,
  }) {
    final rawDocuments = json['documents'];
    return WorkspaceSnapshot(
      collectionViews: json['collectionViews'] is List
          ? (json['collectionViews'] as List).whereType<Map>().map((item) => Map<String, Object?>.from(item)).toList()
          : const [],
      recoveryNotice: recoveryNotice,
      readingPreferences: ReadingPreferences.fromJson(
        json['readingPreferences'],
      ),
      browserState: json['browserState'] is Map
          ? Map<String, Object?>.from(json['browserState'] as Map)
          : const {},
      favoriteAccessTokens: json['favoriteAccessTokens'] is Map
          ? Map<String, String>.from(json['favoriteAccessTokens'] as Map)
          : const {},
      operationGrants: json['operationGrants'] is Map
          ? Map<String, String>.from(json['operationGrants'] as Map)
          : const {},
      documents: rawDocuments is List
          ? rawDocuments
                .whereType<Map>()
                .map((item) => Map<String, Object?>.from(item))
                .toList(growable: false)
          : const <Map<String, Object?>>[],
      activeDocumentId: json['activeDocumentId'] as String?,
      workspaceRoot: json['workspaceRoot'] as String?,
      workspaceAccessToken: json['workspaceAccessToken'] as String?,
      sidebarVisible: json['sidebarVisible'] as bool? ?? true,
      outlineVisible: json['outlineVisible'] as bool? ?? true,
      sidebarWidth: WorkspaceLayout.normalizeSidebarWidth(
        switch (json['sidebarWidth']) {
          final num width => width.toDouble(),
          _ => WorkspaceLayout.defaultSidebarWidth,
        },
      ),
    );
  }

  final List<Map<String, Object?>> documents;
  final String? activeDocumentId;
  final String? workspaceRoot;
  final String? workspaceAccessToken;
  final bool sidebarVisible;
  final bool outlineVisible;
  final double sidebarWidth;
  final ReadingPreferences readingPreferences;
  final Map<String, Object?> browserState;
  final List<Map<String, Object?>> collectionViews;
  final Map<String, String> operationGrants;
  final Map<String, String> favoriteAccessTokens;

  /// A load-time warning, deliberately excluded from persisted session data.
  final String? recoveryNotice;

  Map<String, Object?> toJson() => <String, Object?>{
    'browserState': browserState,
    'collectionViews': collectionViews,
    'operationGrants': operationGrants,
    'favoriteAccessTokens': favoriteAccessTokens,
    'documents': documents,
    'activeDocumentId': activeDocumentId,
    'workspaceRoot': workspaceRoot,
    'workspaceAccessToken': workspaceAccessToken,
    'sidebarVisible': sidebarVisible,
    'outlineVisible': outlineVisible,
    'sidebarWidth': sidebarWidth,
    'readingPreferences': readingPreferences.toJson(),
  };
}

abstract class WorkspaceSessionStore {
  Future<WorkspaceSnapshot?> load();

  Future<void> save(WorkspaceSnapshot snapshot);
}

/// Recovery failed without discarding or replacing the existing session files.
class WorkspaceSessionException implements Exception {
  const WorkspaceSessionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$message${cause == null ? '' : ': $cause'}';
}

class DesktopWorkspaceSessionStore implements WorkspaceSessionStore {
  const DesktopWorkspaceSessionStore({this.directory, this.atomicReplace});

  /// Optional isolated storage for diagnostic sessions; normal hosts omit it.
  final Directory? directory;

  /// Fault-injection seam. Replacements must rename atomically or throw without
  /// modifying the destination; never implement an in-place write fallback.
  final Future<void> Function(File temporary, File destination)? atomicReplace;

  Future<File> _sessionFile() async {
    final support = directory ?? await getApplicationSupportDirectory();
    return File(p.join(support.path, 'ianvs-markdown', 'workspace.json'));
  }

  @override
  Future<WorkspaceSnapshot?> load() async {
    final target = await _sessionFile();
    final primary = await _readRecord(target);
    if (primary.snapshot != null) return primary.snapshot;
    final backup = await _readRecord(File('${target.path}.bak'));
    if (backup.snapshot != null) {
      // Loading is read-only. A later save must preserve any corrupt original
      // before repairing it, and cannot replace an unreadable original at all.
      return _decodeSnapshot(
        backup.bytes!,
        recoveryNotice:
            'Recovered the workspace from the last valid backup. '
            'Newer recovery data was missing or could not be read, so recent '
            'edits may be missing. Any damaged original data is preserved.',
      );
    }
    if (!primary.exists && !backup.exists) return null;
    throw WorkspaceSessionException(
      'Unable to load workspace recovery. Existing files were left untouched',
      cause: primary.error ?? backup.error,
    );
  }

  @override
  Future<void> save(WorkspaceSnapshot snapshot) async {
    // Encode once before any asynchronous work, then validate exactly the data
    // that will reach disk. Bad in-memory data must not replace a good recovery.
    final bytes = utf8.encode(jsonEncode(snapshot.toJson()));
    _decodeSnapshot(bytes);
    final target = await _sessionFile();
    final backupFile = File('${target.path}.bak');
    final primary = await _readRecord(target);
    final backup = await _readRecord(backupFile);
    for (final record in [primary, backup]) {
      if (record.error != null && record.bytes == null) {
        throw WorkspaceSessionException(
          'Unable to read ${record.file.path}; recovery files were not replaced',
          cause: record.error,
        );
      }
    }
    if (primary.snapshot == null &&
        backup.snapshot == null &&
        (primary.exists || backup.exists)) {
      throw WorkspaceSessionException(
        'No valid workspace recovery remains; damaged originals were not replaced',
        cause: primary.error ?? backup.error,
      );
    }
    await target.parent.create(recursive: true);
    for (final record in [primary, backup]) {
      if (record.error != null) await _preserveCorrupt(record);
    }

    // Keep the previous complete primary as backup, never corrupt bytes. On a
    // first save, create a recoverable backup before installing the primary.
    final backupBytes = primary.snapshot != null
        ? primary.bytes!
        : backup.snapshot != null
        ? backup.bytes!
        : bytes;
    if (!_sameBytes(backup.bytes, backupBytes)) {
      await _replaceBytes(backupFile, backupBytes);
    }
    await _replaceBytes(target, bytes);
  }

  Future<_SessionRecord> _readRecord(File file) async {
    List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (error) {
      // exists() alone also reports false for some inaccessible paths. Only a
      // real ENOENT plus a missing directory entry means a fresh installation.
      final code = error.osError?.errorCode;
      final missing = code == 2 || (Platform.isWindows && code == 3);
      if (missing &&
          await FileSystemEntity.type(file.path, followLinks: false) ==
              FileSystemEntityType.notFound) {
        return _SessionRecord(file);
      }
      return _SessionRecord(file, error: error);
    }
    try {
      return _SessionRecord(
        file,
        bytes: bytes,
        snapshot: _decodeSnapshot(bytes),
      );
    } on FormatException catch (error) {
      return _SessionRecord(file, bytes: bytes, error: error);
    }
  }

  Future<void> _preserveCorrupt(_SessionRecord record) async {
    final archive = await record.file.parent.createTemp(
      '${p.basename(record.file.path)}.corrupt-',
    );
    try {
      await File(
        p.join(archive.path, 'original'),
      ).writeAsBytes(record.bytes!, flush: true);
    } catch (_) {
      await _removeStaging(archive);
      rethrow;
    }
  }

  Future<void> _replaceBytes(File target, List<int> bytes) async {
    // A unique same-filesystem staging directory prevents accidental reuse of
    // partial files from a prior crash. Flush before the sole replacement step.
    final staging = await target.parent.createTemp(
      '.${p.basename(target.path)}.staging-',
    );
    try {
      final temporary = File(p.join(staging.path, 'snapshot'));
      await temporary.writeAsBytes(bytes, flush: true);
      final replace = atomicReplace;
      if (replace == null) {
        await temporary.rename(target.path);
      } else {
        await replace(temporary, target);
      }
    } finally {
      await _removeStaging(staging);
    }
  }

  Future<void> _removeStaging(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Cleanup cannot turn a successful commit into a reported failed save.
      // A leftover staging file is never treated as a recoverable snapshot.
    }
  }
}

class _SessionRecord {
  const _SessionRecord(this.file, {this.bytes, this.snapshot, this.error});

  final File file;
  final List<int>? bytes;
  final WorkspaceSnapshot? snapshot;
  final Object? error;

  bool get exists => bytes != null || error != null;
}

bool _sameBytes(List<int>? left, List<int> right) {
  if (left == null || left.length != right.length) return false;
  for (var index = 0; index < right.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

WorkspaceSnapshot _decodeSnapshot(List<int> bytes, {String? recoveryNotice}) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Workspace recovery must be a JSON object');
  }
  final documents = decoded['documents'];
  if (documents is! List) {
    throw const FormatException('Workspace recovery must contain documents');
  }
  final ids = <String>{};
  for (final document in documents) {
    if (document is! Map<String, Object?>) {
      throw const FormatException('Invalid document recovery record');
    }
    for (final key in ['id', 'name', 'text', 'persistedText']) {
      final value = document[key];
      if (value is! String ||
          ((key == 'id' || key == 'name') && value.isEmpty)) {
        throw FormatException('Invalid document recovery field: $key');
      }
    }
    if (!ids.add(document['id'] as String)) {
      throw const FormatException('Duplicate document recovery ID');
    }
    for (final key in [
      'path',
      'accessToken',
      'encoding',
      'lineEnding',
      'mode',
    ]) {
      if (document[key] != null && document[key] is! String) {
        throw FormatException('Invalid document recovery field: $key');
      }
    }
    if (document['mode'] != null &&
        !['source', 'livePreview', 'preview'].contains(document['mode'])) {
      throw const FormatException('Unknown document recovery mode');
    }
  }
  for (final key in [
    'activeDocumentId',
    'workspaceRoot',
    'workspaceAccessToken',
  ]) {
    if (decoded[key] != null && decoded[key] is! String) {
      throw FormatException('Invalid workspace recovery field: $key');
    }
  }
  final activeId = decoded['activeDocumentId'];
  if (activeId != null && !ids.contains(activeId)) {
    throw const FormatException('Active document recovery ID is missing');
  }
  for (final key in ['sidebarVisible', 'outlineVisible']) {
    if (decoded[key] != null && decoded[key] is! bool) {
      throw FormatException('Invalid workspace recovery field: $key');
    }
  }
  for (final key in [
    'browserState',
    'favoriteAccessTokens',
    'operationGrants',
  ]) {
    final value = decoded[key];
    if (value != null && value is! Map<String, Object?>) {
      throw FormatException('Invalid workspace recovery field: $key');
    }
    if (key != 'browserState' &&
        value is Map &&
        value.values.any((item) => item is! String)) {
      throw FormatException('Invalid workspace recovery field: $key');
    }
  }
  return WorkspaceSnapshot.fromJson(decoded, recoveryNotice: recoveryNotice);
}
