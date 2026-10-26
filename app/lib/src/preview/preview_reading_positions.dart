import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/workspace_session_store.dart';

/// Mobile-only reading metadata. Never writes Markdown files or restores grants.
class PreviewReadingPositions {
  PreviewReadingPositions({
    WorkspaceSessionStore? store,
    Future<WorkspaceSessionStore> Function()? createStore,
  }) : _storeOverride = store,
       _storeFactory = createStore;
  final Future<WorkspaceSessionStore> Function()? _storeFactory;
  final WorkspaceSessionStore? _storeOverride;
  Future<WorkspaceSessionStore>? _storeFuture;
  final _positions = <String, IanvsMarkdownViewportAnchor>{};
  Timer? _timer;
  Future<void> _writes = Future.value();
  Future<void>? _loading;
  bool _disposed = false;
  bool _dirty = false;
  bool _loaded = false;
  Object? lastError;
  static const maximumEntries = 24;
  static const maximumSourceUnits = 8 * 1024 * 1024;

  Future<WorkspaceSessionStore> get _store => _storeFuture ??= () async {
    try {
      return await Future<WorkspaceSessionStore>.sync(
        _storeFactory ?? _createStore,
      );
    } catch (_) {
      _storeFuture = null;
      rethrow;
    }
  }();
  Future<WorkspaceSessionStore> _createStore() async =>
      _storeOverride ??
      DesktopWorkspaceSessionStore(
        directory: Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'LinefoldMobileReading',
          ),
        ),
      );

  String _key(String? root, String path) =>
      jsonEncode([root == null ? null : p.normalize(root), p.normalize(path)]);

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      final snapshot = await (await _store).load();
      // A queued final flush may still need to merge disk metadata after dispose.
      final entries = snapshot?.browserState['readingPositions'];
      if (entries is List) {
        final current = Map<String, IanvsMarkdownViewportAnchor>.of(_positions);
        for (final entry in entries.take(maximumEntries)) {
          if (entry is! Map) continue;
          final key = entry['key'];
          final source = entry['source'];
          final offset = entry['offset'];
          final dy = entry['dy'];
          if (key is! String ||
              source is! String ||
              offset is! int ||
              dy is! num ||
              source.length > maximumSourceUnits) {
            continue;
          }
          final anchor = IanvsMarkdownViewportAnchor(
            source: source,
            sourceOffset: offset,
            viewportOffset: dy.toDouble(),
          );
          if (anchor.isValid) _positions[key] = anchor;
        }
        // Scroll events that happened during disk loading always win.
        for (final entry in current.entries) {
          _positions.remove(entry.key);
          _positions[entry.key] = entry.value;
        }
        _trim();
      }
      _loaded = true;
      lastError = null;
    } on Object catch (error) {
      lastError = error;
    }
  }

  IanvsMarkdownViewportAnchor? lookup(
    String? root,
    String path,
    String source,
  ) => _positions[_key(root, path)]?.rebase(source);

  void remember(String? root, String path, IanvsMarkdownViewportAnchor anchor) {
    if (_disposed ||
        !anchor.isValid ||
        anchor.source.length > maximumSourceUnits) {
      return;
    }
    final key = _key(root, path);
    if (_positions[key] == anchor) return;
    _positions.remove(key);
    _positions[key] = anchor;
    _trim();
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), () => unawaited(flush()));
  }

  void _trim() {
    var units = _positions.values.fold(
      0,
      (sum, anchor) => sum + anchor.source.length,
    );
    while (_positions.length > maximumEntries || units > maximumSourceUnits) {
      units -= _positions.remove(_positions.keys.first)!.source.length;
    }
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty) return _writes;
    _dirty = false;
    _writes = _writes.then((_) async {
      try {
        await load();
        // Do not overwrite positions on disk when they could not be read.
        // A later flush retries both initialization and loading first.
        if (!_loaded) {
          throw lastError ??
              const FileSystemException('Reading positions unavailable');
        }
        final entries = [
          for (final entry in _positions.entries)
            {
              'key': entry.key,
              'source': entry.value.source,
              'offset': entry.value.sourceOffset,
              'dy': entry.value.viewportOffset,
            },
        ];
        await (await _store).save(
          WorkspaceSnapshot(
            documents: const [],
            activeDocumentId: null,
            workspaceRoot: null,
            workspaceAccessToken: null,
            sidebarVisible: false,
            outlineVisible: false,
            browserState: {'readingPositions': entries},
          ),
        );
        lastError = null;
      } on Object catch (error) {
        lastError = error;
        _dirty = true;
      }
    });
    return _writes;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(flush());
  }
}
