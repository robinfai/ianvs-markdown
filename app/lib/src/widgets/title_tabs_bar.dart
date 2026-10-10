import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:ianvs_design/ianvs_design.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import '../controllers/workspace_controller.dart';
import '../models/document_session.dart';
import '../desktop_theme.dart';
import '../desktop_typography.dart';
import '../app_icons.dart';
import 'file_context_menu.dart';
import 'middle_ellipsis_text.dart';
import 'window_app_title.dart';

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
          SizedBox(
            key: const ValueKey('document-tabs-row'),
            height: math.max(
              DesktopMetrics.tabsHeight,
              MediaQuery.textScalerOf(context).scale(15) + 12,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: workspace.sidebarVisible ? 12 : 0,
                right: 12,
              ),
              child: Row(
                children: [
                  if (!workspace.sidebarVisible)
                    SizedBox(
                      width: Platform.isMacOS ? 168 : 100,
                      child: const Align(
                        alignment: Alignment.topLeft,
                        child: WindowAppTitle(),
                      ),
                    ),
                  _HeaderIconButton(
                    tooltip: workspace.sidebarVisible
                        ? 'Hide sidebar'
                        : 'Show sidebar',
                    icon: AppIcons.sidebar,
                    selected: workspace.sidebarVisible,
                    onPressed: workspace.toggleSidebar,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DocumentTabs(
                      workspace: workspace,
                      onClose: onClose,
                    ),
                  ),
                  _OpenDocumentsMenu(workspace: workspace),
                  _HeaderIconButton(
                    key: const ValueKey('new-document-button'),
                    tooltip: 'New document (⌘N)',
                    icon: AppIcons.add,
                    onPressed: workspace.newDocument,
                  ),
                  const SizedBox(width: 8),
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
          ),
          Container(
            key: const ValueKey('document-context-row'),
            height: math.max(
              DesktopMetrics.documentContextHeight,
              MediaQuery.textScalerOf(context).scale(16) + 12,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.borderSoft),
                bottom: BorderSide(color: colors.borderSoft),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: _DocumentLocation(workspace: workspace)),
                const SizedBox(width: 16),
                _EditorModePicker(workspace: workspace),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenDocumentsMenu extends StatefulWidget {
  const _OpenDocumentsMenu({required this.workspace});

  final WorkspaceController workspace;

  @override
  State<_OpenDocumentsMenu> createState() => _OpenDocumentsMenuState();
}

class _OpenDocumentsMenuState extends State<_OpenDocumentsMenu> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    return MenuAnchor(
      childFocusNode: _focus,
      consumeOutsideTap: true,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        minimumSize: const WidgetStatePropertyAll(Size(220, 0)),
        maximumSize: WidgetStatePropertyAll(
          Size(340, MediaQuery.sizeOf(context).height - 64),
        ),
      ),
      menuChildren: [
        for (var i = 0; i < workspace.documents.length; i++)
          MenuItemButton(
            key: ValueKey('document-menu-${workspace.documents[i].id}'),
            onPressed: () => workspace.selectDocument(i),
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 28)),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
            ),
            leadingIcon: SizedBox(
              width: 16,
              child: i == workspace.activeIndex
                  ? const Icon(AppIcons.check, size: 14)
                  : null,
            ),
            trailingIcon: i < 9
                ? Text(
                    '⌘${i + 1}',
                    style: DesktopTypography.subheadline.copyWith(
                      color: context.ianvs.subtle,
                    ),
                  )
                : null,
            child: Text(
              workspace.documents[i].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: 'All open documents',
        focusNode: _focus,
        icon: const Icon(AppIcons.tabs, size: 16),
        color: context.ianvs.muted,
        padding: const EdgeInsets.all(6),
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(32, 32)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _DocumentLocation extends StatelessWidget {
  const _DocumentLocation({required this.workspace});

  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) {
    final document = workspace.activeDocument!;
    final root = workspace.workspaceRoot;
    final path = document.path;
    final location = path == null
        ? 'Unsaved / ${document.name}'
        : root != null && p.isWithin(root, path)
        ? '${p.basename(root)} / ${p.relative(path, from: root)}'
        : '${p.basename(p.dirname(path))} / ${document.name}';
    final colors = IanvsMarkdownThemeData.resolve(context);
    return Tooltip(
      message: path ?? 'Unsaved document',
      child: Row(
        children: [
          Icon(AppIcons.document, size: 14, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: MiddleEllipsisText(
              location,
              key: const ValueKey('document-location'),
              style: DesktopTypography.callout.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
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
      style: DefaultTextStyle.of(
        context,
      ).style.merge(_tabTextStyle.copyWith(fontWeight: FontWeight.w600)),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final width = (painter.width.ceilToDouble() + 48).clamp(92.0, 220.0);
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
  bool _reordering = false;

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
      if (!mounted || !_scrollController.hasClients || _reordering) return;
      final workspace = widget.workspace;
      if (workspace.activeDocument == null) return;
      final widths = workspace.documents
          .map((document) => _tabWidth(context, document))
          .toList();
      final start = widths
          .take(workspace.activeIndex)
          .fold(0.0, (sum, width) => sum + width);
      final end = start + widths[workspace.activeIndex];
      final position = _scrollController.position;
      final offset = start < position.pixels
          ? start
          : end > position.pixels + position.viewportDimension
          ? end - position.viewportDimension
          : position.pixels;
      // Lazy lists estimate their scroll extent from the visible children.
      // Use the measured total so distant, wider tabs can be revealed fully.
      final maxOffset = math.max(
        0.0,
        widths.fold(0.0, (sum, width) => sum + width) -
            position.viewportDimension,
      );
      _scrollController.jumpTo(offset.clamp(0.0, maxOffset));
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
      return TooltipVisibility(
        visible: !_reordering,
        child: ReorderableListView.builder(
          scrollController: _scrollController,
          scrollDirection: Axis.horizontal,
          buildDefaultDragHandles: false,
          itemCount: widget.workspace.documents.length,
          onReorderStart: (_) {
            Tooltip.dismissAllToolTips();
            setState(() => _reordering = true);
          },
          onReorderEnd: (_) {
            setState(() => _reordering = false);
            _revealSelection();
          },
          // Keep drag visuals separate from the live tab's tooltips and
          // accessibility nodes.
          proxyDecorator: (_, index, animation) {
            final document = widget.workspace.documents[index];
            return ExcludeSemantics(
              child: IgnorePointer(
                child: TooltipVisibility(
                  visible: false,
                  child: Material(
                    elevation: 2,
                    child: _DocumentTab(
                      document: document,
                      selected: index == widget.workspace.activeIndex,
                      onSelected: () {},
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            );
          },
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
  var _focused = false;

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
            onFocusChange: (focused) => setState(() => _focused = focused),
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
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: document.controller.dirtyListenable,
                    builder: (context, dirty, _) =>
                        dirty && !selected && !_hovered && !_focused
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
                        : Visibility(
                            visible: selected || _hovered || _focused,
                            maintainSize: true,
                            maintainState: true,
                            maintainAnimation: true,
                            maintainSemantics: true,
                            child: IconButton(
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

extension on IanvsMarkdownEditorMode {
  String get label => switch (this) {
    IanvsMarkdownEditorMode.livePreview => 'Live',
    IanvsMarkdownEditorMode.source => 'Source',
    IanvsMarkdownEditorMode.preview => 'Read',
  };

  String get accessibleLabel =>
      this == IanvsMarkdownEditorMode.livePreview ? 'Live Preview' : label;

  IconData get icon => switch (this) {
    IanvsMarkdownEditorMode.livePreview => AppIcons.liveMode,
    IanvsMarkdownEditorMode.source => AppIcons.sourceMode,
    IanvsMarkdownEditorMode.preview => AppIcons.readMode,
  };
}

class _EditorModePicker extends StatefulWidget {
  const _EditorModePicker({required this.workspace});
  final WorkspaceController workspace;

  @override
  State<_EditorModePicker> createState() => _EditorModePickerState();
}

class _EditorModePickerState extends State<_EditorModePicker> {
  final _focus = FocusNode();
  final _menu = MenuController();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<IanvsMarkdownEditorMode>(
    valueListenable: widget.workspace.activeDocument!.controller.modeListenable,
    builder: (context, selected, _) => MenuAnchor(
      controller: _menu,
      childFocusNode: _focus,
      consumeOutsideTap: true,
      alignmentOffset: const Offset(0, 4),
      style: const MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        minimumSize: WidgetStatePropertyAll(Size(168, 0)),
      ),
      menuChildren: [
        for (final mode in IanvsMarkdownEditorMode.values)
          MenuItemButton(
            key: ValueKey('editor-mode-${mode.name}'),
            autofocus: mode == selected,
            leadingIcon: Icon(mode.icon, size: 16),
            trailingIcon: SizedBox(
              width: 16,
              child: mode == selected
                  ? const Icon(AppIcons.check, size: 14)
                  : null,
            ),
            onPressed: () => widget.workspace.setMode(mode),
            child: Semantics(
              selected: mode == selected,
              child: Text(mode.label, semanticsLabel: mode.accessibleLabel),
            ),
          ),
      ],
      builder: (context, controller, child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): controller.open,
        },
        child: Tooltip(
          message: 'Editor mode',
          excludeFromSemantics: true,
          child: SizedBox(
            height: math.max(
              32,
              MediaQuery.textScalerOf(context).scale(16) + 8,
            ),
            child: TextButton(
              key: const ValueKey('editor-mode-button'),
              focusNode: _focus,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(104, 32)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10),
                ),
                alignment: Alignment.center,
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStatePropertyAll(DesktopTypography.callout),
                foregroundColor: WidgetStatePropertyAll(context.ianvs.muted),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(selected.icon, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    selected.label,
                    semanticsLabel: 'Editor mode: ${selected.accessibleLabel}',
                  ),
                  const SizedBox(width: 8),
                  const Icon(AppIcons.tabs, size: 14),
                ],
              ),
            ),
          ),
        ),
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
