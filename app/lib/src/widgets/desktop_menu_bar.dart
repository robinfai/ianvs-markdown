import '../app_localizations.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../controllers/workspace_controller.dart';
import '../tab_shortcuts.dart';
import '../editor_commands.dart';

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
    this.onUseSystemTheme,
    this.onOpenSettings,
    this.onImportImage,
    this.onExportHtml,
    this.onExportMarkdown,
    this.onExportBundle,
    this.onExportPdf,
    this.onFind,
    this.onFindNext,
    this.onFindPrevious,
    required this.child,
  });

  final WorkspaceController workspace;
  final VoidCallback onOpen;
  final VoidCallback onOpenFolder;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onClose;
  final VoidCallback onToggleTheme;
  final VoidCallback? onUseSystemTheme;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onImportImage;
  final VoidCallback? onExportHtml;
  final VoidCallback? onExportMarkdown;
  final VoidCallback? onExportBundle;
  final VoidCallback? onExportPdf;
  final VoidCallback? onFind;
  final VoidCallback? onFindNext;
  final VoidCallback? onFindPrevious;
  final Widget child;

  void _edit(IanvsMarkdownCommand command, Intent fallback) {
    if (IanvsMarkdownShortcuts.invoke(command)) return;
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null && context.mounted) {
      Actions.maybeInvoke(context, fallback);
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
        PlatformMenu(
          label: 'Linefold',
          menus: [
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.about,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: appText(context, "Check for Updates…"),
                  onSelected: () => const MethodChannel(
                    'work.ianvs.linefold/software_update',
                  ).invokeMethod<void>('check'),
                ),
                PlatformMenuItem(
                  label: appText(context, "Settings…"),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: onOpenSettings,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
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
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
          ],
        ),
        PlatformMenu(
          label: appText(context, "File"),
          menus: [
            PlatformMenuItem(
              label: appText(context, "New Document"),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: workspace.newDocument,
            ),
            PlatformMenuItem(
              label: appText(context, "Open…"),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: onOpen,
            ),
            PlatformMenuItem(
              label: appText(context, "Import Image…"),
              onSelected: onImportImage,
            ),
            PlatformMenuItem(
              label: appText(context, "Open Folder…"),
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
                  label: appText(context, "Save"),
                  onSelected: onSave,
                ),
                PlatformMenuItem(
                  label: appText(context, "Save As…"),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: onSaveAs,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: appText(context, "Export HTML…"),
                  onSelected: onExportHtml,
                ),
                PlatformMenuItem(
                  label: appText(context, "Export Markdown Copy…"),
                  onSelected: onExportMarkdown,
                ),
                PlatformMenuItem(
                  label: appText(context, "Export Markdown + Attachments…"),
                  onSelected: onExportBundle,
                ),
                PlatformMenuItem(
                  label: appText(context, "Export PDF…"),
                  onSelected: onExportPdf,
                ),
              ],
            ),
            PlatformMenuItem(
              label: appText(context, "Close Document"),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyW,
                meta: true,
              ),
              onSelected: onClose,
            ),
          ],
        ),
        PlatformMenu(
          label: appText(context, "Edit"),
          menus: [
            PlatformMenuItem(
              label: appText(context, "Undo"),
              onSelected: () => _edit(
                IanvsMarkdownCommand.undo,
                const UndoTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: appText(context, "Redo"),
              onSelected: () => _edit(
                IanvsMarkdownCommand.redo,
                const RedoTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: appText(context, "Cut"),
              onSelected: () => _edit(
                IanvsMarkdownCommand.cut,
                const CopySelectionTextIntent.cut(
                  SelectionChangedCause.keyboard,
                ),
              ),
            ),
            PlatformMenuItem(
              label: appText(context, "Copy"),
              onSelected: () => _edit(
                IanvsMarkdownCommand.copy,
                CopySelectionTextIntent.copy,
              ),
            ),
            PlatformMenuItem(
              label: appText(context, "Paste"),
              onSelected: () => _edit(
                IanvsMarkdownCommand.paste,
                const PasteTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: appText(context, "Paste as Plain Text"),
              onSelected: () => _edit(
                IanvsMarkdownCommand.pastePlainText,
                const PasteTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: appText(context, "Select All"),
              onSelected: () => _edit(
                IanvsMarkdownCommand.selectAll,
                const SelectAllTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenu(
              label: appText(context, "Find"),
              menus: [
                PlatformMenuItem(
                  label: appText(context, "Find…"),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyF,
                    meta: true,
                  ),
                  onSelected: onFind,
                ),
                PlatformMenuItem(
                  label: appText(context, "Find Next"),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyG,
                    meta: true,
                  ),
                  onSelected: onFindNext,
                ),
                PlatformMenuItem(
                  label: appText(context, "Find Previous"),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyG,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: onFindPrevious,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: appText(context, "View"),
          menus: [
            PlatformMenuItem(
              label: appText(context, "Back to Previous Position"),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.bracketLeft,
                meta: true,
              ),
              onSelected: () => navigateBack(workspace),
            ),
            PlatformMenuItem(
              label: workspace.sidebarVisible
                  ? appText(context, "Hide Sidebar")
                  : appText(context, "Show Sidebar"),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                control: true,
              ),
              onSelected: workspace.toggleSidebar,
            ),
            PlatformMenuItem(
              label: workspace.outlineVisible
                  ? appText(context, "Hide Outline")
                  : appText(context, "Show Outline"),
              onSelected: workspace.toggleOutline,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: appText(context, "Live Preview"),
                  onSelected: () => setEditorMode(
                    workspace,
                    IanvsMarkdownEditorMode.livePreview,
                  ),
                ),
                PlatformMenuItem(
                  label: appText(context, "Source"),
                  onSelected: () =>
                      setEditorMode(workspace, IanvsMarkdownEditorMode.source),
                ),
                PlatformMenuItem(
                  label: appText(context, "Read"),
                  onSelected: () =>
                      setEditorMode(workspace, IanvsMarkdownEditorMode.preview),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: appText(context, "Larger Reading Text"),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.equal,
                    meta: true,
                  ),
                  onSelected: () =>
                      changeReadingTextSize(workspace, delta: 0.5),
                ),
                PlatformMenuItem(
                  label: appText(context, "Smaller Reading Text"),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.minus,
                    meta: true,
                  ),
                  onSelected: () =>
                      changeReadingTextSize(workspace, delta: -0.5),
                ),
                PlatformMenuItem(
                  label: appText(context, "Actual Reading Text Size"),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit0,
                    meta: true,
                  ),
                  onSelected: () => changeReadingTextSize(workspace),
                ),
              ],
            ),
            PlatformMenuItem(
              label: appText(context, "Toggle Appearance"),
              onSelected: onToggleTheme,
            ),
            if (onUseSystemTheme != null)
              PlatformMenuItem(
                label: appText(context, "Use System Appearance"),
                onSelected: onUseSystemTheme,
              ),
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen,
            ),
          ],
        ),
        PlatformMenu(
          label: appText(context, "Window"),
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
