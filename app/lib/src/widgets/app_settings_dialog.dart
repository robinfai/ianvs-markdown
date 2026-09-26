import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/file_association_controller.dart';
import '../desktop_typography.dart';

class AppSettingsDialog extends StatelessWidget {
  const AppSettingsDialog({super.key, required this.fileAssociation});

  final FileAssociationController fileAssociation;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: fileAssociation,
      builder: (context, _) {
        final controller = fileAssociation;
        final state = controller.state;
        return AlertDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          title: const Text('Settings'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Markdown files', style: DesktopTypography.headline),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const ValueKey('default-markdown-app-preference'),
                    value: state.preferLinefold ?? state.isDefault,
                    onChanged: state.supported && !controller.busy
                        ? (value) => controller.setPreference(value!)
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Use Linefold to open .md files by default',
                    ),
                  ),
                  Text(
                    state.supported
                        ? 'Current default: ${state.currentApplicationName ?? 'No application selected'}'
                        : 'Default application settings are available on macOS.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.previousApplicationName != null
                        ? 'Turning this off restores ${state.previousApplicationName} if Linefold is still the default.'
                        : 'If Linefold is the default, turning this off lets you choose another application.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your choice is remembered. Linefold will not ask again at startup or override changes made in macOS.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (controller.busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (controller.error case final error?) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.setPreference(
                              state.preferLinefold ?? true,
                            ),
                      child: const Text('Try Again'),
                    ),
                  ] else if (state.preferLinefold == true &&
                      !state.isDefault) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.setPreference(true),
                      child: const Text('Set Linefold as Default'),
                    ),
                  ] else if (state.preferLinefold == false &&
                      state.isDefault) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.setPreference(false),
                      child: Text(
                        state.previousApplicationName == null
                            ? 'Choose Another Application…'
                            : 'Restore Previous Default',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: controller.busy ? null : () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}

class DefaultMarkdownAppPrompt extends StatelessWidget {
  const DefaultMarkdownAppPrompt({super.key, required this.fileAssociation});

  final FileAssociationController fileAssociation;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: fileAssociation,
      builder: (context, _) => CallbackShortcuts(
        bindings: {
          if (!fileAssociation.busy)
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.pop(context, false),
        },
        child: PopScope(
          canPop: !fileAssociation.busy,
          child: AlertDialog(
            constraints: const BoxConstraints(maxWidth: 440),
            title: const Text('Open Markdown files with Linefold?'),
            content: const Text(
              'Use Linefold by default when you open a .md file in Finder. '
              'You can change this later in Linefold → Settings…',
            ),
            actions: [
              OutlinedButton(
                onPressed: fileAssociation.busy
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('Keep Current App'),
              ),
              FilledButton(
                autofocus: true,
                onPressed: fileAssociation.busy
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Use Linefold'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
