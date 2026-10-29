import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import '../controllers/workspace_controller.dart';
import '../models/document_session.dart';
import '../services/workspace_reference_index.dart';

/// A persistent, independently scrollable reference reading surface.
class ReferenceDock extends StatefulWidget {
  const ReferenceDock({
    super.key,
    required this.workspace,
    required this.onClose,
    required this.onInsert,
  });

  final WorkspaceController workspace;
  final VoidCallback onClose;
  final ValueChanged<String> onInsert;

  @override
  State<ReferenceDock> createState() => _ReferenceDockState();
}

class _ReferenceDockState extends State<ReferenceDock> {
  String? _pinnedPath;
  String? _pinnedSession;
  String? _error;
  final _positions = <String, double>{};
  final _scroll = ScrollController();
  String? _readingKey;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      await widget.workspace.references.refresh();
      if (mounted) setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'References unavailable: $error');
    }
  }

  void _pin(String? path, String? session) {
    if (_readingKey != null && _scroll.hasClients) {
      _positions[_readingKey!] = _scroll.offset;
    }
    setState(() {
      _pinnedPath = path;
      _pinnedSession = session;
      _readingKey = session ?? path;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(
          (_positions[_readingKey] ?? 0).clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.workspace,
      widget.workspace.references,
      for (final document in widget.workspace.documents) document.controller,
    ]),
    builder: (context, _) {
      final workspace = widget.workspace;
      final snapshot = workspace.references.snapshot;
      final root = workspace.workspaceRoot;
      final active = workspace.activeDocument;
      final activePath = active?.path;
      final relative = root != null && activePath != null && p.isWithin(root, activePath)
          ? p.relative(activePath, from: root)
          : null;
      DocumentSession? open;
      for (final document in workspace.documents) {
        if (document.id == _pinnedSession ||
            (_pinnedPath != null && document.path == _pinnedPath)) {
          open = document;
          break;
        }
      }
      WorkspaceSemanticNote? indexed;
      for (final note in snapshot?.notes.values ?? <WorkspaceSemanticNote>[]) {
        if (_pinnedPath != null && note.source.path == _pinnedPath) {
          indexed = note;
          break;
        }
      }
      final text = open?.controller.text ?? indexed?.source.text;
      final related = <String, String>{};
      if (relative != null && snapshot != null) {
        for (final edge in snapshot.edges) {
          if (edge.targetPath == relative && edge.note.source.path != null) {
            related[edge.note.source.path!] = 'Backlink';
          }
          if (edge.note.source.path == activePath && edge.targetPath != null) {
            related[p.posix.join(root!, edge.targetPath!)] = 'Outgoing link';
          }
        }
      }
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            ListTile(
              title: const Text('References'),
              trailing: IconButton(
                tooltip: 'Close references',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: active == null ? null : () => _pin(active.path, active.id),
                  child: const Text('Pin current note'),
                ),
                TextButton(onPressed: _refresh, child: const Text('Refresh')),
              ],
            ),
            if (_error != null) Text(_error!),
            if (workspace.references.stale)
              const Text('References changed; refresh to update links.'),
            if (snapshot != null && !snapshot.complete)
              const Text('Some references are unavailable.'),
            SizedBox(
              height: 160,
              child: ListView(
                children: [
                  for (final entry in related.entries)
                    Tooltip(
                      message: _preview(snapshot, entry.key),
                      child: ListTile(
                        dense: true,
                        title: Text(p.basename(entry.key)),
                        subtitle: Text(entry.value),
                        trailing: const Icon(Icons.push_pin_outlined),
                        onTap: () => _pin(entry.key, null),
                      ),
                    ),
                  if (related.isEmpty) const ListTile(title: Text('No known links')),
                  for (final document in workspace.documents)
                    ListTile(
                      dense: true,
                      title: Text(document.name),
                      subtitle: const Text('Open note — read beside editor'),
                      onTap: () => _pin(document.path, document.id),
                    ),
                ],
              ),
            ),
            const Divider(),
            if (_readingKey != null)
              ListTile(
                title: Text(open?.name ?? p.basename(_pinnedPath ?? 'Reference')),
                trailing: IconButton(
                  tooltip: 'Insert reference at cursor',
                  onPressed: text == null ? null : () => widget.onInsert(text),
                  icon: const Icon(Icons.playlist_add),
                ),
              ),
            Expanded(
              child: text == null
                  ? const Center(child: Text('Pin a note to read beside your draft.'))
                  : SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      child: IanvsMarkdown(data: text),
                    ),
            ),
          ],
        ),
      );
    },
  );

  String _preview(WorkspaceReferenceSnapshot? snapshot, String path) {
    for (final note in snapshot?.notes.values ?? <WorkspaceSemanticNote>[]) {
      if (note.source.path == path) {
        final text = note.source.text;
        return text.length > 500 ? '${text.substring(0, 500)}…' : text;
      }
    }
    return 'Preview unavailable';
  }
}
