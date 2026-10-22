import 'package:flutter/material.dart';

import '../controllers/workspace_controller.dart';
import '../services/workspace_note_transaction.dart';

Future<bool?> confirmWorkspaceNoteMoveRecoveryCopies(
  BuildContext context,
  int count,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Create original recovery copies?'),
    content: Text(
      'Create up to $count original note copies in the selected workspace root. Existing notes are never replaced or deleted. Copies consume disk space and may sync with this vault. Copied aliases may introduce new link ambiguities. Partial copies remain separately reported; this does not finish reference maintenance.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Create original copies'),
      ),
    ],
  ),
);

Future<void> showWorkspaceNoteMoveRecovery(
  BuildContext context,
  WorkspaceController workspace,
) => showDialog<void>(
  context: context,
  builder: (_) => _NoteMoveRecovery(workspace: workspace),
);

class _NoteMoveRecovery extends StatefulWidget {
  const _NoteMoveRecovery({required this.workspace});
  final WorkspaceController workspace;
  @override
  State<_NoteMoveRecovery> createState() => _NoteMoveRecoveryState();
}

class _NoteMoveRecoveryState extends State<_NoteMoveRecovery> {
  late final String? _root = widget.workspace.workspaceRoot;
  late final int _epoch = widget.workspace.index.epoch;
  List<WorkspaceNoteMoveRecord> _records = const [];
  bool _busy = true;
  bool _confirmingRecovery = false;
  String? _error;
  WorkspaceNoteMoveJournalList? _listing;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  bool get _current =>
      _root != null &&
      _root == widget.workspace.workspaceRoot &&
      _epoch == widget.workspace.index.epoch;

  Future<void> _refresh() async {
    try {
      if (!_current) {
        throw StateError('Select the original workspace and reopen recovery.');
      }
      final records = await widget.workspace.refreshNoteMoveRecovery();
      if (mounted && _current) {
        setState(() {
          _records = records.transactions;
          _listing = records;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover(WorkspaceNoteMoveRecord record) async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _confirmingRecovery = true;
      _error = null;
    });
    try {
      final approved = await confirmWorkspaceNoteMoveRecoveryCopies(
        context,
        record.entries.length,
      );
      if (approved != true || !mounted || !_current) return;
      setState(() => _confirmingRecovery = false);
      await widget.workspace.recoverNoteMoveCopies(record.transactionId);
      await _refresh();
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
    child: AlertDialog(
      title: const Text('Note move recovery'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No automatic rollback or retry is performed. Original copies never overwrite current files. Hidden recovery artifacts remain beside changed notes and may sync with the vault. Cleanup is not automatic; retained-record limits block new moves rather than discarding recovery data.',
              ),
              if (!_current)
                const Text(
                  'The workspace changed. Close this view and select the original workspace.',
                ),
              if (_busy && !_confirmingRecovery)
                const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              if ((_listing?.unavailableRecords ?? 0) > 0)
                Text(
                  '${_listing!.unavailableRecords} retained journal(s) could not be verified. Their data was not discarded; available records are shown below.',
                ),
              if (_listing?.storageBlocked == true)
                const Text(
                  'Recovery storage is full. New moves are blocked, not pruned. Keep recovery data until explicit recoverable cleanup is available.',
                ),
              if (!_busy && _records.isEmpty && _error == null)
                const Text(
                  'No retained note-move journals for this workspace.',
                ),
              for (final record in _records) ...[
                const SizedBox(height: 16),
                Text('${record.transactionId}: ${record.phase}'),
                if (record.code != null) Text(record.code!),
                for (final entry in record.entries)
                  Text(
                    '${entry.path}: ${entry.state}${entry.verified ? ' (verified)' : ' (unverified)'}${entry.actualPath == null ? '' : ' at ${entry.actualPath}'}',
                  ),
                for (final artifact in record.retainedArtifacts)
                  Text(
                    'Retained artifact: ${artifact.path} (${artifact.state}${artifact.verified ? ', verified' : ', unverified'})',
                  ),
                for (final copy in record.recoveryEntries)
                  Text('Original copy: ${copy.path} (${copy.state})'),
                if (record.entries.isNotEmpty)
                  TextButton(
                    onPressed: _busy || !_current
                        ? null
                        : () => _recover(record),
                    child: const Text('Recover originals as new copies'),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: _busy || !_current
              ? null
              : () {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  _refresh();
                },
          child: const Text('Refresh verified state'),
        ),
      ],
    ),
  );
}
