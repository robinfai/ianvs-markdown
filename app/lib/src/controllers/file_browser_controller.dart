import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../services/markdown_file_service.dart';

enum FileSort { name, modified }

class BrowserPreferences {
  final expanded = <String>{};
  final collapsedExternal = <String>{};
  final favorites = <String, bool>{};
  double scroll = 0;
  FileSort sort = FileSort.name;
  bool follow = false;
  bool favoritesExpanded = true;

  Map<String, Object?> toJson() => {
    'expanded': expanded.toList(),
    'collapsedExternal': collapsedExternal.toList(),
    'favorites': Map.of(favorites),
    'scroll': scroll,
    'sort': sort.name,
    'follow': follow,
    'favoritesExpanded': favoritesExpanded,
  };

  static BrowserPreferences fromJson(Map data) {
    final value = BrowserPreferences();
    if (data['expanded'] is List) {
      value.expanded.addAll((data['expanded'] as List).whereType<String>());
    }
    if (data['collapsedExternal'] is List) {
      value.collapsedExternal.addAll(
        (data['collapsedExternal'] as List).whereType<String>(),
      );
    }
    if (data['favorites'] is Map) {
      for (final entry in (data['favorites'] as Map).entries) {
        if (entry.key is String && entry.value is bool) {
          value.favorites[entry.key as String] = entry.value as bool;
        }
      }
    }
    final offset = data['scroll'];
    if (offset is num && offset.isFinite && offset >= 0) {
      value.scroll = offset.toDouble();
    }
    value.sort = data['sort'] == 'modified' ? FileSort.modified : FileSort.name;
    value.follow = data['follow'] == true;
    value.favoritesExpanded = data['favoritesExpanded'] != false;
    return value;
  }
}

class BrowserRow {
  const BrowserRow.entry(this.entry, this.depth, {this.external = false})
    : label = null,
      statusPath = null;
  const BrowserRow.label(this.label)
    : entry = null,
      depth = 0,
      external = false,
      statusPath = null;
  const BrowserRow.status(this.label, this.statusPath, this.depth)
    : entry = null,
      external = false;
  final WorkspaceEntry? entry;
  final int depth;
  final bool external;
  final String? label;
  final String? statusPath;
}

/// Session-owned tree/index state. Cached directories are also the search index;
/// refresh invalidates only changed directories, never the current tree position.
class FileBrowserController extends ChangeNotifier {
  FileBrowserController(this.service);
  final MarkdownFileService service;
  final _preferences = <String, BrowserPreferences>{};
  final _children = <String, List<WorkspaceEntry>>{};
  final _errors = <String, Object>{};
  final _loading = <String, Future<void>>{};
  final _watchers = <String, StreamSubscription<FileSystemEvent>>{};
  final _versions = <String, int>{};
  final _refreshTimers = <String, Timer>{};
  final selected = <String>{};
  String? focusedPath;
  String? anchor;
  String? root;
  String? activePath;
  List<String> externalPaths = [];
  final _externalModified = <String, DateTime?>{};
  int _metadataGeneration = 0;
  String query = '';
  List<WorkspaceEntry> results = [];
  int matchCount = 0;
  bool searching = false;
  bool disposed = false;
  int _generation = 0;
  int _rootEpoch = 0;
  int _revealGeneration = 0;
  Timer? _searchTimer;
  int revealRevision = 0;
  String? revealedPath;
  int get indexedDirectories => _children.length;
  Map<String, Object> get errors => Map.unmodifiable(_errors);
  BrowserPreferences get preferences =>
      _preferences.putIfAbsent(root ?? '', BrowserPreferences.new);

  Map<String, Object?> toJson() => {
    for (final e in _preferences.entries) e.key: e.value.toJson(),
  };
  void restore(Map<String, Object?> data) {
    for (final e in data.entries) {
      if (e.value is Map) {
        _preferences[e.key] = BrowserPreferences.fromJson(e.value as Map);
      }
    }
  }

  void configure(String? nextRoot, List<String> external, String? active) {
    if (disposed) return;
    final rootChanged = root != nextRoot;
    final externalChanged = !listEquals(externalPaths, external);
    final activeChanged = activePath != active;
    if (rootChanged) {
      _generation++;
      _rootEpoch++;
      _revealGeneration++;
      for (final watcher in _watchers.values) {
        unawaited(watcher.cancel());
      }
      _watchers.clear();
      for (final timer in _refreshTimers.values) {
        timer.cancel();
      }
      _refreshTimers.clear();
      _children.clear();
      _errors.clear();
      _loading.clear();
      _versions.clear();
      selected.clear();
      focusedPath = null;
      anchor = null;
      root = nextRoot;
      if (root != null) unawaited(load(root!));
    }
    externalPaths = external;
    if (externalChanged) unawaited(refreshExternalMetadata());
    activePath = active;
    if ((rootChanged || externalChanged) && query.isNotEmpty) search(query);
    if (activeChanged && preferences.follow && active != null) {
      unawaited(reveal(active));
    }
    if (rootChanged || externalChanged || activeChanged) _emit();
  }

  void _emit() {
    if (!disposed) notifyListeners();
  }

  bool isExternal(String path) =>
      root == null || !(p.equals(root!, path) || p.isWithin(root!, path));
  bool isExpanded(String path, {bool external = false}) => external
      ? !preferences.collapsedExternal.contains(path)
      : preferences.expanded.contains(path);

  Future<void> load(String path, {bool refresh = false}) {
    if (disposed || isExternal(path)) return Future.value();
    if (!refresh && _loading.containsKey(path)) return _loading[path]!;
    if (!refresh &&
        (_children.containsKey(path) || _errors.containsKey(path))) {
      return Future.value();
    }
    final currentRoot = root;
    final epoch = _rootEpoch;
    final version = (_versions[path] ?? 0) + 1;
    _versions[path] = version;
    late final Future<void> task;
    task = () async {
      try {
        final entries = await service.listDirectory(path);
        if (disposed ||
            root != currentRoot ||
            epoch != _rootEpoch ||
            _versions[path] != version) {
          return;
        }
        _children[path] = entries;
        _errors.remove(path);
        // Remove deleted subtrees from the index and release their watchers.
        final directories = entries
            .where((e) => e.isDirectory)
            .map((e) => e.path)
            .toSet();
        final obsolete = {..._children.keys, ..._loading.keys}
            .where(
              (key) => p.dirname(key) == path && !directories.contains(key),
            )
            .toList();
        for (final removed in obsolete) {
          _evict(removed);
        }
        if (!_watchers.containsKey(path)) {
          try {
            _watchers[path] = service
                .watchDirectory(path)
                .listen(
                  (event) {
                    if (disposed || epoch != _rootEpoch) return;
                    if (p.equals(p.dirname(event.path), path) ||
                        p.equals(event.path, path) ||
                        (event is FileSystemMoveEvent &&
                            event.destination != null &&
                            p.equals(p.dirname(event.destination!), path))) {
                      _refreshTimers[path]?.cancel();
                      _refreshTimers[path] = Timer(
                        const Duration(milliseconds: 100),
                        () async {
                          await load(path, refresh: true);
                          if (query.isNotEmpty && !disposed) search(query);
                        },
                      );
                    }
                  },
                  onError: (Object error) {
                    if (disposed || epoch != _rootEpoch) return;
                    final watcher = _watchers.remove(path);
                    if (watcher != null) unawaited(watcher.cancel());
                    _errors[path] = error;
                    _emit();
                  },
                );
          } on Object catch (error) {
            _errors[path] = error;
          }
        }
        for (final entry in entries) {
          if (entry.isDirectory && preferences.expanded.contains(entry.path)) {
            unawaited(load(entry.path));
          }
        }
      } on Object catch (error) {
        if (!disposed &&
            root == currentRoot &&
            epoch == _rootEpoch &&
            _versions[path] == version) {
          _errors[path] = error;
        }
      } finally {
        if (identical(_loading[path], task)) _loading.remove(path);
        _emit();
      }
    }();
    _loading[path] = task;
    return task;
  }

  void _evict(String path) {
    for (final key in {
      ..._children.keys,
      ..._watchers.keys,
      ..._loading.keys,
    }.where((key) => key == path || p.isWithin(path, key)).toList()) {
      _children.remove(key);
      _errors.remove(key);
      _versions[key] = (_versions[key] ?? 0) + 1;
      final watcher = _watchers.remove(key);
      if (watcher != null) unawaited(watcher.cancel());
    }
  }

  Future<void> refreshExternalMetadata() async {
    final generation = ++_metadataGeneration;
    final paths = List.of(externalPaths);
    final timestamps = <String, DateTime?>{};
    for (final path in paths) {
      if (disposed || generation != _metadataGeneration) return;
      try {
        timestamps[path] = await service.readModifiedTime(path);
      } on Object {
        timestamps[path] = null;
      }
    }
    if (disposed || generation != _metadataGeneration) return;
    _externalModified
      ..clear()
      ..addAll(timestamps);
    _emit();
  }

  Future<void> refresh({Iterable<String>? directories}) async {
    final paths = directories?.toSet() ?? {?root, ..._children.keys};
    await Future.wait(
      paths
          .where((path) => !isExternal(path))
          .map((path) => load(path, refresh: true)),
    );
    await refreshExternalMetadata();
    if (query.isNotEmpty) search(query);
  }

  void toggle(String path, {bool external = false}) {
    final set = external ? preferences.collapsedExternal : preferences.expanded;
    if (!set.add(path)) set.remove(path);
    if (!external && set.contains(path)) unawaited(load(path));
    _emit();
  }

  void collapseAll() {
    preferences.expanded.clear();
    preferences.collapsedExternal.addAll(_externalTree().keys);
    _emit();
  }

  void setSort(FileSort sort) {
    preferences.sort = sort;
    _emit();
  }

  void setFollow(bool follow) {
    preferences.follow = follow;
    _emit();
    if (follow && activePath != null) unawaited(reveal(activePath!));
  }

  void setScroll(double offset) {
    if (offset.isFinite && offset >= 0 && preferences.scroll != offset) {
      preferences.scroll = offset;
      _emit();
    }
  }

  void toggleFavorite(WorkspaceEntry entry) {
    if (preferences.favorites.remove(entry.path) == null) {
      preferences.favorites[entry.path] = entry.isDirectory;
    }
    _emit();
  }

  void toggleFavorites() {
    preferences.favoritesExpanded = !preferences.favoritesExpanded;
    _emit();
  }

  List<WorkspaceEntry> sorted(Iterable<WorkspaceEntry> entries) =>
      entries.toList()..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        if (preferences.sort == FileSort.modified) {
          final result = (b.modified ?? DateTime(1970)).compareTo(
            a.modified ?? DateTime(1970),
          );
          if (result != 0) return result;
        }
        return naturalCompare(a.name, b.name);
      });

  List<BrowserRow> get rows {
    final rows = <BrowserRow>[];
    void append(String path, int depth) {
      final entries = _children[path];
      if (_errors.containsKey(path)) {
        rows.add(
          BrowserRow.status('Unable to read folder — Retry', path, depth),
        );
      }
      if (entries == null) {
        if (!_errors.containsKey(path)) {
          rows.add(BrowserRow.status('Loading…', path, depth));
        }
        return;
      }
      if (entries.isEmpty) {
        rows.add(BrowserRow.status('Empty folder', null, depth));
      }
      for (final entry in sorted(entries)) {
        rows.add(BrowserRow.entry(entry, depth));
        if (entry.isDirectory && isExpanded(entry.path)) {
          append(entry.path, depth + 1);
        }
      }
    }

    if (root != null) append(root!, 0);
    if (externalPaths.isNotEmpty) {
      if (root != null) rows.add(const BrowserRow.label('External Files'));
      final tree = _externalTree();
      WorkspaceEntry compact(WorkspaceEntry entry, String? parent) {
        while (tree[entry.path]?.length == 1 &&
            tree[entry.path]!.single.isDirectory) {
          entry = tree[entry.path]!.single;
        }
        return WorkspaceEntry(
          path: entry.path,
          name: parent == null
              ? entry.path
              : p.relative(entry.path, from: parent),
          isDirectory: true,
        );
      }

      void appendExternal(String directory, int depth, {bool top = false}) {
        for (var entry in sorted(tree[directory] ?? [])) {
          if (entry.isDirectory) entry = compact(entry, top ? null : directory);
          rows.add(BrowserRow.entry(entry, depth, external: true));
          if (entry.isDirectory && isExpanded(entry.path, external: true)) {
            appendExternal(entry.path, depth + 1);
          }
        }
      }

      appendExternal('', 0, top: true);
    }
    return rows;
  }

  Map<String, List<WorkspaceEntry>> _externalTree() {
    final tree = <String, Map<String, WorkspaceEntry>>{};
    for (final file in externalPaths) {
      final parts = p.split(file);
      var parent = '';
      for (var index = 0; index < parts.length; index++) {
        final path = index == 0 ? parts[0] : p.join(parent, parts[index]);
        tree.putIfAbsent(parent, () => {})[path] = WorkspaceEntry(
          path: path,
          name: parts[index],
          isDirectory: index < parts.length - 1,
          modified: index == parts.length - 1 ? _externalModified[path] : null,
        );
        parent = path;
      }
    }
    return tree.map((key, value) => MapEntry(key, value.values.toList()));
  }

  Future<void> reveal(String path) async {
    final generation = ++_revealGeneration;
    bool current() => !disposed && generation == _revealGeneration;
    if (isExternal(path)) {
      preferences.collapsedExternal.removeWhere(
        (directory) => p.equals(directory, path) || p.isWithin(directory, path),
      );
    } else {
      final ancestors = <String>[];
      var parent = p.dirname(path);
      while (parent != root && p.isWithin(root!, parent)) {
        ancestors.add(parent);
        parent = p.dirname(parent);
      }
      preferences.expanded.addAll(ancestors);
      await load(root!);
      if (!current()) return;
      for (final directory in ancestors.reversed) {
        await load(directory);
        if (!current()) return;
      }
    }
    if (!current()) return;
    focusedPath = path;
    selected
      ..clear()
      ..add(path);
    anchor = path;
    revealedPath = path;
    revealRevision++;
    _emit();
  }

  void select(
    String path,
    List<String> visible, {
    bool toggle = false,
    bool range = false,
  }) {
    if (range &&
        anchor != null &&
        visible.contains(anchor) &&
        visible.contains(path)) {
      final a = visible.indexOf(anchor!);
      final b = visible.indexOf(path);
      selected
        ..clear()
        ..addAll(visible.sublist(a < b ? a : b, (a > b ? a : b) + 1));
    } else if (toggle) {
      if (!selected.add(path)) selected.remove(path);
      anchor = path;
    } else {
      selected
        ..clear()
        ..add(path);
      anchor = path;
    }
    focusedPath = path;
    _emit();
  }

  void search(String value) {
    query = value.trim().toLowerCase();
    _searchTimer?.cancel();
    final generation = ++_generation;
    results = [];
    matchCount = 0;
    searching = query.isNotEmpty;
    _emit();
    if (query.isEmpty) return;
    _searchTimer = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_search(generation)),
    );
  }

  Future<void> _search(int generation) async {
    final currentQuery = query;
    bool current() => !disposed && generation == _generation;
    final matches = <String, WorkspaceEntry>{};
    void add(WorkspaceEntry entry) {
      final path = root != null && !isExternal(entry.path)
          ? p.relative(entry.path, from: root)
          : entry.path;
      if (!entry.isDirectory && path.toLowerCase().contains(currentQuery)) {
        matches[entry.path] = entry;
      }
    }

    for (final path in externalPaths) {
      add(
        WorkspaceEntry(path: path, name: p.basename(path), isDirectory: false),
      );
    }
    final pending = <String>[?root];
    final visited = <String>{};
    while (pending.isNotEmpty && current()) {
      final path = pending.removeLast();
      if (!visited.add(path)) continue;
      await load(path);
      if (!current()) return;
      for (final entry in _children[path] ?? <WorkspaceEntry>[]) {
        if (entry.isDirectory) {
          pending.add(entry.path);
        } else {
          add(entry);
        }
      }
      // Yield to input, including cancellation, in large cached workspaces.
      if (visited.length % 32 == 0) await Future<void>.delayed(Duration.zero);
    }
    if (!current()) return;
    int rank(WorkspaceEntry e) {
      final name = e.name.toLowerCase();
      if (name == currentQuery ||
          p.basenameWithoutExtension(name) == currentQuery) {
        return 0;
      }
      if (name.startsWith(currentQuery)) return 1;
      if (name.contains(currentQuery)) return 2;
      return 3;
    }

    final ordered = matches.values.toList()
      ..sort((a, b) {
        final order = rank(a).compareTo(rank(b));
        return order != 0 ? order : naturalCompare(a.path, b.path);
      });
    matchCount = ordered.length;
    results = ordered.take(200).toList();
    searching = false;
    _emit();
  }

  void remap(String source, String? destination) {
    String mapped(String path) => p.equals(path, source)
        ? destination!
        : p.join(destination!, p.relative(path, from: source));
    bool affected(String path) =>
        p.equals(path, source) || p.isWithin(source, path);
    for (final preferences in _preferences.values) {
      for (final set in [preferences.expanded, preferences.collapsedExternal]) {
        final paths = set.where(affected).toList();
        set.removeAll(paths);
        if (destination != null) set.addAll(paths.map(mapped));
      }
      for (final path in preferences.favorites.keys.where(affected).toList()) {
        final directory = preferences.favorites.remove(path)!;
        if (destination != null) {
          preferences.favorites[mapped(path)] = directory;
        }
      }
    }
    final paths = selected.where(affected).toList();
    selected.removeAll(paths);
    if (destination != null) selected.addAll(paths.map(mapped));
    if (focusedPath != null && affected(focusedPath!)) {
      focusedPath = destination == null ? null : mapped(focusedPath!);
    }
    _evict(source);
    _emit();
  }

  @override
  void dispose() {
    disposed = true;
    _generation++;
    _searchTimer?.cancel();
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    for (final watcher in _watchers.values) {
      unawaited(watcher.cancel());
    }
    super.dispose();
  }
}

int naturalCompare(String left, String right) {
  final chunks = RegExp(r'\d+|\D+');
  final a = chunks
      .allMatches(left.toLowerCase())
      .map((e) => e.group(0)!)
      .toList();
  final b = chunks
      .allMatches(right.toLowerCase())
      .map((e) => e.group(0)!)
      .toList();
  for (var i = 0; i < a.length && i < b.length; i++) {
    final na = BigInt.tryParse(a[i]);
    final nb = BigInt.tryParse(b[i]);
    final comparison = na != null && nb != null
        ? na.compareTo(nb)
        : a[i].compareTo(b[i]);
    if (comparison != 0) return comparison;
  }
  final length = a.length.compareTo(b.length);
  return length != 0 ? length : left.compareTo(right);
}
