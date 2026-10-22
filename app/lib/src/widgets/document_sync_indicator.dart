import 'package:flutter/material.dart';

import '../controllers/document_sync_controller.dart';
import '../models/document_sync_status.dart';

/// A plain status label, not an unbounded spinner. Details distinguish sampled
/// provider metadata from successful local writes and remote-device delivery.
class DocumentSyncIndicator extends StatelessWidget {
  const DocumentSyncIndicator({super.key, required this.controller});
  final DocumentSyncController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => controller.path == null
        ? const SizedBox.shrink()
        : Tooltip(
            message: 'Cloud status details and retry',
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _SyncDetails(controller: controller),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    controller.checking
                        ? 'Checking cloud status'
                        : controller.metadata.label,
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
  const _SyncDetails({required this.controller});
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
