import '../localization.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'editor_controller.dart';
import 'editor_models.dart';

typedef IanvsMarkdownSaveCallback = FutureOr<void> Function(String markdown);

/// Signals that a host-owned save flow was dismissed without writing.
///
/// Throw this from [IanvsMarkdownSaveCallback] when, for example, the user
/// cancels a Save As dialog. The editor keeps the document dirty and does not
/// report the cancellation as an error.
class IanvsMarkdownSaveCancelledException implements Exception {
  const IanvsMarkdownSaveCancelledException();
}

class IanvsMarkdownEditorToolbar extends StatelessWidget {
  const IanvsMarkdownEditorToolbar({
    super.key,
    required this.controller,
    this.onSaveRequested,
    this.focusNode,
    this.showModeSwitcher = true,
    this.theme,
  });

  final IanvsMarkdownController controller;
  final IanvsMarkdownSaveCallback? onSaveRequested;

  /// Host-owned editing focus, restored after formatting/history actions.
  final FocusNode? focusNode;
  final bool showModeSwitcher;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    return Material(
      key: const ValueKey('ianvs-markdown-editor-toolbar'),
      color: colors.surfaceRaised,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSoft)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ValueListenableBuilder<IanvsMarkdownEditorMode>(
            valueListenable: controller.modeListenable,
            builder: (context, mode, _) {
              final editable = mode != IanvsMarkdownEditorMode.preview;
              return Row(
                children: [
                  if (showModeSwitcher) ...[
                    _ModeButton(
                      tooltip: IanvsMarkdownMessage.livePreview.resolve(
                        context,
                      ),
                      icon: Icons.vertical_split_outlined,
                      selected: mode == IanvsMarkdownEditorMode.livePreview,
                      colors: colors,
                      onPressed: () =>
                          controller.mode = IanvsMarkdownEditorMode.livePreview,
                    ),
                    _ModeButton(
                      tooltip: IanvsMarkdownMessage.sourceMode.resolve(context),
                      icon: Icons.code_rounded,
                      selected: mode == IanvsMarkdownEditorMode.source,
                      colors: colors,
                      onPressed: () =>
                          controller.mode = IanvsMarkdownEditorMode.source,
                    ),
                    _ModeButton(
                      tooltip: IanvsMarkdownMessage.readingMode.resolve(
                        context,
                      ),
                      icon: Icons.menu_book_outlined,
                      selected: mode == IanvsMarkdownEditorMode.preview,
                      colors: colors,
                      onPressed: () =>
                          controller.mode = IanvsMarkdownEditorMode.preview,
                    ),
                    _ToolbarDivider(colors: colors),
                  ],
                  ValueListenableBuilder<IanvsMarkdownHistoryValue>(
                    valueListenable: controller.historyListenable,
                    builder: (context, history, _) {
                      return Row(
                        children: [
                          _ToolbarButton(
                            focusNode: focusNode,
                            tooltip: IanvsMarkdownMessage.undo.resolve(context),
                            icon: Icons.undo_rounded,
                            enabled: history.canUndo,
                            colors: colors,
                            onPressed: controller.undo,
                          ),
                          _ToolbarButton(
                            focusNode: focusNode,
                            tooltip: IanvsMarkdownMessage.redo.resolve(context),
                            icon: Icons.redo_rounded,
                            enabled: history.canRedo,
                            colors: colors,
                            onPressed: controller.redo,
                          ),
                        ],
                      );
                    },
                  ),
                  _ToolbarDivider(colors: colors),
                  _ToolbarButton(
                    focusNode: focusNode,
                    tooltip: IanvsMarkdownMessage.bold.resolve(context),
                    icon: Icons.format_bold_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleInline('**'),
                  ),
                  _ToolbarButton(
                    focusNode: focusNode,
                    tooltip: IanvsMarkdownMessage.italic.resolve(context),
                    icon: Icons.format_italic_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleInline('*'),
                  ),
                  _ToolbarButton(
                    focusNode: focusNode,
                    tooltip: IanvsMarkdownMessage.inlineCode.resolve(context),
                    icon: Icons.data_object_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleInline('`'),
                  ),
                  _ToolbarButton(
                    focusNode: focusNode,
                    tooltip: IanvsMarkdownMessage.link.resolve(context),
                    icon: Icons.link_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: controller.insertLink,
                  ),
                  _ToolbarButton(
                    focusNode: focusNode,
                    tooltip: IanvsMarkdownMessage.heading.resolve(context),
                    icon: Icons.title_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleLinePrefix('## '),
                  ),
                  _ToolbarButton(
                    focusNode: focusNode,
                    tooltip: IanvsMarkdownMessage.bulletList.resolve(context),
                    icon: Icons.format_list_bulleted_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleLinePrefix('- '),
                  ),
                  _ToolbarButton(
                    focusNode: focusNode,
                    tooltip: IanvsMarkdownMessage.taskList.resolve(context),
                    icon: Icons.check_box_outlined,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleLinePrefix('- [ ] '),
                  ),
                  _ToolbarButton(
                    focusNode: focusNode,
                    tooltip: IanvsMarkdownMessage.codeBlock.resolve(context),
                    icon: Icons.terminal_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: controller.insertCodeFence,
                  ),
                  if (onSaveRequested != null) ...[
                    _ToolbarDivider(colors: colors),
                    ValueListenableBuilder<bool>(
                      valueListenable: controller.dirtyListenable,
                      builder: (context, dirty, _) => _ToolbarButton(
                        focusNode: focusNode,
                        tooltip: dirty
                            ? IanvsMarkdownMessage.save.resolve(context)
                            : IanvsMarkdownMessage.saved.resolve(context),
                        icon: dirty
                            ? Icons.save_outlined
                            : Icons.cloud_done_outlined,
                        enabled: dirty,
                        colors: colors,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final callback = onSaveRequested;
    if (callback == null) return;
    final savedText = controller.text;
    controller.commitHistoryGroup();
    try {
      await callback(savedText);
    } on IanvsMarkdownSaveCancelledException {
      return;
    }
    controller.markSaved(savedText: savedText);
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        color: selected ? colors.accentDark : colors.textSecondary,
        style: IconButton.styleFrom(
          backgroundColor: selected ? colors.accentSoft : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.colors,
    required this.onPressed,
    this.focusNode,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final FocusNode? focusNode;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled
          ? () {
              onPressed();
              focusNode?.requestFocus();
            }
          : null,
      icon: Icon(icon, size: 17),
      color: colors.textSecondary,
      disabledColor: colors.textTertiary.withValues(alpha: .42),
      style: IconButton.styleFrom(
        overlayColor: colors.surfaceHover,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider({required this.colors});

  final IanvsMarkdownThemeData colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: colors.borderSoft,
    );
  }
}
