import 'package:flutter/material.dart';

import '../controllers/document_sync_controller.dart';
import '../models/document_sync_status.dart';

/// Routine cloud activity stays in the background. Only actionable provider
/// failures and unresolved versions appear in the document UI.
class DocumentSyncIndicator extends StatelessWidget {
  const DocumentSyncIndicator({
    super.key,
    required this.controller,
    this.onSaveCopy,
    this.onResolve,
  });
  final VoidCallback? onResolve;
  final VoidCallback? onSaveCopy;
  final DocumentSyncController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) =>
        controller.path == null ||
            (controller.metadata.state != CloudSyncState.failure &&
                controller.metadata.state != CloudSyncState.conflict)
        ? const SizedBox.shrink()
        : Tooltip(
            message: 'Cloud status details and retry',
            child: Semantics(
              liveRegion: true,
              button: true,
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _SyncDetails(
                    controller: controller,
                    onSaveCopy: onSaveCopy,
                    onResolve: onResolve,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    controller.metadata.label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
  );
}

class _SyncDetails extends StatelessWidget {
  const _SyncDetails({
    required this.controller,
    this.onSaveCopy,
    this.onResolve,
  });
  final VoidCallback? onResolve;
  final VoidCallback? onSaveCopy;
  final DocumentSyncController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final metadata = controller.metadata;
      return AlertDialog(
        title: const Text('Cloud status'),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                controller.checking ? 'Checking cloud status' : metadata.label,
              ),
              const SizedBox(height: 12),
              Text(metadata.explanation),
              if (metadata.observedAt case final sampled?) ...[
                const SizedBox(height: 8),
                Text('Observed on this device: ${sampled.toLocal()}'),
              ],
              if (metadata.state == CloudSyncState.conflict) ...[
                const SizedBox(height: 12),
                Text(
                  metadata.conflictsAvailable
                      ? 'Conflict versions reported by the system (up to 50):'
                      : 'Conflict version details are unavailable.',
                ),
                for (final version in metadata.conflicts)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${version.name}${version.modified == null ? '' : '\n${version.modified!.toLocal()}'}',
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          if (metadata.state == CloudSyncState.conflict && onResolve != null)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onResolve!();
              },
              child: const Text('解决冲突'),
            ),

          if (onSaveCopy != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onSaveCopy!();
              },
              child: const Text('Save a copy'),
            ),

          TextButton(
            onPressed:
                !controller.canRead ||
                    controller.checking ||
                    controller.path == null
                ? null
                : controller.refresh,
            child: const Text('Check again'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
