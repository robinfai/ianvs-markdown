import '../app_localizations.dart';
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
    title: Text(appText(context, "Create original recovery copies?")),
    content: Text(
      appText(
        context,
        "Create up to {0} original note copies in the selected workspace root. Existing notes are never replaced or deleted. Copies consume disk space and may sync with this vault. Copied aliases may introduce new link ambiguities. Partial copies remain separately reported; this does not finish reference maintenance.",
        [count],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(appText(context, "Cancel")),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(appText(context, "Create original copies")),
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
      title: Text(appText(context, "Note move recovery")),
      content: SizedBox(
        width: 700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              appText(
                context,
                "Storage inspection is read-only. Saved states are historical, not a fresh verification of notes or artifact contents. Nothing is automatically retried, repaired or deleted.",
              ),
            ),
            if (_observing || (_recovering && !_confirmingRecovery))
              const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_storage case final storage?) ...[
              const SizedBox(height: 12),
              Text(
                appText(context, "All app-managed recovery journals"),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                appText(
                  context,
                  "Record slots: {0} / {1} ({2} valid journals; {3} invalid)",
                  [
                    _count(storage.globalRecordSlotCount),
                    storage.recordLimit,
                    _count(storage.globalJournalCount),
                    _count(storage.invalidJournalCount),
                  ],
                ),
              ),
              Text(
                appText(context, "Encoded storage: {0} / {1}", [
                  _bytes(storage.globalJournalBytes),
                  _bytes(storage.journalByteLimit),
                ]),
              ),
              Text(
                appText(
                  context,
                  "Pending remnants: {0} files, {1}. They consume bytes, not record slots.",
                  [_count(storage.pendingCount), _bytes(storage.pendingBytes)],
                ),
              ),
              Text(
                appText(context, "Artifact reservation: {0} / {1}", [
                  _bytes(storage.artifactReservedBytes),
                  _bytes(storage.artifactReservationLimit),
                ]),
              ),
              Text(
                appText(
                  context,
                  "Journal budget headroom: {0}. This is not free disk space or approval for another move.",
                  [_bytes(storage.availableBudgetBytes)],
                ),
              ),
              Text(
                appText(
                  context,
                  "Unavailable records: {0}; unknown entries: {1}",
                  [
                    _count(storage.unavailableCount),
                    _count(storage.unknownEntryCount),
                  ],
                ),
              ),
              if (!storage.observedComplete)
                Text(
                  appText(
                    context,
                    "Incomplete observation. Unknown totals are not zero; no recovery data was discarded.",
                  ),
                ),
              if (storage.storageLimitReached)
                Text(
                  appText(
                    context,
                    "Recovery storage limit reached. New maintained moves are blocked rather than deleting recovery evidence.",
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                appText(context, "Selected workspace only"),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                appText(context, "Journal bytes: {0}", [
                  _bytes(storage.currentRootJournalBytes),
                ]),
              ),
              Text(
                appText(
                  context,
                  "Retained artifacts: {0}; reported allocation: {1}",
                  [
                    _bytes(storage.currentRootArtifactBytes),
                    _bytes(storage.currentRootArtifactAllocatedBytes),
                  ],
                ),
              ),
              Text(
                appText(context, "Unverifiable artifacts: {0}", [
                  _count(storage.artifactUnknownCount),
                ]),
              ),
              Text(
                appText(
                  context,
                  "Allocation is a filesystem metadata sum, not exclusive physical disk usage. Other workspaces and Trash are not scanned. Recovery copies are not included in artifact totals.",
                ),
              ),
              for (final code in storage.blockers.toSet()) Text(_reason(code)),
              const SizedBox(height: 12),
              Text(
                appText(
                  context,
                  "Cleanup is not available. Original-copy recovery does not release record slots or the storage budget. Keep retained artifacts and journals, especially when a result is partial or unknown.",
                ),
              ),
              if (storage.records.isEmpty)
                Text(
                  storage.observedComplete && storage.currentRootKnown
                      ? appText(
                          context,
                          "No retained note-move journals for this workspace.",
                        )
                      : appText(
                          context,
                          "No readable journals were identified for this workspace; the inventory may be incomplete.",
                        ),
                ),
              for (final record in storage.records) ...[
                const SizedBox(height: 16),
                Text(
                  '${record.sourcePath} → ${record.destinationPath}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(appText(context, "Journal: {0}", [record.transactionId])),
                Text(
                  appText(context, "Saved state: {0} (historical)", [
                    record.storedPhase,
                  ]),
                ),
                for (final root in record.namespaces)
                  Text(workspaceBatchRootStatus(root, historical: true)),
                if (record.namespace case final root?)
                  Text(
                    appText(
                      context,
                      "Last recorded directory: {0} → {1}; {2} (historical, not a current observation).",
                      [
                        root.sourcePath,
                        root.destinationPath,
                        root.actualPath ?? 'unknown location',
                      ],
                    ),
                  ),
                if (record.storedCode != null) Text(record.storedCode!),
                Text(
                  appText(
                    context,
                    "Journal {0}; artifacts {1}; reported allocation {2}",
                    [
                      _bytes(record.journalBytes),
                      _bytes(record.artifactBytes),
                      _bytes(record.allocatedBytes),
                    ],
                  ),
                ),
                Text(
                  appText(
                    context,
                    "{0} planned artifacts; {1} unexpectedly absent; {2} unverifiable",
                    [
                      _count(record.artifactCount),
                      _count(record.artifactMissingCount),
                      _count(record.artifactUnknownCount),
                    ],
                  ),
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
                  child: Text(
                    appText(context, "Recover originals as new copies"),
                  ),
                ),
              ],
            ],
            if (_recoveryResult case final result?) ...[
              const SizedBox(height: 16),
              Text(appText(context, "Last explicit recovery result")),
              for (final root in result.namespaces)
                Text(workspaceBatchRootStatus(root)),
              if (result.code != null) Text(result.code!),
              if (result.message != null) Text(result.message!),
              for (final copy in result.recoveryEntries)
                Text(
                  appText(context, "Original copy: {0} ({1})", [
                    copy.path,
                    copy.state,
                  ]),
                ),
              Text(
                appText(
                  context,
                  "Copies do not finish reference maintenance or replace current notes.",
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _recovering ? null : () => Navigator.pop(context),
          child: Text(appText(context, "Close")),
        ),
        TextButton(
          onPressed: _observing || _recovering || !_current ? null : _refresh,
          child: Text(appText(context, "Refresh")),
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
