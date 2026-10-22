import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/literal_source_matcher.dart';
import '../services/workspace_index.dart';
import '../services/workspace_index_source.dart';

class WorkspaceSourceMatch {
  const WorkspaceSourceMatch({
    required this.key,
    required this.path,
    required this.name,
    required this.sessionId,
    required this.revision,
    required this.scopeEpoch,
    required this.range,
    required this.line,
    required this.snippet,
    required this.query,
    required this.matchCase,
    required this.externalConflict,
    this.metadata,
  });
  final String key;
  final String? path;
  final String name;
  final String? sessionId;
  final String revision;
  final int scopeEpoch;
  final TextRange range;
  final int line;
  final String snippet;
  final String query;
  final bool matchCase;
  final bool externalConflict;
  final WorkspaceMetadata? metadata;
}

/// Transient search state. Display limits never truncate the catalog scan.
class WorkspaceSearchController extends ChangeNotifier {
  WorkspaceSearchController(
    this.index, {
    this.maximumResults = 500,
    this.maximumDepth = 64,
  }) {
    _epoch = index.epoch;
    _bufferRevision = index.contentRevision;
    index.addListener(_indexChanged);
  }
  final WorkspaceIndex index;
  final int maximumResults;
  final int maximumDepth;
  String query = '';
  bool matchCase = false;
  bool searching = false;
  bool cancelled = false;
  int known = 0;
  int scanned = 0;
  int matchCount = 0;
  int matchedDocuments = 0;
  final List<WorkspaceSourceMatch> _results = [];
  List<WorkspaceSourceMatch> get results => List.unmodifiable(_results);
  final Map<WorkspaceReadIssue, int> _issues = {};
  Map<WorkspaceReadIssue, int> get issues => Map.unmodifiable(_issues);
  bool get partial => _issues.isNotEmpty || cancelled;
  bool get displayLimited => matchCount > _results.length;
  String? error;
  int _generation = 0;
  int _epoch = 0;
  int _bufferRevision = 0;
  Timer? _timer;
  bool _disposed = false;
  Future<void>? _completion;
  Future<void> get completion => _completion ?? Future.value();

  void _indexChanged() {
    if (_epoch == index.epoch && _bufferRevision == index.contentRevision) {
      return;
    }
    _epoch = index.epoch;
    _bufferRevision = index.contentRevision;
    if (query.isNotEmpty && !cancelled) search(query, matchCase: matchCase);
  }

  void search(
    String value, {
    bool? matchCase,
    bool immediate = false,
    bool refresh = false,
  }) {
    if (_disposed) return;
    query = value; // Spaces and newlines are literal source, never trimmed.
    this.matchCase = matchCase ?? this.matchCase;
    _timer?.cancel();
    final generation = ++_generation;
    _results.clear();
    _issues.clear();
    known = scanned = matchCount = matchedDocuments = 0;
    cancelled = false;
    error = null;
    searching = query.isNotEmpty;
    notifyListeners();
    if (!searching) return;
    if (query.length > 64 * 1024) {
      searching = false;
      _issues[WorkspaceReadIssue.limit] = 1;
      error =
          'Search text exceeds 64 Ki UTF-16 units. Use a shorter literal query.';
      notifyListeners();
      return;
    }
    void start() {
      _completion = _run(generation, index.epoch, refresh: refresh);
    }

    if (immediate) {
      start();
    } else {
      _timer = Timer(const Duration(milliseconds: 180), start);
    }
  }

  void cancel() {
    if (_disposed) return;
    ++_generation;
    _timer?.cancel();
    searching = false;
    cancelled = query.isNotEmpty;
    notifyListeners();
  }

  Future<void> _run(int generation, int epoch, {required bool refresh}) async {
    bool current() =>
        !_disposed && _generation == generation && index.epoch == epoch;
    void issue(WorkspaceReadIssue value) {
      _issues[value] = (_issues[value] ?? 0) + 1;
    }

    final query = this.query;
    final matchCase = this.matchCase;
    final visitedPaths = <String>{};
    var visitedEntries = 0;
    Future<void> scan(
      WorkspaceNoteSnapshot note, {
      WorkspaceMetadata? metadata,
    }) async {
      if (!current()) return;
      final scanner = LiteralSourceMatcher(
        note.text,
        query,
        matchCase: matchCase,
      );
      var matched = false;
      var line = 1;
      var lineOffset = 0;
      do {
        for (final range in scanner.next()) {
          if (!matched) {
            matched = true;
            matchedDocuments++;
          }
          matchCount++;
          if (_results.length < maximumResults) {
            for (var offset = lineOffset; offset < range.start; offset++) {
              if (note.text.codeUnitAt(offset) == 10) line++;
            }
            lineOffset = range.start;
            final start = LiteralSourceMatcher.scalarBoundary(
              note.text,
              math.max(0, range.start - 48),
            );
            final end = LiteralSourceMatcher.scalarBoundary(
              note.text,
              math.min(note.text.length, range.start + 120),
            );
            _results.add(
              WorkspaceSourceMatch(
                key: note.key,
                path: note.path,
                name: note.name,
                sessionId: note.sessionId,
                revision: note.revision,
                scopeEpoch: epoch,
                range: range,
                line: line,
                snippet: note.text
                    .substring(start, end)
                    .replaceAll('\r', ' ')
                    .replaceAll('\n', ' '),
                query: query,
                matchCase: matchCase,
                externalConflict: note.externalConflict,
                metadata: metadata,
              ),
            );
          }
        }
        if (!scanner.complete) {
          await Future<void>.delayed(Duration.zero);
          if (!current()) return;
        }
      } while (!scanner.complete);
      scanned++;
    }

    try {
      // All open buffers win, including clean-but-conflicted documents and
      // standalone files. A single-file grant never enumerates its parent.
      for (final buffer in index.buffers) {
        if (!current()) return;
        known++;
        visitedPaths.add(buffer.key);
        await scan(buffer);
      }
      final root = index.root;
      final pending = <({String path, int depth})>[
        if (root != null) (path: '', depth: 0),
      ];
      while (pending.isNotEmpty && current()) {
        final directory = pending.removeLast();
        if (directory.depth > maximumDepth) {
          issue(WorkspaceReadIssue.limit);
          continue;
        }
        WorkspaceDirectorySnapshot snapshot;
        try {
          snapshot = await index.directory(
            directory.path,
            refresh: refresh,
            reconcile: true,
          );
        } on Object catch (failure) {
          if (!current()) return;
          issue(workspaceReadIssue(failure));
          continue;
        }
        if (!current()) return;
        if (!snapshot.complete) {
          issue(
            snapshot.reason?.startsWith('attachment_') == true
                ? workspaceReadIssue(PlatformException(code: snapshot.reason!))
                : WorkspaceReadIssue.limit,
          );
        }
        for (final entry in snapshot.entries) {
          if (!current()) return;
          if (++visitedEntries > index.maximumEntries) {
            issue(WorkspaceReadIssue.limit);
            pending.clear();
            break;
          }
          if (entry.isDirectory) {
            pending.add((path: entry.relativePath, depth: directory.depth + 1));
          } else {
            final key = p.posix.join(root!, entry.relativePath);
            if (!visitedPaths.add(key)) continue;
            known++;
            try {
              final note = await index.read(entry);
              if (!current()) return;
              await scan(note, metadata: entry);
            } on Object catch (failure) {
              if (!current()) return;
              issue(workspaceReadIssue(failure));
            }
          }
          if (visitedEntries % 16 == 0) {
            notifyListeners();
            await Future<void>.delayed(Duration.zero);
          }
        }
        if (current()) notifyListeners();
      }
    } on Object catch (failure) {
      if (!current()) return;
      issue(workspaceReadIssue(failure));
      error = 'Some source could not be searched.';
    } finally {
      if (current()) {
        searching = false;
        notifyListeners();
      }
    }
  }

  /// Recheck source identity before an existing session is selected/opened.
  /// The shell must also compare the opened buffer with this exact snapshot.
  Future<WorkspaceNoteSnapshot?> resolve(WorkspaceSourceMatch match) async {
    if (_disposed || match.scopeEpoch != index.epoch) return null;
    final epoch = index.epoch;
    final buffer = match.sessionId != null
        ? index.bufferForSession(match.sessionId!)
        : match.path == null
        ? null
        : index.bufferForPath(match.path!);
    if (buffer != null) {
      return buffer.revision == match.revision ? buffer : null;
    }
    if (match.metadata == null || index.root == null) return null;
    try {
      final parent = p.posix.dirname(match.metadata!.relativePath);
      final directory = await index.directory(
        parent == '.' ? '' : parent,
        refresh: true,
      );
      if (_disposed || index.epoch != epoch || !directory.complete) return null;
      final entries = directory.entries.where(
        (entry) =>
            entry.relativePath == match.metadata!.relativePath &&
            entry.revision == match.metadata!.revision,
      );
      if (entries.isEmpty) return null;
      final snapshot = await index.read(entries.first);
      return index.epoch == epoch && snapshot.revision == match.revision
          ? snapshot
          : null;
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    index.removeListener(_indexChanged);
    super.dispose();
  }
}
