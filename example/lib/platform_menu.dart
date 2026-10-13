import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

/// Send macOS menu commands to Flutter's current focus, as the app host does.
class ExamplePlatformMenu extends StatelessWidget {
  const ExamplePlatformMenu({
    super.key,
    required this.controller,
    required this.child,
  });
  final IanvsMarkdownController controller;
  final Widget child;

  void _edit(IanvsMarkdownCommand command, Intent fallback) {
    if (IanvsMarkdownShortcuts.invoke(command)) return;
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null && context.mounted) {
      Actions.maybeInvoke(context, fallback);
    }
  }

  void _mode(IanvsMarkdownCommand command, IanvsMarkdownEditorMode mode) {
    if (IanvsMarkdownShortcuts.invoke(command, controller: controller)) return;
    final composing = controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    controller.mode = mode;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return child;
    return PlatformMenuBar(
      menus: [
        const PlatformMenu(
          label: 'Ianvs Markdown Playground',
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItem(
              label: 'Undo',
              onSelected: () => _edit(
                IanvsMarkdownCommand.undo,
                const UndoTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: 'Redo',
              onSelected: () => _edit(
                IanvsMarkdownCommand.redo,
                const RedoTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: 'Cut',
              onSelected: () => _edit(
                IanvsMarkdownCommand.cut,
                const CopySelectionTextIntent.cut(
                  SelectionChangedCause.keyboard,
                ),
              ),
            ),
            PlatformMenuItem(
              label: 'Copy',
              onSelected: () => _edit(
                IanvsMarkdownCommand.copy,
                CopySelectionTextIntent.copy,
              ),
            ),
            PlatformMenuItem(
              label: 'Paste',
              onSelected: () => _edit(
                IanvsMarkdownCommand.paste,
                const PasteTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: 'Select All',
              onSelected: () => _edit(
                IanvsMarkdownCommand.selectAll,
                const SelectAllTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            for (final entry
                in <(String, IanvsMarkdownCommand, IanvsMarkdownEditorMode)>[
                  (
                    'Live Preview',
                    IanvsMarkdownCommand.livePreview,
                    IanvsMarkdownEditorMode.livePreview,
                  ),
                  (
                    'Source',
                    IanvsMarkdownCommand.source,
                    IanvsMarkdownEditorMode.source,
                  ),
                  (
                    'Read',
                    IanvsMarkdownCommand.reading,
                    IanvsMarkdownEditorMode.preview,
                  ),
                ])
              PlatformMenuItem(
                label: entry.$1,
                onSelected: () => _mode(entry.$2, entry.$3),
              ),
          ],
        ),
        const PlatformMenu(
          label: 'Window',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
