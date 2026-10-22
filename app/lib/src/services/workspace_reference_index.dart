import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import 'wiki_note_resolver.dart';
import 'workspace_index.dart';
import 'workspace_index_source.dart';

enum WorkspaceReferenceStatus {
  resolved,
  ambiguous,
  missing,
  unknown,
  external,
}

class WorkspaceSemanticNote {
  const WorkspaceSemanticNote(
    this.source,
    this.semantics,
    this.metadata, {
    required this.parserVersion,
  });
  final int parserVersion;
  final WorkspaceNoteSnapshot source;
  final IanvsMarkdownNoteSemantics semantics;
  final WorkspaceMetadata? metadata;
}

class WorkspaceReferenceEdge {
  const WorkspaceReferenceEdge({
    required this.note,
    required this.reference,
    required this.status,
    required this.candidatePaths,
  });
  final WorkspaceSemanticNote note;
  final IanvsMarkdownSourceReference reference;
  final WorkspaceReferenceStatus status;

  /// Real root-relative identities, not comparison keys or display aliases.
  final List<String> candidatePaths;
  String? get targetPath => status == WorkspaceReferenceStatus.resolved
      ? candidatePaths.single
      : null;
}

class WorkspaceTagOccurrence {
  const WorkspaceTagOccurrence(this.note, this.tag);
  final WorkspaceSemanticNote note;
  final IanvsMarkdownSourceTag tag;
}

/// A read-only affected-set preview. It deliberately exposes no write API.
/// Definition uses share the same destination span; consumers must deduplicate
/// by (source.key, source.revision, definitionIdentity/destinationRange).
class WorkspaceReferenceImpact {
  const WorkspaceReferenceImpact({
    required this.references,
    required this.possibleReferences,
    required this.complete,
  });
  final List<WorkspaceReferenceEdge> references;
  final List<WorkspaceReferenceEdge> possibleReferences;
  final bool complete;
}

class WorkspaceReferenceSnapshot {
  const WorkspaceReferenceSnapshot({
    required this.epoch,
    required this.contentRevision,
    required this.catalogRevision,
    required this.catalog,
    required this.notes,
    required this.edges,
    required this.tags,
    required this.aliases,
    required this.wikiCandidates,
    required this.noteCandidates,
    required this.issues,
    required this.knownDocuments,
  });
  final int epoch;
  final int contentRevision;
  final int catalogRevision;
  final WorkspaceCatalogSnapshot catalog;
  final Map<String, WorkspaceSemanticNote> notes;
  final List<WorkspaceReferenceEdge> edges;
  final Map<String, List<WorkspaceTagOccurrence>> tags;
  final WikiAliasSnapshot aliases;
  final List<WikiNoteCandidate> wikiCandidates;
  final List<WikiNoteCandidate> noteCandidates;

  /// Per-note and catalog coverage. Empty results with issues are not absence.
  final Map<String, List<String>> issues;
  final int knownDocuments;
  bool get complete => issues.isEmpty;

  List<WorkspaceReferenceEdge> backlinks(String relativePath) => [
    for (final edge in edges)
      if (edge.targetPath == relativePath &&
          edge.reference.kind !=
              IanvsMarkdownSourceReferenceKind.markdownDefinition)
        edge,
  ];

  WorkspaceReferenceImpact impact(String relativePath) =>
      WorkspaceReferenceImpact(
        references: List.unmodifiable([
          for (final edge in edges)
            if (edge.targetPath == relativePath &&
                edge.reference.target.isNotEmpty)
              edge,
        ]),
        possibleReferences: List.unmodifiable([
          for (final edge in edges)
            if (edge.status != WorkspaceReferenceStatus.resolved &&
                edge.candidatePaths.contains(relativePath))
              edge,
        ]),
        complete:
            safeWorkspaceRelativePath(relativePath) &&
            catalog.complete &&
            complete &&
            !edges.any(
              (edge) =>
                  edge.status == WorkspaceReferenceStatus.unknown ||
                  edge.status == WorkspaceReferenceStatus.ambiguous,
            ),
      );
}

/// Session-owned semantic projections of WorkspaceIndex effective snapshots.
/// No filesystem/provider API exists here. All IO is local-only via the shared
/// catalog/read cache; open buffers, including dirty/conflicted buffers, win.
class WorkspaceReferenceIndex extends ChangeNotifier {
  WorkspaceReferenceIndex(
    this.index, {
    this.maximumSourceBytes = 32 * 1024 * 1024,
    this.maximumDocuments = 10000,
    this.maximumOccurrences = 100000,
    WikiPathNormalizer? normalize,
  }) : resolver = WikiNoteResolver(index, normalize: normalize) {
    _epoch = index.epoch;
    _contentRevision = index.contentRevision;
    _catalogRevision = index.catalogRevision;
    index.addListener(_indexChanged);
  }
  static const _parserVersion = 2;
  final WorkspaceIndex index;
  final WikiNoteResolver resolver;
  final int maximumSourceBytes;
  final int maximumDocuments;
  final int maximumOccurrences;
  final _cache = <String, WorkspaceSemanticNote>{};
  int _cacheBytes = 0;
  int _epoch = 0;
  int _contentRevision = 0;
  int _catalogRevision = 0;
  int _parseCount = 0;
  int get parseCount => _parseCount;
  int get cachedBytes => _cacheBytes;
  WorkspaceReferenceSnapshot? _snapshot;
  WorkspaceReferenceSnapshot? get snapshot => _snapshot;
  bool _stale = true;
  bool get stale => _stale;
  bool get scanning => _running != null;
  bool _disposed = false;
  bool _cancelled = false;
  int _request = 0;
  bool get cancelled => _cancelled;
  Future<WorkspaceReferenceSnapshot>? _running;
  bool _pendingMetadataRefresh = false;
  Timer? _timer;

  void _indexChanged() {
    if (_epoch == index.epoch &&
        _contentRevision == index.contentRevision &&
        _catalogRevision == index.catalogRevision) {
      return;
    }
    final rootChanged = _epoch != index.epoch;
    _epoch = index.epoch;
    _contentRevision = index.contentRevision;
    _catalogRevision = index.catalogRevision;
    _stale = true;
    if (rootChanged) {
      _snapshot = null;
      _cache.clear();
      _cacheBytes = 0;
    }
    if (!_disposed) notifyListeners();
    if (hasListeners && !_cancelled && _running == null) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 120), () {
        if (!_disposed && hasListeners) {
          unawaited(refresh().catchError((Object _) => _emptySnapshot()));
        }
      });
    }
  }

  WorkspaceReferenceSnapshot _emptySnapshot() => WorkspaceReferenceSnapshot(
    epoch: index.epoch,
    contentRevision: index.contentRevision,
    catalogRevision: index.catalogRevision,
    catalog: index.catalogSnapshot,
    notes: const {},
    edges: const [],
    tags: const {},
    aliases: WikiAliasSnapshot(
      byPath: const {},
      complete: false,
      epoch: index.epoch,
    ),
    wikiCandidates: const [],
    noteCandidates: const [],
    issues: const {
      'scope': ['unavailable'],
    },
    knownDocuments: 0,
  );

  Future<WorkspaceReferenceSnapshot> refresh({bool refreshMetadata = false}) {
    if (_disposed) {
      return Future.error(
        const WorkspaceIndexFailure(WorkspaceReadIssue.cancelled),
      );
    }
    _timer?.cancel();
    if (refreshMetadata) _stale = true;
    if (_running case final running?) {
      // Creation rechecks must not join an older captured catalog silently.
      // Coalesce forced requests, but rerun before any joined caller receives
      // a result, even when the current scan itself was already forced.
      _pendingMetadataRefresh |= refreshMetadata;
      return running;
    }
    _pendingMetadataRefresh = refreshMetadata;
    _cancelled = false;
    final request = ++_request;
    late final Future<WorkspaceReferenceSnapshot> task;
    task = () async {
      try {
        while (!_disposed && request == _request) {
          final force = _pendingMetadataRefresh;
          _pendingMetadataRefresh = false;
          final value = await _scan(refreshMetadata: force, request: request);
          if (value == null || _pendingMetadataRefresh) {
            continue; // The source changed; never publish old edges.
          }
          _snapshot = value;
          _stale = false;
          return value;
        }
        throw const WorkspaceIndexFailure(WorkspaceReadIssue.cancelled);
      } finally {
        if (identical(_running, task)) _running = null;
        if (!_disposed) notifyListeners();
      }
    }();
    _running = task;
    notifyListeners();
    return task;
  }

  Future<WorkspaceReferenceSnapshot?> _scan({
    required bool refreshMetadata,
    required int request,
  }) async {
    final epoch = index.epoch;
    final contentRevision = index.contentRevision;
    bool current() =>
        !_disposed &&
        request == _request &&
        epoch == index.epoch &&
        contentRevision == index.contentRevision;
    final catalog = await index.catalog(refresh: refreshMetadata);
    if (!current()) return null;
    final catalogRevision = index.catalogRevision;
    bool stable() => current() && catalogRevision == index.catalogRevision;
    final previousSnapshot = _snapshot;
    if (!refreshMetadata &&
        previousSnapshot != null &&
        previousSnapshot.epoch == epoch &&
        previousSnapshot.contentRevision == contentRevision &&
        previousSnapshot.catalogRevision == catalogRevision) {
      return previousSnapshot;
    }
    final root = index.root;
    final issues = <String, List<String>>{};
    if (root != null && !catalog.complete) {
      issues['catalog'] = catalog.issues.map((issue) => issue.name).toList();
    }
    final notes = <String, WorkspaceSemanticNote>{};
    final visited = <String>{};
    var sourceBytes = 0;
    var occurrences = 0;
    var known = 0;
    void consume(
      WorkspaceNoteSnapshot source,
      WorkspaceMetadata? metadata, {
      String? identityKey,
    }) {
      final key = identityKey ?? source.key;
      if (!visited.add(key)) return;
      known++;
      final bytes = source.text.length * 2;
      if (notes.length >= maximumDocuments ||
          sourceBytes + bytes > maximumSourceBytes) {
        issues[source.key] = ['semantic index budget exceeded'];
        return;
      }
      sourceBytes += bytes;
      final previous = _cache[source.key];
      final IanvsMarkdownNoteSemantics semantics;
      try {
        if (previous?.source.revision == source.revision &&
            previous?.parserVersion == _parserVersion) {
          semantics = previous!.semantics;
        } else {
          _parseCount++;
          semantics = parseIanvsMarkdownNoteSemantics(source.text);
        }
      } on Object {
        issues[source.key] = ['source parser unavailable'];
        return;
      }
      bool validRange(TextRange range) =>
          range.isValid &&
          range.isNormalized &&
          range.end <= source.text.length;
      if (semantics.references.any(
            (reference) =>
                !validRange(reference.range) ||
                !validRange(reference.destinationRange),
          ) ||
          semantics.tags.any((tag) => !validRange(tag.range))) {
        issues[source.key] = ['source parser returned unverifiable ranges'];
        return;
      }
      if (occurrences + semantics.references.length + semantics.tags.length >
          maximumOccurrences) {
        issues[source.key] = ['reference/tag occurrence budget exceeded'];
        return;
      }
      occurrences += semantics.references.length + semantics.tags.length;
      final note = WorkspaceSemanticNote(
        source,
        semantics,
        metadata,
        parserVersion: _parserVersion,
      );
      notes[key] = note;
      if (previous != null) _cacheBytes -= previous.source.text.length * 2;
      _cache.remove(source.key);
      while (_cache.isNotEmpty &&
          (_cacheBytes + bytes > maximumSourceBytes ||
              _cache.length >= maximumDocuments)) {
        _cacheBytes -= _cache.remove(_cache.keys.first)!.source.text.length * 2;
      }
      _cache[source.key] = note;
      _cacheBytes += bytes;
      if (!semantics.complete) {
        issues[source.key] = semantics.issues
            .map((issue) => issue.message)
            .toList();
      }
    }

    List<WikiNoteCandidate> noteCandidates;
    try {
      noteCandidates = await resolver.candidates(
        catalog,
        allMarkdownExtensions: true,
      );
    } on Object catch (error) {
      if (!stable()) return null;
      noteCandidates = [];
      issues['identities'] = [workspaceReadIssue(error).name];
    }
    if (!stable()) return null;
    final wikiCandidates = noteCandidates
        .where(
          (candidate) => candidate.relativePath.toLowerCase().endsWith('.md'),
        )
        .toList();
    final sessionPaths = <String, String>{
      for (final candidate in noteCandidates)
        if (candidate.sessionId != null && root != null)
          candidate.sessionId!: p.posix.join(root, candidate.relativePath),
    };
    // Verified filesystem identity unifies an already-open case/NFC alias with
    // its catalog entry. Comparison keys never merge two real files.
    for (final buffer in index.buffers) {
      consume(buffer, null, identityKey: sessionPaths[buffer.sessionId]);
    }
    for (final entry in catalog.entries) {
      if (!stable()) return null;
      if (entry.isDirectory || root == null) continue;
      final key = p.posix.join(root, entry.relativePath);
      if (visited.contains(key)) continue;
      if (notes.length >= maximumDocuments ||
          sourceBytes >= maximumSourceBytes) {
        visited.add(key);
        known++;
        issues[key] = ['semantic index budget exceeded'];
        continue;
      }
      try {
        final source = await index.read(entry);
        if (!stable()) return null;
        consume(source, entry);
      } on Object catch (error) {
        if (!stable()) return null;
        visited.add(key);
        known++;
        issues[key] = [workspaceReadIssue(error).name];
      }
      await Future<void>.delayed(Duration.zero);
    }
    if (!stable()) return null;
    // Retain no deleted, closed, old-scope or over-budget semantic projections.
    final retained = notes.values.map((note) => note.source.key).toSet();
    for (final key
        in _cache.keys.where((key) => !retained.contains(key)).toList()) {
      _cacheBytes -= _cache.remove(key)!.source.text.length * 2;
    }
    final aliasPaths = <String, Set<String>>{};
    var aliasesComplete = catalog.complete && !issues.containsKey('identities');
    for (final candidate in wikiCandidates) {
      final note = root == null
          ? null
          : notes[p.posix.join(root, candidate.relativePath)];
      if (note == null || !note.semantics.aliasesComplete) {
        aliasesComplete = false;
        continue;
      }
      try {
        aliasPaths[candidate.relativePath] = Set.unmodifiable(
          await resolver.comparisonKeys(note.semantics.aliases),
        );
      } on Object {
        aliasesComplete = false;
        issues['aliases:${candidate.relativePath}'] = [
          'alias normalization unavailable',
        ];
      }
      if (!stable()) return null;
    }
    final aliases = WikiAliasSnapshot(
      byPath: Map.unmodifiable(aliasPaths),
      complete: aliasesComplete,
      epoch: epoch,
    );
    final lookup = WikiCandidateLookup(wikiCandidates, aliases);
    final pathMatches = <String, List<String>>{};
    var pathsComplete = catalog.complete;
    if (root != null) {
      final paths = <String>{
        for (final entry in catalog.entries)
          if (!entry.isDirectory) entry.relativePath,
        for (final key in notes.keys)
          if (p.posix.isWithin(root, key)) p.posix.relative(key, from: root),
      }.toList();
      try {
        final keys = await resolver.comparisonKeys(paths);
        for (var i = 0; i < paths.length; i++) {
          pathMatches.putIfAbsent(keys[i], () => []).add(paths[i]);
        }
      } on Object {
        pathsComplete = false;
        issues['paths'] = ['path normalization unavailable'];
      }
    }
    final edges = <WorkspaceReferenceEdge>[];
    final tags = <String, List<WorkspaceTagOccurrence>>{};
    final resolutionCache =
        <String, ({WorkspaceReferenceStatus status, List<String> paths})>{};
    for (final entry in notes.entries) {
      final note = entry.value;
      final originPath = note.source.path == null ? null : entry.key;
      for (final tag in note.semantics.tags) {
        tags
            .putIfAbsent(tag.name.toLowerCase(), () => [])
            .add(WorkspaceTagOccurrence(note, tag));
      }
      for (final reference in note.semantics.references) {
        if (!stable()) return null;
        final wiki =
            reference.kind == IanvsMarkdownSourceReferenceKind.wikiLink ||
            reference.kind == IanvsMarkdownSourceReferenceKind.wikiEmbed;
        final cacheKey =
            '$originPath\u0000${reference.kind}\u0000${reference.target}';
        var resolved = resolutionCache[cacheKey];
        final imageEmbed =
            reference.kind == IanvsMarkdownSourceReferenceKind.wikiEmbed &&
            IanvsMarkdownWikiEmbedReference(
              source: reference.range.textInside(note.source.text),
              target: reference.target,
              note: reference.target,
            ).isImageEmbed;
        resolved ??= imageEmbed
            ? (status: WorkspaceReferenceStatus.external, paths: <String>[])
            : wiki
            ? await _resolveWiki(
                reference.target,
                originPath,
                catalog,
                wikiCandidates,
                aliases,
                lookup,
              )
            : await _resolveMarkdown(
                reference.target,
                originPath,
                pathMatches,
                pathsComplete,
              );
        resolutionCache[cacheKey] = resolved;
        if (resolved.status == WorkspaceReferenceStatus.unknown) {
          issues
              .putIfAbsent(note.source.key, () => [])
              .add('A reference target could not be resolved.');
        }
        edges.add(
          WorkspaceReferenceEdge(
            note: note,
            reference: reference,
            status: resolved.status,
            candidatePaths: List.unmodifiable(resolved.paths),
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
    }
    if (!stable()) return null;
    return WorkspaceReferenceSnapshot(
      epoch: epoch,
      contentRevision: contentRevision,
      catalogRevision: catalogRevision,
      catalog: catalog,
      notes: Map.unmodifiable(notes),
      edges: List.unmodifiable(edges),
      tags: Map.unmodifiable({
        for (final entry in tags.entries)
          entry.key: List<WorkspaceTagOccurrence>.unmodifiable(entry.value),
      }),
      aliases: aliases,
      wikiCandidates: List.unmodifiable(wikiCandidates),
      noteCandidates: List.unmodifiable(noteCandidates),
      issues: Map.unmodifiable({
        for (final entry in issues.entries)
          entry.key: List<String>.unmodifiable(entry.value.toSet()),
      }),
      knownDocuments: known,
    );
  }

  Future<({WorkspaceReferenceStatus status, List<String> paths})> _resolveWiki(
    String target,
    String? originPath,
    WorkspaceCatalogSnapshot catalog,
    List<WikiNoteCandidate> candidates,
    WikiAliasSnapshot aliases,
    WikiCandidateLookup lookup,
  ) async {
    if (target.isEmpty &&
        originPath != null &&
        index.root != null &&
        p.posix.isWithin(index.root!, originPath)) {
      return (
        status: WorkspaceReferenceStatus.resolved,
        paths: [p.posix.relative(originPath, from: index.root)],
      );
    }
    final result = await resolver.resolve(
      target,
      originPath: originPath,
      catalog: catalog,
      knownCandidates: candidates,
      aliases: aliases,
      lookup: lookup,
    );
    return (
      status: switch (result.status) {
        WikiNoteStatus.resolved => WorkspaceReferenceStatus.resolved,
        WikiNoteStatus.ambiguous => WorkspaceReferenceStatus.ambiguous,
        WikiNoteStatus.missing => WorkspaceReferenceStatus.missing,
        _ => WorkspaceReferenceStatus.unknown,
      },
      paths: result.candidates
          .map((candidate) => candidate.relativePath)
          .toList(),
    );
  }

  Future<({WorkspaceReferenceStatus status, List<String> paths})>
  _resolveMarkdown(
    String target,
    String? originPath,
    Map<String, List<String>> pathMatches,
    bool complete,
  ) async {
    const unknown = (
      status: WorkspaceReferenceStatus.unknown,
      paths: <String>[],
    );
    const external = (
      status: WorkspaceReferenceStatus.external,
      paths: <String>[],
    );
    final root = index.root;
    // The parser already decoded the destination once. Do not decode % again.
    final scheme = RegExp(
      r'^([A-Za-z][A-Za-z0-9+.-]*):',
    ).firstMatch(target)?.group(1)?.toLowerCase();
    if (scheme != null) {
      // file: URI authority/encoding requires a separate source-safe contract.
      // It must not disappear from a future rename's coverage as "external".
      return const {'http', 'https', 'mailto', 'data'}.contains(scheme)
          ? external
          : unknown;
    }
    if (target.startsWith('//')) return unknown;
    if (root == null ||
        originPath == null ||
        !p.posix.isWithin(root, originPath)) {
      return unknown;
    }
    final absolute = target.isEmpty
        ? originPath
        : p.posix.normalize(
            p.posix.isAbsolute(target)
                ? target
                : p.posix.join(p.posix.dirname(originPath), target),
          );
    if (!p.posix.isWithin(root, absolute)) return unknown;
    final relative = p.posix.relative(absolute, from: root);
    if (!safeWorkspaceRelativePath(relative)) return unknown;
    if (!isMarkdownName(relative)) return external;
    if (target.isEmpty) {
      return (status: WorkspaceReferenceStatus.resolved, paths: [relative]);
    }
    try {
      final key = (await resolver.comparisonKeys([relative])).single;
      final matches = pathMatches[key] ?? const <String>[];
      return (
        status: matches.length > 1
            ? WorkspaceReferenceStatus.ambiguous
            : !complete
            ? WorkspaceReferenceStatus.unknown
            : matches.isEmpty
            ? WorkspaceReferenceStatus.missing
            : WorkspaceReferenceStatus.resolved,
        paths: matches,
      );
    } on Object {
      return unknown;
    }
  }

  Future<WikiNoteResolution> resolveWiki(
    String target, {
    required String? originPath,
    bool refreshMetadata = false,
  }) async {
    // Explicit paths never consult destination aliases. Fragment navigation is
    // still explicitly unsupported by the existing Wiki navigation contract.
    if (target.contains('/') || target.contains('#')) {
      return resolver.resolve(
        target,
        originPath: originPath,
        refresh: refreshMetadata,
      );
    }
    final value = await refresh(refreshMetadata: refreshMetadata);
    final result = await resolver.resolve(
      target,
      originPath: originPath,
      catalog: value.catalog,
      knownCandidates: value.wikiCandidates,
      aliases: value.aliases,
    );
    if (_disposed ||
        value.epoch != index.epoch ||
        value.contentRevision != index.contentRevision ||
        value.catalogRevision != index.catalogRevision) {
      return WikiNoteResolution(
        WikiNoteStatus.unavailable,
        epoch: value.epoch,
        message: 'The source or catalog changed. Follow the link again.',
      );
    }
    return result;
  }

  WorkspaceReferenceImpact previewImpact(String relativePath) {
    final value = _snapshot;
    if (_stale || value == null) {
      return const WorkspaceReferenceImpact(
        references: [],
        possibleReferences: [],
        complete: false,
      );
    }
    return value.impact(relativePath);
  }

  void cancel() {
    if (_disposed) return;
    _cancelled = true;
    _pendingMetadataRefresh = false;
    ++_request;
    _timer?.cancel();
    _stale = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    index.removeListener(_indexChanged);
    _cache.clear();
    _snapshot = null;
    super.dispose();
  }
}

/// Exact source navigation text, never a normalized destination or rendered label.
String workspaceReferenceSnippet(String source, TextRange range) {
  var start = math.max(0, range.start - 40);
  var end = math.min(source.length, range.end + 80);
  // Avoid slicing a supplementary scalar at either display boundary.
  if (start > 0 &&
      source.codeUnitAt(start) >= 0xdc00 &&
      source.codeUnitAt(start) <= 0xdfff) {
    start--;
  }
  if (end < source.length &&
      source.codeUnitAt(end) >= 0xdc00 &&
      source.codeUnitAt(end) <= 0xdfff) {
    end++;
  }
  return source
      .substring(start, end)
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');
}
