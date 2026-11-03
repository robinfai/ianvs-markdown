import '../app_localizations.dart';
import 'dart:io';
import 'finder_preview_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/file_association_controller.dart';
import '../desktop_typography.dart';
import '../controllers/workspace_controller.dart';
import '../models/reading_preferences.dart';

class AppSettingsDialog extends StatelessWidget {
  const AppSettingsDialog({
    super.key,
    required this.fileAssociation,
    this.workspace,
  });

  final FileAssociationController fileAssociation;
  final WorkspaceController? workspace;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([fileAssociation, ?workspace]),
      builder: (context, _) {
        final controller = fileAssociation;
        final state = controller.state;
        return AlertDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          title: Text(appText(context, "Settings")),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (workspace case final workspace?) ...[
                    Text(
                      appText(context, "Reading"),
                      style: DesktopTypography.headline,
                    ),
                    Text(
                      appText(context, "Text size: {0}", [
                        workspace.readingPreferences.fontSize.toStringAsFixed(
                          1,
                        ),
                      ]),
                    ),
                    Slider(
                      key: const ValueKey('reading-font-size'),
                      label:
                          '${workspace.readingPreferences.fontSize.toStringAsFixed(1)} pt',
                      semanticFormatterCallback: (value) => appText(
                        context,
                        'Text size {0} points',
                        [value.toStringAsFixed(1)],
                      ),
                      min: 12,
                      max: 28,
                      divisions: 32,
                      value: workspace.readingPreferences.fontSize,
                      onChanged: (value) => workspace.setReadingPreferences(
                        workspace.readingPreferences.copyWith(fontSize: value),
                      ),
                    ),
                    Text(
                      appText(context, "Line spacing: {0}", [
                        workspace.readingPreferences.lineHeight.toStringAsFixed(
                          2,
                        ),
                      ]),
                    ),
                    Slider(
                      key: const ValueKey('reading-line-height'),
                      label: workspace.readingPreferences.lineHeight
                          .toStringAsFixed(2),
                      semanticFormatterCallback: (value) => appText(
                        context,
                        'Line spacing {0}',
                        [value.toStringAsFixed(2)],
                      ),
                      min: 1.2,
                      max: 2.2,
                      divisions: 50,
                      value: workspace.readingPreferences.lineHeight,
                      onChanged: (value) => workspace.setReadingPreferences(
                        workspace.readingPreferences.copyWith(
                          lineHeight: value,
                        ),
                      ),
                    ),
                    DropdownButton<ReadingWidth>(
                      key: const ValueKey('reading-width'),
                      value: workspace.readingPreferences.width,
                      items: [
                        DropdownMenuItem(
                          value: ReadingWidth.narrow,
                          child: Text(appText(context, "Narrow body")),
                        ),
                        DropdownMenuItem(
                          value: ReadingWidth.standard,
                          child: Text(appText(context, "Standard body")),
                        ),
                        DropdownMenuItem(
                          value: ReadingWidth.wide,
                          child: Text(appText(context, "Wide body")),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          workspace.setReadingPreferences(
                            workspace.readingPreferences.copyWith(width: value),
                          );
                        }
                      },
                    ),
                    CheckboxListTile(
                      key: const ValueKey('reading-wrap-code'),
                      title: Text(appText(context, "Wrap code lines")),
                      contentPadding: EdgeInsets.zero,
                      value: workspace.readingPreferences.wrapCode,
                      onChanged: (value) => workspace.setReadingPreferences(
                        workspace.readingPreferences.copyWith(wrapCode: value),
                      ),
                    ),
                    TextButton(
                      onPressed: () => workspace.setReadingPreferences(
                        ReadingPreferences.defaults,
                      ),
                      child: Text(appText(context, "Reset reading settings")),
                    ),
                    const Divider(),
                  ],
                  Text(
                    appText(context, "Markdown files"),
                    style: DesktopTypography.headline,
                  ),
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
                    title: Text(
                      appText(
                        context,
                        "Use Linefold to open .md files by default",
                      ),
                    ),
                  ),
                  Text(
                    state.supported
                        ? appText(context, "Current default: {0}", [
                            state.currentApplicationName ??
                                appText(context, 'No application selected'),
                          ])
                        : appText(
                            context,
                            "Default application settings are available on macOS.",
                          ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.previousApplicationName != null
                        ? appText(
                            context,
                            "Turning this off restores {0} if Linefold is still the default.",
                            [state.previousApplicationName],
                          )
                        : appText(
                            context,
                            "If Linefold is the default, turning this off lets you choose another application.",
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appText(
                      context,
                      "Your choice is remembered. Linefold will not ask again at startup or override changes made in macOS.",
                    ),
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
                      child: Text(appText(context, "Try Again")),
                    ),
                  ] else if (state.preferLinefold == true &&
                      !state.isDefault) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.setPreference(true),
                      child: Text(appText(context, "Set Linefold as Default")),
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
                            ? appText(context, "Choose Another Application…")
                            : appText(context, "Restore Previous Default"),
                      ),
                    ),
                  ],
                  if (Platform.isMacOS) ...[
                    const Divider(),
                    const FinderPreviewSettings(),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: controller.busy ? null : () => Navigator.pop(context),
              child: Text(appText(context, "Done")),
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
            title: Text(appText(context, "Open Markdown files with Linefold?")),
            content: Text(
              appText(
                context,
                "Use Linefold by default when you open a .md file in Finder. You can change this later in Linefold → Settings…",
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: fileAssociation.busy
                    ? null
                    : () => Navigator.pop(context, false),
                child: Text(appText(context, "Keep Current App")),
              ),
              FilledButton(
                autofocus: true,
                onPressed: fileAssociation.busy
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(appText(context, "Use Linefold")),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
