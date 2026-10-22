import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import 'attachment_resolver.dart';
import 'wiki_note_resolver.dart';
import 'workspace_index.dart';
import 'workspace_index_source.dart';
import 'workspace_reference_index.dart';

/// One exact UTF-16 source replacement, never a rendered-label replacement.
class WorkspaceReferenceEdit {
  const WorkspaceReferenceEdit(this.range, this.before, this.after);
  final TextRange range;
  final String before;
  final String after;
}

class WorkspaceNoteMoveFile {
  WorkspaceNoteMoveFile({
    required this.path,
    required this.destination,
    required this.source,
    required this.contents,
    required List<WorkspaceReferenceEdit> edits,
  }) : edits = List.unmodifiable(edits);
  final String path;
  final String destination;
  final WorkspaceNoteSnapshot source;
  final String contents;
  final List<WorkspaceReferenceEdit> edits;
}

class WorkspaceNoteMoveBlocker {
  const WorkspaceNoteMoveBlocker(this.code, this.message, {this.path});
  final String code;
  final String message;
  final String? path;
}

/// A read-only proposal, not a transaction and not authority to write.
/// Even a complete proposal requires fresh native identity/CAS preflight and
/// explicit user approval of this exact proposal before a future executor runs.
class WorkspaceNoteMovePlan {
  WorkspaceNoteMovePlan({
    required this.root,
    required this.snapshot,
    required this.sourcePath,
    required this.destinationPath,
    required List<WorkspaceNoteMoveFile> files,
    required List<WorkspaceNoteMoveBlocker> blockers,
    required List<AttachmentMetadata> attachmentRequirements,
  }) : files = List.unmodifiable(files),
       blockers = List.unmodifiable(blockers),
       attachmentRequirements = List.unmodifiable(attachmentRequirements);
  final String? root;
  final WorkspaceReferenceSnapshot snapshot;
  final String sourcePath;
  final String destinationPath;
  final List<WorkspaceNoteMoveFile> files;
  final List<WorkspaceNoteMoveBlocker> blockers;

  /// Metadata-only evidence. The future native preflight must verify these
  /// exact paths/revisions are regular, local files without downloading them.
  final List<AttachmentMetadata> attachmentRequirements;
  bool get complete => blockers.isEmpty;
  int get editCount => files.fold(0, (sum, file) => sum + file.edits.length);

  bool isCurrent(WorkspaceIndex index) =>
      root == index.root &&
      snapshot.epoch == index.epoch &&
      snapshot.contentRevision == index.contentRevision &&
      snapshot.catalogRevision == index.catalogRevision;
}

/// Bounded single-note planning over the existing effective-source index.
/// No IO, mutation, provider download, creation, rename or rollback API exists
/// here. Optional attachment metadata is supplied by the host's scoped index.
class WorkspaceNoteMovePlanner {
  WorkspaceNoteMovePlanner(
    this.references, {
    this.maximumFiles = 128,
    this.maximumBackupBytes = 32 * 1024 * 1024,
  });
  final WorkspaceReferenceIndex references;
  final int maximumFiles;
  final int maximumBackupBytes;

  Future<WorkspaceNoteMovePlan> build({
    required WorkspaceReferenceSnapshot snapshot,
    required String sourcePath,
    required String destinationPath,
    required Set<String> dirtySessionIds,
    AttachmentIndex? attachments,
  }) async {
    final index = references.index;
    final root = index.root;
    final blockers = <WorkspaceNoteMoveBlocker>[];
    final files = <WorkspaceNoteMoveFile>[];
    final assets = <String, AttachmentMetadata>{};
    void block(String code, String message, [String? path]) {
      if (!blockers.any((b) => b.code == code && b.path == path)) {
        blockers.add(WorkspaceNoteMoveBlocker(code, message, path: path));
      }
    }

    WorkspaceNoteMovePlan finish() {
      final plan = WorkspaceNoteMovePlan(
        root: root,
        snapshot: snapshot,
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        files: files,
        blockers: blockers,
        attachmentRequirements: assets.values.toList(),
      );
      if (!plan.isCurrent(index)) {
        block('stale', 'The workspace or source changed. Refresh the preview.');
        return WorkspaceNoteMovePlan(
          root: root,
          snapshot: snapshot,
          sourcePath: sourcePath,
          destinationPath: destinationPath,
          files: files,
          blockers: blockers,
          attachmentRequirements: assets.values.toList(),
        );
      }
      return plan;
    }

    if (snapshot.epoch != index.epoch ||
        snapshot.contentRevision != index.contentRevision ||
        snapshot.catalogRevision != index.catalogRevision) {
      block('stale', 'The workspace or source changed. Refresh the preview.');
      return finish();
    }
    if (root == null ||
        !safeWorkspaceRelativePath(sourcePath) ||
        !safeWorkspaceRelativePath(destinationPath) ||
        !isScalarAttachmentPath(sourcePath) ||
        !isScalarAttachmentPath(destinationPath)) {
      block('scope', 'Both paths must stay inside the selected workspace.');
      return finish();
    }
    if (sourcePath == destinationPath) {
      block('samePath', 'Choose a different destination.');
      return finish();
    }
    final metadata = {
      for (final entry in snapshot.catalog.entries) entry.relativePath: entry,
    };
    final sourceEntry = metadata[sourcePath];
    if (sourceEntry == null || sourceEntry.isDirectory) {
      block(
        'singleNoteOnly',
        'Reference maintenance supports one existing note, not folders or multiple items.',
        sourcePath,
      );
      return finish();
    }
    if (!isMarkdownName(destinationPath)) {
      block('extension', 'Use a supported Markdown or text extension.');
      return finish();
    }
    if (p.posix.extension(sourcePath).toLowerCase() !=
        p.posix.extension(destinationPath).toLowerCase()) {
      block(
        'extensionChange',
        'Changing the note extension can change Wiki and alias eligibility. Automatic maintenance does not support it yet.',
      );
    }
    if (!snapshot.complete || !snapshot.catalog.complete) {
      for (final issue in snapshot.issues.entries) {
        block('coverage', issue.value.join('; '), issue.key);
      }
      block(
        'incomplete',
        'Reference coverage is incomplete. No automatic maintenance is safe.',
      );
    }
    final keys = <String, String>{};
    Future<String> key(String value) async => keys[value] ??=
        (await references.resolver.comparisonKeys([value])).single;
    final String destinationKey;
    try {
      // Normalize bounded catalog paths in the resolver's native-sized batches,
      // rather than issuing one platform request per filename.
      final paths = <String>{
        sourcePath,
        destinationPath,
        ...metadata.keys,
        for (final candidate in snapshot.noteCandidates) candidate.relativePath,
      }.toList();
      final normalized = await references.resolver.comparisonKeys(paths);
      for (var i = 0; i < paths.length; i++) {
        keys[paths[i]] = normalized[i];
      }
      destinationKey = await key(destinationPath);
      if (destinationKey == await key(sourcePath)) {
        block(
          'sameIdentitySpelling',
          'Case-only or Unicode-equivalent moves need a separate safe protocol.',
        );
      }
      // Effective buffer identities also reserve destinations. A deleted file
      // can remain open and dirty without appearing in the disk catalog.
      for (final path in <String>{
        ...metadata.keys,
        for (final candidate in snapshot.noteCandidates) candidate.relativePath,
      }) {
        if (path != sourcePath && await key(path) == destinationKey) {
          block(
            'destinationExists',
            'The destination already exists or has an equivalent spelling.',
            destinationPath,
          );
        }
      }
      final parent = p.posix.dirname(destinationPath);
      if (parent != '.' && metadata[parent]?.local == false) {
        block(
          'offline',
          'The destination folder is not locally available.',
          parent,
        );
      }
      if (parent != '.' &&
          !snapshot.catalog.entries.any(
            (entry) => entry.isDirectory && entry.relativePath == parent,
          )) {
        block(
          'destinationParent',
          'The exact destination folder must already exist.',
          parent,
        );
      }
    } on Object {
      block('normalization', 'Filename normalization is unavailable.');
      return finish();
    }
    final originPaths = <WorkspaceSemanticNote, String>{
      for (final entry in snapshot.notes.entries)
        if (p.posix.isWithin(root, entry.key))
          entry.value: p.posix.relative(entry.key, from: root),
    };
    final moving = originPaths.entries
        .where((entry) => entry.value == sourcePath)
        .firstOrNull
        ?.key;
    if (moving == null) {
      block('sourceUnavailable', 'The note source is unavailable.', sourcePath);
      return finish();
    }
    final newCandidates = <WikiNoteCandidate>[
      for (final candidate in snapshot.wikiCandidates)
        if (candidate.relativePath != sourcePath)
          candidate
        else if (destinationPath.toLowerCase().endsWith('.md'))
          WikiNoteCandidate(
            relativePath: destinationPath,
            comparisonPath: destinationKey,
          ),
      if (!sourcePath.toLowerCase().endsWith('.md') &&
          destinationPath.toLowerCase().endsWith('.md'))
        WikiNoteCandidate(
          relativePath: destinationPath,
          comparisonPath: destinationKey,
        ),
    ];
    final newAliases = WikiAliasSnapshot(
      byPath: {
        for (final entry in snapshot.aliases.byPath.entries)
          (entry.key == sourcePath ? destinationPath : entry.key): entry.value,
      },
      complete: snapshot.aliases.complete,
      epoch: snapshot.epoch,
    );
    final newCatalog = WorkspaceCatalogSnapshot(
      epoch: snapshot.catalog.epoch,
      entries: snapshot.catalog.entries,
      complete: snapshot.catalog.complete,
      issues: snapshot.catalog.issues,
    );
    final lookup = WikiCandidateLookup(newCandidates, newAliases);
    final newNoteKeys = <String>{
      for (final candidate in snapshot.noteCandidates)
        if (candidate.relativePath != sourcePath)
          await key(candidate.relativePath),
      destinationKey,
    };
    final byNote = <WorkspaceSemanticNote, List<WorkspaceReferenceEdge>>{};
    for (final edge in snapshot.edges) {
      byNote.putIfAbsent(edge.note, () => []).add(edge);
    }
    var backupBytes = 0;
    for (final entry in originPaths.entries) {
      final note = entry.key;
      final origin = entry.value;
      final moved = origin == sourcePath;
      final newOrigin = moved ? destinationPath : origin;
      final directoryChanged =
          p.posix.dirname(origin) != p.posix.dirname(newOrigin);
      final changes = <String, WorkspaceReferenceEdit>{};
      final targets = <IanvsMarkdownSourceReference, String>{};
      for (final edge in byNote[note] ?? const <WorkspaceReferenceEdge>[]) {
        final ref = edge.reference;
        final wiki = _wiki(ref);
        if (edge.status == WorkspaceReferenceStatus.unknown ||
            edge.status == WorkspaceReferenceStatus.ambiguous) {
          block(
            'unresolved',
            'An unknown or ambiguous reference prevents complete maintenance.',
            origin,
          );
          continue;
        }
        if (ref.target.isEmpty) continue;
        String? nextTarget;
        if (!wiki && edge.status == WorkspaceReferenceStatus.missing) {
          final absolute = p.posix.normalize(
            p.posix.isAbsolute(ref.target)
                ? ref.target
                : p.posix.join(root, p.posix.dirname(newOrigin), ref.target),
          );
          if (p.posix.isWithin(root, absolute) &&
              newNoteKeys.contains(
                await key(p.posix.relative(absolute, from: root)),
              )) {
            block(
              'newMarkdownResolution',
              'This move would change a previously missing Markdown reference.',
              origin,
            );
          }
        }
        if (wiki && edge.status != WorkspaceReferenceStatus.external) {
          final after = await references.resolver.resolve(
            ref.target,
            originPath: p.posix.join(root, newOrigin),
            catalog: newCatalog,
            knownCandidates: newCandidates,
            aliases: newAliases,
            lookup: lookup,
          );
          final expected = edge.targetPath == sourcePath
              ? destinationPath
              : edge.targetPath;
          if (expected == null) {
            if (after.status != WikiNoteStatus.missing) {
              block(
                'newWikiResolution',
                'This move would change a previously missing Wiki reference.',
                origin,
              );
            }
          } else if (after.status != WikiNoteStatus.resolved ||
              after.candidates.single.relativePath != expected) {
            if (!expected.toLowerCase().endsWith('.md') ||
                expected.contains(RegExp(r'[\[\]#|\\\r\n]'))) {
              block(
                'wikiSpelling',
                'The new path cannot be represented safely as a Wiki target.',
                origin,
              );
            } else {
              nextTarget = '/$expected';
              if (!ref.target.toLowerCase().endsWith('.md')) {
                nextTarget = nextTarget.substring(0, nextTarget.length - 3);
              }
              final rewritten = await references.resolver.resolve(
                nextTarget,
                originPath: p.posix.join(root, newOrigin),
                catalog: newCatalog,
                knownCandidates: newCandidates,
                aliases: newAliases,
                lookup: lookup,
              );
              if (rewritten.status != WikiNoteStatus.resolved ||
                  rewritten.candidates.single.relativePath != expected) {
                block(
                  'wikiResolution',
                  'The proposed Wiki spelling does not uniquely preserve its target.',
                  origin,
                );
              }
            }
          }
        } else if (edge.status == WorkspaceReferenceStatus.resolved) {
          final target = edge.targetPath == sourcePath
              ? destinationPath
              : edge.targetPath!;
          if (edge.targetPath == sourcePath || moved) {
            nextTarget = _markdownPath(root, newOrigin, target, ref.target);
          }
        } else if (directoryChanged && !_remote(ref.target)) {
          // Non-note assets use the image renderer's scoped resolver, not the
          // note resolver's intentionally external classification.
          if (attachments == null ||
              !attachmentExtensions.contains(
                p.posix.extension(ref.target).toLowerCase(),
              )) {
            block(
              'assetCoverage',
              'A local outgoing target needs verified attachment metadata or is unsupported.',
              origin,
            );
            continue;
          }
          try {
            // Semantic Markdown paths were decoded once already. Passing the
            // wiki mode here avoids a second percent decode; kind is restored
            // below through a dedicated source spelling.
            final spelling = wiki
                ? ref.target
                : _encodeMarkdownPath(ref.target);
            final reference = AttachmentReference(
              spelling,
              wiki ? AttachmentLinkKind.wiki : AttachmentLinkKind.markdown,
            );
            final asset = attachments.resolve(
              reference: reference,
              documentRelativePath: origin,
              normalizedReference: await key(reference.path),
              normalizedDocument: await key(origin),
            );
            assets[asset.relativePath] = asset;
            if (asset.revision == null) {
              block(
                'assetRevision',
                'The attachment has no stable revision for native preflight.',
                asset.relativePath,
              );
              continue;
            }
            if (wiki) {
              if (asset.relativePath.contains(RegExp(r'[\[\]#|\\\r\n]'))) {
                block(
                  'wikiSpelling',
                  'The attachment path cannot be represented safely as a Wiki target.',
                  origin,
                );
              } else {
                nextTarget = '/${asset.relativePath}';
              }
            } else {
              // Image Markdown leading slash means workspace-root, unlike
              // ordinary note links. Explicit relative avoids that ambiguity
              // and suppresses the renderer's root fallback.
              nextTarget = p.posix.relative(
                asset.relativePath,
                from: p.posix.dirname(newOrigin),
              );
              if (!nextTarget.startsWith('../')) nextTarget = './$nextTarget';
            }
          } on Object {
            block(
              'assetResolution',
              'The outgoing attachment is missing, ambiguous or unavailable.',
              origin,
            );
          }
        }
        if (nextTarget == null || nextTarget == ref.target) continue;
        final replacement = wiki ? nextTarget : _encodeMarkdownPath(nextTarget);
        final range = ref.destinationRange;
        final before = range.textInside(note.source.text);
        final identity = '${range.start}:${range.end}';
        final previous = changes[identity];
        if (previous != null && previous.after != replacement) {
          block(
            'sharedDestination',
            'A shared reference definition has conflicting rewrites.',
            origin,
          );
          continue;
        }
        targets[ref] = nextTarget;
        changes[identity] = WorkspaceReferenceEdit(range, before, replacement);
      }
      if (!moved && changes.isEmpty) continue;
      final disk = metadata[origin];
      if (disk == null || disk.isDirectory || disk.revision.isEmpty) {
        block(
          'sourceUnavailable',
          'The affected note needs a verified on-disk identity.',
          origin,
        );
      }
      var location = origin;
      while (location != '.') {
        if (metadata[location]?.local == false) {
          block(
            'offline',
            'The affected note or parent folder is not locally available, even if a buffer is open.',
            location,
          );
        }
        location = p.posix.dirname(location);
      }
      if (note.source.externalConflict ||
          (note.source.sessionId != null &&
              dirtySessionIds.contains(note.source.sessionId))) {
        block(
          'dirty',
          'Save or resolve the affected open note before automatic maintenance.',
          origin,
        );
      }
      final edits = changes.values.toList()
        ..sort((a, b) => a.range.start.compareTo(b.range.start));
      var contents = note.source.text;
      var end = 0;
      var overlap = false;
      for (final edit in edits) {
        if (edit.range.start < end) overlap = true;
        end = edit.range.end;
      }
      if (overlap) {
        block('overlapping', 'Source replacement ranges overlap.', origin);
        continue;
      }
      for (final edit in edits.reversed) {
        contents = contents.replaceRange(
          edit.range.start,
          edit.range.end,
          edit.after,
        );
      }
      if (!_verifyReparse(note, contents, edits, targets)) {
        block(
          'reparse',
          'The rewritten source did not preserve every reference and metadata item.',
          origin,
        );
      }
      backupBytes +=
          utf8.encode(note.source.text).length + utf8.encode(contents).length;
      if (files.length >= maximumFiles || backupBytes > maximumBackupBytes) {
        block(
          'transactionBudget',
          'The affected set exceeds the bounded recovery budget.',
        );
        break;
      }
      files.add(
        WorkspaceNoteMoveFile(
          path: origin,
          destination: newOrigin,
          source: note.source,
          contents: contents,
          edits: edits,
        ),
      );
    }
    return finish();
  }
}

bool _wiki(IanvsMarkdownSourceReference reference) =>
    reference.kind == IanvsMarkdownSourceReferenceKind.wikiLink ||
    reference.kind == IanvsMarkdownSourceReferenceKind.wikiEmbed;

bool _remote(String path) =>
    RegExp(r'^(?:https?|mailto|data):', caseSensitive: false).hasMatch(path);

String _markdownPath(String root, String origin, String target, String old) {
  if (p.posix.isAbsolute(old)) return p.posix.join(root, target);
  var next = p.posix.relative(target, from: p.posix.dirname(origin));
  if (old.startsWith('./') && !next.startsWith('../')) next = './$next';
  return next;
}

String _encodeMarkdownPath(String path) => path
    .split('/')
    .map(
      (segment) => Uri.encodeComponent(segment)
          .replaceAll('(', '%28')
          .replaceAll(')', '%29')
          .replaceAll("'", '%27')
          .replaceAll('*', '%2A')
          .replaceAll('!', '%21'),
    )
    .join('/');

bool _verifyReparse(
  WorkspaceSemanticNote note,
  String contents,
  List<WorkspaceReferenceEdit> edits,
  Map<IanvsMarkdownSourceReference, String> targets,
) {
  final parsed = parseIanvsMarkdownNoteSemantics(contents);
  if (!parsed.complete ||
      parsed.references.length != note.semantics.references.length ||
      parsed.tags.length != note.semantics.tags.length ||
      !listEquals(parsed.aliases, note.semantics.aliases)) {
    return false;
  }
  final cumulative = <int>[0];
  for (final edit in edits) {
    cumulative.add(cumulative.last + edit.after.length - edit.before.length);
  }
  int translated(int offset) {
    var low = 0;
    var high = edits.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (edits[middle].range.end <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return offset + cumulative[low];
  }

  TextRange range(TextRange old) =>
      TextRange(start: translated(old.start), end: translated(old.end));
  final actual =
      <
        (IanvsMarkdownSourceReferenceKind, int, int),
        List<IanvsMarkdownSourceReference>
      >{};
  for (final ref in parsed.references) {
    actual
        .putIfAbsent((ref.kind, ref.range.start, ref.range.end), () => [])
        .add(ref);
  }
  final replacements = {
    for (final edit in edits) (edit.range.start, edit.range.end): edit,
  };
  final tags = {
    for (final tag in parsed.tags) (tag.name, tag.range.start, tag.range.end),
  };
  for (final before in note.semantics.references) {
    final translatedRange = range(before.range);
    final candidates =
        actual[(before.kind, translatedRange.start, translatedRange.end)];
    final after = candidates == null || candidates.isEmpty
        ? null
        : candidates.removeLast();
    final matchingEdit =
        replacements[(
          before.destinationRange.start,
          before.destinationRange.end,
        )];
    final expectedTarget =
        targets[before] ??
        (matchingEdit == null
            ? before.target
            : (_wiki(before)
                  ? matchingEdit.after
                  : Uri.decodeComponent(
                      'x${matchingEdit.after}',
                    ).substring(1)));
    if (after == null ||
        after.target != expectedTarget ||
        after.fragment != before.fragment ||
        after.query != before.query ||
        after.alias != before.alias ||
        after.title != before.title ||
        after.destinationRange.start !=
            translated(before.destinationRange.start) ||
        after.destinationRange.end != translated(before.destinationRange.end)) {
      return false;
    }
  }
  for (final before in note.semantics.tags) {
    final translatedRange = range(before.range);
    if (!tags.contains((
      before.name,
      translatedRange.start,
      translatedRange.end,
    ))) {
      return false;
    }
  }
  return true;
}
