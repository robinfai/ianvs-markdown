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

/// The application's deliberately conservative Wiki policy, not a claim about
/// Obsidian's undocumented duplicate-name priority. Raw Wiki paths are NOT URIs.
/// Display aliases never become destination aliases; YAML aliases are deferred.
class WikiNoteResolver {
  WikiNoteResolver(this.index, {WikiPathNormalizer? normalize})
    : normalize = normalize ?? const AppleAttachmentSource().normalize;
  final WorkspaceIndex index;
  final WikiPathNormalizer normalize;

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
    WorkspaceCatalogSnapshot catalog,
  ) async {
    final root = index.root;
    if (root == null || catalog.epoch != index.epoch) return [];
    final entries = <String, WikiNoteCandidate>{};
    for (final entry in catalog.entries) {
      if (entry.isDirectory ||
          !entry.relativePath.toLowerCase().endsWith('.md')) {
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
      if (path == null ||
          !p.posix.isWithin(root, path) ||
          !path.toLowerCase().endsWith('.md')) {
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
  }) async {
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
      final catalog = await index.catalog(refresh: refresh);
      final notes = await candidates(catalog);
      final key = (await _keys([proposed])).single;
      if (epoch != index.epoch) {
        return unavailable('The workspace changed. Follow the link again.');
      }
      final byPath = relative || anchored || target.contains('/');
      final matches = notes
          .where(
            (note) => byPath
                ? note.comparisonPath == key
                : p.posix.basename(note.comparisonPath) == key,
          )
          .toList();
      if (matches.length > 1) {
        return WikiNoteResolution(
          WikiNoteStatus.ambiguous,
          epoch: epoch,
          candidates: matches,
          message:
              'Choose a note. Names differing only by case or Unicode normalization are also ambiguous.'
              '${catalog.complete ? '' : ' The catalog is incomplete; only known candidates are shown.'}',
        );
      }
      if (!catalog.complete) {
        return unavailable(
          'The note catalog is incomplete or unavailable. Retry after files are locally available; no missing note will be created.',
        );
      }
      if (matches.length == 1) {
        return WikiNoteResolution(
          WikiNoteStatus.resolved,
          epoch: epoch,
          candidates: matches,
        );
      }
      final parent = p.posix.dirname(proposed);
      final parentKey = p.posix.dirname(key);
      final parents = catalog.entries.where((e) => e.isDirectory).toList();
      final parentKeys = await _keys(
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
            : 'No matching .md note. Create "$createPath"? YAML aliases are not searched in this version.',
      );
    } on Object catch (error) {
      return unavailable(
        'Unable to resolve this note (${workspaceReadIssue(error).name}). No file was created.',
      );
    }
  }
}
