import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controllers/workspace_search_controller.dart';
import '../services/workspace_reference_index.dart';

/// Backlinks and exact tag postings share one source-preserving index.
class WorkspaceReferencesPanel extends StatefulWidget {
  const WorkspaceReferencesPanel({
    super.key,
    required this.index,
    this.targetPath,
    this.targetSessionId,
    this.tag,
  }) : assert(targetPath != null || tag != null);
  final WorkspaceReferenceIndex index;
  final String? targetPath;
  final String? targetSessionId;
  final String? tag;
  @override
  State<WorkspaceReferencesPanel> createState() =>
      _WorkspaceReferencesPanelState();
}

class _WorkspaceReferencesPanelState extends State<WorkspaceReferencesPanel> {
  String? _error;
  late final int _epoch;
  @override
  void initState() {
    super.initState();
    _epoch = widget.index.index.epoch;
    unawaited(_refresh());
  }

  Future<void> _refresh({bool metadata = false}) async {
    try {
      await widget.index.refresh(refreshMetadata: metadata);
      if (mounted) setState(() => _error = null);
    } on Object {
      if (mounted) {
        setState(
          () => _error = widget.index.cancelled
              ? 'Indexing cancelled. Refresh to continue.'
              : 'The reference index is unavailable. Refresh to retry.',
        );
      }
    }
  }

  WorkspaceSourceMatch _match(
    WorkspaceSemanticNote note,
    TextRange range,
    int epoch,
    int line,
  ) {
    final source = note.source;
    return WorkspaceSourceMatch(
      key: source.key,
      path: source.path,
      name: source.name,
      sessionId: source.sessionId,
      revision: source.revision,
      scopeEpoch: epoch,
      range: range,
      line: line,
      snippet: workspaceReferenceSnippet(source.text, range),
      query: range.textInside(source.text),
      matchCase: true,
      externalConflict: source.externalConflict,
      metadata: note.metadata,
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('workspace-references-panel'),
    child: SizedBox(
      width: 720,
      height: 540,
      child: AnimatedBuilder(
        animation: widget.index,
        builder: (context, _) {
          final index = widget.index;
          final scopeChanged = index.index.epoch != _epoch;
          final snapshot = index.stale || scopeChanged ? null : index.snapshot;
          final selected = snapshot?.noteCandidates.where(
            (candidate) =>
                candidate.sessionId != null &&
                candidate.sessionId == widget.targetSessionId,
          );
          final targetPath = selected != null && selected.length == 1
              ? selected.single.relativePath
              : widget.targetPath;
          final visible = <WorkspaceSourceMatch>[];
          var matchCount = 0;
          final matchingNotes = <String>{};
          final lineCursors =
              <WorkspaceSemanticNote, ({int offset, int line})>{};
          void add(WorkspaceSemanticNote note, TextRange range) {
            matchCount++;
            matchingNotes.add(note.source.key);
            if (visible.length >= 500) return;
            final cursor = lineCursors[note];
            var offset = cursor?.offset ?? 0;
            var line = cursor?.line ?? 1;
            if (offset > range.start) {
              offset = 0;
              line = 1;
            }
            for (; offset < range.start; offset++) {
              if (note.source.text.codeUnitAt(offset) == 10) line++;
            }
            lineCursors[note] = (offset: offset, line: line);
            visible.add(_match(note, range, snapshot!.epoch, line));
          }

          final tag = widget.tag;
          if (snapshot != null) {
            if (tag != null) {
              for (final item
                  in snapshot.tags[tag.toLowerCase()] ??
                      const <WorkspaceTagOccurrence>[]) {
                add(item.note, item.tag.range);
              }
            } else {
              for (final edge in snapshot.backlinks(targetPath!)) {
                add(edge.note, edge.reference.range);
              }
            }
          }
          final ambiguous = snapshot == null || tag != null
              ? 0
              : snapshot.edges
                    .where(
                      (edge) =>
                          edge.status != WorkspaceReferenceStatus.resolved &&
                          edge.candidatePaths.contains(targetPath),
                    )
                    .length;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tag == null
                            ? 'Backlinks · ${p.posix.basename(widget.targetPath!)}'
                            : 'Tag · #$tag',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close references',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Local source + open buffers. Cloud-only files are never downloaded.',
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: index.scanning || scopeChanged
                                    ? null
                                    : () => _refresh(metadata: true),
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Refresh metadata'),
                              ),
                            ),
                            if (index.scanning) ...[
                              const LinearProgressIndicator(),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: index.cancel,
                                  child: const Text('Cancel indexing'),
                                ),
                              ),
                            ],
                            if (scopeChanged)
                              const Text(
                                'Workspace changed. Close and reopen references.',
                              ),
                            if (_error case final error?) Text(error),
                            if (snapshot != null) ...[
                              Text(
                                '${snapshot.notes.length}/${snapshot.knownDocuments} known documents parsed · $matchCount occurrences in ${matchingNotes.length} notes${matchCount > visible.length ? ' · showing first ${visible.length}' : ''}',
                              ),
                              if (!snapshot.complete || ambiguous > 0)
                                Text(
                                  'Coverage unknown: ${snapshot.issues.length} unavailable, unsupported or limited sources${ambiguous > 0 ? '; $ambiguous ambiguous references need an explicit target' : ''}. This is not a complete absence check.',
                                  key: const ValueKey(
                                    'workspace-references-partial',
                                  ),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                      if (visible.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              snapshot == null
                                  ? scopeChanged
                                        ? 'References belong to the previous workspace.'
                                        : index.cancelled
                                        ? 'Indexing cancelled.'
                                        : 'Updating source references…'
                                  : snapshot.complete && ambiguous == 0
                                  ? 'No ${tag == null ? 'backlinks' : 'tag occurrences'}.'
                                  : 'No confirmed matches in the source that could be indexed.',
                            ),
                          ),
                        )
                      else
                        SliverList.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final match = visible[i];
                            final root = index.index.root;
                            final path = match.path;
                            final label = path == null
                                ? match.name
                                : root != null && p.posix.isWithin(root, path)
                                ? p.posix.relative(path, from: root)
                                : path;
                            return ListTile(
                              key: ValueKey('workspace-reference-result-$i'),
                              dense: true,
                              title: Text(
                                '$label:${match.line}${match.sessionId != null ? ' · buffer' : ''}${match.externalConflict ? ' · external conflict' : ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                match.snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                if (!mounted ||
                                    match.scopeEpoch != index.index.epoch) {
                                  return;
                                }
                                Navigator.of(this.context).pop(match);
                              },
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
