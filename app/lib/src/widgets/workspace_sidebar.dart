import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controllers/workspace_controller.dart';
import '../desktop_theme.dart';
import '../desktop_typography.dart';
import '../app_icons.dart';
import '../services/markdown_file_service.dart';
import 'middle_ellipsis_text.dart';

const _sidebarBackground = Color(0xff17191a);
const _sidebarRaised = Color(0xff242728);
const _sidebarBorder = Color(0xff323536);
const _sidebarText = Color(0xffe6e7e7);
const _sidebarSecondary = Color(0xffb7b9ba);
const _sidebarMuted = Color(0xff92969a);
const _sidebarAccent = Color(0xff64aaff);
const _treeHover = Color(0x12ffffff);
const _treeSelection = Color(0xff365f87);

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
  final _searchController = TextEditingController();
  var _searching = false;
  List<WorkspaceEntry> _results = const <WorkspaceEntry>[];
  Timer? _debounce;
  var _searchGeneration = 0;
  late int _filesRevision;
  late List<String> _temporaryPaths;
  final _temporaryTree = _TemporaryFileTree();
  String? _root;

  @override
  void initState() {
    super.initState();
    _root = widget.workspace.workspaceRoot;
    _filesRevision = widget.workspace.workspaceFilesRevision;
    _temporaryPaths = _collectTemporaryPaths();
    _temporaryTree.updatePaths(_temporaryPaths);
    widget.workspace.addListener(_workspaceChanged);
  }

  @override
  void didUpdateWidget(WorkspaceSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.removeListener(_workspaceChanged);
      widget.workspace.addListener(_workspaceChanged);
      _workspaceChanged();
    }
  }

  void _workspaceChanged() {
    final root = widget.workspace.workspaceRoot;
    final revision = widget.workspace.workspaceFilesRevision;
    final temporaryPaths = _collectTemporaryPaths();
    final temporaryPathsChanged = !listEquals(temporaryPaths, _temporaryPaths);
    final refreshSearch =
        root != _root || revision != _filesRevision || temporaryPathsChanged;
    if (temporaryPathsChanged) _temporaryTree.updatePaths(temporaryPaths);
    setState(() {
      _root = root;
      _filesRevision = revision;
      _temporaryPaths = temporaryPaths;
    });
    if (refreshSearch && _searchController.text.trim().isNotEmpty) {
      _search(_searchController.text, showProgress: false);
    }
  }

  List<String> _collectTemporaryPaths() {
    final root = widget.workspace.workspaceRoot;
    // Single-file access does not grant permission to browse its parent.
    // Build these branches from open sessions without listing directories.
    return widget.workspace.documents
        .map((document) => document.path)
        .whereType<String>()
        .map((path) => p.normalize(p.absolute(path)))
        .where((path) => root == null || !p.isWithin(root, path))
        .toSet()
        .toList()
      ..sort();
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_workspaceChanged);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.workspace.workspaceRoot;
    return Theme(
      data: desktopTheme(Brightness.dark),
      child: Material(
        color: _sidebarBackground,
        child: Container(
          width: widget.width ?? widget.workspace.sidebarWidth,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: _sidebarBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: DesktopMetrics.toolbarHeight),
              const _SectionLabel('Workspace'),
              _ProjectTitle(
                root: root,
                hasTemporaryFiles: _temporaryPaths.isNotEmpty,
                onOpen: () => _run(widget.workspace.chooseWorkspaceFolder),
              ),
              Expanded(child: _buildSearchPanel(root)),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilesPanel(String? root) {
    final temporaryBranches = <Widget>[
      if (root != null && _temporaryPaths.isNotEmpty)
        const _SectionLabel('Temporary Files'),
      for (final directory in _temporaryTree.roots)
        _DirectoryTile(
          key: ValueKey('temporary-directory-${directory.path}'),
          entry: directory,
          depth: 0,
          service: widget.workspace.fileService,
          revision: _filesRevision,
          selectedPath: widget.workspace.activeDocument?.path,
          temporaryTree: _temporaryTree,
          onOpen: (path) => _run(() => widget.workspace.openPath(path)),
        ),
    ];
    if (root != null) {
      return _DirectoryBranch(
        key: ValueKey(root),
        path: root,
        depth: 0,
        service: widget.workspace.fileService,
        revision: _filesRevision,
        selectedPath: widget.workspace.activeDocument?.path,
        onOpen: (path) => _run(() => widget.workspace.openPath(path)),
        trailing: temporaryBranches,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
      children: temporaryBranches,
    );
  }

  Widget _buildSearchPanel(String? root) {
    final hasFiles = root != null || _temporaryPaths.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasFiles)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: SizedBox(
              height: 30,
              child: TextField(
                key: const ValueKey('workspace-search-field'),
                controller: _searchController,
                autofocus: false,
                onChanged: _search,
                cursorColor: _sidebarAccent,
                style: DesktopTypography.body.copyWith(color: _sidebarText),
                decoration: InputDecoration(
                  hintText: 'Search Files',
                  prefixIcon: const Icon(
                    AppIcons.search,
                    size: 16,
                    color: _sidebarMuted,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 28),
                  hintStyle: const TextStyle(color: _sidebarMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                          icon: const Icon(
                            AppIcons.close,
                            size: 12,
                            color: _sidebarMuted,
                          ),
                        ),
                  filled: true,
                  fillColor: _sidebarRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: _sidebarBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: _sidebarBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: _sidebarAccent),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: !hasFiles
              ? _EmptyWorkspace()
              : IndexedStack(
                  index: _searchController.text.trim().isEmpty ? 0 : 1,
                  children: [
                    _buildFilesPanel(root),
                    _SearchResults(
                      searching: _searching,
                      results: _results,
                      root: root,
                      onOpen: (path) =>
                          _run(() => widget.workspace.openPath(path)),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  void _search(String query, {bool showProgress = true}) {
    setState(() {});
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    final root = widget.workspace.workspaceRoot;
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      setState(() {
        _searching = false;
        _results = const <WorkspaceEntry>[];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _searching = showProgress);
      try {
        final results = await _findFiles(root, normalized);
        if (!mounted ||
            generation != _searchGeneration ||
            widget.workspace.workspaceRoot != root ||
            _searchController.text.trim().toLowerCase() != normalized) {
          return;
        }
        setState(() {
          _searching = false;
          _results = results;
        });
      } on Object catch (error) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() => _searching = false);
        widget.onError(error.toString());
      }
    });
  }

  Future<List<WorkspaceEntry>> _findFiles(String? root, String query) async {
    final service = widget.workspace.fileService;
    final matches = _temporaryPaths
        .where((path) => path.toLowerCase().contains(query))
        .take(200)
        .map(
          (path) => WorkspaceEntry(
            path: path,
            name: p.basename(path),
            isDirectory: false,
          ),
        )
        .toList();
    final pending = <String>[?root];
    while (pending.isNotEmpty && matches.length < 200) {
      final directory = pending.removeLast();
      for (final entry in await service.listDirectory(directory)) {
        if (entry.isDirectory) {
          pending.add(entry.path);
        } else if (entry.name.toLowerCase().contains(query)) {
          matches.add(entry);
          if (matches.length >= 200) break;
        }
      }
    }
    return matches;
  }

  void _run(Future<Object?> Function() action) {
    unawaited(
      action().catchError((Object error, StackTrace stackTrace) {
        widget.onError(error.toString());
        return null;
      }),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 19, 12, 7),
      child: Text(
        label,
        style: DesktopTypography.sectionLabel.copyWith(color: _sidebarMuted),
      ),
    );
  }
}

class _ProjectTitle extends StatelessWidget {
  const _ProjectTitle({
    required this.root,
    required this.hasTemporaryFiles,
    required this.onOpen,
  });

  final String? root;
  final bool hasTemporaryFiles;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            root == null ? AppIcons.openFolder : AppIcons.folder,
            size: 14,
            color: _sidebarSecondary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              root != null
                  ? p.basename(root!)
                  : hasTemporaryFiles
                  ? 'Temporary Files'
                  : 'No folder open',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopTypography.emphasizedBody.copyWith(
                color: _sidebarText,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('open-workspace-button'),
            tooltip: 'Open folder (⌘⇧O)',
            onPressed: onOpen,
            icon: const Icon(
              AppIcons.openFolder,
              size: 14,
              color: _sidebarMuted,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.openFolder, size: 32, color: _sidebarMuted),
            const SizedBox(height: 12),
            Text(
              'Open a folder to browse Markdown files.',
              textAlign: TextAlign.center,
              style: DesktopTypography.callout.copyWith(color: _sidebarMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemporaryFileTree {
  final _roots = <String, WorkspaceEntry>{};
  final _children = <String, Map<String, WorkspaceEntry>>{};
  final _collapsedDirectories = <String>{};

  void updatePaths(List<String> paths) {
    _roots.clear();
    _children.clear();
    for (final path in paths) {
      final parts = p.split(path);
      var directory = parts.first;
      _roots.putIfAbsent(
        directory,
        () =>
            WorkspaceEntry(path: directory, name: directory, isDirectory: true),
      );
      var children = _children.putIfAbsent(directory, () => {});
      for (final name in parts.skip(1).take(parts.length - 2)) {
        directory = p.join(directory, name);
        children.putIfAbsent(
          directory,
          () => WorkspaceEntry(path: directory, name: name, isDirectory: true),
        );
        children = _children.putIfAbsent(directory, () => {});
      }
      children[path] = WorkspaceEntry(
        path: path,
        name: parts.last,
        isDirectory: false,
      );
    }
    _collapsedDirectories.retainAll(_children.keys);
  }

  Iterable<WorkspaceEntry> get roots =>
      _roots.values.map((entry) => _compactDirectory(entry));

  List<WorkspaceEntry> childrenOf(String directory) {
    final entries = _children[directory]!.values
        .map(
          (entry) => entry.isDirectory
              ? _compactDirectory(entry, parent: directory)
              : entry,
        )
        .toList();
    entries.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.name.compareTo(right.name);
    });
    return entries;
  }

  WorkspaceEntry _compactDirectory(WorkspaceEntry entry, {String? parent}) {
    // Keep shared ancestors and folders containing files as branch points.
    // Compact unbranched paths so deep absolute paths fit in the sidebar.
    var children = _children[entry.path]!;
    while (children.length == 1 && children.values.single.isDirectory) {
      entry = children.values.single;
      children = _children[entry.path]!;
    }
    return WorkspaceEntry(
      path: entry.path,
      name: parent == null ? entry.path : p.relative(entry.path, from: parent),
      isDirectory: true,
    );
  }

  bool isExpanded(String directory) =>
      !_collapsedDirectories.contains(directory);

  void toggleDirectory(String directory) {
    if (!_collapsedDirectories.add(directory)) {
      _collapsedDirectories.remove(directory);
    }
  }
}

class _DirectoryBranch extends StatefulWidget {
  const _DirectoryBranch({
    super.key,
    required this.path,
    required this.depth,
    required this.service,
    required this.revision,
    required this.selectedPath,
    required this.onOpen,
    this.trailing = const <Widget>[],
  });

  final String path;
  final int depth;
  final MarkdownFileService service;
  final int revision;
  final String? selectedPath;
  final ValueChanged<String> onOpen;
  final List<Widget> trailing;

  @override
  State<_DirectoryBranch> createState() => _DirectoryBranchState();
}

class _DirectoryBranchState extends State<_DirectoryBranch> {
  late Future<List<WorkspaceEntry>> _entries = widget.service.listDirectory(
    widget.path,
  );

  @override
  void didUpdateWidget(_DirectoryBranch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.service != widget.service ||
        oldWidget.revision != widget.revision) {
      // FutureBuilder retains the current data while refreshing, so keyed
      // directory children and the ListView keep their expansion and scroll.
      _entries = widget.service.listDirectory(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkspaceEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildChildren([
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Unable to read folder: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: DesktopTypography.callout.copyWith(
                    color: _sidebarMuted,
                  ),
                ),
              ),
            ),
          ]);
        }
        if (!snapshot.hasData) {
          return _buildChildren(const [
            Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _sidebarAccent,
              ),
            ),
          ]);
        }
        final children = <Widget>[
          for (final entry in snapshot.data!)
            if (entry.isDirectory)
              _DirectoryTile(
                key: ValueKey(entry.path),
                entry: entry,
                depth: widget.depth,
                service: widget.service,
                revision: widget.revision,
                selectedPath: widget.selectedPath,
                onOpen: widget.onOpen,
              )
            else
              _FileTile(
                entry: entry,
                depth: widget.depth,
                selected:
                    widget.selectedPath != null &&
                    p.equals(entry.path, widget.selectedPath!),
                onOpen: widget.onOpen,
              ),
        ];
        return _buildChildren(children);
      },
    );
  }

  Widget _buildChildren(List<Widget> children) {
    if (widget.depth == 0) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
        children: [...children, ...widget.trailing],
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _DirectoryTile extends StatefulWidget {
  const _DirectoryTile({
    super.key,
    required this.entry,
    required this.depth,
    required this.service,
    required this.revision,
    required this.selectedPath,
    required this.onOpen,
    this.temporaryTree,
  });

  final WorkspaceEntry entry;
  final int depth;
  final MarkdownFileService service;
  final int revision;
  final String? selectedPath;
  final ValueChanged<String> onOpen;
  final _TemporaryFileTree? temporaryTree;

  @override
  State<_DirectoryTile> createState() => _DirectoryTileState();
}

class _DirectoryTileState extends State<_DirectoryTile> {
  var _workspaceExpanded = false;
  var _hovered = false;

  bool get _expanded =>
      widget.temporaryTree?.isExpanded(widget.entry.path) ?? _workspaceExpanded;

  void _toggleExpanded() {
    setState(() {
      if (widget.temporaryTree case final tree?) {
        tree.toggleDirectory(widget.entry.path);
      } else {
        _workspaceExpanded = !_workspaceExpanded;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final temporary = widget.temporaryTree != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Semantics(
            button: true,
            onTap: _toggleExpanded,
            label: entry.name,
            hint: temporary ? entry.path : null,
            value: _expanded ? 'Expanded' : 'Collapsed',
            excludeSemantics: true,
            child: Tooltip(
              message: entry.path,
              child: MouseRegion(
                cursor: SystemMouseCursors.basic,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Material(
                  color: _hovered ? _treeHover : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    onTap: _toggleExpanded,
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 26,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: 5 + widget.depth * 14,
                          right: 7,
                        ),
                        child: Row(
                          children: [
                            AnimatedRotation(
                              turns: _expanded ? .25 : 0,
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                              child: const Icon(
                                AppIcons.disclosure,
                                size: 12,
                                color: _sidebarMuted,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              AppIcons.folder,
                              size: 14,
                              color: _sidebarSecondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: MiddleEllipsisText(
                                entry.name,
                                style: DesktopTypography.body.copyWith(
                                  color: _sidebarSecondary,
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
            ),
          ),
        ),
        if (_expanded)
          if (widget.temporaryTree case final tree?)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final child in tree.childrenOf(entry.path))
                  if (child.isDirectory)
                    _DirectoryTile(
                      key: ValueKey('temporary-directory-${child.path}'),
                      entry: child,
                      depth: widget.depth + 1,
                      service: widget.service,
                      revision: widget.revision,
                      selectedPath: widget.selectedPath,
                      onOpen: widget.onOpen,
                      temporaryTree: tree,
                    )
                  else
                    _FileTile(
                      key: ValueKey(child.path),
                      entry: child,
                      depth: widget.depth + 1,
                      selected:
                          widget.selectedPath != null &&
                          p.equals(child.path, widget.selectedPath!),
                      onOpen: widget.onOpen,
                    ),
              ],
            )
          else
            _DirectoryBranch(
              path: entry.path,
              depth: widget.depth + 1,
              service: widget.service,
              revision: widget.revision,
              selectedPath: widget.selectedPath,
              onOpen: widget.onOpen,
            ),
      ],
    );
  }
}

class _FileTile extends StatefulWidget {
  const _FileTile({
    super.key,
    required this.entry,
    required this.depth,
    required this.selected,
    required this.onOpen,
  });

  final WorkspaceEntry entry;
  final int depth;
  final bool selected;
  final ValueChanged<String> onOpen;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Semantics(
        button: true,
        onTap: () => widget.onOpen(widget.entry.path),
        selected: selected,
        label: widget.entry.name,
        hint: widget.entry.path,
        excludeSemantics: true,
        child: Tooltip(
          message: widget.entry.path,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Material(
              key: ValueKey('workspace-file-${widget.entry.path}'),
              color: selected
                  ? _treeSelection
                  : _hovered
                  ? _treeHover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              child: InkWell(
                onTap: () => widget.onOpen(widget.entry.path),
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: 26,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 20 + widget.depth * 14,
                      right: 7,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.document,
                          size: 14,
                          color: selected ? Colors.white : _sidebarMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopTypography.body.copyWith(
                              color: selected
                                  ? Colors.white
                                  : _sidebarSecondary,
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
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.searching,
    required this.results,
    required this.root,
    required this.onOpen,
  });

  final bool searching;
  final List<WorkspaceEntry> results;
  final String? root;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _sidebarAccent),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No matching files',
          style: DesktopTypography.callout.copyWith(color: _sidebarMuted),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return ListTile(
          dense: true,
          leading: const Icon(
            AppIcons.document,
            size: 14,
            color: _sidebarMuted,
          ),
          title: Text(
            result.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopTypography.body.copyWith(color: _sidebarText),
          ),
          subtitle: Tooltip(
            message: result.path,
            child: MiddleEllipsisText(
              root != null && p.isWithin(root!, result.path)
                  ? p.relative(p.dirname(result.path), from: root)
                  : p.dirname(result.path),
              style: DesktopTypography.subheadline.copyWith(
                color: _sidebarMuted,
              ),
            ),
          ),
          onTap: () => onOpen(result.path),
        );
      },
    );
  }
}
