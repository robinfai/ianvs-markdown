import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../controllers/workspace_controller.dart';
import '../models/document_session.dart';
import 'floating_outline.dart';
import 'desktop_menu_bar.dart';
import '../app_icons.dart';
import '../tab_shortcuts.dart';
import 'title_tabs_bar.dart';
import 'workspace_sidebar.dart';

class EditorShell extends StatefulWidget {
  const EditorShell({
    super.key,
    required this.workspace,
    required this.dark,
    required this.onToggleTheme,
    this.enableFileDrop = true,
  });

  final WorkspaceController workspace;
  final bool dark;
  final VoidCallback onToggleTheme;
  final bool enableFileDrop;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  var _draggingFiles = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.workspace,
      builder: (context, _) {
        final workspace = widget.workspace;
        final document = workspace.activeDocument;
        if (!workspace.initialized || document == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return DesktopMenuBar(
          workspace: workspace,
          onOpen: () => _guard(workspace.chooseAndOpenFiles),
          onOpenFolder: () => _guard(workspace.chooseWorkspaceFolder),
          onSave: () => _guard(workspace.saveActive),
          onSaveAs: () => _guard(() => workspace.saveActive(saveAs: true)),
          onClose: () => _guard(() => _closeDocument(document)),
          onToggleTheme: widget.onToggleTheme,
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                  workspace.newDocument,
              const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  workspace.newDocument,
              const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () =>
                  _guard(workspace.chooseAndOpenFiles),
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () =>
                  _guard(workspace.chooseAndOpenFiles),
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
                shift: true,
              ): () =>
                  _guard(workspace.chooseWorkspaceFolder),
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
                shift: true,
              ): () =>
                  _guard(workspace.chooseWorkspaceFolder),
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
                  _guard(workspace.saveActive),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () =>
                  _guard(workspace.saveActive),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                shift: true,
              ): () =>
                  _guard(() => workspace.saveActive(saveAs: true)),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
                shift: true,
              ): () =>
                  _guard(() => workspace.saveActive(saveAs: true)),
              const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
                  _closeDocument(document),
              const SingleActivator(
                LogicalKeyboardKey.keyW,
                control: true,
              ): () =>
                  _closeDocument(document),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                control: true,
              ): workspace.toggleSidebar,
              const SingleActivator(LogicalKeyboardKey.keyB, control: true):
                  workspace.toggleSidebar,
              for (var i = 0; i < tabDigitKeys.length; i++)
                SingleActivator(tabDigitKeys[i], meta: true): () =>
                    workspace.selectDocument(i),
            },
            child: Scaffold(
              body: Row(
                children: [
                  if (workspace.sidebarVisible)
                    WorkspaceSidebar(
                      key: ValueKey(workspace.workspaceRoot),
                      workspace: workspace,
                      onError: _showError,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        TitleTabsBar(
                          workspace: workspace,
                          onClose: _closeDocument,
                        ),
                        if (document.hasExternalChanges)
                          _ExternalChangeBanner(
                            document: document,
                            onReload: () => _guard(
                              () => workspace.reloadFromDisk(document),
                            ),
                            onKeepLocal: () =>
                                workspace.keepLocalVersion(document),
                          ),
                        Expanded(
                          child: DropTarget(
                            enable: widget.enableFileDrop,
                            onDragEntered: (_) =>
                                setState(() => _draggingFiles = true),
                            onDragExited: (_) =>
                                setState(() => _draggingFiles = false),
                            onDragDone: (details) {
                              setState(() => _draggingFiles = false);
                              _guard(
                                () => workspace.openPaths(
                                  details.files.map((file) => file.path),
                                ),
                              );
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final inset =
                                              constraints.maxWidth < 500
                                              ? 24.0
                                              : 48.0;
                                          return IanvsMarkdownLiveEditor(
                                            key: ValueKey(document.id),
                                            controller: document.controller,
                                            scrollController:
                                                document.scrollController,
                                            showToolbar: false,
                                            enableModeShortcuts: false,
                                            showNavigationPane: false,
                                            showOutlineInPreview: false,
                                            showFrontMatter: false,
                                            contentMaxWidth: 720,
                                            padding: EdgeInsets.fromLTRB(
                                              inset,
                                              32,
                                              inset,
                                              56,
                                            ),
                                            onSaveRequested: (_) async {
                                              final saved = await workspace
                                                  .saveDocument(document);
                                              if (!saved) {
                                                throw const IanvsMarkdownSaveCancelledException();
                                              }
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                    if (workspace.outlineVisible)
                                      FloatingOutline(document: document),
                                  ],
                                ),
                                if (_draggingFiles) const _DropOverlay(),
                              ],
                            ),
                          ),
                        ),
                        _DocumentStatusBar(document: document),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _guard(Future<dynamic> Function() action) {
    unawaited(
      action().catchError((Object error, StackTrace stackTrace) {
        _showError(error.toString());
      }),
    );
  }

  Future<void> _closeDocument(DocumentSession document) async {
    if (document.controller.isDirty) {
      final choice = await showDialog<_CloseChoice>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 420),
          title: Text('Save changes to “${document.name}”?'),
          content: const Text(
            'Unsaved changes will be lost if you discard them.',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, _CloseChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _CloseChoice.discard),
              child: const Text('Don’t Save'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, _CloseChoice.save),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == _CloseChoice.cancel) return;
      if (choice == _CloseChoice.save &&
          !await widget.workspace.saveDocument(document)) {
        return;
      }
    }
    widget.workspace.removeDocument(document);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
  }
}

enum _CloseChoice { save, discard, cancel }

class _ExternalChangeBanner extends StatelessWidget {
  const _ExternalChangeBanner({
    required this.document,
    required this.onReload,
    required this.onKeepLocal,
  });

  final DocumentSession document;
  final VoidCallback onReload;
  final VoidCallback onKeepLocal;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return Material(
      color: colors.surfaceMuted,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSoft)),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(AppIcons.info, size: 16, color: colors.accent),
            Text(
              '${document.name} changed on disk.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            OutlinedButton(
              onPressed: onKeepLocal,
              child: const Text('Keep My Changes'),
            ),
            FilledButton(onPressed: onReload, child: const Text('Reload')),
          ],
        ),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('markdown-drop-overlay'),
      color: scheme.surface.withValues(alpha: .94),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.primary, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.document, size: 42),
              SizedBox(height: 12),
              Text(
                'Open Markdown Files',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                'Drop files here to open them in tabs.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentStatusBar extends StatelessWidget {
  const _DocumentStatusBar({required this.document});
  final DocumentSession document;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: document.controller,
      builder: (context, value, _) {
        final words = RegExp(r'\S+').allMatches(value.text).length;
        return Container(
          height: 25,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderSoft)),
          ),
          child: DefaultTextStyle(
            style: TextStyle(color: colors.textTertiary, fontSize: 11),
            child: Row(
              children: [
                Text('$words words'),
                const SizedBox(width: 14),
                Text('${value.text.runes.length} characters'),
                const Spacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: document.controller.dirtyListenable,
                  builder: (context, dirty, _) =>
                      Text(dirty ? 'Edited' : 'Saved'),
                ),
                const SizedBox(width: 12),
                Text(document.encoding),
                const SizedBox(width: 12),
                Text(document.lineEnding),
              ],
            ),
          ),
        );
      },
    );
  }
}
