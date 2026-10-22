import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_clipboard/ianvs_markdown_clipboard.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';
import 'package:path/path.dart' as p;

import '../widgets/document_diagram.dart';
import '../widgets/document_sync_indicator.dart';
import '../widgets/document_attachment_scope.dart';
import '../services/attachment_repository.dart';
import '../services/apple_workspace_service.dart';
import 'preview_controller.dart';
import 'preview_library.dart';
import 'preview_platform.dart';
import 'preview_draft_store.dart';
import 'preview_editor_controller.dart';
import 'preview_links.dart';

class LinefoldPreviewApp extends StatefulWidget {
  const LinefoldPreviewApp({
    super.key,
    this.controller,
    this.platform,
    this.draftStore,
    this.attachmentSource = const AppleAttachmentSource(),
  });

  final PreviewController? controller;
  final PreviewPlatform? platform;
  final PreviewDraftStore? draftStore;
  final AttachmentSource attachmentSource;

  @override
  State<LinefoldPreviewApp> createState() => _LinefoldPreviewAppState();
}

class _LinefoldPreviewAppState extends State<LinefoldPreviewApp>
    with WidgetsBindingObserver {
  late final _controller =
      widget.controller ??
      PreviewController(
        library: PreviewLibrary(
          workspaceService: const AppleWorkspaceService(),
        ),
      );
  late final _editor = PreviewEditorController(
    library: _controller.library,
    store: widget.draftStore ?? ReliablePreviewDraftStore(),
  );
  late final _platform = widget.platform ?? PreviewPlatform();
  late final _renderer = NativeMermanRenderer();
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<void>? _cloudChanges;
  bool _prompting = false;
  String? _fragment;
  int _fragmentRequest = 0;
  bool get _canStartEditing =>
      _editor.canBegin && !_controller.busy && !_controller.navigating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.blocksNavigation = () =>
        _editor.editing || _editor.busy || _prompting;
    _cloudChanges = _controller.library.workspaceService?.changes.listen((_) {
      if (_controller.initialized) _controller.notifyCloudChange();
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    unawaited(_editor.initialize());
    await _controller.initialize();
    if (!mounted) return;
    await _platform.start(_controller.receive, _controller.reportError);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _controller.initialized) {
      unawaited(_platform.refresh());
      unawaited(_controller.refresh());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_editor.flushDraft());
    }
  }

  Future<bool> _save() async {
    final saved = await _editor.save((conflict) async {
      if (!mounted) return PreviewConflictChoice.cancel;
      return await showDialog<PreviewConflictChoice>(
            context: _navigator.currentContext!,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('文件已在其他地方改变'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p.basename(conflict.path)} 的磁盘版本已变化。保留两份会创建新笔记；覆盖只针对这次检测到的版本。',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    conflict.currentContents == null
                        ? '检测时文件已不存在，覆盖将重新创建同名笔记。'
                        : '检测到的磁盘内容（最多显示前 2000 字符）：',
                  ),
                  if (conflict.currentContents case final current?)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          String.fromCharCodes(current.runes.take(2000)),
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, PreviewConflictChoice.cancel),
                  child: const Text('取消保存'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, PreviewConflictChoice.keepBoth),
                  child: const Text('保留两份'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, PreviewConflictChoice.overwrite),
                  child: const Text('覆盖此版本'),
                ),
              ],
            ),
          ) ??
          PreviewConflictChoice.cancel;
    });
    if (saved && mounted && !_editor.editing) {
      _controller.showEditorResult(
        _editor.path!,
        _editor.source.text,
        _editor.generation!,
      );
      unawaited(_controller.refresh());
    }
    return saved && !_editor.editing;
  }

  Future<bool> _leaveEditor() async {
    if (_editor.busy || _prompting) return false;
    if (!_editor.editing) return true;
    if (!_editor.dirty) return _editor.discard();
    _prompting = true;
    final choice = await showDialog<String>(
      context: _navigator.currentContext!,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('保留这次修改？'),
        content: const Text('本机恢复草稿不等于保存到原文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('丢弃草稿'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('保存后离开'),
          ),
        ],
      ),
    );
    _prompting = false;
    if (!mounted) return false;
    if (choice == 'save') return _save();
    return choice == 'discard' ? _editor.discard() : false;
  }

  Future<void> _cancelEditor() async {
    if (await _leaveEditor() && mounted) {
      // Refresh events suppressed during Source must not leave a stale cached
      // reader behind when the user discards edits.
      await _controller.refresh();
    }
  }

  Future<void> _navigate(FutureOr<void> Function() action) async {
    if (await _leaveEditor() && mounted) {
      _fragment = null;
      await action();
    }
  }

  Future<void> _chooseFiles() => _navigate(() async {
    _controller.cancelPendingOperation();
    try {
      await _platform.chooseFiles();
    } on Object {
      if (mounted) _controller.reportError('暂时无法打开文件选择器，请重试。');
    }
  });

  Future<void> _newNote() async {
    if (!_canStartEditing || _prompting) return;
    if (_editor.recovery != null) {
      _controller.reportError('请先恢复或丢弃已有草稿。');
      return;
    }
    final intendedGeneration = _controller.library.workspaceGeneration;
    final intendedRoot = _controller.library.workspace?.path;
    _prompting = true;
    final name = TextEditingController();
    final chosen = await showDialog<String>(
      context: _navigator.currentContext!,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('新建 Markdown 笔记'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '文件名',
            hintText: '新笔记.md',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, name.text),
            child: const Text('新建'),
          ),
        ],
      ),
    );
    // The dialog's exit animation may still reference its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    _prompting = false;
    if (!mounted || chosen == null || chosen.trim().isEmpty) return;
    if (intendedGeneration != _controller.library.workspaceGeneration ||
        intendedRoot != _controller.library.workspace?.path) {
      _controller.reportError('文件夹已改变，请重新发起新建。');
      return;
    }
    final path = await _editor.create(chosen);
    if (!mounted || path == null) return;
    await _controller.open(path);
    if (mounted) await _editor.begin(path);
  }

  Future<void> _recover() async {
    final draft = _editor.recovery;
    if (draft == null || !_editor.canRecover || !_canStartEditing) return;
    await _editor.begin(draft.path, restore: true);
  }

  Future<void> _recoverToNewNote() async {
    if (!_canStartEditing || _prompting) return;
    final intendedGeneration = _controller.library.workspaceGeneration;
    final intendedRoot = _controller.library.workspace?.path;
    final intendedDraft = _editor.recovery;
    _prompting = true;
    final approved = await showDialog<bool>(
      context: _navigator.currentContext!,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('在当前文件夹恢复为新笔记？'),
        content: const Text('只复制草稿文字，不复制附件，也不改动原文件。新笔记仍需点击保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建恢复副本'),
          ),
        ],
      ),
    );
    _prompting = false;
    if (!mounted || approved != true) return;
    if (intendedGeneration != _controller.library.workspaceGeneration ||
        intendedRoot != _controller.library.workspace?.path ||
        !identical(intendedDraft, _editor.recovery)) {
      _controller.reportError('文件夹或恢复草稿已改变，请重新发起恢复。');
      return;
    }
    await _editor.recoverToNewNote();
  }

  Future<void> _followLocal(IanvsMarkdownLinkTarget link) async {
    final root = _controller.activeRoot;
    final origin = _controller.activePath;
    final generation = _controller.library.workspaceGeneration;
    if (root == null ||
        origin == null ||
        root != _controller.library.workspace?.path) {
      _controller.reportError('请先手动选择包含关联文档的文件夹。');
      return;
    }
    try {
      final destination = resolvePreviewLink(
        link: link,
        root: root,
        origin: origin,
        documents: _controller.documents,
      );
      String? path;
      if (destination.paths.length == 1) {
        path = destination.paths.single;
      } else {
        path = await showModalBottomSheet<String>(
          context: _navigator.currentContext!,
          useSafeArea: true,
          showDragHandle: true,
          builder: (context) => ListView(
            children: [
              const ListTile(title: Text('选择同名笔记')),
              for (final candidate in destination.paths)
                ListTile(
                  title: Text(p.relative(candidate, from: root)),
                  onTap: () => Navigator.pop(context, candidate),
                ),
            ],
          ),
        );
      }
      if (!mounted ||
          path == null ||
          generation != _controller.library.workspaceGeneration ||
          origin != _controller.activePath) {
        return;
      }
      _fragment = destination.fragment;
      ++_fragmentRequest;
      if (path != origin) await _controller.open(path);
      if (mounted) setState(() {});
    } on FormatException catch (error) {
      _controller.reportError(error.message);
    } on Object {
      _controller.reportError('无法打开这个本地链接。');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.blocksNavigation = null;
    _platform.dispose();
    _cloudChanges?.cancel();
    _renderer.dispose();
    _editor.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: 'Linefold',
    debugShowCheckedModeBanner: false,
    theme: _previewTheme(Brightness.light),
    darkTheme: _previewTheme(Brightness.dark),
    home: ListenableBuilder(
      listenable: Listenable.merge([_controller, _editor]),
      builder: (context, _) => PopScope(
        canPop:
            !_editor.editing && !_editor.busy && _controller.activePath == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_navigate(_controller.showLibrary));
        },
        child: Scaffold(
          appBar: AppBar(
            leading: _editor.editing || _controller.activePath != null
                ? IconButton(
                    tooltip: _editor.editing ? '取消编辑' : '最近文档',
                    icon: Icon(
                      _editor.editing
                          ? CupertinoIcons.xmark
                          : CupertinoIcons.chevron_back,
                    ),
                    onPressed: _editor.busy
                        ? null
                        : () {
                            if (_editor.editing) {
                              unawaited(_cancelEditor());
                            } else {
                              unawaited(_navigate(_controller.showLibrary));
                            }
                          },
                  )
                : null,
            title: Text(
              _editor.editing ? p.basename(_editor.path!) : _controller.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: _editor.editing
                ? [
                    TextButton(
                      onPressed: _editor.busy ? null : _save,
                      child: const Text('保存'),
                    ),
                  ]
                : [
                    if (_controller.activePath == null &&
                        _controller.library.workspaceService != null)
                      PopupMenuButton<String>(
                        tooltip: '切换文件夹',
                        enabled: !_editor.busy,
                        icon: const Icon(CupertinoIcons.ellipsis_circle),
                        onSelected: (value) => _navigate(
                          () => _controller.changeWorkspace(
                            useCloud: value == 'icloud',
                          ),
                        ),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'icloud',
                            child: Text('iCloud · Linefold'),
                          ),
                          PopupMenuItem(
                            value: 'folder',
                            child: Text('选择其他文件夹…'),
                          ),
                        ],
                      ),
                    if (_controller.activePath == null &&
                        _controller.library.canWrite)
                      IconButton(
                        tooltip: '新建笔记',
                        icon: const Icon(CupertinoIcons.add),
                        onPressed: _canStartEditing ? _newNote : null,
                      ),
                    if (_controller.activePath != null &&
                        _controller.library.canWrite)
                      IconButton(
                        tooltip: '编辑源码',
                        icon: const Icon(CupertinoIcons.pencil),
                        onPressed: _canStartEditing
                            ? () => _editor.begin(_controller.activePath!)
                            : null,
                      ),
                    if (_controller.busy)
                      IconButton(
                        tooltip: '取消等待',
                        icon: const Icon(CupertinoIcons.xmark),
                        onPressed: _editor.busy
                            ? null
                            : _controller.cancelPendingOperation,
                      )
                    else if (_controller.activePath != null)
                      IconButton(
                        tooltip: '刷新文档',
                        icon: const Icon(CupertinoIcons.refresh),
                        onPressed: _editor.busy ? null : _controller.refresh,
                      ),
                    IconButton(
                      tooltip: '打开文件',
                      icon: const Icon(CupertinoIcons.folder_open),
                      onPressed: _editor.busy ? null : _chooseFiles,
                    ),
                  ],
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, viewport) => Column(
                children: [
                  if (_editor.error ?? _controller.error case final error?)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: viewport.maxHeight * .24,
                      ),
                      child: SingleChildScrollView(
                        child: Material(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(error),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  children: [
                                    if (_controller.canRetry &&
                                        !_editor.editing)
                                      TextButton(
                                        onPressed: _controller.retry,
                                        child: const Text('重试'),
                                      ),
                                    IconButton(
                                      tooltip: '关闭提示',
                                      icon: const Icon(CupertinoIcons.xmark),
                                      onPressed: () {
                                        _editor.error = null;
                                        _controller.clearError();
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_controller.busy ||
                      (_editor.busy && !_editor.awaitingDecision))
                    const LinearProgressIndicator(),
                  if (_editor.recovery case final draft? when !_editor.editing)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: viewport.maxHeight * .5,
                      ),
                      child: SingleChildScrollView(
                        key: const ValueKey('mobile-recovery-banner'),
                        child: Material(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text('有未保存草稿：${p.basename(draft.path)}'),
                                TextButton(
                                  onPressed:
                                      _editor.canRecover && _canStartEditing
                                      ? _recover
                                      : null,
                                  child: const Text('恢复草稿'),
                                ),
                                TextButton(
                                  onPressed: _canStartEditing
                                      ? _recoverToNewNote
                                      : null,
                                  child: const Text('恢复为新笔记'),
                                ),
                                TextButton(
                                  onPressed: _editor.busy
                                      ? null
                                      : () async {
                                          final approved =
                                              await showDialog<bool>(
                                                context: context,
                                                builder: (context) =>
                                                    AlertDialog(
                                                      title: const Text(
                                                        '丢弃恢复草稿？',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                false,
                                                              ),
                                                          child: const Text(
                                                            '取消',
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                true,
                                                              ),
                                                          child: const Text(
                                                            '丢弃草稿',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                              );
                                          if (approved == true) {
                                            await _editor.discard();
                                          }
                                        },
                                  child: const Text('丢弃草稿'),
                                ),
                                if (!_editor.canRecover)
                                  const Text('请先手动选择草稿原来的文件夹。'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_controller.activePath != null && !_editor.editing)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: viewport.maxHeight * .18,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          child: DocumentSyncIndicator(
                            controller: _controller.sync,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: !_controller.initialized
                        ? const Center(
                            child: CircularProgressIndicator.adaptive(),
                          )
                        : _editor.editing
                        ? _PreviewSourceEditor(editor: _editor)
                        : _controller.contents == null
                        ? _PreviewLibraryView(
                            controller: _controller,
                            onOpen: _chooseFiles,
                          )
                        : _PreviewReader(
                            key: ValueKey((
                              _controller.activeRoot,
                              _controller.activeWorkspaceGeneration,
                              _controller.activePath,
                            )),
                            contents: _controller.contents!,
                            documentPath: _controller.activePath,
                            root: _controller.activeRoot,
                            attachmentSource: widget.attachmentSource,
                            renderer: _renderer,
                            platform: _platform,
                            onError: _controller.reportError,
                            onLocalLink: _followLocal,
                            fragment: _fragment,
                            fragmentRequest: _fragmentRequest,
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
}

class _PreviewSourceEditor extends StatefulWidget {
  const _PreviewSourceEditor({required this.editor});
  final PreviewEditorController editor;
  @override
  State<_PreviewSourceEditor> createState() => _PreviewSourceEditorState();
}

class _PreviewSourceEditorState extends State<_PreviewSourceEditor> {
  final _focus = FocusNode();
  final _undo = UndoHistoryController();
  @override
  void dispose() {
    _focus.dispose();
    _undo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) => Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: viewport.maxHeight * .25),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                widget.editor.busy ? '正在处理，请等待结果。' : 'Source · 本机草稿恢复不会自动保存原文件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
        Expanded(
          child: TextField(
            key: const ValueKey('mobile-source'),
            controller: widget.editor.source,
            focusNode: _focus,
            undoController: _undo,
            autofocus: true,
            readOnly: widget.editor.busy,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              height: 1.5,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              hintText: '写下 Markdown…',
            ),
          ),
        ),
      ],
    ),
  );
}

ThemeData _previewTheme(Brightness brightness) {
  final markdown = brightness == Brightness.light
      ? IanvsMarkdownThemeData.light
      : IanvsMarkdownThemeData.dark;
  return ThemeData(
    brightness: brightness,
    platform: TargetPlatform.iOS,
    fontFamily: '.SF UI Text',
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff2673dd),
      brightness: brightness,
      surface: markdown.surface,
    ),
    scaffoldBackgroundColor: markdown.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: markdown.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: markdown.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    extensions: [markdown],
  );
}

class _PreviewLibraryView extends StatefulWidget {
  const _PreviewLibraryView({required this.controller, required this.onOpen});

  final PreviewController controller;
  final VoidCallback onOpen;

  @override
  State<_PreviewLibraryView> createState() => _PreviewLibraryViewState();
}

class _PreviewLibraryViewState extends State<_PreviewLibraryView> {
  String _query = '';
  PreviewController get controller => widget.controller;
  VoidCallback get onOpen => widget.onOpen;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
        children: [
          Icon(
            CupertinoIcons.doc_text,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            '随手阅读与记录',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            '分享或打开文件会导入副本，不会修改原来源。选择整个文件夹后，可查找、链接导航与轻编辑。',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton(
              onPressed: onOpen,
              child: const Text('打开 Markdown 文件', textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            controller.library.workspace?.notice ??
                (controller.library.workspace?.isCloud == true
                    ? '文档保存在 iCloud，与 Mac 共享'
                    : '导入文档默认保存在 Linefold 的 iCloud 文件夹'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (controller.library.workspace case final workspace?) ...[
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                workspace.isCloud
                    ? CupertinoIcons.cloud
                    : CupertinoIcons.folder,
              ),
              title: Text(workspace.name),
              trailing: IconButton(
                tooltip: '刷新文档',
                icon: const Icon(CupertinoIcons.refresh),
                onPressed: controller.refresh,
              ),
              subtitle: const Text('其他文件夹需手动选择'),
            ),
            if (controller.documents.isEmpty)
              const Text('这个文件夹还没有 Markdown 文档。'),
          ],
          if (controller.documents.isNotEmpty) ...[
            const SizedBox(height: 40),
            Text('最近文档', style: Theme.of(context).textTheme.titleMedium),
            TextField(
              key: const ValueKey('mobile-note-search'),
              decoration: const InputDecoration(
                labelText: '查找文件名或路径',
                prefixIcon: Icon(CupertinoIcons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase()),
            ),
            const SizedBox(height: 12),
            for (final document in controller.documents)
              if (document.path.toLowerCase().contains(_query))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.doc_text),
                  title: Text(
                    document.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    controller.library.workspace == null
                        ? '${document.openedAt.year}/${document.openedAt.month}/${document.openedAt.day}'
                        : '路径：${p.relative(document.path, from: controller.library.workspace!.path)}',
                  ),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                  onTap: () => controller.open(document.path),
                ),
          ],
        ],
      ),
    ),
  );
}

class _PreviewReader extends StatefulWidget {
  const _PreviewReader({
    super.key,
    required this.contents,
    required this.documentPath,
    required this.root,
    required this.attachmentSource,
    required this.renderer,
    required this.platform,
    required this.onError,
    required this.onLocalLink,
    this.fragment,
    required this.fragmentRequest,
  });

  final String contents;
  final String? documentPath;
  final String? root;
  final AttachmentSource attachmentSource;
  final MermaidRenderer renderer;
  final PreviewPlatform platform;
  final ValueChanged<String> onError;
  final Future<void> Function(IanvsMarkdownLinkTarget) onLocalLink;
  final String? fragment;
  final int fragmentRequest;

  @override
  State<_PreviewReader> createState() => _PreviewReaderState();
}

class _PreviewReaderState extends State<_PreviewReader> {
  final _navigation = ValueNotifier<IanvsMarkdownHeadingNavigation?>(null);

  void _revealRequestedFragment() {
    final fragment = widget.fragment;
    if (fragment == null || fragment.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          _openLink(
            IanvsMarkdownLinkTarget(
              text: '',
              href: Uri(fragment: fragment).toString(),
              kind: IanvsMarkdownLinkKind.markdown,
            ),
          ),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _revealRequestedFragment();
  }

  @override
  void didUpdateWidget(covariant _PreviewReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fragmentRequest != widget.fragmentRequest) {
      _revealRequestedFragment();
    }
  }

  List<(int, String)> get _headings => [
    for (final block in parseMarkdownBlocks(widget.contents))
      if (block.type == IanvsMarkdownBlockType.heading)
        for (final heading in parseMarkdownHeadings(block.source))
          (block.start, heading.text),
  ];

  Future<void> _openLink(IanvsMarkdownLinkTarget target) async {
    final href = target.href;
    if (href == null) return;
    if (target.kind == IanvsMarkdownLinkKind.wiki) {
      await widget.onLocalLink(target);
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    final String fragment;
    try {
      fragment = Uri.decodeComponent(uri.fragment);
    } on FormatException {
      widget.onError('链接中的标题编码无效。');
      return;
    }
    if (uri.path.isEmpty && uri.fragment.isNotEmpty && !uri.hasScheme) {
      final counts = <String, int>{};
      for (final (offset, title) in _headings) {
        final slug = title
            .toLowerCase()
            .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}_\-\s]', unicode: true), '')
            .replaceAll(RegExp(r'\s'), '-');
        final count = counts.update(slug, (n) => n + 1, ifAbsent: () => 0);
        if (fragment == title ||
            fragment.toLowerCase() == (count == 0 ? slug : '$slug-$count')) {
          _navigation.value = IanvsMarkdownHeadingNavigation(offset);
          return;
        }
      }
      widget.onError('未找到对应的标题。');
    } else if ({'https', 'http', 'mailto'}.contains(uri.scheme.toLowerCase())) {
      try {
        await widget.platform.openExternal(uri);
      } on Object {
        if (mounted) widget.onError('无法打开这个链接。');
      }
    } else {
      await widget.onLocalLink(target);
    }
  }

  Future<void> _showOutline() async {
    final headings = _headings;
    final offset = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          ListTile(
            title: Text('文档目录', style: Theme.of(context).textTheme.titleLarge),
          ),
          if (headings.isEmpty) const ListTile(title: Text('这篇文档还没有标题')),
          for (final (offset, title) in headings)
            ListTile(
              title: Text(title),
              onTap: () => Navigator.pop(context, offset),
            ),
        ],
      ),
    );
    if (mounted && offset != null) {
      _navigation.value = IanvsMarkdownHeadingNavigation(offset);
    }
  }

  @override
  void dispose() {
    _navigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: widget.contents.isEmpty
            ? const Center(child: Text('这是一个空文档'))
            : DocumentAttachmentScope(
                root: widget.root,
                documentPath: widget.documentPath,
                source: widget.attachmentSource,
                builder: (context, images) => IanvsMarkdownView(
                  imageBuilder: images.image,
                  wikiEmbedBuilder: images.wiki,
                  data: widget.contents,
                  preserveScrollOnUpdate: true,
                  clipboardWriter: (data) => writeIanvsMarkdownRichClipboard(
                    markdown: data.markdown,
                    html: data.html,
                  ),
                  showOutline: false,
                  headingNavigation: _navigation,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  contentMaxWidth: 720,
                  onTapLinkTarget: (target) => unawaited(_openLink(target)),
                  diagramBuilder: (context, source) => DocumentDiagram(
                    source: source,
                    renderer: widget.renderer,
                  ),
                ),
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            const Text('阅读预览', style: TextStyle(fontSize: 13)),
            TextButton.icon(
              onPressed: _showOutline,
              icon: const Icon(CupertinoIcons.list_bullet, size: 20),
              label: const Text('目录'),
            ),
          ],
        ),
      ),
    ],
  );
}
