import 'package:flutter/material.dart';

import '../services/workspace_note_move_plan.dart';
import '../services/workspace_note_transaction.dart';
import 'workspace_note_move_recovery.dart';

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
    this.onMaintain,
    this.onRecoverCopies,
  });
  final List<String> sources;
  final List<String> destinations;
  final Future<(WorkspaceNoteMovePlan?, bool)>? pending;
  final String? unavailable;
  final Future<WorkspaceNoteMoveRecord> Function(WorkspaceNoteMovePlan)?
  onMaintain;
  final Future<WorkspaceNoteMoveRecord> Function(String)? onRecoverCopies;
  @override
  State<_MovePreviewDialog> createState() => _MovePreviewDialogState();
}

class _MovePreviewDialogState extends State<_MovePreviewDialog> {
  bool _busy = false;
  bool _confirmingRecovery = false;
  bool _attempted = false;
  WorkspaceNoteMoveRecord? _record;
  String? _error;

  Future<void> _maintain(WorkspaceNoteMovePlan plan) async {
    if (_busy ||
        _attempted ||
        !plan.executionSupported ||
        !plan.complete ||
        widget.onMaintain == null) {
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
            child: Text(_attempted ? 'Close' : 'Cancel'),
          ),
          if (!_attempted)
            TextButton(
              key: const ValueKey('move-without-updating-links'),
              onPressed: waiting
                  ? null
                  : () => Navigator.pop(
                      context,
                      const WorkspaceNoteMoveDecision(manual: true),
                    ),
              child: const Text('Move without updating links'),
            ),
          if (!_attempted &&
              plan?.complete == true &&
              plan?.executionSupported == true &&
              widget.onMaintain != null)
            FilledButton(
              key: const ValueKey('move-and-update-links'),
              onPressed: waiting ? null : () => _maintain(plan!),
              child: const Text('Move and update links'),
            ),
          if (_record != null &&
              _record!.entries.isNotEmpty &&
              widget.onRecoverCopies != null)
            TextButton(
              key: const ValueKey('recover-note-move-copies'),
              onPressed: _busy ? null : _recover,
              child: const Text('Recover originals as new copies'),
            ),
        ];
        return AlertDialog(
          actions: scrollActions ? null : actions,
          scrollable: true,
          title: const Text('Preview rename / move'),
          content: SizedBox(
            width: 620,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.sources.length && i < 20; i++)
                  Text('${widget.sources[i]} → ${widget.destinations[i]}'),
                if (widget.sources.length > 20)
                  Text('… and ${widget.sources.length - 20} more items.'),
                const SizedBox(height: 16),
                const Text(
                  'Move without updating links only moves the selected files. Links in other notes and relative links or images inside moved notes will NOT be updated and may break.',
                ),
                const SizedBox(height: 12),
                if (waiting) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('Preparing a read-only reference preview…'),
                ] else if (plan != null) ...[
                  if (plan.kind == WorkspaceNoteMovePlanKind.directory) ...[
                    const Text(
                      'Directory reference maintenance moves one folder and updates affected notes. Native preflight rechecks the complete tree and destination vacancy. No merging, overwriting or automatic rollback.',
                    ),
                    if (plan.treeSnapshot case final tree?) ...[
                      Text(
                        'Directory members observed: ${tree.members.length}${tree.complete ? '' : ' (incomplete scan)'}.',
                      ),
                      if (tree.members.isNotEmpty)
                        ExpansionTile(
                          key: const ValueKey('directory-move-manifest'),
                          title: const Text('Observed directory members'),
                          subtitle: const Text(
                            'Metadata only. Unsupported members are included.',
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
                    ],
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'Proposed reference maintenance: ${plan.editCount} source replacement(s) across ${plan.files.length} affected note(s)${plan.kind == WorkspaceNoteMovePlanKind.singleNote ? ', including the moved note' : ', including moved notes with unchanged text'}.',
                  ),
                  const SizedBox(height: 8),
                  if (plan.complete)
                    Text(
                      plan.executionSupported
                          ? 'Supported-source coverage is complete. Execution rechecks local identities and exact bytes. Files change independently; a failure can leave a partial result.'
                          : 'Supported-source impact coverage is complete for this preview. No directory move transaction is available.',
                    )
                  else
                    const Text(
                      'Coverage is incomplete or blocked. This is not a safe-maintenance approval.',
                    ),
                  if (!plan.executionSupported)
                    const Text(
                      'Destination vacancy and conflicts with all filesystem objects have not been verified. This is a hypothetical impact preview, not approval to move safely.',
                    ),
                  for (final blocker in plan.blockers.take(12))
                    Text(
                      '• ${blocker.path == null ? '' : '${blocker.path}: '}${blocker.message}',
                    ),
                  if (plan.blockers.length > 12)
                    Text(
                      '… and ${plan.blockers.length - 12} more coverage issue(s).',
                    ),
                  const SizedBox(height: 8),
                  if (plan.complete &&
                      plan.executionSupported &&
                      widget.onMaintain != null)
                    const Text(
                      'Moving with updates retains original recovery copies: a private app journal and hidden recovery files beside changed notes. Hidden files use disk space and may sync with your vault. They are not automatically deleted. Review recovery before retrying a partial or unknown result.',
                    ),
                  for (final file in plan.files)
                    ExpansionTile(
                      key: ValueKey('note-move-diff-${file.path}'),
                      title: Text(
                        '${file.path}${file.destination == file.path ? '' : ' → ${file.destination}'}',
                      ),
                      subtitle: Text(
                        '${file.edits.length} exact source replacement(s)',
                      ),
                      children: [
                        if (file.edits.isEmpty)
                          const Text(
                            'The note contents stay byte-for-byte unchanged.',
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
                                    'Line $line: ${edit.before} → ${edit.after}',
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                ] else
                  Text(
                    (state.data?.$2 == true
                            ? 'The reference preview is unavailable. No complete maintenance plan could be verified.'
                            : widget.unavailable) ??
                        'No complete reference preview is available. Multi-item reference maintenance is not supported.',
                  ),
                if (_busy && !_confirmingRecovery) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const Text(
                    'Verifying and recording the operation. Do not start another move.',
                  ),
                ],
                if (_error != null) Text(_error!),
                if (_record case final record?) ...[
                  const SizedBox(height: 12),
                  Text(
                    record.completed
                        ? 'Move and reference updates verified.'
                        : 'Operation state: ${record.phase}. Do not assume every file changed.',
                  ),
                  if (record.message != null) Text(record.message!),
                  if (record.code != null) Text(record.code!),
                  if (record.namespace case final namespace?)
                    Text(
                      'Directory: ${namespace.sourcePath} → ${namespace.destinationPath}; ${namespace.verified ? 'verified' : 'unverified'} at ${namespace.actualPath ?? 'unknown location'}.',
                    ),
                  for (final entry in record.entries)
                    Text(
                      '${entry.path}: ${entry.state}${entry.verified ? ' (verified)' : ' (not verified)'}${entry.actualPath == null ? '' : ' at ${entry.actualPath}'}',
                    ),
                  for (final artifact in record.retainedArtifacts)
                    Text(
                      'Retained artifact: ${artifact.path} (${artifact.state}${artifact.verified ? ', verified' : ', unverified'})',
                    ),
                  for (final copy in record.recoveryEntries)
                    Text('Original copy: ${copy.path} (${copy.state})'),
                  for (final path in record.recoveryPaths)
                    Text('Recovered original copy: $path'),
                  Text('Recovery journal: ${record.transactionId}'),
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
