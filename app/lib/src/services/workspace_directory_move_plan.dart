part of 'workspace_note_move_plan.dart';

class _DirectoryPlanningStopped implements Exception {}

typedef _DirectoryResolution = ({
  WorkspaceReferenceStatus status,
  String? path,
});

Future<WorkspaceNoteMovePlan> _buildDirectoryMovePlan(
  WorkspaceNoteMovePlanner planner, {
  required WorkspaceReferenceSnapshot snapshot,
  required String sourcePath,
  required String destinationPath,
  required Set<String> dirtySessionIds,
  required WorkspaceMoveTreeSnapshot? tree,
  List<WorkspaceBatchMoveRoot>? batchRoots,
  AttachmentIndex? attachments,
  bool Function()? isCancelled,
}) async {
  final references = planner.references;
  final index = references.index;
  final root = index.root;
  final blockers = <WorkspaceNoteMoveBlocker>[];
  final files = <WorkspaceNoteMoveFile>[];
  final assets = <String, AttachmentMetadata>{};
  WorkspaceMoveNamespace? namespace;
  final elapsed = Stopwatch()..start();
  var work = 0;
  void block(String code, String message, [String? path]) {
    if (!blockers.any((b) => b.code == code && b.path == path)) {
      blockers.add(WorkspaceNoteMoveBlocker(code, message, path: path));
    }
  }

  bool current() =>
      root == index.root &&
      snapshot.epoch == index.epoch &&
      snapshot.contentRevision == index.contentRevision &&
      snapshot.catalogRevision == index.catalogRevision;
  bool stopped() {
    final cancelled = isCancelled?.call() == true;
    if (cancelled) block('cancelled', 'Directory preview was cancelled.');
    if (!current()) {
      block('stale', 'The workspace or source changed. Refresh the preview.');
    }
    final exhausted = work > planner.maximumDirectoryOperations;
    final timedOut = elapsed.elapsed >= planner.directoryPreviewTimeout;
    if (exhausted) {
      block(
        'planningBudget',
        'The workspace exceeds the bounded directory-reference comparison budget.',
      );
    }
    if (timedOut) {
      block(
        'planningDeadline',
        'Directory reference planning reached its time limit; the preview is incomplete.',
      );
    }
    return cancelled || !current() || exhausted || timedOut;
  }

  void charge([int amount = 1]) {
    work += amount;
    if (stopped()) throw _DirectoryPlanningStopped();
  }

  Future<T> checked<T>(Future<T> Function() operation) async {
    if (stopped()) throw _DirectoryPlanningStopped();
    final result = await operation();
    if (stopped()) throw _DirectoryPlanningStopped();
    return result;
  }

  WorkspaceNoteMovePlan finish() {
    stopped();
    return WorkspaceNoteMovePlan(
      kind: batchRoots == null
          ? WorkspaceNoteMovePlanKind.directory
          : WorkspaceNoteMovePlanKind.batch,
      batchRoots: List.unmodifiable(batchRoots ?? const []),
      treeSnapshot: tree,
      namespace: namespace,
      root: root,
      snapshot: snapshot,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      files: files,
      blockers: blockers,
      attachmentRequirements: assets.values.toList(),
    );
  }

  if (stopped()) return finish();
  try {
    if (batchRoots != null &&
        (batchRoots.length < 2 || batchRoots.length > 8)) {
      throw const FormatException('A batch needs 2–8 roots.');
    }
    namespace = batchRoots == null
        ? WorkspaceMoveNamespace(
            source: sourcePath,
            destination: destinationPath,
          )
        : WorkspaceBatchMoveNamespace([
            for (final root in batchRoots)
              WorkspaceMoveNamespace(
                source: root.source,
                destination: root.destination,
              ),
          ]);
  } on FormatException {
    block(
      'scope',
      'Choose non-overlapping, non-root directories inside the workspace.',
    );
    return finish();
  }
  final transform = namespace;
  if (root == null) {
    block('scope', 'A selected workspace is required.');
    return finish();
  }
  final roots =
      batchRoots ??
      [
        WorkspaceBatchMoveRoot(
          source: sourcePath,
          destination: destinationPath,
          tree: tree,
        ),
      ];
  final members = <String, WorkspaceMoveTreeMember>{};
  final noteRoots = <String>{};
  String? targetParent;
  String? rootIdentity;
  for (final intent in roots) {
    final sourcePath = intent.source;
    final destinationPath = intent.destination;
    if (batchRoots != null) {
      final parent = p.posix.dirname(destinationPath);
      if ((targetParent != null && targetParent != parent) ||
          p.posix.basename(sourcePath) != p.posix.basename(destinationPath)) {
        block(
          'batchTarget',
          'All batch roots must retain their names in one destination folder.',
        );
      }
      targetParent = parent;
    }
    final tree = intent.tree;
    if (tree == null) {
      if (!isMarkdownName(sourcePath)) {
        block(
          'batchKind',
          'Only notes or verified directories are supported.',
          sourcePath,
        );
      }
      noteRoots.add(sourcePath);
      continue;
    }
    if (tree.root != root || tree.sourcePath != sourcePath) {
      block(
        'treeScope',
        'Directory evidence does not match this workspace and source.',
      );
      return finish();
    }
    if (tree.sourceState != WorkspaceMoveTreeSourceState.directory) {
      block(
        switch (tree.sourceState) {
          WorkspaceMoveTreeSourceState.missing => 'sourceMissing',
          WorkspaceMoveTreeSourceState.notDirectory => 'sourceNotDirectory',
          _ => 'sourceUnavailable',
        },
        'The selected directory could not be verified.',
        sourcePath,
      );
      return finish();
    }
    if (!tree.complete) {
      block(
        'treeIncomplete',
        'The directory member scan is incomplete.',
        sourcePath,
      );
    }
    for (final issue in tree.issues) {
      block('tree:${issue.code}', issue.message, issue.path ?? sourcePath);
    }
    if (rootIdentity != null && rootIdentity != tree.rootIdentity) {
      block(
        'treeIdentity',
        'Batch scans refer to different workspace identities.',
      );
    }
    rootIdentity = tree.rootIdentity;
    if (tree.rootIdentity == null || tree.sourceIdentity == null) {
      block(
        'treeIdentity',
        'The workspace and directory need verified filesystem identities.',
        sourcePath,
      );
    }
    if (tree.members.length > workspaceMoveTreeMaximumMembers ||
        tree.members
                .where((m) => m.kind == WorkspaceMoveTreeMemberKind.directory)
                .length >
            workspaceMoveTreeMaximumDirectories ||
        tree.observedEntryCount != tree.members.length) {
      block(
        'treeBudget',
        'The complete directory exceeds the bounded inspection budget.',
        sourcePath,
      );
    }
    for (final member in tree.members) {
      if (!isSafeAttachmentRelativePath(member.path, allowHidden: true) ||
          !WorkspaceMoveNamespace.contains(sourcePath, member.path) ||
          members.containsKey(member.path)) {
        block(
          'treePath',
          'Directory evidence contains an invalid or duplicate member.',
          member.path,
        );
        continue;
      }
      members[member.path] = member;
      if (member.path
          .split('/')
          .any((part) => part.startsWith('.linefold-note-move-'))) {
        block(
          'retainedArtifacts',
          'Retained recovery evidence cannot be relocated by this preview.',
          member.path,
        );
      } else if (member.path.split('/').any((part) => part.startsWith('.'))) {
        block(
          'hiddenMember',
          'Hidden directory members are not supported by maintained moves.',
          member.path,
        );
      }
      if (!const {
        WorkspaceMoveTreeMemberKind.directory,
        WorkspaceMoveTreeMemberKind.note,
        WorkspaceMoveTreeMemberKind.image,
      }.contains(member.kind)) {
        block(
          'unsupportedMember',
          'This directory contains an unsupported ${member.kind.name} member.',
          member.path,
        );
      }
      if (member.local != true) {
        block(
          'offline',
          'Every directory member must be verified locally available.',
          member.path,
        );
      }
      if (member.identity == null ||
          member.revision == null ||
          member.revision!.isEmpty) {
        block(
          'treeIdentity',
          'A directory member has unknown identity or revision.',
          member.path,
        );
      }
      if (member.identity != null &&
          tree.rootIdentity != null &&
          member.identity!.split(':').first !=
              tree.rootIdentity!.split(':').first) {
        block(
          'crossDevice',
          'All moved members must be on the workspace filesystem.',
          member.path,
        );
      }
      if (member.kind == WorkspaceMoveTreeMemberKind.note &&
              !isMarkdownName(member.path) ||
          member.kind == WorkspaceMoveTreeMemberKind.image &&
              !attachmentExtensions.contains(
                p.posix.extension(member.path).toLowerCase(),
              )) {
        block(
          'treeKind',
          'Directory member type does not match its supported extension.',
          member.path,
        );
      }
    }
    final sourceMember = members[sourcePath];
    if (sourceMember?.kind != WorkspaceMoveTreeMemberKind.directory ||
        sourceMember?.identity != tree.sourceIdentity) {
      block(
        'treeIdentity',
        'The source directory is not represented by the expected identity.',
        sourcePath,
      );
    }
    for (final member in members.values.where(
      (m) => WorkspaceMoveNamespace.contains(sourcePath, m.path),
    )) {
      if (member.path != sourcePath &&
          members[p.posix.dirname(member.path)]?.kind !=
              WorkspaceMoveTreeMemberKind.directory) {
        block(
          'treeCoverage',
          'The directory manifest omits a member parent.',
          member.path,
        );
      }
    }
  }
  if (members.length + noteRoots.length > workspaceMoveTreeMaximumMembers ||
      members.values
              .where((m) => m.kind == WorkspaceMoveTreeMemberKind.directory)
              .length >
          workspaceMoveTreeMaximumDirectories) {
    block('treeBudget', 'The entire batch exceeds the shared member budget.');
  }
  final metadata = {
    for (final e in snapshot.catalog.entries) e.relativePath: e,
  };
  for (final path in noteRoots) {
    final item = metadata[path];
    if (item == null ||
        item.isDirectory ||
        item.local != true ||
        item.revision.isEmpty) {
      block(
        'sourceUnavailable',
        'The selected note requires a local disk baseline.',
        path,
      );
    }
  }
  final origins = <WorkspaceSemanticNote, String>{
    for (final e in snapshot.notes.entries)
      if (p.posix.isWithin(root, e.key))
        e.value: p.posix.relative(e.key, from: root),
  };
  final originNotes = {for (final e in origins.entries) e.value: e.key};
  for (final path in noteRoots) {
    if (originNotes[path] == null) {
      block(
        'sourceUnavailable',
        'The selected note has no complete semantic source.',
        path,
      );
    }
  }
  final edgesByNote = <WorkspaceSemanticNote, List<WorkspaceReferenceEdge>>{};
  for (final edge in snapshot.edges) {
    edgesByNote.putIfAbsent(edge.note, () => []).add(edge);
  }
  bool imageReference(
    WorkspaceSemanticNote note,
    IanvsMarkdownSourceReference ref,
  ) {
    if (ref.kind == IanvsMarkdownSourceReferenceKind.markdownImage ||
        ref.kind == IanvsMarkdownSourceReferenceKind.markdownReferenceImage) {
      return true;
    }
    if (ref.kind == IanvsMarkdownSourceReferenceKind.wikiEmbed) {
      return attachmentExtensions.contains(
        p.posix.extension(ref.target).toLowerCase(),
      );
    }
    if (ref.kind == IanvsMarkdownSourceReferenceKind.markdownDefinition) {
      final uses = note.semantics.references.where(
        (other) =>
            other.kind != IanvsMarkdownSourceReferenceKind.markdownDefinition &&
            other.destinationRange == ref.destinationRange,
      );
      return uses.isNotEmpty &&
          uses.every(
            (other) =>
                other.kind ==
                IanvsMarkdownSourceReferenceKind.markdownReferenceImage,
          );
    }
    return false;
  }

  // The note-only graph can call a renderer-valid rooted image "unknown".
  // Discharge only that exact typed occurrence with the image resolver below;
  // source/parser/budget/alias failures and non-image unknowns remain blockers.
  for (final issue in snapshot.issues.entries) {
    final note = snapshot.notes.values
        .where((n) => n.source.key == issue.key)
        .firstOrNull;
    final unknown = note == null
        ? <WorkspaceReferenceEdge>[]
        : (edgesByNote[note] ?? [])
              .where((e) => e.status == WorkspaceReferenceStatus.unknown)
              .toList();
    final imageOnly =
        note != null &&
        note.semantics.complete &&
        unknown.isNotEmpty &&
        unknown.every((e) => imageReference(note, e.reference)) &&
        issue.value.every(
          (message) => message == 'A reference target could not be resolved.',
        );
    if (!imageOnly) block('coverage', issue.value.join('; '), issue.key);
  }
  if (!snapshot.catalog.complete ||
      !snapshot.aliases.complete ||
      snapshot.knownDocuments != snapshot.notes.length) {
    block(
      'incomplete',
      'Complete note, directory and alias coverage is required.',
    );
  }
  for (final member in members.values) {
    if (member.kind == WorkspaceMoveTreeMemberKind.note) {
      if (originNotes[member.path] == null ||
          metadata[member.path]?.revision != member.revision) {
        block(
          'treeCatalog',
          'The moved note source and directory evidence do not agree.',
          member.path,
        );
      }
    } else if (member.kind == WorkspaceMoveTreeMemberKind.directory &&
        (metadata[member.path]?.isDirectory != true ||
            metadata[member.path]?.revision != member.revision)) {
      block(
        'treeCatalog',
        'The directory catalog and tree evidence do not agree.',
        member.path,
      );
    }
  }
  for (final e in metadata.values.where(
    (e) => transform.moves(e.relativePath),
  )) {
    if (!members.containsKey(e.relativePath) &&
        !noteRoots.contains(e.relativePath)) {
      block(
        'treeCoverage',
        'The member scan omits a catalog item.',
        e.relativePath,
      );
    }
  }
  final parent = p.posix.dirname(destinationPath);
  if (parent != '.' && metadata[parent]?.isDirectory != true) {
    block(
      'destinationParent',
      'The exact destination parent must already exist.',
      parent,
    );
  }
  var ancestor = parent;
  while (ancestor != '.') {
    if (metadata[ancestor]?.local != true) {
      block(
        'offline',
        'The destination parent must be locally available.',
        ancestor,
      );
    }
    ancestor = p.posix.dirname(ancestor);
  }
  for (final e in origins.entries) {
    if (transform.moves(e.value) &&
        !members.containsKey(e.value) &&
        !noteRoots.contains(e.value)) {
      block(
        'sourceGhost',
        'An open source-subtree note has no verified disk member.',
        e.value,
      );
    }
    if (roots.any(
      (r) => WorkspaceMoveNamespace.contains(r.destination, e.value),
    )) {
      block(
        'destinationGhost',
        'An open note reserves the destination subtree.',
        e.value,
      );
    }
    if ((e.key.source.externalConflict ||
            dirtySessionIds.contains(e.key.source.sessionId)) &&
        (transform.moves(e.value) ||
            e.key.semantics.references.isNotEmpty ||
            e.key.semantics.aliases.isNotEmpty)) {
      block(
        'dirty',
        'Save or resolve the affected note or semantic dependency first.',
        e.value,
      );
    }
  }
  final keys = <String, String>{};
  Future<String> key(String value) async {
    charge();
    if (keys.containsKey(value)) return keys[value]!;
    return keys[value] = (await checked(
      () => references.resolver.comparisonKeys([value]),
    )).single;
  }

  final allPaths = <String>{
    ...metadata.keys,
    ...members.keys,
    ...origins.values,
    for (final c in snapshot.noteCandidates) c.relativePath,
    for (final a in attachments?.entries ?? <AttachmentMetadata>[])
      a.relativePath,
  };
  try {
    for (final path in allPaths.where(transform.moves)) {
      final mapped = transform.map(path);
      final directory =
          members[path]?.kind == WorkspaceMoveTreeMemberKind.directory ||
          metadata[path]?.isDirectory == true;
      if (!isSupportedWorkspaceMovePath(mapped, directory: directory)) {
        block(
          'mappedPath',
          'A mapped destination exceeds supported directory depth, UTF-8 filename or path limits.',
          mapped,
        );
      }
    }
    final toNormalize = <String>{
      for (final intent in roots) intent.source,
      for (final intent in roots) intent.destination,
      ...allPaths,
      ...allPaths.map(transform.map),
    }.toList();
    for (var start = 0; start < toNormalize.length; start += 32) {
      if (stopped()) return finish();
      final batch = toNormalize.skip(start).take(32).toList();
      charge(batch.length);
      final normalized = await checked(
        () => references.resolver.comparisonKeys(batch),
      );
      for (var i = 0; i < batch.length; i++) {
        keys[batch[i]] = normalized[i];
      }
      await Future<void>.delayed(Duration.zero);
    }
    final normalizedRoots = [
      for (final intent in roots)
        (
          source: await key(intent.source),
          destination: await key(intent.destination),
        ),
    ];
    for (var i = 0; i < normalizedRoots.length; i++) {
      final a = normalizedRoots[i];
      for (var j = 0; j < normalizedRoots.length; j++) {
        final b = normalizedRoots[j];
        if (WorkspaceMoveNamespace.contains(a.source, b.destination) ||
            WorkspaceMoveNamespace.contains(b.destination, a.source) ||
            i != j &&
                (WorkspaceMoveNamespace.contains(a.source, b.source) ||
                    WorkspaceMoveNamespace.contains(
                      a.destination,
                      b.destination,
                    ))) {
          block(
            'sameIdentitySpelling',
            'Equivalent or overlapping batch paths are not supported.',
          );
        }
      }
    }
    final beforeKeys = <String, String>{};
    final afterKeys = <String, String>{};
    for (final path in allPaths) {
      final beforeKey = await key(path);
      final afterKey = await key(transform.map(path));
      final beforePrevious = beforeKeys[beforeKey];
      final afterPrevious = afterKeys[afterKey];
      if (beforePrevious != null && beforePrevious != path ||
          afterPrevious != null && afterPrevious != path) {
        block(
          'normalizationCollision',
          'Distinct paths have equivalent filename spellings.',
          path,
        );
      }
      beforeKeys[beforeKey] = path;
      afterKeys[afterKey] = path;
      if (!transform.moves(path) &&
          normalizedRoots.any(
            (r) => WorkspaceMoveNamespace.contains(r.destination, beforeKey),
          )) {
        block(
          'destinationExists',
          'The destination subtree already exists or is reserved.',
          path,
        );
      }
      if (normalizedRoots.any(
            (r) => WorkspaceMoveNamespace.contains(r.source, beforeKey),
          ) &&
          !transform.moves(path)) {
        block(
          'sourceGhost',
          'A source-subtree path alias lacks canonical member evidence.',
          path,
        );
      }
    }
    WorkspaceMetadata mappedMetadata(WorkspaceMetadata e) => WorkspaceMetadata(
      relativePath: transform.map(e.relativePath),
      comparisonPath: keys[transform.map(e.relativePath)],
      isDirectory: e.isDirectory,
      revision: e.revision,
      size: e.size,
      modified: e.modified,
      local: e.local,
    );
    final afterCatalog = WorkspaceCatalogSnapshot(
      epoch: snapshot.catalog.epoch,
      entries: snapshot.catalog.entries.map(mappedMetadata).toList(),
      complete: snapshot.catalog.complete,
      issues: snapshot.catalog.issues,
    );
    final afterCandidates = [
      for (final c in snapshot.wikiCandidates)
        WikiNoteCandidate(
          relativePath: transform.map(c.relativePath),
          comparisonPath: keys[transform.map(c.relativePath)]!,
          metadata: c.metadata == null ? null : mappedMetadata(c.metadata!),
          sessionId: c.sessionId,
        ),
    ];
    final afterAliases = WikiAliasSnapshot(
      byPath: {
        for (final e in snapshot.aliases.byPath.entries)
          transform.map(e.key): e.value,
      },
      complete: snapshot.aliases.complete,
      epoch: snapshot.aliases.epoch,
    );
    final beforeLookup = WikiCandidateLookup(
      snapshot.wikiCandidates,
      snapshot.aliases,
    );
    final afterLookup = WikiCandidateLookup(afterCandidates, afterAliases);
    final beforeNoteKeys = <String, List<String>>{};
    final afterNoteKeys = <String, List<String>>{};
    for (final c in snapshot.noteCandidates) {
      beforeNoteKeys
          .putIfAbsent(keys[c.relativePath]!, () => [])
          .add(c.relativePath);
      afterNoteKeys
          .putIfAbsent(keys[transform.map(c.relativePath)]!, () => [])
          .add(transform.map(c.relativePath));
    }
    final afterAttachments = attachments == null
        ? null
        : AttachmentIndex([
            for (final a in attachments.entries)
              AttachmentMetadata(
                relativePath: transform.map(a.relativePath),
                comparisonPath: keys[transform.map(a.relativePath)]!,
                size: a.size,
                modified: a.modified,
                revision: a.revision,
              ),
          ]);
    final assetMap = {
      for (final a in attachments?.entries ?? <AttachmentMetadata>[])
        a.relativePath: a,
    };
    for (final member in members.values.where(
      (m) => m.kind == WorkspaceMoveTreeMemberKind.image,
    )) {
      final asset = assetMap[member.path];
      if (asset == null ||
          asset.revision == null ||
          asset.revision != member.revision ||
          asset.size != member.size) {
        block(
          'assetCoverage',
          'The moved image requires matching complete attachment metadata.',
          member.path,
        );
      } else {
        assets[asset.relativePath] = asset;
      }
    }
    void requireAsset(String path) {
      final asset = assetMap[path];
      if (asset == null || asset.revision == null) {
        block(
          'assetRevision',
          'The attachment requires a stable native revision.',
          path,
        );
      } else {
        assets[path] = asset;
      }
    }

    Future<_DirectoryResolution> resolveRaw(
      WorkspaceSemanticNote note,
      IanvsMarkdownSourceReference ref,
      String target,
      String origin, {
      required bool after,
    }) async {
      const unknown = (status: WorkspaceReferenceStatus.unknown, path: null);
      if (_remote(target)) {
        return (status: WorkspaceReferenceStatus.external, path: null);
      }
      final image = imageReference(note, ref);
      final imageIndex = after ? afterAttachments : attachments;
      if (image) {
        if (imageIndex == null || ref.query != null || ref.fragment != null) {
          return unknown;
        }
        try {
          final reference = AttachmentReference(
            _wiki(ref) ? target : _encodeMarkdownPath(target),
            _wiki(ref) ? AttachmentLinkKind.wiki : AttachmentLinkKind.markdown,
          );
          final asset = imageIndex.resolve(
            reference: reference,
            documentRelativePath: origin,
            normalizedReference: await key(reference.path),
            normalizedDocument: await key(origin),
          );
          return (
            status: WorkspaceReferenceStatus.resolved,
            path: asset.relativePath,
          );
        } on AttachmentFailure catch (e) {
          return (
            status: switch (e.kind) {
              AttachmentFailureKind.missing => WorkspaceReferenceStatus.missing,
              AttachmentFailureKind.ambiguous =>
                WorkspaceReferenceStatus.ambiguous,
              _ => WorkspaceReferenceStatus.unknown,
            },
            path: null,
          );
        }
      }
      if (target.isEmpty) {
        return (status: WorkspaceReferenceStatus.resolved, path: origin);
      }
      if (_wiki(ref)) {
        final result = await references.resolver.resolve(
          target,
          originPath: p.posix.join(root, origin),
          catalog: after ? afterCatalog : snapshot.catalog,
          knownCandidates: after ? afterCandidates : snapshot.wikiCandidates,
          aliases: after ? afterAliases : snapshot.aliases,
          lookup: after ? afterLookup : beforeLookup,
          includeCreatePath: false,
          resolutionKeys: (paths) {
            charge(paths.length);
            return checked(() => references.resolver.comparisonKeys(paths));
          },
        );
        return (
          status: switch (result.status) {
            WikiNoteStatus.resolved => WorkspaceReferenceStatus.resolved,
            WikiNoteStatus.missing => WorkspaceReferenceStatus.missing,
            WikiNoteStatus.ambiguous => WorkspaceReferenceStatus.ambiguous,
            _ => WorkspaceReferenceStatus.unknown,
          },
          path: result.status == WikiNoteStatus.resolved
              ? result.candidates.single.relativePath
              : null,
        );
      }
      if (target.startsWith('//') ||
          RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(target)) {
        return unknown;
      }
      final absolute = p.posix.normalize(
        p.posix.isAbsolute(target)
            ? target
            : p.posix.join(root, p.posix.dirname(origin), target),
      );
      if (!p.posix.isWithin(root, absolute)) return unknown;
      final relative = p.posix.relative(absolute, from: root);
      if (!safeWorkspaceRelativePath(relative)) return unknown;
      final List<String> matches;
      if (isMarkdownName(relative)) {
        matches =
            (after ? afterNoteKeys : beforeNoteKeys)[await key(relative)] ?? [];
      } else if (attachmentExtensions.contains(
            p.posix.extension(relative).toLowerCase(),
          ) &&
          imageIndex != null) {
        final normalized = await key(relative);
        matches = imageIndex.entries
            .where((a) => a.comparisonPath == normalized)
            .map((a) => a.relativePath)
            .toList();
      } else {
        return unknown;
      }
      return (
        status: matches.length > 1
            ? WorkspaceReferenceStatus.ambiguous
            : matches.isEmpty
            ? WorkspaceReferenceStatus.missing
            : WorkspaceReferenceStatus.resolved,
        path: matches.length == 1 ? matches.single : null,
      );
    }

    Future<_DirectoryResolution> resolve(
      WorkspaceSemanticNote note,
      IanvsMarkdownSourceReference ref,
      String target,
      String origin, {
      required bool after,
    }) {
      charge();
      return checked(() => resolveRaw(note, ref, target, origin, after: after));
    }

    var bytes = 0;
    var operations = 0;
    for (final entry in origins.entries) {
      if (stopped()) return finish();
      final note = entry.key;
      final origin = entry.value;
      final newOrigin = transform.map(origin);
      final originalBytes = utf8.encode(note.source.text).length;
      var replacementBytes = originalBytes;
      if (transform.moves(origin) &&
          (files.length >= planner.maximumFiles ||
              bytes + originalBytes * 2 > planner.maximumBackupBytes)) {
        block(
          'transactionBudget',
          'The complete affected set exceeds the bounded recovery budget.',
        );
        return finish();
      }
      final changes = <(int, int), WorkspaceReferenceEdit>{};
      final targets = <IanvsMarkdownSourceReference, String>{};
      final expected = <IanvsMarkdownSourceReference, _DirectoryResolution>{};
      if (!note.semantics.complete) {
        block(
          'coverage',
          'The note contains unsupported or unknown source syntax.',
          origin,
        );
      }
      for (final ref in note.semantics.references) {
        if (++operations % 32 == 0) {
          await Future<void>.delayed(Duration.zero);
          if (stopped()) return finish();
        }
        final before = await resolve(
          note,
          ref,
          ref.target,
          origin,
          after: false,
        );
        if (before.status == WorkspaceReferenceStatus.unknown ||
            before.status == WorkspaceReferenceStatus.ambiguous) {
          block(
            'unresolved',
            'An unknown or ambiguous reference prevents complete directory maintenance.',
            origin,
          );
          continue;
        }
        final wanted = (
          status: before.status,
          path: before.path == null ? null : transform.map(before.path!),
        );
        expected[ref] = wanted;
        if (before.path != null && assetMap.containsKey(before.path)) {
          requireAsset(before.path!);
        }
        final after = await resolve(
          note,
          ref,
          ref.target,
          newOrigin,
          after: true,
        );
        if (after == wanted) continue;
        if (before.status != WorkspaceReferenceStatus.resolved ||
            wanted.path == null) {
          block(
            'newResolution',
            'The move would change a previously missing or external reference.',
            origin,
          );
          continue;
        }
        final String next;
        if (_wiki(ref)) {
          if (wanted.path!.contains(RegExp(r'[\[\]#|\\\r\n]'))) {
            block(
              'wikiSpelling',
              'The new path has no safe Wiki spelling.',
              origin,
            );
            continue;
          }
          var spelling = '/${wanted.path}';
          if (!imageReference(note, ref) &&
              !ref.target.toLowerCase().endsWith('.md') &&
              spelling.toLowerCase().endsWith('.md')) {
            spelling = spelling.substring(0, spelling.length - 3);
          }
          next = spelling;
        } else if (imageReference(note, ref)) {
          var spelling = p.posix.relative(
            wanted.path!,
            from: p.posix.dirname(newOrigin),
          );
          if (!spelling.startsWith('../')) spelling = './$spelling';
          next = spelling;
        } else {
          next = _markdownPath(root, newOrigin, wanted.path!, ref.target);
        }
        final checked = await resolve(note, ref, next, newOrigin, after: true);
        if (checked != wanted) {
          block(
            'resolutionProof',
            'The proposed spelling does not uniquely preserve its target.',
            origin,
          );
          continue;
        }
        final replacement = _wiki(ref) ? next : _encodeMarkdownPath(next);
        final range = ref.destinationRange;
        final span = (range.start, range.end);
        if (changes[span] != null && changes[span]!.after != replacement) {
          // Image and ordinary-link serializers may choose ./path vs path.
          // Reuse an already proposed spelling when it proves this use too.
          final existing = changes[span]!.after;
          final existingTarget = _wiki(ref)
              ? existing
              : Uri.decodeComponent('x$existing').substring(1);
          if (await resolve(
                note,
                ref,
                existingTarget,
                newOrigin,
                after: true,
              ) ==
              wanted) {
            targets[ref] = existingTarget;
            continue;
          }
          block(
            'sharedDestination',
            'A shared definition requires conflicting rewrites.',
            origin,
          );
          continue;
        }
        if (!changes.containsKey(span)) {
          replacementBytes +=
              utf8.encode(replacement).length -
              utf8.encode(range.textInside(note.source.text)).length;
          if (files.length >= planner.maximumFiles ||
              bytes + originalBytes + replacementBytes >
                  planner.maximumBackupBytes) {
            block(
              'transactionBudget',
              'The complete affected set exceeds the bounded recovery budget.',
            );
            return finish();
          }
        }
        targets[ref] = next;
        changes[span] = WorkspaceReferenceEdit(
          range,
          range.textInside(note.source.text),
          replacement,
        );
      }
      final edits = changes.values.toList()
        ..sort((a, b) => a.range.start.compareTo(b.range.start));
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
      String? reparseTextLimit(int length, Iterable<String> pieces) {
        if (length > planner.maximumDirectoryReparseCodeUnits) {
          return '${planner.maximumDirectoryReparseCodeUnits}-code-unit source length';
        }
        var line = 0;
        var pendingCR = false;
        for (final piece in pieces) {
          for (var i = 0; i < piece.length; i++) {
            final unit = piece.codeUnitAt(i);
            if (unit == 0x0a) {
              line = 0;
              pendingCR = false;
              continue;
            }
            if (pendingCR) line++;
            pendingCR = unit == 0x0d;
            if (!pendingCR) line++;
            if (line > planner.maximumDirectoryReparseLineCodeUnits) {
              return '${planner.maximumDirectoryReparseLineCodeUnits}-code-unit line length';
            }
          }
        }
        return line + (pendingCR ? 1 : 0) >
                planner.maximumDirectoryReparseLineCodeUnits
            ? '${planner.maximumDirectoryReparseLineCodeUnits}-code-unit line length'
            : null;
      }

      Iterable<String> projectedPieces() sync* {
        var offset = 0;
        for (final edit in edits) {
          yield note.source.text.substring(offset, edit.range.start);
          yield edit.after;
          offset = edit.range.end;
        }
        yield note.source.text.substring(offset);
      }

      void reparseComplexity(String limit) => block(
        'reparseComplexity',
        'A changed note exceeds the conservative directory-preview $limit limit.',
        origin,
      );
      if (edits.isNotEmpty) {
        final projectedLength =
            note.source.text.length +
            edits.fold<int>(
              0,
              (sum, edit) => sum + edit.after.length - edit.before.length,
            );
        // Stream the projected pieces before any repeated full-source copy.
        // A longer destination cannot bypass either source or line limits.
        final limit =
            note.semantics.references.length >
                planner.maximumDirectoryReparseReferences
            ? '${planner.maximumDirectoryReparseReferences}-reference count'
            : reparseTextLimit(note.source.text.length, [note.source.text]) ??
                  reparseTextLimit(projectedLength, projectedPieces());
        if (limit != null) {
          reparseComplexity(limit);
          return finish();
        }
      }
      var contents = note.source.text;
      for (final edit in edits.reversed) {
        contents = contents.replaceRange(
          edit.range.start,
          edit.range.end,
          edit.after,
        );
      }
      if (edits.isNotEmpty) {
        final limit = reparseTextLimit(contents.length, [contents]);
        if (limit != null) {
          reparseComplexity(limit);
          return finish();
        }
        await Future<void>.delayed(Duration.zero);
        if (stopped()) return finish();
        if (!_verifyReparse(note, contents, edits, targets)) {
          block(
            'reparse',
            'Rewritten source did not preserve all references and metadata.',
            origin,
          );
        }
        if (stopped()) return finish();
      }
      // Shared definitions can alter an occurrence that did not ask for edits.
      // Prove all resulting references, including unchanged external sources.
      for (final e in expected.entries) {
        if (++operations % 32 == 0) {
          await Future<void>.delayed(Duration.zero);
          if (stopped()) return finish();
        }
        final ref = e.key;
        final edit =
            changes[(ref.destinationRange.start, ref.destinationRange.end)];
        final actualTarget = edit == null
            ? ref.target
            : _wiki(ref)
            ? edit.after
            : Uri.decodeComponent('x${edit.after}').substring(1);
        final actual = await resolve(
          note,
          ref,
          actualTarget,
          newOrigin,
          after: true,
        );
        if (actual != e.value) {
          block(
            'semanticProof',
            'A rewritten or unchanged occurrence changed target identity.',
            origin,
          );
        }
      }
      if (!transform.moves(origin) && edits.isEmpty) continue;
      final disk = metadata[origin];
      if (disk == null || disk.isDirectory || disk.revision.isEmpty) {
        block(
          'sourceUnavailable',
          'An affected note lacks a verified disk baseline.',
          origin,
        );
      }
      if (note.source.externalConflict ||
          dirtySessionIds.contains(note.source.sessionId)) {
        block('dirty', 'Save or resolve the affected note first.', origin);
      }
      var location = origin;
      while (location != '.') {
        if (metadata[location]?.local != true) {
          block(
            'offline',
            'The affected note and its parents must be local.',
            location,
          );
        }
        location = p.posix.dirname(location);
      }
      bytes +=
          utf8.encode(note.source.text).length + utf8.encode(contents).length;
      if (files.length >= planner.maximumFiles ||
          bytes > planner.maximumBackupBytes) {
        block(
          'transactionBudget',
          'The complete affected set exceeds the bounded recovery budget.',
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
  } on _DirectoryPlanningStopped {
    // The exact cancellation/staleness/budget reason was recorded at its source.
  } on Object {
    block(
      'normalization',
      'The virtual namespace or filename normalization could not be verified.',
    );
  }
  return finish();
}
