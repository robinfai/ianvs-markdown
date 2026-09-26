import 'dart:async';

import 'package:flutter/material.dart';
import 'desktop_theme.dart';

import 'controllers/file_association_controller.dart';
import 'controllers/workspace_controller.dart';
import 'services/file_association_service.dart';
import 'services/incoming_files_service.dart';
import 'services/markdown_file_service.dart';
import 'services/workspace_session_store.dart';
import 'widgets/app_settings_dialog.dart';
import 'widgets/editor_shell.dart';

class LinefoldApp extends StatefulWidget {
  const LinefoldApp({
    super.key,
    this.workspaceController,
    this.fileAssociationController,
    this.incomingFilesService,
  });

  final WorkspaceController? workspaceController;
  final FileAssociationController? fileAssociationController;
  final IncomingFilesService? incomingFilesService;

  @override
  State<LinefoldApp> createState() => _LinefoldAppState();
}

class _LinefoldAppState extends State<LinefoldApp> with WidgetsBindingObserver {
  late final WorkspaceController _workspace =
      widget.workspaceController ??
      WorkspaceController(
        fileService: const DesktopMarkdownFileService(),
        sessionStore: const DesktopWorkspaceSessionStore(),
      );
  late final FileAssociationController _fileAssociation =
      widget.fileAssociationController ??
      FileAssociationController(service: const MacOSFileAssociationService());
  late final IncomingFilesService _incomingFiles =
      widget.incomingFilesService ?? MacOSIncomingFilesService();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  var _dark = false;
  var _settingsOpen = false;
  var _promptOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _workspace.initialize();
    if (!mounted) return;
    try {
      await _incomingFiles.start(_openIncomingFiles);
    } on Object catch (error) {
      _showError('Unable to receive files from Finder: $error');
    }
    if (!mounted) return;
    await _fileAssociation.initialize();
    if (!mounted || !_fileAssociation.needsPrompt) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _settingsOpen) return;
    _promptOpen = true;
    final choice = await showDialog<bool>(
      context: _navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (_) =>
          DefaultMarkdownAppPrompt(fileAssociation: _fileAssociation),
    );
    if (!mounted) return;
    // Dismissing with Escape records the same choice as Keep Current App.
    final saved = await _fileAssociation.setPreference(choice ?? false);
    _promptOpen = false;
    if (mounted && !saved) await _openSettings();
  }

  Future<void> _openIncomingFiles(List<String> paths) async {
    for (final path in paths) {
      if (!mounted) return;
      try {
        await _workspace.openPaths([path]);
      } on Object catch (error) {
        _showError('Unable to open $path: $error');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), showCloseIcon: true),
    );
  }

  Future<void> _openSettings() async {
    if (_settingsOpen || _promptOpen) return;
    _settingsOpen = true;
    try {
      await _fileAssociation.refresh();
      if (!mounted) return;
      await showDialog<void>(
        context: _navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (_) => AppSettingsDialog(fileAssociation: _fileAssociation),
      );
    } finally {
      _settingsOpen = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _fileAssociation.initialized) {
      unawaited(_fileAssociation.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingFiles.dispose();
    if (widget.fileAssociationController == null) _fileAssociation.dispose();
    if (widget.workspaceController == null) _workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Linefold',
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: desktopTheme(Brightness.light),
      darkTheme: desktopTheme(Brightness.dark),
      // Isolate editor semantics when modal routes block and reveal the document.
      home: Semantics(
        container: true,
        explicitChildNodes: true,
        child: EditorShell(
          workspace: _workspace,
          dark: _dark,
          onToggleTheme: () => setState(() => _dark = !_dark),
          onOpenSettings: _openSettings,
        ),
      ),
    );
  }
}
