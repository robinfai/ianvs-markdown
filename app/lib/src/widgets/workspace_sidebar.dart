import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controllers/workspace_controller.dart';
import '../desktop_theme.dart';
import '../app_icons.dart';
import '../services/markdown_file_service.dart';

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
  });

  final WorkspaceController workspace;
  final ValueChanged<String> onError;

  @override
  State<WorkspaceSidebar> createState() => _WorkspaceSidebarState();
}

class _WorkspaceSidebarState extends State<WorkspaceSidebar> {
  final _searchController = TextEditingController();
  var _searching = false;
  List<WorkspaceEntry> _results = const <WorkspaceEntry>[];
  Timer? _debounce;

  @override
  void dispose() {
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
          width: DesktopMetrics.sidebarWidth,
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
    return root == null
        ? _EmptyWorkspace()
        : _DirectoryBranch(
            key: ValueKey(root),
            path: root,
            depth: 0,
            service: widget.workspace.fileService,
            selectedPath: widget.workspace.activeDocument?.path,
            onOpen: (path) => _run(() => widget.workspace.openPath(path)),
          );
  }

  Widget _buildSearchPanel(String? root) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (root != null)
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
                style: const TextStyle(color: _sidebarText, fontSize: 13),
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
          child: root == null
              ? _EmptyWorkspace()
              : _searchController.text.trim().isEmpty
              ? _buildFilesPanel(root)
              : _SearchResults(
                  searching: _searching,
                  results: _results,
                  root: root,
                  onOpen: (path) => _run(() => widget.workspace.openPath(path)),
                ),
        ),
      ],
    );
  }

  void _search(String query) {
    setState(() {});
    _debounce?.cancel();
    final root = widget.workspace.workspaceRoot;
    final normalized = query.trim().toLowerCase();
    if (root == null || normalized.isEmpty) {
      setState(() {
        _searching = false;
        _results = const <WorkspaceEntry>[];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final results = await _findFiles(root, normalized);
        if (!mounted ||
            _searchController.text.trim().toLowerCase() != normalized) {
          return;
        }
        setState(() {
          _searching = false;
          _results = results;
        });
      } on Object catch (error) {
        if (mounted) setState(() => _searching = false);
        widget.onError(error.toString());
      }
    });
  }

  Future<List<WorkspaceEntry>> _findFiles(String root, String query) async {
    final matches = <WorkspaceEntry>[];
    final pending = <String>[root];
    while (pending.isNotEmpty && matches.length < 200) {
      final directory = pending.removeLast();
      for (final entry in await widget.workspace.fileService.listDirectory(
        directory,
      )) {
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
        style: const TextStyle(
          color: _sidebarMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProjectTitle extends StatelessWidget {
  const _ProjectTitle({required this.root, required this.onOpen});

  final String? root;
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
              root == null ? 'No folder open' : p.basename(root!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _sidebarText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -.1,
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
            const Text(
              'Open a folder to browse Markdown files.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _sidebarMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectoryBranch extends StatefulWidget {
  const _DirectoryBranch({
    super.key,
    required this.path,
    required this.depth,
    required this.service,
    required this.selectedPath,
    required this.onOpen,
  });

  final String path;
  final int depth;
  final MarkdownFileService service;
  final String? selectedPath;
  final ValueChanged<String> onOpen;

  @override
  State<_DirectoryBranch> createState() => _DirectoryBranchState();
}

class _DirectoryBranchState extends State<_DirectoryBranch> {
  late final Future<List<WorkspaceEntry>> _entries = widget.service
      .listDirectory(widget.path);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkspaceEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Unable to read folder: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _sidebarMuted, fontSize: 12),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _sidebarAccent,
            ),
          );
        }
        final children = <Widget>[
          for (final entry in snapshot.data!)
            if (entry.isDirectory)
              _DirectoryTile(
                key: ValueKey(entry.path),
                entry: entry,
                depth: widget.depth,
                service: widget.service,
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
        if (widget.depth == 0) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
            children: children,
          );
        }
        return Column(mainAxisSize: MainAxisSize.min, children: children);
      },
    );
  }
}

class _DirectoryTile extends StatefulWidget {
  const _DirectoryTile({
    super.key,
    required this.entry,
    required this.depth,
    required this.service,
    required this.selectedPath,
    required this.onOpen,
  });

  final WorkspaceEntry entry;
  final int depth;
  final MarkdownFileService service;
  final String? selectedPath;
  final ValueChanged<String> onOpen;

  @override
  State<_DirectoryTile> createState() => _DirectoryTileState();
}

class _DirectoryTileState extends State<_DirectoryTile> {
  var _expanded = false;
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Semantics(
            button: true,
            onTap: () => setState(() => _expanded = !_expanded),
            label: entry.name,
            value: _expanded ? 'Expanded' : 'Collapsed',
            excludeSemantics: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.basic,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Material(
                color: _hovered ? _treeHover : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
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
                            child: Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _sidebarSecondary,
                                fontSize: 12.5,
                                height: 1,
                                letterSpacing: -.1,
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
        if (_expanded)
          _DirectoryBranch(
            path: entry.path,
            depth: widget.depth + 1,
            service: widget.service,
            selectedPath: widget.selectedPath,
            onOpen: widget.onOpen,
          ),
      ],
    );
  }
}

class _FileTile extends StatefulWidget {
  const _FileTile({
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
        excludeSemantics: true,
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
                          style: TextStyle(
                            color: selected ? Colors.white : _sidebarSecondary,
                            fontSize: 12.5,
                            height: 1,
                            letterSpacing: -.1,
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
  final String root;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _sidebarAccent),
      );
    }
    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No matching files',
          style: TextStyle(color: _sidebarMuted, fontSize: 12),
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
            style: const TextStyle(color: _sidebarText, fontSize: 12.5),
          ),
          subtitle: Text(
            p.relative(p.dirname(result.path), from: root),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _sidebarMuted, fontSize: 10.5),
          ),
          onTap: () => onOpen(result.path),
        );
      },
    );
  }
}
