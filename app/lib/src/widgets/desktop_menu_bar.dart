import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../controllers/workspace_controller.dart';
import '../tab_shortcuts.dart';

/// macOS menu commands share the same callbacks as the window controls.
class DesktopMenuBar extends StatelessWidget {
  const DesktopMenuBar({
    super.key,
    required this.workspace,
    required this.onOpen,
    required this.onOpenFolder,
    required this.onSave,
    required this.onSaveAs,
    required this.onClose,
    required this.onToggleTheme,
    required this.child,
  });

  final WorkspaceController workspace;
  final VoidCallback onOpen;
  final VoidCallback onOpenFolder;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onClose;
  final VoidCallback onToggleTheme;
  final Widget child;

  void _undo({required bool redo}) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final inEditor =
        focusContext
            ?.findAncestorWidgetOfExactType<IanvsMarkdownLiveEditor>() !=
        null;
    if (inEditor) {
      final controller = workspace.activeDocument?.controller;
      if (redo) {
        controller?.redo();
      } else {
        controller?.undo();
      }
    } else if (focusContext != null) {
      Actions.maybeInvoke(
        focusContext,
        redo
            ? const RedoTextIntent(SelectionChangedCause.keyboard)
            : const UndoTextIntent(SelectionChangedCause.keyboard),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS ||
        !PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.about)) {
      return child;
    }
    return PlatformMenuBar(
      menus: [
        const PlatformMenu(
          label: 'Linefold',
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New Document',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: workspace.newDocument,
            ),
            PlatformMenuItem(
              label: 'Open…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: onOpen,
            ),
            PlatformMenuItem(
              label: 'Open Folder…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
                shift: true,
              ),
              onSelected: onOpenFolder,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Save',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    meta: true,
                  ),
                  onSelected: onSave,
                ),
                PlatformMenuItem(
                  label: 'Save As…',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: onSaveAs,
                ),
              ],
            ),
            PlatformMenuItem(
              label: 'Close Document',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyW,
                meta: true,
              ),
              onSelected: onClose,
            ),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItem(
              label: 'Undo',
              shortcut: SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
              onSelected: () => _undo(redo: false),
            ),
            PlatformMenuItem(
              label: 'Redo',
              shortcut: SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected: () => _undo(redo: true),
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Cut',
                  shortcut: SingleActivator(
                    LogicalKeyboardKey.keyX,
                    meta: true,
                  ),
                  onSelectedIntent: CopySelectionTextIntent.cut(
                    SelectionChangedCause.keyboard,
                  ),
                ),
                PlatformMenuItem(
                  label: 'Copy',
                  shortcut: SingleActivator(
                    LogicalKeyboardKey.keyC,
                    meta: true,
                  ),
                  onSelectedIntent: CopySelectionTextIntent.copy,
                ),
                PlatformMenuItem(
                  label: 'Paste',
                  shortcut: SingleActivator(
                    LogicalKeyboardKey.keyV,
                    meta: true,
                  ),
                  onSelectedIntent: PasteTextIntent(
                    SelectionChangedCause.keyboard,
                  ),
                ),
                PlatformMenuItem(
                  label: 'Select All',
                  shortcut: SingleActivator(
                    LogicalKeyboardKey.keyA,
                    meta: true,
                  ),
                  onSelectedIntent: SelectAllTextIntent(
                    SelectionChangedCause.keyboard,
                  ),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: workspace.sidebarVisible ? 'Hide Sidebar' : 'Show Sidebar',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                control: true,
              ),
              onSelected: workspace.toggleSidebar,
            ),
            PlatformMenuItem(
              label: workspace.outlineVisible ? 'Hide Outline' : 'Show Outline',
              onSelected: workspace.toggleOutline,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Live Preview',
                  onSelected: () =>
                      workspace.setMode(IanvsMarkdownEditorMode.livePreview),
                ),
                PlatformMenuItem(
                  label: 'Source',
                  onSelected: () =>
                      workspace.setMode(IanvsMarkdownEditorMode.source),
                ),
                PlatformMenuItem(
                  label: 'Read',
                  onSelected: () =>
                      workspace.setMode(IanvsMarkdownEditorMode.preview),
                ),
              ],
            ),
            PlatformMenuItem(
              label: 'Toggle Appearance',
              onSelected: onToggleTheme,
            ),
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen,
            ),
          ],
        ),
        PlatformMenu(
          label: 'Window',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
            PlatformMenuItemGroup(
              members: [
                for (var i = 0; i < workspace.documents.length; i++)
                  PlatformMenuItem(
                    label: workspace.documents[i].name,
                    shortcut: i < tabDigitKeys.length
                        ? SingleActivator(tabDigitKeys[i], meta: true)
                        : null,
                    onSelected: () => workspace.selectDocument(i),
                  ),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
