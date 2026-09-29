import 'dart:async';
import 'dart:math' as math;

import 'package:ianvs_design/ianvs_design.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app_icons.dart';
import '../controllers/file_browser_controller.dart';
import '../controllers/workspace_controller.dart';
import '../desktop_theme.dart';
import '../desktop_typography.dart';
import '../services/markdown_file_service.dart';
import 'file_context_menu.dart';
import 'middle_ellipsis_text.dart';

const _background = Color(0xff17191a);
final _secondary = IanvsTokens.dark.muted;
final _accent = IanvsTokens.dark.focus;
final _selection = IanvsTokens.dark.selected;

class WorkspaceSidebar extends StatefulWidget {
  const WorkspaceSidebar({
    super.key,
    required this.workspace,
    required this.onError,
    this.width,
  });
  final WorkspaceController workspace;
  final ValueChanged<String> onError;
  final double? width;
  @override
  State<WorkspaceSidebar> createState() => _WorkspaceSidebarState();
}

class _WorkspaceSidebarState extends State<WorkspaceSidebar> {
  FileBrowserController get browser => widget.workspace.browser;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _treeFocus = FocusNode(debugLabel: 'Workspace files');
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  late ScrollController _scroll;
  final _searchScroll = ScrollController();
  String? _root;
  int _revealRevision = 0;
  String? _flash;
  Timer? _flashTimer;
  String? _editingPath;
  String? _creatingIn;
  bool _creatingFolder = false;
  String? _inlineError;
  bool _committing = false;
  bool _restoringScroll = false;

  @override
  void initState() {
    super.initState();
    _treeFocus.addListener(_workspaceChanged);
    _root = browser.root;
    _revealRevision = browser.revealRevision;
    _scroll = ScrollController(initialScrollOffset: browser.preferences.scroll)
      ..addListener(_saveScroll);
    browser.addListener(_changed);
    widget.workspace.addListener(_workspaceChanged);
    unawaited(_restorePosition());
  }

  @override
  void didUpdateWidget(WorkspaceSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.browser.removeListener(_changed);
      oldWidget.workspace.removeListener(_workspaceChanged);
      browser.addListener(_changed);
      widget.workspace.addListener(_workspaceChanged);
      _changed();
    }
  }

  void _workspaceChanged() {
    if (mounted) setState(() {});
  }

  void _saveScroll() {
    if (!_restoringScroll &&
        _scroll.hasClients &&
        !browser.searching &&
        browser.query.isEmpty) {
      browser.setScroll(_scroll.offset);
    }
  }

  Future<void> _restorePosition() async {
    _restoringScroll = true;
    final root = browser.root;
    final offset = browser.preferences.scroll;
    if (root != null) {
      await browser.load(root);
      await Future.wait(
        browser.preferences.expanded
            .where((path) => p.isWithin(root, path))
            .map(browser.load),
      );
    }
    if (!mounted || browser.root != root) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || browser.root != root) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      }
      _restoringScroll = false;
    });
  }

  void _changed() {
    if (!mounted) return;
    if (_root != browser.root) {
      _root = browser.root;
      _cancelEdit();
      unawaited(_restorePosition());
    }
    if (_revealRevision != browser.revealRevision) {
      _revealRevision = browser.revealRevision;
      _clearSearch();
      _flash = browser.revealedPath;
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _flash = null);
      });
      _ensureVisible(browser.revealedPath);
    }
    setState(() {});
  }

  @override
  void dispose() {
    browser.removeListener(_changed);
    widget.workspace.removeListener(_workspaceChanged);
    _flashTimer?.cancel();
    _treeFocus.removeListener(_workspaceChanged);
    _scroll.dispose();
    _searchScroll.dispose();
    _search.dispose();
    _name.dispose();
    _searchFocus.dispose();
    _treeFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // Outline rows are denser than general Ianvs lists, but still grow with text.
  double get _fileRowHeight =>
      math.max(28, MediaQuery.textScalerOf(context).scale(16) + 12);
  double get _resultRowHeight => math.max(
    48,
    MediaQuery.textScalerOf(context).scale(16) +
        MediaQuery.textScalerOf(context).scale(14) +
        12,
  );
  bool get _isSearching => browser.query.isNotEmpty;
  List<BrowserRow> get _rows {
    if (_isSearching) {
      return browser.results
          .map(
            (entry) => BrowserRow.entry(
              entry,
              0,
              external: browser.isExternal(entry.path),
            ),
          )
          .toList();
    }
    final rows = browser.rows;
    if (_creatingIn != null) {
      final index = rows.indexWhere((row) => row.entry?.path == _creatingIn);
      rows.insert(
        index < 0 ? 0 : index + 1,
        BrowserRow.entry(
          WorkspaceEntry(
            path: '__new__',
            name: '',
            isDirectory: _creatingFolder,
          ),
          index < 0 ? 0 : rows[index].depth + 1,
        ),
      );
    }
    return rows;
  }

  List<String> get _visiblePaths => _rows
      .map((row) => row.entry?.path)
      .whereType<String>()
      .where((path) => path != '__new__')
      .toList();

  void _ensureVisible(String? path) {
    if (path == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _rows.indexWhere((row) => row.entry?.path == path);
      final controller = _isSearching ? _searchScroll : _scroll;
      if (index < 0 || !controller.hasClients) return;
      final height = _isSearching ? _resultRowHeight : _fileRowHeight;
      final top = index * height;
      final bottom = top + height;
      final position = controller.position;
      var offset = position.pixels;
      if (top < offset) offset = top;
      if (bottom > offset + position.viewportDimension) {
        offset = bottom - position.viewportDimension;
      }
      controller.jumpTo(offset.clamp(0, position.maxScrollExtent));
    });
  }

  void _clearSearch() {
    if (_search.text.isNotEmpty || browser.query.isNotEmpty) {
      _search.clear();
      browser.search('');
    }
  }

  void _run(Future<void> Function() action) {
    unawaited(() async {
      try {
        await action();
      } on Object catch (error) {
        if (mounted) widget.onError(describeFileError(error));
      }
    }());
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = browser.root;
    final hasFiles = root != null || browser.externalPaths.isNotEmpty;
    return Theme(
      data: desktopTheme(Brightness.dark),
      child: Material(
        color: _background,
        child: Container(
          width: widget.width ?? widget.workspace.sidebarWidth,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0xff323536))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: DesktopMetrics.toolbarHeight),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 19, 12, 7),
                child: Text(
                  'Workspace',
                  style: TextStyle(fontSize: 11, color: _secondary),
                ),
              ),
              _dropTarget(
                root,
                FileContextMenu(
                  path: root,
                  actions: root == null ? [] : _folderActions(root),
                  child: SizedBox(
                    height: math.max(32, _fileRowHeight),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(AppIcons.folder, size: 14, color: _secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            root != null
                                ? p.basename(root)
                                : hasFiles
                                ? 'External Files'
                                : 'No folder open',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopTypography.emphasizedBody,
                          ),
                        ),
                        if ((widget.width ?? widget.workspace.sidebarWidth) >=
                            230)
                          _icon(
                            'Reveal active file',
                            Icons.my_location,
                            () => _run(_revealActive),
                          ),
                        _icon(
                          'Open folder (⌘⇧O)',
                          AppIcons.openFolder,
                          () => _run(widget.workspace.chooseWorkspaceFolder),
                          key: const ValueKey('open-workspace-button'),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Workspace actions',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 220),
                          icon: const Icon(Icons.more_horiz, size: 16),
                          onSelected: _toolbarAction,
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              height: 32,
                              value: 'new',
                              child: Text('New Markdown'),
                            ),
                            const PopupMenuItem(
                              height: 32,
                              value: 'folder',
                              child: Text('New Folder'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              height: 32,
                              value: 'reveal',
                              child: Text('Reveal Active File'),
                            ),
                            CheckedPopupMenuItem(
                              height: 32,
                              value: 'follow',
                              checked: browser.preferences.follow,
                              child: const Text('Follow Active File'),
                            ),
                            const PopupMenuItem(
                              height: 32,
                              value: 'collapse',
                              child: Text('Collapse All'),
                            ),
                            const PopupMenuItem(
                              height: 32,
                              value: 'refresh',
                              child: Text('Refresh'),
                            ),
                            const PopupMenuDivider(),
                            CheckedPopupMenuItem(
                              height: 32,
                              value: 'name',
                              checked:
                                  browser.preferences.sort == FileSort.name,
                              child: const Text('Sort by Name'),
                            ),
                            CheckedPopupMenuItem(
                              height: 32,
                              value: 'modified',
                              checked:
                                  browser.preferences.sort == FileSort.modified,
                              child: const Text('Sort by Modified Time'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasFiles)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 32),
                    child: Focus(
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.escape) {
                          _clearSearch();
                          _treeFocus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _treeFocus.requestFocus();
                          if (_visiblePaths.isNotEmpty) {
                            browser.select(_visiblePaths.first, _visiblePaths);
                          }
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: IanvsTextField(
                        key: const ValueKey('workspace-search-field'),
                        controller: _search,
                        focusNode: _searchFocus,
                        onChanged: browser.search,
                        style: DesktopTypography.body,
                        decoration: InputDecoration(
                          hintText: 'Search Files',
                          isDense: true,
                          prefixIcon: const Icon(AppIcons.search, size: 16),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  onPressed: _clearSearch,
                                  icon: const Icon(AppIcons.close, size: 12),
                                ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          filled: true,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_inlineError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Text(
                    _inlineError!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Text(
                    browser.searching
                        ? 'Searching…'
                        : browser.matchCount > 200
                        ? 'Showing 200 of ${browser.matchCount} — refine search'
                        : '${browser.matchCount} ${browser.matchCount == 1 ? 'result' : 'results'}',
                    key: const ValueKey('search-count'),
                    style: TextStyle(fontSize: 11, color: _secondary),
                  ),
                ),
              if (_isSearching && browser.errors.isNotEmpty)
                TextButton(
                  onPressed: () => _run(() => browser.refresh()),
                  child: const Text('Some folders unavailable — Retry'),
                ),
              if (!_isSearching && browser.preferences.favorites.isNotEmpty)
                _favorites(),
              if (browser.selected.length > 1)
                SizedBox(
                  height: math.max(32, _fileRowHeight),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${browser.selected.length} selected',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      _icon(
                        'Move selected',
                        Icons.drive_file_move_outline,
                        () => _run(() => _move(_topLevel(browser.selected))),
                      ),
                      _icon(
                        'Trash selected',
                        Icons.delete_outline,
                        () => _run(() => _trash(_topLevel(browser.selected))),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: !hasFiles
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Open a folder to browse Markdown files.',
                                textAlign: TextAlign.center,
                              ),
                              TextButton(
                                onPressed: () => _run(
                                  widget.workspace.chooseWorkspaceFolder,
                                ),
                                child: const Text('Open Folder'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Focus(
                        focusNode: _treeFocus,
                        onKeyEvent: _onTreeKey,
                        child: _list(),
                      ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _icon(
    String tooltip,
    IconData icon,
    VoidCallback action, {
    Key? key,
  }) => IconButton(
    key: key,
    tooltip: tooltip,
    icon: Icon(icon, size: 14, color: _secondary),
    onPressed: action,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
  );

  Widget _list() {
    final rows = _rows;
    if (_isSearching && rows.isEmpty) {
      return Center(
        child: Text(
          browser.searching ? 'Searching…' : 'No matching files',
          style: TextStyle(color: _secondary),
        ),
      );
    }
    final root = browser.root;
    final hasRootDropSpace = root != null && !_isSearching;
    final rowHeight = _isSearching ? _resultRowHeight : _fileRowHeight;
    return LayoutBuilder(
      builder: (context, constraints) => ListView.builder(
        key: ValueKey(_isSearching ? 'file-search-results' : 'file-tree'),
        controller: _isSearching ? _searchScroll : _scroll,
        padding: const EdgeInsets.only(top: 2, bottom: 12),
        itemExtentBuilder: (index, _) => index == rows.length
            ? math.max(
                40.0,
                constraints.maxHeight - rows.length * rowHeight - 14,
              )
            : rowHeight,
        itemCount: rows.length + (hasRootDropSpace ? 1 : 0),
        itemBuilder: (_, index) {
          if (index == rows.length) {
            return _dropTarget(
              root,
              const SizedBox.expand(),
              key: const ValueKey('workspace-root-drop-space'),
              showDestination: true,
              expandedTarget: true,
            );
          }
          final row = rows[index];
          if (row.entry == null) {
            return Padding(
              padding: EdgeInsets.only(
                left: 15 + math.min(row.depth * 14.0, 70),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    row.statusPath != null &&
                        browser.errors.containsKey(row.statusPath)
                    ? Tooltip(
                        message: describeFileError(
                          browser.errors[row.statusPath]!,
                        ),
                        child: InkWell(
                          onTap: () => _run(
                            () => browser.load(row.statusPath!, refresh: true),
                          ),
                          child: Text(
                            row.label!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        row.label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: _secondary),
                      ),
              ),
            );
          }
          return _row(row);
        },
      ),
    );
  }

  Widget _row(BrowserRow row) {
    final entry = row.entry!;
    if (entry.path == '__new__' || _editingPath == entry.path) {
      return _inlineName(row);
    }
    final active = widget.workspace.activeDocument?.path == entry.path;
    final selected = browser.selected.contains(entry.path);
    final focused = browser.focusedPath == entry.path;
    final dirty = widget.workspace.documents.any(
      (document) => document.path == entry.path && document.controller.isDirty,
    );
    final expanded = browser.isExpanded(entry.path, external: row.external);
    final relative = browser.root != null && !row.external
        ? p.relative(p.dirname(entry.path), from: browser.root)
        : p.dirname(entry.path);
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Semantics(
        button: true,
        selected: selected || active,
        label: entry.name,
        hint: '${entry.path}${dirty ? ', unsaved changes' : ''}',
        value: entry.isDirectory
            ? expanded
                  ? 'Expanded'
                  : 'Collapsed'
            : null,
        onTap: () => _tap(row),
        excludeSemantics: true,
        child: Tooltip(
          message: entry.path,
          child: Material(
            key: ValueKey(
              'workspace-${entry.isDirectory ? 'directory' : 'file'}-${entry.path}',
            ),
            color: active
                ? _selection
                : selected
                ? IanvsTokens.dark.raised
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
              side: BorderSide(
                color: _flash == entry.path
                    ? _accent
                    : focused && _treeFocus.hasFocus
                    ? _accent
                    : Colors.transparent,
              ),
            ),
            child: InkWell(
              onTap: () => _tap(row),
              borderRadius: BorderRadius.circular(5),
              hoverColor: const Color(0x12ffffff),
              child: Padding(
                padding: EdgeInsets.only(
                  left:
                      5 +
                      math.min(
                        row.depth * 14.0,
                        math.max(
                          0,
                          (widget.width ?? widget.workspace.sidebarWidth) - 135,
                        ),
                      ),
                  right: 7,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 15,
                      child: entry.isDirectory
                          ? Icon(
                              expanded
                                  ? Icons.keyboard_arrow_down
                                  : AppIcons.disclosure,
                              size: 12,
                              color: _secondary,
                            )
                          : null,
                    ),
                    Icon(
                      entry.isDirectory ? AppIcons.folder : AppIcons.document,
                      size: 14,
                      color: active ? Colors.white : _secondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _isSearching
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _highlight(entry.name, DesktopTypography.body),
                                _highlight(
                                  relative,
                                  DesktopTypography.subheadline.copyWith(
                                    color: _secondary,
                                  ),
                                ),
                              ],
                            )
                          : entry.isDirectory
                          ? MiddleEllipsisText(
                              entry.name,
                              style: DesktopTypography.body.copyWith(
                                color: _secondary,
                              ),
                            )
                          : Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopTypography.body.copyWith(
                                color: active ? Colors.white : _secondary,
                              ),
                            ),
                    ),
                    if (dirty)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          semanticLabel: 'Unsaved changes',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    content = FileContextMenu(
      path: entry.path,
      onShow: () {
        if (!browser.selected.contains(entry.path)) {
          browser.select(entry.path, _visiblePaths);
        }
        _treeFocus.requestFocus();
      },
      actions: _entryActions(entry, row.external),
      child: content,
    );
    if (!row.external || !entry.isDirectory) {
      content = Draggable<List<String>>(
        affinity: Axis.horizontal,
        data: _targets(entry.path),
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Transform.translate(
          offset: const Offset(12, 16),
          child: Material(
            color: _selection,
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _targets(entry.path).length > 1
                    ? '${_targets(entry.path).length} items'
                    : entry.name,
                key: const ValueKey('workspace-drag-label'),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),
        child: content,
      );
    }
    if (entry.isDirectory) return _dropTarget(entry.path, content);
    // A file is not a container: dropping on its row means its parent folder.
    return _dropTarget(p.dirname(entry.path), content, showDestination: true);
  }

  Widget _highlight(String value, TextStyle style) {
    final parts = browser.query
        .split('/')
        .where((part) => part.isNotEmpty)
        .map(RegExp.escape)
        .toList();
    final spans = <TextSpan>[];
    var offset = 0;
    if (parts.isNotEmpty) {
      for (final match in RegExp(
        parts.join('|'),
        caseSensitive: false,
      ).allMatches(value)) {
        spans.add(TextSpan(text: value.substring(offset, match.start)));
        spans.add(
          TextSpan(
            text: value.substring(match.start, match.end),
            style: TextStyle(color: _accent, fontWeight: FontWeight.w600),
          ),
        );
        offset = match.end;
      }
    }
    spans.add(TextSpan(text: value.substring(offset)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Widget _dropTarget(
    String? path,
    Widget child, {
    Key? key,
    bool showDestination = false,
    bool expandedTarget = false,
  }) {
    if (path == null) return child;
    return DragTarget<List<String>>(
      key: key,
      onWillAcceptWithDetails: (details) => details.data.every(
        (source) =>
            source != path &&
            !p.isWithin(source, path) &&
            p.dirname(source) != path,
      ),
      onAcceptWithDetails: (details) =>
          _run(() => _move(details.data, destination: path)),
      builder: (_, candidates, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? Colors.transparent
              : _accent.withValues(alpha: .16),
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            child,
            if (showDestination && candidates.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: expandedTarget
                          ? Color.alphaBlend(
                              _accent.withValues(alpha: .10),
                              _background,
                            )
                          : _selection,
                      border: Border.all(color: _accent.withValues(alpha: .6)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              AppIcons.folder,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Move to ${p.basename(path)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopTypography.body.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
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
  }

  Widget _favorites() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        onTap: browser.toggleFavorites,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Icon(
                browser.preferences.favoritesExpanded
                    ? Icons.keyboard_arrow_down
                    : AppIcons.disclosure,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                'Favorites',
                style: TextStyle(fontSize: 11, color: _secondary),
              ),
            ],
          ),
        ),
      ),
      if (browser.preferences.favoritesExpanded)
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 4 * _fileRowHeight),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final favorite in browser.preferences.favorites.entries)
                  FileContextMenu(
                    path: favorite.key,
                    actions: [
                      FileMenuAction(
                        'Remove Favorite',
                        () => widget.workspace.toggleFileFavorite(
                          WorkspaceEntry(
                            path: favorite.key,
                            name: p.basename(favorite.key),
                            isDirectory: favorite.value,
                          ),
                        ),
                      ),
                    ],
                    child: SizedBox(
                      height: _fileRowHeight,
                      child: Tooltip(
                        message: favorite.key,
                        child: InkWell(
                          onTap: () => _run(() async {
                            await widget.workspace.openFavorite(
                              favorite.key,
                              directory: favorite.value,
                            );
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                Icon(
                                  favorite.value
                                      ? AppIcons.folder
                                      : AppIcons.document,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    p.basename(favorite.key),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: DesktopTypography.body,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ],
  );

  void _tap(BrowserRow row) {
    final entry = row.entry!;
    final keyboard = HardwareKeyboard.instance;
    final toggle =
        keyboard.isMetaPressed ||
        (Theme.of(context).platform != TargetPlatform.macOS &&
            keyboard.isControlPressed);
    final range = keyboard.isShiftPressed;
    _treeFocus.requestFocus();
    browser.select(entry.path, _visiblePaths, toggle: toggle, range: range);
    if (toggle || range) return;
    if (entry.isDirectory) {
      browser.toggle(entry.path, external: row.external);
    } else {
      _run(() async {
        await widget.workspace.openPath(entry.path);
      });
    }
  }

  KeyEventResult _onTreeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_nameFocus.hasFocus) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _clearSearch();
      _cancelEdit();
      return KeyEventResult.handled;
    }
    final paths = _visiblePaths;
    if (paths.isEmpty) return KeyEventResult.ignored;
    var index = paths.indexOf(browser.focusedPath ?? '');
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      index = index < 0
          ? 0
          : (index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(
              0,
              paths.length - 1,
            );
      browser.select(
        paths[index],
        paths,
        range: HardwareKeyboard.instance.isShiftPressed,
      );
      _ensureVisible(paths[index]);
      return KeyEventResult.handled;
    }
    final path = index < 0 ? paths.first : paths[index];
    final row = _rows.firstWhere((row) => row.entry?.path == path);
    final entry = row.entry!;
    if (key == LogicalKeyboardKey.enter) {
      if (entry.isDirectory) {
        browser.toggle(path, external: row.external);
      } else {
        _run(() async {
          await widget.workspace.openPath(path);
        });
      }
    } else if (key == LogicalKeyboardKey.arrowRight && entry.isDirectory) {
      if (!browser.isExpanded(path, external: row.external)) {
        browser.toggle(path, external: row.external);
      } else if (index + 1 < paths.length &&
          p.isWithin(path, paths[index + 1])) {
        browser.select(paths[index + 1], paths);
        _ensureVisible(paths[index + 1]);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (entry.isDirectory &&
          browser.isExpanded(path, external: row.external)) {
        browser.toggle(path, external: row.external);
      } else {
        final parents = paths
            .where((parent) => p.isWithin(parent, path))
            .toList();
        if (parents.isNotEmpty) {
          browser.select(parents.last, paths);
          _ensureVisible(parents.last);
        }
      }
    } else if (key == LogicalKeyboardKey.keyA &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      browser.select(paths.first, paths);
      browser.select(paths.last, paths, range: true);
    } else if (key == LogicalKeyboardKey.f2) {
      _run(() => _rename(entry));
    } else if (key == LogicalKeyboardKey.backspace &&
        HardwareKeyboard.instance.isMetaPressed) {
      _run(() => _trash(_targets(path)));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _toolbarAction(String action) {
    switch (action) {
      case 'new':
        _run(() => _startCreate(folder: false));
      case 'folder':
        _run(() => _startCreate(folder: true));
      case 'reveal':
        _run(_revealActive);
      case 'follow':
        browser.setFollow(!browser.preferences.follow);
      case 'collapse':
        browser.collapseAll();
      case 'refresh':
        _run(() => browser.refresh());
      case 'name':
        browser.setSort(FileSort.name);
      case 'modified':
        browser.setSort(FileSort.modified);
    }
  }

  Future<void> _revealActive() async {
    final path = widget.workspace.activeDocument?.path;
    if (path != null) {
      await browser.reveal(path);
      _treeFocus.requestFocus();
    }
  }

  List<String> _targets(String path) =>
      _topLevel(browser.selected.contains(path) ? browser.selected : [path]);
  List<String> _topLevel(Iterable<String> paths) {
    // External directory rows are synthetic groups, not complete disk listings.
    // Batch commands act only on their explicitly opened descendants.
    final unique = <String>{};
    for (final path in paths) {
      if (browser.isExternal(path) && !browser.externalPaths.contains(path)) {
        unique.addAll(
          browser.externalPaths.where((file) => p.isWithin(path, file)),
        );
      } else {
        unique.add(path);
      }
    }
    return unique
        .where(
          (path) => !unique.any(
            (parent) => parent != path && p.isWithin(parent, path),
          ),
        )
        .toList();
  }

  List<FileMenuAction> _folderActions(String path) => [
    FileMenuAction(
      'New Markdown',
      () => _startCreate(folder: false, directory: path),
    ),
    FileMenuAction(
      'New Folder',
      () => _startCreate(folder: true, directory: path),
    ),
  ];
  List<FileMenuAction> _entryActions(WorkspaceEntry entry, bool external) => [
    if (entry.isDirectory) ...[
      FileMenuAction(
        browser.isExpanded(entry.path, external: external)
            ? 'Collapse Folder'
            : 'Expand Folder',
        () => browser.toggle(entry.path, external: external),
      ),
      ..._folderActions(entry.path),
    ] else
      FileMenuAction('Open', () async {
        await widget.workspace.openPath(entry.path);
      }),
    if (_isSearching)
      FileMenuAction('Show in File Tree', () => browser.reveal(entry.path)),
    FileMenuAction(
      browser.preferences.favorites.containsKey(entry.path)
          ? 'Remove Favorite'
          : 'Add Favorite',
      () async {
        if (entry.isDirectory &&
            external &&
            !browser.preferences.favorites.containsKey(entry.path) &&
            !await _authorize(entry.path)) {
          return;
        }
        await widget.workspace.toggleFileFavorite(entry);
      },
    ),
    if (!external || !entry.isDirectory) ...[
      FileMenuAction('Rename', () => _rename(entry)),
      FileMenuAction(
        'Duplicate Saved Copy',
        () => _batch(_targets(entry.path), (path) async {
          if (!await _authorize(p.dirname(path))) return false;
          await widget.workspace.duplicateFileEntry(path);
          return true;
        }, 'duplicated'),
      ),
      FileMenuAction('Move to…', () => _move(_targets(entry.path))),
      FileMenuAction(
        'Move to Trash',
        () => _trash(_targets(entry.path)),
        destructive: true,
      ),
    ],
    if (!external && browser.root != null)
      FileMenuAction(
        'Copy Relative Path',
        () => Clipboard.setData(
          ClipboardData(text: p.relative(entry.path, from: browser.root)),
        ),
      ),
  ];

  Future<bool> _authorize(String directory) async {
    if (widget.workspace.canManage(directory)) return true;
    if (!mounted) return false;
    final grant = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Folder access needed'),
        content: Text(
          'Choose "$directory" or a containing folder to manage these files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose Folder'),
          ),
        ],
      ),
    );
    if (grant != true) return false;
    final folder = await widget.workspace.chooseOperationFolder();
    if (folder == null) return false;
    if (!widget.workspace.canManage(directory)) {
      throw StateError('The selected folder does not contain this item.');
    }
    return true;
  }

  Future<void> _startCreate({required bool folder, String? directory}) async {
    if (directory == null) {
      final selected = browser.focusedPath;
      final row = _rows.where((row) => row.entry?.path == selected).firstOrNull;
      directory = row?.entry?.isDirectory == true
          ? selected
          : selected == null
          ? browser.root
          : p.dirname(selected);
    }
    directory ??= await widget.workspace.chooseOperationFolder();
    if (directory == null || !await _authorize(directory) || !mounted) return;
    if (browser.isExternal(directory)) {
      // Creating beside an external file must not invent a browsable parent tree.
      await _externalCreate(directory, folder);
      return;
    }
    _clearSearch();
    if (directory != browser.root) {
      await browser.reveal(directory);
      if (!browser.isExpanded(directory)) browser.toggle(directory);
      await browser.load(directory);
    }
    setState(() {
      _creatingIn = directory;
      _creatingFolder = folder;
      _editingPath = null;
      _inlineError = null;
      _name.text = folder ? 'New Folder' : 'Untitled.md';
    });
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: folder
          ? _name.text.length
          : p.basenameWithoutExtension(_name.text).length,
    );
    _nameFocus.requestFocus();
    _ensureVisible('__new__');
  }

  Future<void> _externalCreate(String directory, bool folder) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ExternalCreateDialog(
        workspace: widget.workspace,
        directory: directory,
        folder: folder,
      ),
    );
    if (result != null) {
      if (!folder) await widget.workspace.openPath(result);
      _message(folder ? 'Folder created in $directory.' : 'File created.');
    }
  }

  Future<void> _rename(WorkspaceEntry entry) async {
    if (entry.isDirectory && browser.isExternal(entry.path)) {
      _message('Open this folder as a workspace to rename it.');
      return;
    }
    if (!await _authorize(p.dirname(entry.path)) || !mounted) return;
    await browser.reveal(entry.path);
    setState(() {
      _editingPath = entry.path;
      _creatingIn = null;
      _inlineError = null;
      _name.text = entry.name;
    });
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: entry.isDirectory
          ? entry.name.length
          : p.basenameWithoutExtension(entry.name).length,
    );
    _nameFocus.requestFocus();
    _ensureVisible(entry.path);
  }

  Widget _inlineName(BrowserRow row) => Padding(
    padding: EdgeInsets.only(
      left: 25 + math.min(row.depth * 14.0, 56),
      right: 8,
    ),
    child: Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEdit();
          _treeFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        key: const ValueKey('file-name-editor'),
        controller: _name,
        focusNode: _nameFocus,
        autofocus: true,
        enabled: !_committing,
        style: DesktopTypography.body,
        onSubmitted: (_) => _run(_commitName),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          border: OutlineInputBorder(),
        ),
      ),
    ),
  );

  void _cancelEdit() {
    _editingPath = null;
    _creatingIn = null;
    _inlineError = null;
    if (mounted) setState(() {});
  }

  Future<void> _commitName() async {
    if (_committing) return;
    setState(() => _committing = true);
    try {
      String? result;
      if (_creatingIn != null) {
        result = await widget.workspace.createFileEntry(
          _creatingIn!,
          _name.text,
          folder: _creatingFolder,
        );
        if (!_creatingFolder) await widget.workspace.openPath(result);
      } else if (_editingPath != null) {
        final name = WorkspaceController.validateEntryName(_name.text);
        final old = _editingPath!;
        result = p.join(p.dirname(old), name);
        if (result != old) {
          final row = _rows.where((row) => row.entry?.path == old).firstOrNull;
          if (row?.entry?.isDirectory == false && !isMarkdownFileName(name)) {
            throw const FormatException('Use a Markdown or text extension.');
          }
          await widget.workspace.moveFileEntry(old, result);
          _message('Renamed. Relative Markdown links were not updated.');
        }
      }
      if (!mounted) return;
      _cancelEdit();
      if (result != null) await browser.reveal(result);
      _treeFocus.requestFocus();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _inlineError = describeFileError(error));
        _nameFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  Future<void> _batch(
    List<String> paths,
    Future<bool> Function(String) action,
    String verb,
  ) async {
    var completed = 0;
    final failures = <String>[];
    for (final path in _topLevel(paths)) {
      try {
        if (!await action(path)) break;
        completed++;
      } on Object catch (error) {
        failures.add('${p.basename(path)}: ${describeFileError(error)}');
      }
    }
    if (failures.isNotEmpty) {
      if (mounted) {
        widget.onError('$completed item(s) $verb. ${failures.join('\n')}');
      }
    } else if (completed > 0) {
      _message(
        '$completed item(s) $verb.${verb == 'moved' ? ' Relative Markdown links were not updated.' : ''}',
      );
    }
  }

  Future<void> _move(List<String> paths, {String? destination}) async {
    if (paths.isEmpty) return;
    destination ??= await showDialog<String>(
      context: context,
      builder: (_) =>
          _MoveFolderDialog(workspace: widget.workspace, initial: browser.root),
    );
    if (destination == null || !await _authorize(destination)) return;
    final target = destination;
    // Preflight every target before changing any item, including duplicate basenames.
    final destinations = <String>{};
    for (final source in paths) {
      final path = p.join(target, p.basename(source));
      if (source == path || p.isWithin(source, path)) {
        throw StateError('Cannot move an item into itself.');
      }
      if (!destinations.add(path.toLowerCase()) ||
          await widget.workspace.fileService.entryExists(path)) {
        throw StateError('Destination already exists: ${p.basename(path)}');
      }
    }
    for (final source in paths) {
      if (!await _authorize(p.dirname(source))) return;
    }
    await _batch(paths, (path) async {
      await widget.workspace.moveFileEntry(
        path,
        p.join(target, p.basename(path)),
      );
      return true;
    }, 'moved');
  }

  Future<void> _trash(List<String> paths) async {
    if (paths.isEmpty) return;
    for (final path in paths) {
      if (!await _authorize(p.dirname(path))) return;
    }
    final dirty = widget.workspace
        .documentsWithin(paths)
        .where((document) => document.controller.isDirty)
        .toList();
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move ${paths.length} item(s) to Trash?'),
        content: Text(
          dirty.isEmpty
              ? 'You can restore these items from Finder’s Trash.'
              : '${dirty.length} open document(s) have unsaved changes. Save before moving to Trash, or discard those changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (dirty.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard and Trash'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(dirty.isEmpty ? 'Move to Trash' : 'Save and Trash'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'save') {
      for (final document in dirty) {
        if (!await widget.workspace.saveDocument(document)) return;
      }
    }
    await _batch(paths, (path) async {
      await widget.workspace.trashFileEntry(
        path,
        discardChanges: choice == 'discard',
      );
      return true;
    }, 'moved to Trash');
  }
}

class _MoveFolderDialog extends StatefulWidget {
  const _MoveFolderDialog({required this.workspace, this.initial});
  final WorkspaceController workspace;
  final String? initial;
  @override
  State<_MoveFolderDialog> createState() => _MoveFolderDialogState();
}

class _MoveFolderDialogState extends State<_MoveFolderDialog> {
  String? _path;
  String? _boundary;
  Future<List<WorkspaceEntry>>? _entries;
  @override
  void initState() {
    super.initState();
    _boundary = widget.initial;
    _navigate(widget.initial);
  }

  void _navigate(String? path) {
    _path = path;
    _entries = path == null
        ? null
        : widget.workspace.fileService.listDirectory(path);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Move to Folder'),
    content: SizedBox(
      width: 380,
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_path != null)
            Row(
              children: [
                IconButton(
                  tooltip: 'Parent folder',
                  onPressed: _path == _boundary
                      ? null
                      : () => setState(() => _navigate(p.dirname(_path!))),
                  icon: const Icon(Icons.arrow_upward, size: 16),
                ),
                Expanded(
                  child: Tooltip(
                    message: _path!,
                    child: Text(
                      _path!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          Expanded(
            child: _entries == null
                ? const Center(child: Text('Choose a destination folder.'))
                : FutureBuilder<List<WorkspaceEntry>>(
                    future: _entries,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return TextButton(
                          onPressed: () => setState(() => _navigate(_path)),
                          child: const Text('Unable to read folder — Retry'),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final folders =
                          snapshot.data!
                              .where((entry) => entry.isDirectory)
                              .toList()
                            ..sort((a, b) => naturalCompare(a.name, b.name));
                      if (folders.isEmpty) {
                        return const Center(
                          child: Text('No subfolders. You can move here.'),
                        );
                      }
                      return ListView.builder(
                        itemCount: folders.length,
                        itemBuilder: (_, index) => ListTile(
                          leading: const Icon(AppIcons.folder, size: 16),
                          title: Text(folders[index].name),
                          onTap: () =>
                              setState(() => _navigate(folders[index].path)),
                        ),
                      );
                    },
                  ),
          ),
          TextButton(
            onPressed: () async {
              final path = await widget.workspace.chooseOperationFolder();
              if (path != null && mounted) {
                setState(() {
                  _boundary = path;
                  _navigate(path);
                });
              }
            },
            child: const Text('Choose Other Folder…'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _path == null ? null : () => Navigator.pop(context, _path),
        child: const Text('Move Here'),
      ),
    ],
  );
}

class _ExternalCreateDialog extends StatefulWidget {
  const _ExternalCreateDialog({
    required this.workspace,
    required this.directory,
    required this.folder,
  });
  final WorkspaceController workspace;
  final String directory;
  final bool folder;
  @override
  State<_ExternalCreateDialog> createState() => _ExternalCreateDialogState();
}

class _ExternalCreateDialogState extends State<_ExternalCreateDialog> {
  late final _name = TextEditingController(
    text: widget.folder ? 'New Folder' : 'Untitled.md',
  );
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await widget.workspace.createFileEntry(
        widget.directory,
        _name.text,
        folder: widget.folder,
      );
      if (mounted) Navigator.pop(context, path);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = describeFileError(error);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.folder ? 'New Folder' : 'New Markdown'),
    content: TextField(
      controller: _name,
      autofocus: true,
      enabled: !_busy,
      decoration: InputDecoration(errorText: _error),
      onSubmitted: (_) => _create(),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _create,
        child: const Text('Create'),
      ),
    ],
  );
}
