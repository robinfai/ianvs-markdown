import 'app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'widgets/finder_preview_settings.dart';
import 'dart:async';
import 'dart:io';

import 'services/mobile_markdown_file_service.dart';
import 'services/attachment_import_service.dart';
import 'preview/preview_platform.dart';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'desktop_theme.dart';

import 'controllers/file_association_controller.dart';
import 'controllers/workspace_controller.dart';
import 'local_performance.dart';
import 'services/file_association_service.dart';
import 'services/incoming_files_service.dart';
import 'services/markdown_file_service.dart';
import 'services/workspace_session_store.dart';
import 'services/apple_workspace_service.dart';
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
  late final _performanceFiles = LocalPerformanceFiles();
  final _mobileFiles = MobileMarkdownFileService();
  final _mobileIncoming = PreviewPlatform();
  late final WorkspaceController _workspace =
      widget.workspaceController ??
      (localPerformanceEnabled
          ? localPerformanceWorkspace(_performanceFiles)
          : WorkspaceController(
              fileService: Platform.isIOS
                  ? _mobileFiles
                  : const DesktopMarkdownFileService(
                      workspace: AppleWorkspaceService(),
                    ),
              welcomeText: Platform.isIOS
                  ? mobileWelcomeMarkdown
                  : welcomeMarkdown,
              indexSource: Platform.isIOS ? _mobileFiles.indexSource : null,
              sessionStore: const DesktopWorkspaceSessionStore(),
              defaultWorkspaceDirectory: Platform.isIOS
                  ? _mobileFiles.defaultDirectory
                  : const AppleWorkspaceService().defaultDirectory,
            ));
  late final FileAssociationController _fileAssociation =
      widget.fileAssociationController ??
      FileAssociationController(service: const MacOSFileAssociationService());
  late final IncomingFilesService _incomingFiles =
      widget.incomingFilesService ?? MacOSIncomingFilesService();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  var _themeMode = localPerformanceEnabled ? ThemeMode.light : ThemeMode.system;
  var _settingsOpen = false;
  var _promptOpen = false;
  StreamSubscription<void>? _cloudChanges;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mobileFiles.requestName = _requestMobileName;
    if (widget.workspaceController == null && !localPerformanceEnabled) {
      _cloudChanges = const AppleWorkspaceService().changes.listen((_) {
        if (_workspace.initialized) {
          _workspace.sync.scheduleRefresh();
          if (_workspace.isCloudWorkspace) {
            unawaited(_workspace.browser.refresh());
          }
        }
      });
    }
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _workspace.initialize();
    if (!mounted || localPerformanceEnabled || !_workspace.initialized) return;
    try {
      if (Platform.isIOS) {
        await _mobileIncoming.start(_openIncomingFiles, _showError);
      } else {
        await _incomingFiles.start(_openIncomingFiles);
      }
    } on Object catch (error) {
      _showError('Unable to receive files from Finder: $error');
    }
    if (!mounted) return;
    await _fileAssociation.initialize();
    if (!mounted) return;
    if (!_fileAssociation.needsPrompt) {
      await offerFinderPreviewSetup(_navigatorKey.currentContext!);
      return;
    }
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
    if (mounted) await offerFinderPreviewSetup(_navigatorKey.currentContext!);
  }

  Future<String?> _requestMobileName(String name) async {
    final input = TextEditingController(text: name);
    try {
      return await showDialog<String>(
        context: _navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('保存文档'),
          content: TextField(
            controller: input,
            autofocus: true,
            decoration: const InputDecoration(labelText: '文件名'),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, input.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      // The dialog's exit animation can still reference its controller.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      input.dispose();
    }
  }

  Future<void> _openIncomingFiles(List<String> paths) async {
    if (Platform.isIOS && paths.isNotEmpty) {
      await _workspace.useDefaultWorkspace();
    }
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
      // Reading controls must remain available while the OS association query
      // is pending. The dialog listens to the controller for the later result.
      unawaited(_fileAssociation.refresh());
      await showDialog<void>(
        context: _navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (_) => AppSettingsDialog(
          fileAssociation: _fileAssociation,
          workspace: _workspace,
        ),
      );
    } finally {
      _settingsOpen = false;
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    try {
      await _workspace.flushSession();
      return AppExitResponse.exit;
    } on Object catch (error) {
      _showError('Unable to save recovery. Linefold remains open: $error');
      return AppExitResponse.cancel;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(
        _workspace.flushSession().catchError((Object error) {
          _showError('Unable to save recovery: $error');
        }),
      );
    }
    if (state == AppLifecycleState.resumed && _fileAssociation.initialized) {
      if (Platform.isIOS) _mobileFiles.refreshExternalChanges();
      unawaited(_fileAssociation.refresh());
      _workspace.sync.scheduleRefresh();
      if (_workspace.isCloudWorkspace) unawaited(_workspace.browser.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isIOS) _mobileIncoming.dispose();
    _incomingFiles.dispose();
    _cloudChanges?.cancel();
    if (widget.fileAssociationController == null) _fileAssociation.dispose();
    if (widget.workspaceController == null) _workspace.dispose();
    super.dispose();
  }

  Widget _withPerformance(Widget child) => localPerformanceEnabled
      ? LocalPerformancePanel(
          host: localPerformanceHost(_workspace, _performanceFiles),
          child: child,
        )
      : child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Linefold',
      supportedLocales: appSupportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      localeListResolutionCallback: resolveAppLocale,
      builder: (context, child) => IanvsMarkdownLocalization(
        strings: Localizations.localeOf(context).languageCode == 'zh'
            ? const IanvsMarkdownStrings.chinese()
            : const IanvsMarkdownStrings.english(),
        child: child!,
      ),
      themeMode: _themeMode,
      theme: desktopTheme(
        Brightness.light,
        platform: Platform.isIOS ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      darkTheme: desktopTheme(
        Brightness.dark,
        platform: Platform.isIOS ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      // Isolate editor semantics when modal routes block and reveal the document.
      home: Builder(
        builder: (context) => Semantics(
          container: true,
          explicitChildNodes: true,
          child: _withPerformance(
            EditorShell(
              workspace: _workspace,
              attachmentImportPlatform: Platform.isIOS
                  ? MobileAttachmentImportPlatform(_mobileFiles.library)
                  : const AppleAttachmentImportPlatform(),
              onRetryInitialization: _initialize,
              dark: Theme.of(context).brightness == Brightness.dark,
              onToggleTheme: () => setState(
                () =>
                    _themeMode = Theme.of(context).brightness == Brightness.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
              ),
              onUseSystemTheme: () =>
                  setState(() => _themeMode = ThemeMode.system),
              onOpenSettings: _openSettings,
            ),
          ),
        ),
      ),
    );
  }
}
