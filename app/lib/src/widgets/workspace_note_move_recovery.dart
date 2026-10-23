import 'package:flutter/material.dart';

import '../controllers/workspace_controller.dart';
import '../services/workspace_note_transaction.dart';

Future<bool?> confirmWorkspaceNoteMoveRecoveryCopies(
  BuildContext context,
  int count,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    scrollable: true,
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
  WorkspaceNoteMoveStorage? _storage;
  WorkspaceNoteMoveRecord? _recoveryResult;
  bool _observing = false;
  bool _recovering = false;
  bool _confirmingRecovery = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_workspaceChanged);
    _refresh();
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_workspaceChanged);
    super.dispose();
  }

  bool get _current =>
      _root != null &&
      _root == widget.workspace.workspaceRoot &&
      _epoch == widget.workspace.index.epoch;

  void _workspaceChanged() {
    if (mounted && !_current) {
      setState(() {
        _storage = null;
        _recoveryResult = null;
        _error = 'The workspace changed. Close this view and reopen recovery.';
      });
    }
  }

  Future<void> _refresh() async {
    if (_observing || !_current) return;
    setState(() {
      _observing = true;
      _error = null;
    });
    try {
      final storage = await widget.workspace.inspectNoteMoveStorage();
      if (mounted && _current) setState(() => _storage = storage);
    } on Object catch (error) {
      if (mounted && _current) {
        setState(() {
          _storage = null;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _observing = false);
    }
  }

  Future<void> _recover(WorkspaceNoteMoveStorageRecord record) async {
    if (!_current ||
        _observing ||
        _recovering ||
        _storage?.currentRootKnown != true) {
      return;
    }
    setState(() {
      _recovering = true;
      _confirmingRecovery = true;
      _error = null;
    });
    try {
      final approved = await confirmWorkspaceNoteMoveRecoveryCopies(
        context,
        record.entryCount,
      );
      if (approved != true || !mounted || !_current) return;
      setState(() => _confirmingRecovery = false);
      final result = await widget.workspace.recoverNoteMoveCopies(
        record.transactionId,
      );
      if (!mounted || !_current) return;
      setState(() => _recoveryResult = result);
      await _refresh();
    } on Object catch (error) {
      if (mounted && _current) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _recovering = false;
          _confirmingRecovery = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Observations are safe to dismiss, even when the native read is pending.
    canPop: !_recovering,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Note move recovery'),
      content: SizedBox(
        width: 700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Storage inspection is read-only. Saved states are historical, not a fresh verification of notes or artifact contents. Nothing is automatically retried, repaired or deleted.',
            ),
            if (_observing || (_recovering && !_confirmingRecovery))
              const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_storage case final storage?) ...[
              const SizedBox(height: 12),
              Text(
                'All app-managed recovery journals',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                'Record slots: ${_count(storage.globalRecordSlotCount)} / ${storage.recordLimit} (${_count(storage.globalJournalCount)} valid journals; ${_count(storage.invalidJournalCount)} invalid)',
              ),
              Text(
                'Encoded storage: ${_bytes(storage.globalJournalBytes)} / ${_bytes(storage.journalByteLimit)}',
              ),
              Text(
                'Pending remnants: ${_count(storage.pendingCount)} files, ${_bytes(storage.pendingBytes)}. They consume bytes, not record slots.',
              ),
              Text(
                'Artifact reservation: ${_bytes(storage.artifactReservedBytes)} / ${_bytes(storage.artifactReservationLimit)}',
              ),
              Text(
                'Journal budget headroom: ${_bytes(storage.availableBudgetBytes)}. This is not free disk space or approval for another move.',
              ),
              Text(
                'Unavailable records: ${_count(storage.unavailableCount)}; unknown entries: ${_count(storage.unknownEntryCount)}',
              ),
              if (!storage.observedComplete)
                const Text(
                  'Incomplete observation. Unknown totals are not zero; no recovery data was discarded.',
                ),
              if (storage.storageLimitReached)
                const Text(
                  'Recovery storage limit reached. New maintained moves are blocked rather than deleting recovery evidence.',
                ),
              const SizedBox(height: 12),
              Text(
                'Selected workspace only',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text('Journal bytes: ${_bytes(storage.currentRootJournalBytes)}'),
              Text(
                'Retained artifacts: ${_bytes(storage.currentRootArtifactBytes)}; reported allocation: ${_bytes(storage.currentRootArtifactAllocatedBytes)}',
              ),
              Text(
                'Unverifiable artifacts: ${_count(storage.artifactUnknownCount)}',
              ),
              const Text(
                'Allocation is a filesystem metadata sum, not exclusive physical disk usage. Other workspaces and Trash are not scanned. Recovery copies are not included in artifact totals.',
              ),
              for (final code in storage.blockers.toSet()) Text(_reason(code)),
              const SizedBox(height: 12),
              const Text(
                'Cleanup is not available. Original-copy recovery does not release record slots or the storage budget. Keep retained artifacts and journals, especially when a result is partial or unknown.',
              ),
              if (storage.records.isEmpty)
                Text(
                  storage.observedComplete && storage.currentRootKnown
                      ? 'No retained note-move journals for this workspace.'
                      : 'No readable journals were identified for this workspace; the inventory may be incomplete.',
                ),
              for (final record in storage.records) ...[
                const SizedBox(height: 16),
                Text(
                  '${record.sourcePath} → ${record.destinationPath}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text('Journal: ${record.transactionId}'),
                Text('Saved state: ${record.storedPhase} (historical)'),
                for (final root in record.namespaces)
                  Text(workspaceBatchRootStatus(root, historical: true)),
                if (record.namespace case final root?)
                  Text(
                    'Last recorded directory: ${root.sourcePath} → ${root.destinationPath}; ${root.actualPath ?? 'unknown location'} (historical, not a current observation).',
                  ),
                if (record.storedCode != null) Text(record.storedCode!),
                Text(
                  'Journal ${_bytes(record.journalBytes)}; artifacts ${_bytes(record.artifactBytes)}; reported allocation ${_bytes(record.allocatedBytes)}',
                ),
                Text(
                  '${_count(record.artifactCount)} planned artifacts; ${_count(record.artifactMissingCount)} unexpectedly absent; ${_count(record.artifactUnknownCount)} unverifiable',
                ),
                for (final code in record.blockers.toSet().where(
                  (code) =>
                      code != 'cleanup_not_implemented' &&
                      code != 'platform_recovery_surface_unverified',
                ))
                  Text(_reason(code)),
                TextButton(
                  onPressed:
                      _observing ||
                          _recovering ||
                          !_current ||
                          !storage.currentRootKnown
                      ? null
                      : () => _recover(record),
                  child: const Text('Recover originals as new copies'),
                ),
              ],
            ],
            if (_recoveryResult case final result?) ...[
              const SizedBox(height: 16),
              const Text('Last explicit recovery result'),
              for (final root in result.namespaces)
                Text(workspaceBatchRootStatus(root)),
              if (result.code != null) Text(result.code!),
              if (result.message != null) Text(result.message!),
              for (final copy in result.recoveryEntries)
                Text('Original copy: ${copy.path} (${copy.state})'),
              const Text(
                'Copies do not finish reference maintenance or replace current notes.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _recovering ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: _observing || _recovering || !_current ? null : _refresh,
          child: const Text('Refresh'),
        ),
      ],
    ),
  );
}

String _count(int? count) => count?.toString() ?? 'Unknown';
String _bytes(int? bytes) {
  if (bytes == null) return 'Unknown';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

String _reason(String code) => switch (code) {
  'cleanup_not_implemented' => 'Recoverable cleanup has not been implemented.',
  'platform_recovery_surface_unverified' =>
    'Cleanup is disabled: a user-visible recovery location has not been verified on this platform.',
  'journal_unavailable' => 'Private journal storage could not be read safely.',
  'journal_changed_during_observation' =>
    'Journal storage changed while it was being observed.',
  'journal_entry_limit' =>
    'The bounded journal directory scan could not cover every entry.',
  'journal_read_limit' => 'The bounded journal read budget was reached.',
  'journal_invalid' =>
    'Some saved journals are invalid or cannot be decoded safely.',
  'journal_unknown_entries' =>
    'Unrecognized storage entries were retained without modification.',
  'journal_pending_remnants' =>
    'Pending journal remnants were retained; their status has not been resolved.',
  'journal_record_limit' => 'The retained record-slot limit has been reached.',
  'journal_byte_limit' => 'The encoded journal-byte limit has been reached.',
  'artifact_reservation_limit' =>
    'The retained artifact-reservation limit has been reached.',
  'scope_unavailable' => 'The selected workspace could not be accessed safely.',
  'scope_changed_during_observation' =>
    'The selected workspace identity changed during observation.',
  'artifact_unverified' => 'Some artifact metadata could not be verified.',
  'partial_unverified' =>
    'This saved result is unfinished or unverified. Its recovery evidence must be retained.',
  'artifact_missing' =>
    'A planned artifact is absent. This observation does not prove cleanup or successful recovery.',
  'artifact_changed' =>
    'An artifact no longer matches its saved identity or metadata. Keep it as possible recovery evidence.',
  'artifact_unavailable' =>
    'An artifact could not be inspected safely and was not opened for its contents.',
  'admission_not_evaluated' =>
    'A new move still needs its own complete preflight, including journal rewrite headroom and actual free disk space.',
  _ => 'Additional storage constraint: $code',
};

/// A root may be independently completed even when another root is uncertain.
String workspaceBatchRootStatus(
  WorkspaceBatchMoveReceipt root, {
  bool historical = false,
}) {
  final state = root.completed
      ? 'verified destination'
      : root.atSource
      ? 'verified source'
      : 'uncertain';
  return '${historical ? 'Last recorded: ' : ''}${root.sourcePath} → ${root.destinationPath}: $state at ${root.actualPath ?? 'unknown location'}${historical ? ' (historical, not a current observation)' : ''}.';
}
