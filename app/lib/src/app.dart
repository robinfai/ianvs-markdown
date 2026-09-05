import 'package:flutter/material.dart';
import 'desktop_theme.dart';

import 'controllers/workspace_controller.dart';
import 'services/markdown_file_service.dart';
import 'services/workspace_session_store.dart';
import 'widgets/editor_shell.dart';

class IanvsMarkdownDesktopApp extends StatefulWidget {
  const IanvsMarkdownDesktopApp({super.key, this.workspaceController});

  final WorkspaceController? workspaceController;

  @override
  State<IanvsMarkdownDesktopApp> createState() =>
      _IanvsMarkdownDesktopAppState();
}

class _IanvsMarkdownDesktopAppState extends State<IanvsMarkdownDesktopApp> {
  late final WorkspaceController _workspace =
      widget.workspaceController ??
      WorkspaceController(
        fileService: const DesktopMarkdownFileService(),
        sessionStore: const DesktopWorkspaceSessionStore(),
      );
  var _dark = false;

  @override
  void initState() {
    super.initState();
    _workspace.initialize();
  }

  @override
  void dispose() {
    if (widget.workspaceController == null) _workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ianvs Markdown',
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: desktopTheme(Brightness.light),
      darkTheme: desktopTheme(Brightness.dark),
      home: EditorShell(
        workspace: _workspace,
        dark: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }
}
