import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'workspace_index_source.dart';

/// A source revision is independent of save baselines and cursor/selection.
class WorkspaceNoteSnapshot {
  const WorkspaceNoteSnapshot({
    required this.key,
    required this.path,
    required this.name,
    required this.text,
    required this.revision,
    this.sessionId,
    this.externalConflict = false,
  });
  final String key;
  final String? path;
  final String name;
  final String text;
  final String revision;
  final String? sessionId;
  final bool externalConflict;
  bool get fromBuffer => sessionId != null;
}

class _DirectoryTask {
  late final Future<WorkspaceDirectorySnapshot> future;
  bool refreshAgain = false;
}

/// Session-owned catalog and bounded source cache shared by tree and search.
/// No database, global cache, eager body preload, or provider downloads.
class WorkspaceIndex extends ChangeNotifier {
  WorkspaceIndex({
    required this.source,
    this.maximumCacheBytes = 32 * 1024 * 1024,
    this.maximumEntries = 50000,
  });
  final WorkspaceIndexSource source;
  final int maximumCacheBytes;
  final int maximumEntries;
  String? _root;
  int _epoch = 0;
  bool _disposed = false;
  final _directories = <String, WorkspaceDirectorySnapshot>{};
  final _entries = <String, WorkspaceMetadata>{};
  final _listedAt = <String, DateTime>{};
  final _directoryTasks = <String, _DirectoryTask>{};
  final _directoryVersions = <String, int>{};
  int _metadataEntries = 0;
  final _textTasks = <String, Future<WorkspaceNoteSnapshot>>{};
  final _bodies = <String, WorkspaceNoteSnapshot>{};
  final _overlays = <String, WorkspaceNoteSnapshot>{};
  final _overlayRevisions = <String, int>{};
  int _cacheBytes = 0;
  int _contentRevision = 0;
  int _catalogRevision = 0;
  int _reads = 0;
  final _readWaiters = Queue<Completer<void>>();
  String? get root => _root;
  int get epoch => _epoch;
  int get contentRevision => _contentRevision;
  int get catalogRevision => _catalogRevision;
  int get cachedBytes => _cacheBytes;
  int get cachedDocuments => _bodies.length;
  int get indexedDirectories => _directories.length;
  List<WorkspaceNoteSnapshot> get buffers =>
      List.unmodifiable(_overlays.values);
  WorkspaceDirectorySnapshot? cachedDirectory(String relativePath) =>
      _directories[relativePath];

  void configure(String? root) {
    if (_disposed || _root == root) return;
    if (root != null &&
        (!p.posix.isAbsolute(root) ||
            p.posix.normalize(root) != root ||
            root.contains('\u0000'))) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.denied);
    }
    _root = root;
    ++_epoch;
    _directories.clear();
    _entries.clear();
    _listedAt.clear();
    _directoryTasks.clear();
    _directoryVersions.clear();
    _metadataEntries = 0;
    _textTasks.clear();
    _bodies.clear();
    _cacheBytes = 0;
    ++_catalogRevision;
    _emit();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _check(int epoch) {
    if (_disposed || epoch != _epoch) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.cancelled);
    }
  }

  String relativeDirectory(String absolutePath) {
    final root = _root;
    if (root == null ||
        (absolutePath != root && !p.posix.isWithin(root, absolutePath))) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.denied);
    }
    return absolutePath == root
        ? ''
        : p.posix.relative(absolutePath, from: root);
  }

  Future<WorkspaceDirectorySnapshot> directory(
    String relativePath, {
    bool refresh = false,
    bool reconcile = false,
  }) {
    if (_disposed ||
        _root == null ||
        !safeWorkspaceRelativePath(relativePath, directory: true)) {
      return Future.error(
        const WorkspaceIndexFailure(WorkspaceReadIssue.denied),
      );
    }
    final running = _directoryTasks[relativePath];
    if (running != null) {
      if (refresh) running.refreshAgain = true;
      return running.future;
    }
    final cached = _directories[relativePath];
    final recent = _listedAt[relativePath];
    if (!refresh &&
        cached != null &&
        (!reconcile ||
            (recent != null &&
                DateTime.now().difference(recent) <
                    const Duration(seconds: 2)))) {
      return Future.value(cached);
    }
    final epoch = _epoch;
    final version = _directoryVersions[relativePath] ?? 0;
    final root = _root!;
    final task = _DirectoryTask();
    _directoryTasks[relativePath] = task;
    task.future = () async {
      try {
        while (true) {
          task.refreshAgain = false;
          final result = await source.listWorkspaceDirectory(
            root,
            relativePath,
          );
          _check(epoch);
          if ((_directoryVersions[relativePath] ?? 0) != version) {
            throw const WorkspaceIndexFailure(WorkspaceReadIssue.changed);
          }
          if (result.entries.length > maximumEntries) {
            throw const WorkspaceIndexFailure(WorkspaceReadIssue.limit);
          }
          for (final entry in result.entries) {
            final parent = p.posix.dirname(entry.relativePath);
            if (!safeWorkspaceRelativePath(entry.relativePath) ||
                (parent == '.' ? '' : parent) != relativePath ||
                (!entry.isDirectory && !isMarkdownName(entry.relativePath))) {
              throw const WorkspaceIndexFailure(WorkspaceReadIssue.denied);
            }
          }
          if (task.refreshAgain) continue;
          final old = _directories[relativePath];
          final entries = {
            if (!result.complete && old != null)
              for (final entry in old.entries) entry.relativePath: entry,
            for (final entry in result.entries) entry.relativePath: entry,
          };
          final available =
              maximumEntries - _metadataEntries + (old?.entries.length ?? 0);
          final limited = entries.length > available;
          final snapshot = WorkspaceDirectorySnapshot(
            List.unmodifiable(entries.values.take(available)),
            complete: result.complete && !limited,
            reason: limited ? 'Metadata cache limit' : result.reason,
          );
          _metadataEntries +=
              snapshot.entries.length - (old?.entries.length ?? 0);
          if (old != null) {
            for (final entry in old.entries) {
              _entries.remove(entry.relativePath);
            }
          }
          for (final entry in snapshot.entries) {
            _entries[entry.relativePath] = entry;
          }
          _directories[relativePath] = snapshot;
          _listedAt[relativePath] = DateTime.now();
          if (old != null) {
            final current = {
              for (final e in snapshot.entries) e.relativePath: e,
            };
            for (final previous in old.entries) {
              if (current[previous.relativePath]?.revision !=
                  previous.revision) {
                _evictBody(previous.relativePath);
              }
              final next = current[previous.relativePath];
              if (previous.isDirectory &&
                  ((snapshot.complete && next == null) ||
                      (next != null &&
                          (!next.isDirectory ||
                              next.revision != previous.revision)))) {
                _evictDirectory(previous.relativePath);
              }
            }
          }
          ++_catalogRevision;
          _emit();
          return snapshot;
        }
      } finally {
        if (identical(_directoryTasks[relativePath], task)) {
          _directoryTasks.remove(relativePath);
        }
      }
    }();
    return task.future;
  }

  void _evictBody(String relativePath) {
    for (final key
        in _bodies.keys
            .where((key) => key.startsWith('$relativePath\u0000'))
            .toList()) {
      _cacheBytes -= _bodies.remove(key)!.text.length * 2;
    }
  }

  void _evictDirectory(String path) {
    for (final key in {
      path,
      ..._directories.keys,
      ..._directoryTasks.keys,
    }.where((key) => key == path || p.posix.isWithin(path, key)).toList()) {
      _directoryVersions[key] = (_directoryVersions[key] ?? 0) + 1;
      _directoryTasks.remove(key);
      final old = _directories.remove(key);
      if (old != null) {
        _metadataEntries -= old.entries.length;
        for (final entry in old.entries) {
          _evictBody(entry.relativePath);
          _entries.remove(entry.relativePath);
        }
      }
      _listedAt.remove(key);
    }
  }

  /// Watchers are hints, never authoritative changes. Reconciliation and source
  /// identities decide what changed; duplicate hints only coalesce more work.
  void invalidateDirectory(String relativePath) {
    if (_disposed || _root == null) return;
    _listedAt.remove(relativePath);
    ++_contentRevision;
    _emit();
  }

  bool _metadataStillCurrent(WorkspaceMetadata entry) {
    final parent = p.posix.dirname(entry.relativePath);
    final key = parent == '.' ? '' : parent;
    final directory = _directories[key];
    // An evicted directory is not an unlisted directory. Keep its tombstone
    // until a fresh listing arrives, so in-flight descendants cannot return.
    if (directory == null) return !_directoryVersions.containsKey(key);
    return _entries[entry.relativePath]?.revision == entry.revision;
  }

  void updateBuffer({
    required String sessionId,
    required String? path,
    required String name,
    required String text,
    bool externalConflict = false,
  }) {
    if (_disposed) return;
    final old = _overlays[sessionId];
    if (old != null &&
        old.text == text &&
        old.path == path &&
        old.name == name &&
        old.externalConflict == externalConflict) {
      return;
    }
    final revision = (_overlayRevisions[sessionId] ?? 0) + 1;
    _overlayRevisions[sessionId] = revision;
    _overlays[sessionId] = WorkspaceNoteSnapshot(
      key: path ?? 'draft:$sessionId',
      path: path,
      name: name,
      text: text,
      revision: 'buffer:$sessionId:$revision',
      sessionId: sessionId,
      externalConflict: externalConflict,
    );
    ++_contentRevision;
    _emit();
  }

  void removeBuffer(String sessionId) {
    if (_overlays.remove(sessionId) != null) {
      ++_contentRevision;
      _emit();
    }
  }

  WorkspaceNoteSnapshot? bufferForPath(String path) {
    for (final buffer in _overlays.values) {
      if (buffer.path == path) return buffer;
    }
    return null;
  }

  WorkspaceNoteSnapshot? bufferForSession(String id) => _overlays[id];

  Future<void> _acquireRead() async {
    if (_reads < 2) {
      ++_reads;
      return;
    }
    final waiter = Completer<void>();
    _readWaiters.add(waiter);
    await waiter.future;
  }

  void _releaseRead() {
    if (_readWaiters.isEmpty) {
      --_reads;
    } else {
      _readWaiters.removeFirst().complete();
    }
  }

  Future<WorkspaceNoteSnapshot> read(WorkspaceMetadata entry) {
    final root = _root;
    if (_disposed ||
        root == null ||
        entry.isDirectory ||
        !safeWorkspaceRelativePath(entry.relativePath) ||
        !isMarkdownName(entry.relativePath)) {
      return Future.error(
        const WorkspaceIndexFailure(WorkspaceReadIssue.denied),
      );
    }
    if (!_metadataStillCurrent(entry)) {
      return Future.error(
        const WorkspaceIndexFailure(WorkspaceReadIssue.changed),
      );
    }
    final absolute = p.posix.join(root, entry.relativePath);
    final overlay = bufferForPath(absolute);
    if (overlay != null) return Future.value(overlay);
    if (!entry.local) {
      return Future.error(
        const WorkspaceIndexFailure(WorkspaceReadIssue.offline),
      );
    }
    if (entry.size > workspaceTextMaximumBytes) {
      return Future.error(
        const WorkspaceIndexFailure(WorkspaceReadIssue.oversized),
      );
    }
    final parent = p.posix.dirname(entry.relativePath);
    final directoryKey = parent == '.' ? '' : parent;
    final directoryVersion = _directoryVersions[directoryKey] ?? 0;
    final key =
        '${entry.relativePath}\u0000${entry.revision}\u0000$directoryVersion';
    final cached = _bodies.remove(key);
    if (cached != null) {
      _bodies[key] = cached;
      return Future.value(cached);
    }
    if (_textTasks[key] case final running?) return running;
    final epoch = _epoch;
    late final Future<WorkspaceNoteSnapshot> task;
    task = () async {
      await _acquireRead();
      try {
        _check(epoch);
        final value = await source.readWorkspaceText(
          root,
          entry.relativePath,
          workspaceTextMaximumBytes,
        );
        _check(epoch);
        final buffer = bufferForPath(absolute);
        if (buffer != null) return buffer;
        // Metadata is only a hint. A snapshot whose identity changed during
        // enumeration is not silently cached under the earlier disk stamp.
        if (value.revision != entry.revision ||
            (_directoryVersions[directoryKey] ?? 0) != directoryVersion ||
            !_metadataStillCurrent(entry)) {
          throw const WorkspaceIndexFailure(WorkspaceReadIssue.changed);
        }
        if (value.text.length * 2 > workspaceTextMaximumBytes * 2) {
          throw const WorkspaceIndexFailure(WorkspaceReadIssue.oversized);
        }
        final result = WorkspaceNoteSnapshot(
          key: absolute,
          path: absolute,
          name: p.posix.basename(absolute),
          text: value.text,
          revision: 'disk:${value.revision}',
        );
        final bytes = value.text.length * 2;
        if (bytes <= maximumCacheBytes) {
          while (_cacheBytes + bytes > maximumCacheBytes &&
              _bodies.isNotEmpty) {
            _cacheBytes -= _bodies.remove(_bodies.keys.first)!.text.length * 2;
          }
          _bodies[key] = result;
          _cacheBytes += bytes;
        }
        return result;
      } finally {
        _releaseRead();
        if (identical(_textTasks[key], task)) _textTasks.remove(key);
      }
    }();
    _textTasks[key] = task;
    return task;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _bodies.clear();
    _overlays.clear();
    _directories.clear();
    _entries.clear();
    super.dispose();
  }
}

bool isMarkdownName(String path) => const {
  '.md',
  '.markdown',
  '.mdown',
  '.mkd',
  '.txt',
}.contains(p.posix.extension(path).toLowerCase());
