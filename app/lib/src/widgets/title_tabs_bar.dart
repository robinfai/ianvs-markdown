import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../controllers/workspace_controller.dart';
import '../models/document_session.dart';
import '../desktop_theme.dart';
import '../app_icons.dart';

class TitleTabsBar extends StatelessWidget {
  const TitleTabsBar({
    super.key,
    required this.workspace,
    required this.onClose,
  });

  final WorkspaceController workspace;
  final ValueChanged<DocumentSession> onClose;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return Material(
      color: colors.surfaceMuted,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: DesktopMetrics.toolbarHeight,
            child: Padding(
              padding: EdgeInsets.only(
                left: Platform.isMacOS && !workspace.sidebarVisible ? 78 : 8,
                right: 8,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    children: [
                      _HeaderIconButton(
                        tooltip: workspace.sidebarVisible
                            ? 'Hide sidebar'
                            : 'Show sidebar',
                        icon: AppIcons.sidebar,
                        onPressed: workspace.toggleSidebar,
                      ),
                      Expanded(
                        child: Center(
                          child: _EditorModePicker(workspace: workspace),
                        ),
                      ),
                      _HeaderIconButton(
                        tooltip: workspace.outlineVisible
                            ? 'Hide outline'
                            : 'Show outline',
                        icon: AppIcons.outline,
                        onPressed: workspace.toggleOutline,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const Divider(),
          SizedBox(
            height: DesktopMetrics.tabsHeight,
            child: Row(
              children: [
                Expanded(
                  child: _DocumentTabs(workspace: workspace, onClose: onClose),
                ),
                _HeaderIconButton(
                  key: const ValueKey('new-document-button'),
                  tooltip: 'New document (⌘N)',
                  icon: AppIcons.add,
                  onPressed: workspace.newDocument,
                ),
                PopupMenuButton<int>(
                  tooltip: 'All open documents',
                  icon: const Icon(AppIcons.tabs, size: 16),
                  constraints: const BoxConstraints(
                    minWidth: 220,
                    maxWidth: 340,
                  ),
                  onSelected: workspace.selectDocument,
                  itemBuilder: (context) => [
                    for (var i = 0; i < workspace.documents.length; i++)
                      PopupMenuItem(
                        height: 28,
                        value: i,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              child: i == workspace.activeIndex
                                  ? const Icon(AppIcons.check, size: 14)
                                  : null,
                            ),
                            Expanded(
                              child: Text(
                                workspace.documents[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (i < 9) ...[
                              const SizedBox(width: 16),
                              Text(
                                '⌘${i + 1}',
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}

double _tabWidth(DocumentSession document) =>
    (document.name.runes.length * 7.0 + 42).clamp(92.0, 220.0);

class _DocumentTabs extends StatefulWidget {
  const _DocumentTabs({required this.workspace, required this.onClose});
  final WorkspaceController workspace;
  final ValueChanged<DocumentSession> onClose;

  @override
  State<_DocumentTabs> createState() => _DocumentTabsState();
}

class _DocumentTabsState extends State<_DocumentTabs> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  @override
  void didUpdateWidget(covariant _DocumentTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _revealSelection();
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final workspace = widget.workspace;
      if (workspace.activeDocument == null) return;
      final start = workspace.documents
          .take(workspace.activeIndex)
          .fold(0.0, (sum, document) => sum + _tabWidth(document));
      final end = start + _tabWidth(workspace.activeDocument!);
      final position = _scrollController.position;
      final offset = start < position.pixels
          ? start
          : end > position.pixels + position.viewportDimension
          ? end - position.viewportDimension
          : position.pixels;
      _scrollController.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReorderableListView.builder(
    scrollController: _scrollController,
    scrollDirection: Axis.horizontal,
    buildDefaultDragHandles: false,
    itemCount: widget.workspace.documents.length,
    onReorderItem: widget.workspace.reorderDocument,
    itemBuilder: (context, index) {
      final document = widget.workspace.documents[index];
      return ReorderableDragStartListener(
        key: ValueKey(document.id),
        index: index,
        child: _DocumentTab(
          document: document,
          selected: index == widget.workspace.activeIndex,
          onSelected: () => widget.workspace.selectDocument(index),
          onClose: () => widget.onClose(document),
        ),
      );
    },
  );
}

class _DocumentTab extends StatefulWidget {
  const _DocumentTab({
    required this.document,
    required this.selected,
    required this.onSelected,
    required this.onClose,
  });

  final DocumentSession document;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onClose;

  @override
  State<_DocumentTab> createState() => _DocumentTabState();
}

class _DocumentTabState extends State<_DocumentTab> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    final document = widget.document;
    final selected = widget.selected;
    final width = _tabWidth(document);
    return Tooltip(
      message: document.path ?? document.name,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: selected
              ? colors.surface
              : _hovered
              ? colors.surfaceHover
              : Colors.transparent,
          child: InkWell(
            onTap: widget.onSelected,
            child: Container(
              width: width,
              padding: const EdgeInsets.only(left: 9, right: 3),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? colors.textTertiary : Colors.transparent,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      document.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: document.controller.dirtyListenable,
                    builder: (context, dirty, _) =>
                        dirty && !selected && !_hovered
                        ? Container(
                            key: const ValueKey('document-dirty-indicator'),
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 7),
                            decoration: BoxDecoration(
                              color: colors.accent,
                              shape: BoxShape.circle,
                            ),
                          )
                        : IconButton(
                            tooltip: 'Close ${document.name}',
                            onPressed: widget.onClose,
                            icon: const Icon(AppIcons.close, size: 12),
                            color: colors.textTertiary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 28,
                              height: 28,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorModePicker extends StatelessWidget {
  const _EditorModePicker({required this.workspace});
  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return ValueListenableBuilder<IanvsMarkdownEditorMode>(
      valueListenable: workspace.activeDocument!.controller.modeListenable,
      builder: (context, selected, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceHover,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in IanvsMarkdownEditorMode.values)
                  Semantics(
                    selected: selected == mode,
                    child: Tooltip(
                      message: switch (mode) {
                        IanvsMarkdownEditorMode.livePreview => 'Live Preview',
                        IanvsMarkdownEditorMode.source => 'Source',
                        IanvsMarkdownEditorMode.preview => 'Read',
                      },
                      child: Material(
                        color: selected == mode
                            ? colors.surfaceRaised
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => workspace.setMode(mode),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Text(
                              switch (mode) {
                                IanvsMarkdownEditorMode.livePreview => 'Live',
                                IanvsMarkdownEditorMode.source => 'Source',
                                IanvsMarkdownEditorMode.preview => 'Read',
                              },
                              style: TextStyle(
                                fontSize: 11,
                                color: selected == mode
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      color: colors.textSecondary,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
    );
  }
}
