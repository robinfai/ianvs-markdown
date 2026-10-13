import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelected: () {
                if (controller.mode != IanvsMarkdownEditorMode.preview) {
                  controller.undo();
                }
              },
            ),
            PlatformMenuItem(
              label: 'Redo',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected: () {
                if (controller.mode != IanvsMarkdownEditorMode.preview) {
                  controller.redo();
                }
              },
            ),
            const PlatformMenuItem(
              label: 'Cut',
              shortcut: SingleActivator(LogicalKeyboardKey.keyX, meta: true),
              onSelectedIntent: CopySelectionTextIntent.cut(
                SelectionChangedCause.keyboard,
              ),
            ),
            const PlatformMenuItem(
              label: 'Copy',
              shortcut: SingleActivator(LogicalKeyboardKey.keyC, meta: true),
              onSelectedIntent: CopySelectionTextIntent.copy,
            ),
            const PlatformMenuItem(
              label: 'Paste',
              shortcut: SingleActivator(LogicalKeyboardKey.keyV, meta: true),
              onSelectedIntent: PasteTextIntent(SelectionChangedCause.keyboard),
            ),
            const PlatformMenuItem(
              label: 'Select All',
              shortcut: SingleActivator(LogicalKeyboardKey.keyA, meta: true),
              onSelectedIntent: SelectAllTextIntent(
                SelectionChangedCause.keyboard,
              ),
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            for (final entry
                in <(String, IanvsMarkdownEditorMode, LogicalKeyboardKey)>[
                  (
                    'Live Preview',
                    IanvsMarkdownEditorMode.livePreview,
                    LogicalKeyboardKey.digit1,
                  ),
                  (
                    'Source',
                    IanvsMarkdownEditorMode.source,
                    LogicalKeyboardKey.digit2,
                  ),
                  (
                    'Read',
                    IanvsMarkdownEditorMode.preview,
                    LogicalKeyboardKey.digit3,
                  ),
                ])
              PlatformMenuItem(
                label: entry.$1,
                shortcut: SingleActivator(entry.$3, meta: true),
                onSelected: () => controller.mode = entry.$2,
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
