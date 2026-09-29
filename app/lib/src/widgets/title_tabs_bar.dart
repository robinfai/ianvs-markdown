import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ianvs_design/ianvs_design.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../controllers/workspace_controller.dart';
import '../models/document_session.dart';
import '../desktop_theme.dart';
import '../desktop_typography.dart';
import '../app_icons.dart';
import 'file_context_menu.dart';

class TitleTabsBar extends StatelessWidget {
  const TitleTabsBar({
    super.key,
    required this.workspace,
    required this.onClose,
  });

  final WorkspaceController workspace;
  final FutureOr<void> Function(DocumentSession) onClose;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return Material(
      color: colors.surfaceMuted,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: Platform.isMacOS && !workspace.sidebarVisible ? 70 : 0,
            ),
            child: IanvsToolbar(
              height: DesktopMetrics.toolbarHeight,
              leading: _HeaderIconButton(
                tooltip: workspace.sidebarVisible
                    ? 'Hide sidebar'
                    : 'Show sidebar',
                icon: AppIcons.sidebar,
                selected: workspace.sidebarVisible,
                onPressed: workspace.toggleSidebar,
              ),
              title: Center(child: _EditorModePicker(workspace: workspace)),
              actions: [
                _HeaderIconButton(
                  tooltip: workspace.outlineVisible
                      ? 'Hide outline'
                      : 'Show outline',
                  icon: AppIcons.outline,
                  selected: workspace.outlineVisible,
                  onPressed: workspace.toggleOutline,
                ),
              ],
            ),
          ),
          SizedBox(
            height: math.max(
              DesktopMetrics.tabsHeight,
              MediaQuery.textScalerOf(context).scale(15) + 12,
            ),
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
                                style: DesktopTypography.subheadline.copyWith(
                                  color: colors.textTertiary,
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

final _tabTextStyle = DesktopTypography.callout;

double _tabWidth(BuildContext context, DocumentSession document) {
  final painter = TextPainter(
    text: TextSpan(
      text: document.name,
      style: DefaultTextStyle.of(context).style.merge(_tabTextStyle),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final width = (painter.width.ceilToDouble() + 42).clamp(92.0, 220.0);
  painter.dispose();
  return width;
}

class _DocumentTabs extends StatefulWidget {
  const _DocumentTabs({required this.workspace, required this.onClose});
  final WorkspaceController workspace;
  final FutureOr<void> Function(DocumentSession) onClose;

  @override
  State<_DocumentTabs> createState() => _DocumentTabsState();
}

class _DocumentTabsState extends State<_DocumentTabs> {
  final _scrollController = ScrollController();
  double? _viewportWidth;

  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
          .fold(0.0, (sum, document) => sum + _tabWidth(context, document));
      final end = start + _tabWidth(context, workspace.activeDocument!);
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_viewportWidth != constraints.maxWidth) {
        _viewportWidth = constraints.maxWidth;
        _revealSelection();
      }
      return ReorderableListView.builder(
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
            child: FileContextMenu(
              path: document.path,
              actions: [
                FileMenuAction('Save', () async {
                  await widget.workspace.saveDocument(document);
                }),
                FileMenuAction('Save As…', () async {
                  await widget.workspace.saveDocument(document, saveAs: true);
                }),
                FileMenuAction('Close Tab', () => widget.onClose(document)),
              ],
              child: _DocumentTab(
                document: document,
                selected: index == widget.workspace.activeIndex,
                onSelected: () => widget.workspace.selectDocument(index),
                onClose: () => widget.onClose(document),
              ),
            ),
          );
        },
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
    final width = _tabWidth(context, document);
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
                    color: selected ? colors.accent : Colors.transparent,
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
                      style: _tabTextStyle.copyWith(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: document.controller.dirtyListenable,
                    builder: (context, dirty, _) =>
                        dirty && !selected && !_hovered
                        ? SizedBox(
                            width: 28,
                            height: 28,
                            child: Center(
                              child: Container(
                                key: const ValueKey('document-dirty-indicator'),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: colors.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
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
  Widget build(BuildContext context) =>
      ValueListenableBuilder<IanvsMarkdownEditorMode>(
        valueListenable: workspace.activeDocument!.controller.modeListenable,
        builder: (context, selected, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SegmentedButton<IanvsMarkdownEditorMode>(
            showSelectedIcon: false,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              ),
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            segments: const [
              ButtonSegment(
                value: IanvsMarkdownEditorMode.livePreview,
                label: Tooltip(
                  message: 'Live Preview: edit with inline formatting',
                  excludeFromSemantics: true,
                  child: Text('Live', semanticsLabel: 'Live Preview'),
                ),
              ),
              ButtonSegment(
                value: IanvsMarkdownEditorMode.source,
                label: Tooltip(
                  message: 'Source: edit Markdown source',
                  excludeFromSemantics: true,
                  child: Text('Source'),
                ),
              ),
              ButtonSegment(
                value: IanvsMarkdownEditorMode.preview,
                label: Tooltip(
                  message: 'Read: preview without editing',
                  excludeFromSemantics: true,
                  child: Text('Read'),
                ),
              ),
            ],
            selected: {selected},
            onSelectionChanged: (modes) => workspace.setMode(modes.single),
          ),
        ),
      );
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => IanvsIconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: icon,
    selected: selected,
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(32, 32)),
      iconSize: const WidgetStatePropertyAll(16),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? context.ianvs.selected
            : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? context.ianvs.onSelected
            : context.ianvs.muted,
      ),
    ),
  );
}
