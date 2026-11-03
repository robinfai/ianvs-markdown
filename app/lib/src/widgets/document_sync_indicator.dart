import '../app_localizations.dart';
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
            message: appText(context, "Cloud status details and retry"),
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
                    appText(context, controller.metadata.label),
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
        title: Text(appText(context, "Cloud status")),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                controller.checking
                    ? appText(context, "Checking cloud status")
                    : appText(context, metadata.label),
              ),
              const SizedBox(height: 12),
              Text(metadata.detail ?? appText(context, metadata.explanation)),
              if (metadata.observedAt case final sampled?) ...[
                const SizedBox(height: 8),
                Text(
                  appText(context, "Observed on this device: {0}", [
                    sampled.toLocal(),
                  ]),
                ),
              ],
              if (metadata.state == CloudSyncState.conflict) ...[
                const SizedBox(height: 12),
                Text(
                  metadata.conflictsAvailable
                      ? appText(
                          context,
                          "Conflict versions reported by the system (up to 50):",
                        )
                      : appText(
                          context,
                          "Conflict version details are unavailable.",
                        ),
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
              child: Text(appText(context, "解决冲突")),
            ),

          if (onSaveCopy != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onSaveCopy!();
              },
              child: Text(appText(context, "Save a copy")),
            ),

          TextButton(
            onPressed:
                !controller.canRead ||
                    controller.checking ||
                    controller.path == null
                ? null
                : controller.refresh,
            child: Text(appText(context, "Check again")),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText(context, "Close")),
          ),
        ],
      );
    },
  );
}
