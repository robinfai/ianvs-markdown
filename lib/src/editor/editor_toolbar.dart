import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'editor_controller.dart';
import 'editor_models.dart';

typedef IanvsMarkdownSaveCallback = FutureOr<void> Function(String markdown);

class IanvsMarkdownEditorToolbar extends StatelessWidget {
  const IanvsMarkdownEditorToolbar({
    super.key,
    required this.controller,
    this.onSaveRequested,
    this.showModeSwitcher = true,
    this.theme,
  });

  final IanvsMarkdownController controller;
  final IanvsMarkdownSaveCallback? onSaveRequested;
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
                      tooltip: '实时预览',
                      icon: Icons.vertical_split_outlined,
                      selected: mode == IanvsMarkdownEditorMode.livePreview,
                      colors: colors,
                      onPressed: () =>
                          controller.mode = IanvsMarkdownEditorMode.livePreview,
                    ),
                    _ModeButton(
                      tooltip: '源码模式',
                      icon: Icons.code_rounded,
                      selected: mode == IanvsMarkdownEditorMode.source,
                      colors: colors,
                      onPressed: () =>
                          controller.mode = IanvsMarkdownEditorMode.source,
                    ),
                    _ModeButton(
                      tooltip: '阅读模式',
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
                            tooltip: '撤销',
                            icon: Icons.undo_rounded,
                            enabled: history.canUndo,
                            colors: colors,
                            onPressed: controller.undo,
                          ),
                          _ToolbarButton(
                            tooltip: '重做',
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
                    tooltip: '粗体',
                    icon: Icons.format_bold_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleInline('**'),
                  ),
                  _ToolbarButton(
                    tooltip: '斜体',
                    icon: Icons.format_italic_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleInline('*'),
                  ),
                  _ToolbarButton(
                    tooltip: '行内代码',
                    icon: Icons.data_object_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleInline('`'),
                  ),
                  _ToolbarButton(
                    tooltip: '链接',
                    icon: Icons.link_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: controller.insertLink,
                  ),
                  _ToolbarButton(
                    tooltip: '标题',
                    icon: Icons.title_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleLinePrefix('## '),
                  ),
                  _ToolbarButton(
                    tooltip: '项目列表',
                    icon: Icons.format_list_bulleted_rounded,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleLinePrefix('- '),
                  ),
                  _ToolbarButton(
                    tooltip: '任务列表',
                    icon: Icons.check_box_outlined,
                    enabled: editable,
                    colors: colors,
                    onPressed: () => controller.toggleLinePrefix('- [ ] '),
                  ),
                  _ToolbarButton(
                    tooltip: '代码块',
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
                        tooltip: dirty ? '保存' : '已保存',
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
    await callback(controller.text);
    controller.markSaved();
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
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
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
