import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../controllers/workspace_controller.dart';
import '../models/document_session.dart';
import '../services/wiki_note_resolver.dart';

class NoteLinkPreviewBuilder extends MarkdownElementBuilder {
  NoteLinkPreviewBuilder({
    required this.workspace,
    required this.document,
    required this.onTap,
  });
  final WorkspaceController workspace;
  final DocumentSession document;
  final IanvsMarkdownTapLinkTargetCallback onTap;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final child =
        IanvsMarkdownInlineLinkBuilder(
          onTapLink: null,
          onTapLinkTarget: onTap,
          enableFileLinkChips: true,
          editing: document.controller.mode != IanvsMarkdownEditorMode.preview,
        ).visitElementAfterWithContext(
          context,
          element,
          preferredStyle,
          parentStyle,
        );
    final href = element.attributes['href'];
    if (child == null ||
        href == null ||
        element.attributes['data-ianvs-tag'] == 'true')
      return child;
    final wiki = element.attributes['data-ianvs-wiki-link'] == 'true';
    final uri = Uri.tryParse(href);
    if (!wiki && (uri == null || uri.hasScheme || uri.host.isNotEmpty))
      return child;
    return NoteLinkPreview(
      workspace: workspace,
      origin: document.path,
      href: href,
      wiki: wiki,
      child: child,
    );
  }
}

class NoteLinkPreview extends StatefulWidget {
  const NoteLinkPreview({
    super.key,
    required this.workspace,
    required this.origin,
    required this.href,
    required this.wiki,
    required this.child,
  });
  final WorkspaceController workspace;
  final String? origin;
  final String href;
  final bool wiki;
  final Widget child;

  @override
  State<NoteLinkPreview> createState() => _NoteLinkPreviewState();
}

class _NoteLinkPreviewState extends State<NoteLinkPreview> {
  final _tooltip = GlobalKey<TooltipState>();
  String _preview = 'Loading note preview…';
  bool _hovering = false;
  int _request = 0;

  Future<void> _load() async {
    _hovering = true;
    final request = ++_request;
    final workspace = widget.workspace;
    final root = workspace.workspaceRoot;
    final epoch = workspace.index.epoch;
    bool current() =>
        mounted &&
        _hovering &&
        request == _request &&
        workspace.index.epoch == epoch;
    if (root == null) return;
    try {
      String? path;
      if (widget.wiki) {
        final result = await workspace.references.resolveWiki(
          widget.href,
          originPath: widget.origin,
        );
        if (result.status == WikiNoteStatus.resolved)
          path = p.posix.join(root, result.candidates.single.relativePath);
      } else if (widget.origin != null) {
        final uri = Uri.parse(widget.href);
        path = uri.path.isEmpty
            ? widget.origin
            : p.normalize(
                p.join(
                  p.dirname(widget.origin!),
                  Uri.decodeComponent(uri.path),
                ),
              );
      }
      final snapshot = await workspace.references.refresh();
      String? text;
      if (path != null && p.isWithin(root, path)) {
        for (final note in snapshot.notes.values) {
          if (note.source.path == path) text = note.source.text;
        }
      }
      if (!current()) return;
      final body = text == null ? null : parseMarkdownFrontMatter(text).body;
      setState(
        () => _preview = body == null
            ? 'Local preview unavailable'
            : body.length > 1000
            ? '${body.substring(0, 1000)}…'
            : body,
      );
      _tooltip.currentState?.ensureTooltipVisible();
    } on Object {
      if (current()) setState(() => _preview = 'Local preview unavailable');
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _load(),
    onExit: (_) => _hovering = false,
    child: Tooltip(
      key: _tooltip,
      message: _preview,
      waitDuration: const Duration(milliseconds: 400),
      child: widget.child,
    ),
  );
}
