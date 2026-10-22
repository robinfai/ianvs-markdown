import 'package:flutter/material.dart';

import '../services/workspace_note_move_plan.dart';

/// This intermediate surface never applies the source edits it displays.
/// Returning true authorizes only the existing, explicitly unmaintained move.
Future<bool> showWorkspaceNoteMovePreview({
  required BuildContext context,
  required List<String> sources,
  required List<String> destinations,
  Future<WorkspaceNoteMovePlan>? preview,
  String? unavailable,
}) async {
  // Attach the error handler before the dialog's first frame. A fast native
  // failure must not become an unhandled Future error before FutureBuilder
  // subscribes, and cancellation must safely absorb a late result.
  final pending = preview?.then<(WorkspaceNoteMovePlan?, bool)>(
    (plan) => (plan, false),
    onError: (Object _, StackTrace _) => (null, true),
  );
  return await showDialog<bool>(
        context: context,
        builder: (context) => FutureBuilder<(WorkspaceNoteMovePlan?, bool)>(
          future: pending,
          builder: (context, state) {
            final waiting =
                preview != null &&
                state.connectionState != ConnectionState.done;
            final plan = state.data?.$1;
            return AlertDialog(
              title: const Text('Preview rename / move'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < sources.length && i < 20; i++)
                        Text('${sources[i]} → ${destinations[i]}'),
                      if (sources.length > 20)
                        Text('… and ${sources.length - 20} more items.'),
                      const SizedBox(height: 16),
                      const Text(
                        'Continuing only renames or moves the selected files. Links in other notes and relative links or images inside moved notes will NOT be updated and may break.',
                      ),
                      const SizedBox(height: 12),
                      if (waiting) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('Preparing a read-only reference preview…'),
                      ] else if (plan != null) ...[
                        Text(
                          'Proposed reference maintenance: ${plan.editCount} source replacement(s) across ${plan.files.length} affected note(s), including the moved note. These edits are not applied.',
                        ),
                        const SizedBox(height: 8),
                        if (plan.complete)
                          const Text(
                            'Supported-source coverage is complete. Recoverable automatic execution is not available yet.',
                          )
                        else
                          const Text(
                            'Coverage is incomplete or blocked. This is not a safe-maintenance approval.',
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
                        for (final file in plan.files.take(20))
                          Text(
                            '${file.path}: ${file.edits.length} proposed source replacement(s)',
                          ),
                        if (plan.files.length > 20)
                          Text(
                            '… and ${plan.files.length - 20} more affected notes.',
                          ),
                      ] else
                        Text(
                          (state.data?.$2 == true
                                  ? 'The reference preview is unavailable. No complete maintenance plan could be verified.'
                                  : unavailable) ??
                              'Folder and multi-item reference maintenance is not supported. No complete reference preview is available.',
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  key: const ValueKey('move-without-updating-links'),
                  onPressed: waiting
                      ? null
                      : () => Navigator.pop(context, true),
                  child: const Text('Move without updating links'),
                ),
              ],
            );
          },
        ),
      ) ??
      false;
}
