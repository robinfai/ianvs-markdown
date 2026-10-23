import 'package:path/path.dart' as p;

import 'attachment_repository.dart';
import 'workspace_index.dart';
import 'workspace_index_source.dart';

typedef WikiPathNormalizer = Future<List<String>> Function(List<String> paths);

enum WikiNoteStatus { resolved, ambiguous, missing, unavailable, unsupported }

class WikiNoteCandidate {
  const WikiNoteCandidate({
    required this.relativePath,
    required this.comparisonPath,
    this.metadata,
    this.sessionId,
  });
  final String relativePath;
  final String comparisonPath;
  final WorkspaceMetadata? metadata;
  final String? sessionId;
}

class WikiNoteResolution {
  const WikiNoteResolution(
    this.status, {
    this.candidates = const [],
    this.message,
    this.createPath,
    required this.epoch,
  });
  final WikiNoteStatus status;
  final List<WikiNoteCandidate> candidates;
  final String? message;
  final String? createPath;
  final int epoch;
}

/// Bounded YAML aliases from the same effective source snapshot as references.
/// Keys are real catalog paths; values are native NFC/lowercase comparison keys.
class WikiAliasSnapshot {
  const WikiAliasSnapshot({
    required this.byPath,
    required this.complete,
    required this.epoch,
  });
  final Map<String, Set<String>> byPath;
  final bool complete;
  final int epoch;
}

/// Immutable lookup for resolving many references without rescanning candidates.
class WikiCandidateLookup {
  WikiCandidateLookup(
    List<WikiNoteCandidate> notes,
    WikiAliasSnapshot? aliases,
  ) {
    for (final note in notes) {
      _paths.putIfAbsent(note.comparisonPath, () => []).add(note);
      _names
          .putIfAbsent(p.posix.basename(note.comparisonPath), () => [])
          .add(note);
      for (final alias in aliases?.byPath[note.relativePath] ?? <String>{}) {
        _aliases.putIfAbsent(alias, () => []).add(note);
      }
    }
  }
  final _paths = <String, List<WikiNoteCandidate>>{};
  final _names = <String, List<WikiNoteCandidate>>{};
  final _aliases = <String, List<WikiNoteCandidate>>{};
  List<WikiNoteCandidate> matches(
    String key, {
    required bool byPath,
    String? aliasKey,
  }) {
    if (byPath) return List.of(_paths[key] ?? const []);
    final matches = <String, WikiNoteCandidate>{
      for (final note in _names[key] ?? const <WikiNoteCandidate>[])
        note.relativePath: note,
      for (final note in _aliases[aliasKey] ?? const <WikiNoteCandidate>[])
        note.relativePath: note,
    };
    return matches.values.toList()
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
  }
}

/// The application's deliberately conservative Wiki policy, not a claim about
/// Obsidian's undocumented duplicate-name priority. Raw Wiki paths are NOT URIs.
/// Filename identities and YAML aliases contribute separate candidate matches.
class WikiNoteResolver {
  WikiNoteResolver(this.index, {WikiPathNormalizer? normalize})
    : normalize = normalize ?? const AppleAttachmentSource().normalize;
  final WorkspaceIndex index;
  final WikiPathNormalizer normalize;

  Future<List<String>> comparisonKeys(List<String> paths) => _keys(paths);

  Future<List<String>> _keys(List<String> paths) async {
    final keys = <String>[];
    for (var start = 0; start < paths.length; start += 32) {
      final batch = paths.skip(start).take(32).toList();
      // ASCII has no nontrivial NFC composition. This also keeps portable test
      // hosts usable without a native normalization plugin for ASCII vaults.
      if (batch.every((s) => s.codeUnits.every((c) => c < 128))) {
        keys.addAll(batch.map((s) => s.toLowerCase()));
      } else {
        final values = await normalize(batch);
        if (values.length != batch.length) {
          throw const WorkspaceIndexFailure(WorkspaceReadIssue.unavailable);
        }
        keys.addAll(values);
      }
    }
    return keys;
  }

  Future<List<WikiNoteCandidate>> candidates(
    WorkspaceCatalogSnapshot catalog, {
    bool allMarkdownExtensions = false,
  }) async {
    bool included(String path) => allMarkdownExtensions
        ? isMarkdownName(path)
        : path.toLowerCase().endsWith('.md');
    final root = index.root;
    if (root == null || catalog.epoch != index.epoch) return [];
    final entries = <String, WikiNoteCandidate>{};
    for (final entry in catalog.entries) {
      if (entry.isDirectory || !included(entry.relativePath)) {
        continue;
      }
      entries[entry.relativePath] = WikiNoteCandidate(
        relativePath: entry.relativePath,
        comparisonPath: entry.comparisonPath ?? '',
        metadata: entry,
      );
    }
    for (final buffer in index.buffers) {
      final path = buffer.path;
      if (path == null || !p.posix.isWithin(root, path) || !included(path)) {
        continue;
      }
      var relative = p.posix.relative(path, from: root);
      // A prior ordinary Markdown open may use a case/NFC alias on a
      // case-insensitive volume. Only filesystem evidence may coalesce it.
      final identitySource = index.source;
      if (!entries.containsKey(relative) &&
          identitySource is WorkspacePathIdentitySource) {
        try {
          final actual = await (identitySource as WorkspacePathIdentitySource)
              .resolveWorkspacePath(root, relative);
          if (safeWorkspaceRelativePath(actual.relativePath)) {
            relative = actual.relativePath;
          }
        } on Object {
          // Deleted dirty notes still remain addressable by their saved path.
          // An unverifiable alias is not silently merged with another identity.
        }
      }
      if (!safeWorkspaceRelativePath(relative)) continue;
      if (entries[relative]?.sessionId case final previousSession?) {
        if (previousSession != buffer.sessionId) {
          // Never choose between two pre-existing buffers for one verified file.
          throw const WorkspaceIndexFailure(WorkspaceReadIssue.changed);
        }
      }
      entries[relative] = WikiNoteCandidate(
        relativePath: relative,
        comparisonPath: entries[relative]?.comparisonPath ?? '',
        metadata: entries[relative]?.metadata,
        sessionId: buffer.sessionId,
      );
    }
    final unknown = entries.values
        .where((e) => e.comparisonPath.isEmpty)
        .toList();
    final keys = await _keys(unknown.map((e) => e.relativePath).toList());
    for (var i = 0; i < unknown.length; i++) {
      final old = unknown[i];
      entries[old.relativePath] = WikiNoteCandidate(
        relativePath: old.relativePath,
        comparisonPath: keys[i],
        metadata: old.metadata,
        sessionId: old.sessionId,
      );
    }
    if (catalog.epoch != index.epoch) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.cancelled);
    }
    return entries.values.toList()
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
  }

  Future<WikiNoteResolution> resolve(
    String rawTarget, {
    required String? originPath,
    bool refresh = false,
    WorkspaceCatalogSnapshot? catalog,
    List<WikiNoteCandidate>? knownCandidates,
    WikiAliasSnapshot? aliases,
    WikiCandidateLookup? lookup,
    // Read-only callers do not need a missing-note creation proposal. Defaults
    // preserve navigation behavior, including the existing createPath contract.
    bool includeCreatePath = true,
    // A bounded preview may charge/check each query and alias normalization at
    // its own async boundary. Ordinary navigation keeps the native normalizer.
    WikiPathNormalizer? resolutionKeys,
  }) async {
    final keys = resolutionKeys ?? _keys;
    final epoch = index.epoch;
    WikiNoteResolution unavailable(String message) => WikiNoteResolution(
      WikiNoteStatus.unavailable,
      epoch: epoch,
      message: message,
    );
    final root = index.root;
    if (root == null ||
        originPath == null ||
        !p.posix.isWithin(root, originPath)) {
      return unavailable(
        'Open a workspace folder and a note inside it to use Wiki links.',
      );
    }
    final target = rawTarget.trim();
    if (target.contains('#')) {
      return WikiNoteResolution(
        WikiNoteStatus.unsupported,
        epoch: epoch,
        message:
            'Wiki heading and block navigation is not available yet. Open the note without its #fragment.',
      );
    }
    if (target.isEmpty ||
        target.length > 4096 ||
        target.contains(RegExp(r'[\\:\x00-\x1f\x7f|\[\]]'))) {
      return WikiNoteResolution(
        WikiNoteStatus.unsupported,
        epoch: epoch,
        message: 'This Wiki target is not a supported note path.',
      );
    }
    final relative = target.startsWith('./') || target.startsWith('../');
    final anchored = target.startsWith('/');
    final path = p.posix.normalize(
      relative
          ? p.posix.join(
              p.posix.dirname(p.posix.relative(originPath, from: root)),
              target,
            )
          : anchored
          ? target.substring(1)
          : target,
    );
    if (!safeWorkspaceRelativePath(path) || path.split('/').length > 65) {
      return WikiNoteResolution(
        WikiNoteStatus.unsupported,
        epoch: epoch,
        message:
            'Wiki links must stay inside the current workspace, outside hidden folders.',
      );
    }
    final proposed = path.toLowerCase().endsWith('.md') ? path : '$path.md';
    try {
      catalog ??= await index.catalog(refresh: refresh);
      if (catalog.epoch != epoch ||
          (aliases != null && aliases.epoch != epoch)) {
        return unavailable('The workspace changed. Follow the link again.');
      }
      final notes = knownCandidates ?? await candidates(catalog);
      final key = (await keys([proposed])).single;
      if (epoch != index.epoch) {
        return unavailable('The workspace changed. Follow the link again.');
      }
      final byPath = relative || anchored || target.contains('/');
      final aliasKey = !byPath && aliases != null
          ? (await keys([target])).single
          : null;
      if (epoch != index.epoch) {
        return unavailable('The workspace changed. Follow the link again.');
      }
      final complete =
          catalog.complete && (byPath || aliases == null || aliases.complete);
      final matches = (lookup ?? WikiCandidateLookup(notes, aliases)).matches(
        key,
        byPath: byPath,
        aliasKey: aliasKey,
      );
      if (matches.length > 1) {
        return WikiNoteResolution(
          WikiNoteStatus.ambiguous,
          epoch: epoch,
          candidates: matches,
          message:
              'Choose a note. Names differing only by case or Unicode normalization are also ambiguous.'
              '${complete ? '' : ' The catalog or aliases are incomplete; only known candidates are shown.'}',
        );
      }
      if (!complete) {
        return WikiNoteResolution(
          WikiNoteStatus.unavailable,
          epoch: epoch,
          candidates: matches,
          message:
              'The note catalog or aliases are incomplete or unavailable. Use an explicit workspace path, or retry after files are locally available; no missing note will be created.',
        );
      }
      if (matches.length == 1) {
        return WikiNoteResolution(
          WikiNoteStatus.resolved,
          epoch: epoch,
          candidates: matches,
        );
      }
      if (!includeCreatePath) {
        return WikiNoteResolution(
          WikiNoteStatus.missing,
          epoch: epoch,
          message: 'No matching .md note or alias.',
        );
      }
      final parent = p.posix.dirname(proposed);
      final parentKey = p.posix.dirname(key);
      final parents = catalog.entries.where((e) => e.isDirectory).toList();
      final parentKeys = await keys(
        parents.map((e) => e.relativePath).toList(),
      );
      final parentMatches = <String>[
        for (var i = 0; i < parents.length; i++)
          if (parentKeys[i] == parentKey) parents[i].relativePath,
      ];
      final createPath = parent == '.'
          ? proposed
          : parentMatches.length == 1
          ? p.posix.join(parentMatches.single, p.posix.basename(proposed))
          : null;
      return WikiNoteResolution(
        WikiNoteStatus.missing,
        epoch: epoch,
        createPath: createPath,
        message: createPath == null
            ? 'The note is missing and its parent folder is unavailable or ambiguous. Create the folder yourself first.'
            : 'No matching .md note${aliases == null ? ' (aliases were not searched)' : ' or alias'}. Create "$createPath"?',
      );
    } on Object catch (error) {
      return unavailable(
        'Unable to resolve this note (${workspaceReadIssue(error).name}). No file was created.',
      );
    }
  }
}
