import '../app_localizations.dart';
import 'package:ianvs_design/ianvs_design.dart';
import 'package:path/path.dart' as p;

import '../services/workspace_note_move_plan.dart';
import '../services/workspace_note_transaction.dart';
import 'workspace_note_move_recovery.dart';
import 'workspace_move_preview_icon.dart';

class WorkspaceNoteMoveDecision {
  const WorkspaceNoteMoveDecision({this.manual = false, this.automatic});
  final bool manual;
  final WorkspaceNoteMoveRecord? automatic;
  bool get cancelled => !manual && automatic == null;
}

/// The only executor entry point requires an explicit choice on this preview.
Future<WorkspaceNoteMoveDecision> showWorkspaceNoteMovePreview({
  required BuildContext context,
  required List<String> sources,
  required List<String> destinations,
  Future<WorkspaceNoteMovePlan>? preview,
  String? unavailable,
  String? displayRoot,
  Future<WorkspaceNoteMoveRecord> Function(WorkspaceNoteMovePlan)? onMaintain,
  Future<WorkspaceNoteMoveRecord> Function(String)? onRecoverCopies,
  VoidCallback? onCancelPreview,
}) async {
  // Attach the error handler before the dialog's first frame. A fast native
  // failure must not become an unhandled Future error before FutureBuilder
  // subscribes, and cancellation must safely absorb a late result.
  final pending = preview?.then<(WorkspaceNoteMovePlan?, bool)>(
    (plan) => (plan, false),
    onError: (Object _, StackTrace _) => (null, true),
  );
  try {
    return await showDialog<WorkspaceNoteMoveDecision>(
          context: context,
          builder: (context) => _MovePreviewDialog(
            displayRoot: displayRoot,
            sources: sources,
            destinations: destinations,
            pending: pending,
            unavailable: unavailable,
            onMaintain: onMaintain,
            onRecoverCopies: onRecoverCopies,
          ),
        ) ??
        const WorkspaceNoteMoveDecision();
  } finally {
    onCancelPreview?.call();
  }
}

class _MovePreviewDialog extends StatefulWidget {
  const _MovePreviewDialog({
    required this.sources,
    required this.destinations,
    required this.pending,
    this.unavailable,
    this.displayRoot,
    this.onMaintain,
    this.onRecoverCopies,
  });
  final List<String> sources;
  final List<String> destinations;
  final Future<(WorkspaceNoteMovePlan?, bool)>? pending;
  final String? unavailable;
  final String? displayRoot;
  final Future<WorkspaceNoteMoveRecord> Function(WorkspaceNoteMovePlan)?
  onMaintain;
  final Future<WorkspaceNoteMoveRecord> Function(String)? onRecoverCopies;
  @override
  State<_MovePreviewDialog> createState() => _MovePreviewDialogState();
}

class _MovePreviewDialogState extends State<_MovePreviewDialog> {
  String _displayPath(String path) {
    final root = widget.displayRoot;
    if (root == null || !p.isAbsolute(path)) return path;
    if (p.isWithin(root, path)) return p.relative(path, from: root);
    // External folder grants may live outside the workspace. Keep the useful
    // folder and filename without exposing the iOS container implementation.
    return '…/${p.basename(p.dirname(path))}/${p.basename(path)}';
  }

  final Map<String, bool> _expanded = {};

  Widget _chevron(String id, {bool down = false}) => AnimatedRotation(
    turns: _expanded[id] == true ? (down ? .5 : .25) : 0,
    duration: const Duration(milliseconds: 180),
    child: MovePreviewIcon(
      down ? MovePreviewGlyph.chevronDown : MovePreviewGlyph.chevronRight,
      size: 18,
    ),
  );

  bool _busy = false;
  bool _confirmingRecovery = false;
  bool _attempted = false;
  WorkspaceNoteMoveRecord? _record;
  String? _error;

  Future<void> _maintain(WorkspaceNoteMovePlan plan) async {
    if (_busy || _attempted || !plan.canExecute || widget.onMaintain == null) {
      return;
    }
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      final record = await widget.onMaintain!(plan);
      if (mounted) setState(() => _record = record);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    if (_busy) return;
    final id = _record?.transactionId;
    if (id == null || widget.onRecoverCopies == null) return;
    setState(() {
      _busy = true;
      _confirmingRecovery = true;
      _error = null;
    });
    try {
      final approved = await confirmWorkspaceNoteMoveRecoveryCopies(
        context,
        _record!.entries.length,
      );
      if (approved != true || !mounted) return;
      setState(() => _confirmingRecovery = false);
      final record = await widget.onRecoverCopies!(id);
      if (mounted) setState(() => _record = record);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirmingRecovery = false;
        });
      }
    }
  }

  bool get _renaming =>
      widget.sources.length == 1 &&
      widget.destinations.length == 1 &&
      p.dirname(widget.sources.single) == p.dirname(widget.destinations.single);

  Widget _paths(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.sources.length && i < 20; i++) ...[
          _nameRow(context, 'Current name', p.basename(widget.sources[i])),
          const SizedBox(height: 10),
          _nameRow(
            context,
            'New name',
            p.basename(widget.destinations[i]),
            accent: true,
          ),
          const SizedBox(height: 12),
        ],
        if (widget.sources.length > 20)
          Text(
            appText(context, '… and {0} more items.', [
              widget.sources.length - 20,
            ]),
          ),
        ExpansionTile(
          key: const ValueKey('move-full-paths'),
          trailing: _chevron('move-full-paths', down: true),
          onExpansionChanged: (expanded) =>
              setState(() => _expanded['move-full-paths'] = expanded),
          leading: const MovePreviewIcon(MovePreviewGlyph.location, size: 18),
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          subtitle: widget.sources.length == 1
              ? Text(
                  appText(context, 'Location: {0}', [
                    widget.displayRoot == null
                        ? p.basename(p.dirname(widget.sources.single))
                        : p.relative(
                            p.dirname(widget.sources.single),
                            from: widget.displayRoot!,
                          ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          title: Text(
            appText(context, 'View full paths'),
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
          children: [
            for (var i = 0; i < widget.sources.length && i < 20; i++)
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  '${widget.sources[i]} → ${widget.destinations[i]}',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _nameRow(
    BuildContext context,
    String label,
    String name, {
    bool accent = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            appText(context, label),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(BuildContext context, MovePreviewGlyph icon, String label) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MovePreviewIcon(
            icon,
            size: 19,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );

  Widget _status(BuildContext context, WorkspaceNoteMovePlan plan) {
    final colors = Theme.of(context).colorScheme;
    final warning =
        Theme.of(context).extension<IanvsTokens>()?.warning ??
        (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xffffc250)
            : const Color(0xff895700));
    final blocked = !plan.canExecute;
    final partial = plan.warnings.isNotEmpty;
    final caution = blocked || partial;
    final title = blocked
        ? 'Link updates are blocked'
        : partial
        ? 'Some links could not be checked'
        : 'Ready to update links';
    final blockingMessage = switch (plan.blockers.firstOrNull?.code) {
      'offline' ||
      'tree:offline' ||
      'sourceUnavailable' => 'Some affected files are not available locally.',
      'destinationExists' || 'destinationGhost' =>
        'A file or folder already occupies the destination.',
      'dirty' => 'Save or resolve the affected notes first.',
      'coverage' ||
      'unresolved' => 'An affected note could not be fully parsed or resolved.',
      _ =>
        'Resolve the affected files or destination issues before updating links.',
    };
    final message = blocked
        ? blockingMessage
        : partial
        ? 'Only confirmed links will be updated. Unchecked notes may still contain old links.'
        : 'Known references have been checked. The destination will be verified before changes.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: caution
            ? warning.withValues(alpha: .10)
            : colors.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caution)
            MovePreviewIcon(MovePreviewGlyph.warning, size: 24, color: warning)
          else
            Icon(Icons.check_circle_outline, size: 22, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText(context, title),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(appText(context, message)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: FutureBuilder<(WorkspaceNoteMovePlan?, bool)>(
      future: widget.pending,
      builder: (context, state) {
        final waiting =
            widget.pending != null &&
            state.connectionState != ConnectionState.done;
        final plan = state.data?.$1;
        final media = MediaQuery.of(context);
        // An oversized fixed action footer can consume the entire compact
        // dialog at accessibility text sizes. Keep it scrollable in that case.
        final scrollActions =
            media.textScaler.scale(14) > 28 || media.size.height < 480;
        final actions = <Widget>[
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.pop(
                    context,
                    WorkspaceNoteMoveDecision(automatic: _record),
                  ),
            child: Text(
              _attempted
                  ? appText(context, "Close")
                  : appText(context, "Cancel"),
            ),
          ),
          if (!_attempted)
            OutlinedButton(
              key: const ValueKey('move-without-updating-links'),
              onPressed: waiting
                  ? null
                  : () => Navigator.pop(
                      context,
                      const WorkspaceNoteMoveDecision(manual: true),
                    ),
              child: Text(
                appText(
                  context,
                  _renaming ? 'Rename only' : 'Move without updating links',
                ),
              ),
            ),
          if (!_attempted)
            FilledButton(
              key: const ValueKey('move-and-update-links'),
              onPressed:
                  waiting ||
                      plan?.canExecute != true ||
                      widget.onMaintain == null
                  ? null
                  : () => _maintain(plan!),
              child: Text(
                appText(
                  context,
                  plan?.canExecute == true && plan!.warnings.isNotEmpty
                      ? 'Rename and update confirmed links'
                      : _renaming
                      ? 'Rename and update links'
                      : 'Move and update links',
                ),
              ),
            ),
          if (_record != null &&
              _record!.entries.isNotEmpty &&
              widget.onRecoverCopies != null)
            TextButton(
              key: const ValueKey('recover-note-move-copies'),
              onPressed: _busy ? null : _recover,
              child: Text(appText(context, "Recover originals as new copies")),
            ),
        ];
        return AlertDialog(
          actions: scrollActions ? null : actions,
          scrollable: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: MovePreviewIcon(
                  plan?.kind == WorkspaceNoteMovePlanKind.directory
                      ? MovePreviewGlyph.folder
                      : MovePreviewGlyph.note,
                  size: 32,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText(
                        context,
                        _renaming
                            ? plan?.kind == WorkspaceNoteMovePlanKind.directory
                                  ? 'Rename folder'
                                  : 'Rename preview'
                            : 'Preview rename / move',
                      ),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appText(context, 'Review name changes and link impact'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: appText(context, 'Close'),
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(
                        context,
                        WorkspaceNoteMoveDecision(automatic: _record),
                      ),
                icon: const MovePreviewIcon(MovePreviewGlyph.close, size: 20),
              ),
            ],
          ),
          content: SizedBox(
            width: 680,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _paths(context),
                const Divider(height: 24),
                if (waiting) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    appText(
                      context,
                      'Preparing a read-only reference preview…',
                    ),
                  ),
                ] else if (plan != null) ...[
                  Text(
                    appText(context, 'Impact overview'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      if (plan.treeSnapshot case final tree?)
                        _metric(
                          context,
                          MovePreviewGlyph.folder,
                          appText(context, '{0} directory items', [
                            tree.members.length,
                          ]),
                        ),
                      _metric(
                        context,
                        MovePreviewGlyph.note,
                        appText(context, '{0} involved notes', [
                          plan.files.length,
                        ]),
                      ),
                      _metric(
                        context,
                        MovePreviewGlyph.link,
                        appText(context, '{0} link replacements', [
                          plan.editCount,
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    appText(
                      context,
                      'Includes relocated notes whose contents do not need changes.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _status(context, plan),
                  const SizedBox(height: 12),
                  if (plan.treeSnapshot case final tree?)
                    if (tree.members.isNotEmpty)
                      ExpansionTile(
                        key: const ValueKey('directory-move-manifest'),
                        trailing: _chevron('directory-move-manifest'),
                        onExpansionChanged: (expanded) => setState(
                          () => _expanded['directory-move-manifest'] = expanded,
                        ),
                        leading: const MovePreviewIcon(
                          MovePreviewGlyph.folder,
                          size: 20,
                        ),
                        title: Text(appText(context, "Directory contents")),
                        tilePadding: EdgeInsets.zero,
                        subtitle: Text(
                          appText(context, '{0} directory items', [
                            tree.members.length,
                          ]),
                        ),
                        children: [
                          SizedBox(
                            height: 260,
                            child: ListView.builder(
                              itemCount: tree.members.length,
                              itemBuilder: (context, index) {
                                final member = tree.members[index];
                                final locality = switch (member.local) {
                                  true => 'local',
                                  false => 'not local',
                                  null => 'availability unknown',
                                };
                                return Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    '${member.path} · ${member.kind.name} · $locality',
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),

                  ExpansionTile(
                    key: const ValueKey('move-check-details'),
                    trailing: _chevron('move-check-details'),
                    onExpansionChanged: (expanded) => setState(
                      () => _expanded['move-check-details'] = expanded,
                    ),
                    leading: const MovePreviewIcon(
                      MovePreviewGlyph.note,
                      size: 20,
                    ),
                    tilePadding: EdgeInsets.zero,
                    title: Text(appText(context, 'Check details')),
                    subtitle: Text(
                      appText(context, '{0} blockers · {1} coverage warnings', [
                        plan.blockers.length,
                        plan.warnings.length,
                      ]),
                    ),
                    children: [
                      if (plan.kind == WorkspaceNoteMovePlanKind.directory)
                        Text(
                          appText(
                            context,
                            'Directory reference maintenance moves one folder and updates affected notes. Native preflight rechecks the complete tree and destination vacancy. No merging, overwriting or automatic rollback.',
                          ),
                        ),
                      if (plan.kind == WorkspaceNoteMovePlanKind.batch)
                        Text(
                          appText(
                            context,
                            'Batch reference maintenance maps all selected roots simultaneously and rewrites each affected note once. Destination vacancy and all root identities are rechecked by native preflight before any user file changes. Root moves are not all-or-nothing: a failure can leave some roots at their old locations after references have changed. Review each root receipt; never repeat a partial move blindly.',
                          ),
                        ),
                      for (final issue in [...plan.blockers, ...plan.warnings])
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            issue.path == null
                                ? issue.code
                                : _displayPath(issue.path!),
                          ),
                          subtitle: SelectableText(issue.message),
                        ),
                      if (plan.canExecute)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            appText(
                              context,
                              'Moving with updates retains original recovery copies: a private app journal and hidden recovery files beside changed notes. Hidden files use disk space and may sync with your vault. They are not automatically deleted. Review recovery before retrying a partial or unknown result.',
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (plan.files.isNotEmpty)
                    ExpansionTile(
                      key: const ValueKey('move-link-details'),
                      trailing: _chevron('move-link-details'),
                      onExpansionChanged: (expanded) => setState(
                        () => _expanded['move-link-details'] = expanded,
                      ),
                      leading: const MovePreviewIcon(
                        MovePreviewGlyph.link,
                        size: 20,
                      ),
                      tilePadding: EdgeInsets.zero,
                      title: Text(appText(context, 'Link changes')),
                      subtitle: Text(
                        appText(context, '{0} involved notes', [
                          plan.files.length,
                        ]),
                      ),
                      children: [
                        for (final file in plan.files)
                          ExpansionTile(
                            key: ValueKey('note-move-diff-${file.path}'),
                            trailing: _chevron('diff:${file.path}'),
                            onExpansionChanged: (expanded) => setState(
                              () => _expanded['diff:${file.path}'] = expanded,
                            ),
                            title: Text(
                              '${file.path}${file.destination == file.path ? '' : ' → ${file.destination}'}',
                            ),
                            subtitle: Text(
                              appText(
                                context,
                                "{0} exact source replacement(s)",
                                [file.edits.length],
                              ),
                            ),
                            children: [
                              if (file.edits.isEmpty)
                                Text(
                                  appText(
                                    context,
                                    "The note contents stay byte-for-byte unchanged.",
                                  ),
                                ),
                              if (file.edits.isNotEmpty)
                                SizedBox(
                                  height: file.edits.length < 4
                                      ? file.edits.length * 90.0
                                      : 300,
                                  child: ListView.builder(
                                    itemCount: file.edits.length,
                                    itemBuilder: (context, index) {
                                      final edit = file.edits[index];
                                      final line =
                                          '\n'
                                              .allMatches(
                                                file.source.text.substring(
                                                  0,
                                                  edit.range.start,
                                                ),
                                              )
                                              .length +
                                          1;
                                      return Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: SelectableText(
                                          appText(
                                            context,
                                            "Line {0}: {1} → {2}",
                                            [line, edit.before, edit.after],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                ] else
                  Text(
                    (state.data?.$2 == true
                            ? appText(
                                context,
                                'The reference preview is unavailable. No complete maintenance plan could be verified.',
                              )
                            : widget.unavailable) ??
                        appText(
                          context,
                          'No complete reference preview is available for this selection.',
                        ),
                  ),
                if (!_attempted) ...[
                  const Divider(height: 24),
                  Text(
                    appText(
                      context,
                      _renaming
                          ? 'Renaming without updates may break existing links.'
                          : 'Moving without updates may break existing links.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (plan?.canExecute == true)
                    Text(
                      appText(
                        context,
                        'Original recovery copies are retained and may sync with your vault.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
                if (_busy && !_confirmingRecovery) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  Text(
                    appText(
                      context,
                      "Verifying and recording the operation. Do not start another move.",
                    ),
                  ),
                ],
                if (_error != null) Text(_error!),
                if (_record case final record?) ...[
                  const SizedBox(height: 12),
                  Text(
                    record.completed
                        ? appText(
                            context,
                            plan?.warnings.isNotEmpty == true
                                ? 'Rename and confirmed link updates verified. Unchecked links may remain.'
                                : 'Move and reference updates verified.',
                          )
                        : appText(
                            context,
                            "Operation state: {0}. Do not assume every file changed.",
                            [record.phase],
                          ),
                  ),
                  if (record.message != null) Text(record.message!),
                  if (record.code != null) Text(record.code!),
                  if (record.namespace case final namespace?)
                    Text(
                      appText(context, "Directory: {0} → {1}; {2} at {3}.", [
                        namespace.sourcePath,
                        namespace.destinationPath,
                        namespace.verified ? 'verified' : 'unverified',
                        namespace.actualPath ?? 'unknown location',
                      ]),
                    ),
                  for (final root in record.namespaces)
                    Text(workspaceBatchRootStatus(root)),
                  for (final entry in record.entries)
                    Text(
                      '${entry.path}: ${entry.state}${entry.verified ? ' (verified)' : ' (not verified)'}${entry.actualPath == null ? '' : ' at ${entry.actualPath}'}',
                    ),
                  for (final artifact in record.retainedArtifacts)
                    Text(
                      appText(context, "Retained artifact: {0} ({1}{2})", [
                        artifact.path,
                        artifact.state,
                        artifact.verified ? ', verified' : ', unverified',
                      ]),
                    ),
                  for (final copy in record.recoveryEntries)
                    Text(
                      appText(context, "Original copy: {0} ({1})", [
                        copy.path,
                        copy.state,
                      ]),
                    ),
                  for (final path in record.recoveryPaths)
                    Text(
                      appText(context, "Recovered original copy: {0}", [path]),
                    ),
                  Text(
                    appText(context, "Recovery journal: {0}", [
                      record.transactionId,
                    ]),
                  ),
                ],
                if (scrollActions) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
