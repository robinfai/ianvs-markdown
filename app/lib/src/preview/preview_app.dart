import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_clipboard/ianvs_markdown_clipboard.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';

import '../widgets/document_diagram.dart';
import '../services/apple_workspace_service.dart';
import 'preview_controller.dart';
import 'preview_library.dart';
import 'preview_platform.dart';

class LinefoldPreviewApp extends StatefulWidget {
  const LinefoldPreviewApp({super.key, this.controller, this.platform});

  final PreviewController? controller;
  final PreviewPlatform? platform;

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
  late final _platform = widget.platform ?? PreviewPlatform();
  late final _renderer = NativeMermanRenderer();
  StreamSubscription<void>? _cloudChanges;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller == null) {
      _cloudChanges = const AppleWorkspaceService().changes.listen((_) {
        if (_controller.initialized) unawaited(_controller.refresh());
      });
    }
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _controller.initialize();
    if (!mounted) return;
    await _platform.start(_controller.receive, _controller.reportError);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _controller.initialized) {
      unawaited(_platform.refresh());
      unawaited(_controller.refresh());
    }
  }

  Future<void> _chooseFiles() async {
    try {
      await _platform.chooseFiles();
    } on Object {
      if (mounted) _controller.reportError('暂时无法打开文件选择器，请重试。');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _platform.dispose();
    _cloudChanges?.cancel();
    _renderer.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Linefold',
    debugShowCheckedModeBanner: false,
    theme: _previewTheme(Brightness.light),
    darkTheme: _previewTheme(Brightness.dark),
    home: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: _controller.activePath == null
              ? null
              : IconButton(
                  tooltip: '最近文档',
                  icon: const Icon(CupertinoIcons.chevron_back),
                  onPressed: _controller.showLibrary,
                ),
          title: Text(
            _controller.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_controller.activePath == null &&
                _controller.library.workspaceService != null)
              PopupMenuButton<String>(
                tooltip: '切换文件夹',
                icon: const Icon(CupertinoIcons.ellipsis_circle),
                onSelected: (value) =>
                    _controller.changeWorkspace(useCloud: value == 'icloud'),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'icloud',
                    child: Text('iCloud · Linefold'),
                  ),
                  PopupMenuItem(value: 'folder', child: Text('选择其他文件夹…')),
                ],
              ),
            IconButton(
              tooltip: '打开文件',
              onPressed: _chooseFiles,
              icon: const Icon(CupertinoIcons.folder_open),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_controller.error case final error?)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(error)),
                        IconButton(
                          tooltip: '关闭提示',
                          onPressed: _controller.clearError,
                          icon: const Icon(CupertinoIcons.xmark),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_controller.busy) const LinearProgressIndicator(),
              Expanded(
                child: !_controller.initialized
                    ? const Center(child: CircularProgressIndicator.adaptive())
                    : _controller.contents == null
                    ? _PreviewLibraryView(
                        controller: _controller,
                        onOpen: _chooseFiles,
                      )
                    : _PreviewReader(
                        key: ValueKey(_controller.activePath),
                        contents: _controller.contents!,
                        renderer: _renderer,
                        platform: _platform,
                        onError: _controller.reportError,
                      ),
              ),
            ],
          ),
        ),
      ),
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

class _PreviewLibraryView extends StatelessWidget {
  const _PreviewLibraryView({required this.controller, required this.onOpen});

  final PreviewController controller;
  final VoidCallback onOpen;

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
            '让 Markdown 随手可读',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            '在其他应用中分享 Markdown 文件，选择 Linefold 即可预览；也可以从“文件”中打开。',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(CupertinoIcons.folder_open),
              label: const Text('打开 Markdown 文件'),
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
            const SizedBox(height: 12),
            for (final document in controller.documents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.doc_text),
                title: Text(
                  document.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${document.openedAt.year}/${document.openedAt.month}/${document.openedAt.day}',
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
    required this.renderer,
    required this.platform,
    required this.onError,
  });

  final String contents;
  final MermaidRenderer renderer;
  final PreviewPlatform platform;
  final ValueChanged<String> onError;

  @override
  State<_PreviewReader> createState() => _PreviewReaderState();
}

class _PreviewReaderState extends State<_PreviewReader> {
  final _navigation = ValueNotifier<IanvsMarkdownHeadingNavigation?>(null);

  List<(int, String)> get _headings => [
    for (final block in parseMarkdownBlocks(widget.contents))
      if (block.type == IanvsMarkdownBlockType.heading)
        for (final heading in parseMarkdownHeadings(block.source))
          (block.start, heading.text),
  ];

  Future<void> _openLink(String? href) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (uri.path.isEmpty && uri.fragment.isNotEmpty && !uri.hasScheme) {
      final counts = <String, int>{};
      for (final (offset, title) in _headings) {
        final slug = title
            .toLowerCase()
            .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}_\-\s]', unicode: true), '')
            .replaceAll(RegExp(r'\s'), '-');
        final count = counts.update(slug, (n) => n + 1, ifAbsent: () => 0);
        if (uri.fragment == title ||
            uri.fragment.toLowerCase() ==
                (count == 0 ? slug : '$slug-$count')) {
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
      widget.onError('此链接指向其他本地文件，请单独导入该文件。');
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
            : IanvsMarkdownView(
                data: widget.contents,
                clipboardWriter: (data) => writeIanvsMarkdownRichClipboard(
                  markdown: data.markdown,
                  html: data.html,
                ),
                showOutline: false,
                headingNavigation: _navigation,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                contentMaxWidth: 720,
                onTapLink: (_, href, _) => unawaited(_openLink(href)),
                diagramBuilder: (context, source) =>
                    DocumentDiagram(source: source, renderer: widget.renderer),
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Row(
          children: [
            const Expanded(child: Text('阅读预览', style: TextStyle(fontSize: 13))),
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
