import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'preview_library.dart';
import '../controllers/document_sync_controller.dart';

class PreviewController extends ChangeNotifier {
  PreviewController({
    required this.library,
    this.operationTimeout = const Duration(seconds: 15),
    this.cloudRefreshInterval = const Duration(milliseconds: 500),
  }) {
    sync = DocumentSyncController(
      canRead: library.workspaceService != null,
      read: library.readSyncMetadata,
    );
  }

  late final DocumentSyncController sync;

  final PreviewLibrary library;
  final Duration operationTimeout;
  final Duration cloudRefreshInterval;
  List<PreviewDocument> documents = [];
  String? activePath;
  String? activeRoot;
  int? activeWorkspaceGeneration;
  String? contents;
  String? error;
  bool busy = false;
  bool initialized = false;
  bool _disposed = false;
  bool _navigating = false;
  int _request = 0;
  Object? _refreshToken;
  Future<void>? _refreshFuture;
  Future<void> Function()? _retry;
  Timer? _cloudTimer;
  bool _cloudRefreshPending = false;

  String get title => activePath == null ? 'Linefold' : p.basename(activePath!);
  bool get canRetry => _retry != null && !busy;

  void _notify() {
    if (_disposed) return;
    sync.configure(
      path: activeRoot == library.workspace?.path ? activePath : null,
      identity: (activeRoot, library.workspaceGeneration, activePath),
    );
    notifyListeners();
  }

  bool _current(int request, [int? scope]) =>
      !_disposed &&
      request == _request &&
      (scope == null || scope == library.workspaceGeneration);

  int _beginIntent() {
    library.invalidateWorkspaceRequests();
    _refreshToken = null;
    _refreshFuture = null;
    _cloudTimer?.cancel();
    _cloudTimer = null;
    _cloudRefreshPending = false;
    _navigating = false;
    busy = false;
    _retry = null;
    return ++_request;
  }

  Future<T> _bounded<T>(Future<T> future) => future.timeout(operationTimeout);

  Future<void> initialize() async {
    final request = _beginIntent();
    error = null;
    _navigating = true;
    try {
      await _bounded(library.useDefaultWorkspace());
      if (!_current(request)) return;
      final scope = library.workspaceGeneration;
      final recent = await _bounded(library.list());
      if (_current(request, scope)) documents = recent;
    } on Object {
      if (_current(request)) {
        library.invalidateWorkspaceRequests();
        error = '无法载入最近文档，请重新打开文件。';
        _retry = initialize;
      }
    } finally {
      if (!_disposed) {
        initialized = true;
        if (_current(request)) _navigating = false;
        _notify();
        _scheduleCloudRefresh();
      }
    }
  }

  Future<void> open(String path) async {
    final request = _beginIntent();
    await _open(path, request);
  }

  Future<void> _open(String path, int request) async {
    if (!_current(request)) return;
    final scope = library.workspaceGeneration;
    final root = library.workspace?.path;
    _navigating = true;
    busy = true;
    error = null;
    _retry = null;
    _notify();
    try {
      final text = await _bounded(library.read(path));
      if (!_current(request, scope)) return;
      activePath = path;
      activeRoot = root;
      activeWorkspaceGeneration = scope;
      contents = text;
      _notify();
      final recent = await _bounded(library.list());
      if (_current(request, scope)) documents = recent;
    } on Object catch (failure) {
      if (!_current(request, scope)) return;
      error = _readError(failure, path);
      _retry = () => open(path);
    } finally {
      if (_current(request)) {
        _navigating = false;
        busy = false;
        _notify();
        _scheduleCloudRefresh();
      }
    }
  }

  String _readError(Object failure, String path) => failure is TimeoutException
      ? '读取 ${p.basename(path)} 超时，已保留当前内容，请重试。'
      : failure is FormatException
      ? failure.message
      : failure is PlatformException && failure.message != null
      ? failure.message!
      : '无法打开 ${p.basename(path)}，请重新分享或选择文件。';

  Future<void> receive(List<String> paths) async {
    if (paths.isEmpty || _disposed) return;
    final request = _beginIntent();
    _navigating = true;
    busy = true;
    _notify();
    try {
      await _bounded(library.useDefaultWorkspace());
      if (!_current(request)) return;
      final scope = library.workspaceGeneration;
      final failures = <String>[];
      for (final path in paths) {
        if (!_current(request, scope)) return;
        await _open(path, request);
        if (!_current(request, scope)) return;
        if (error case final message?) {
          failures.add(
            message.contains(p.basename(path))
                ? message
                : '${p.basename(path)}：$message',
          );
        }
      }
      if (failures.isNotEmpty) reportError(failures.join('\n'));
    } on Object {
      if (_current(request)) {
        library.invalidateWorkspaceRequests();
        reportError('无法打开共享文件，请重试。');
        _retry = () => receive(paths);
      }
    } finally {
      if (_current(request)) {
        _navigating = false;
        busy = false;
        _notify();
        _scheduleCloudRefresh();
      }
    }
  }

  Future<void> changeWorkspace({bool useCloud = false}) async {
    final request = _beginIntent();
    _navigating = true;
    _notify();
    try {
      if (useCloud) {
        await _bounded(library.useDefaultWorkspace());
      } else if (!await library.chooseWorkspace()) {
        return;
      }
      if (!_current(request)) return;
      activePath = null;
      activeRoot = null;
      activeWorkspaceGeneration = null;
      contents = null;
      documents = [];
      error = null;
      _navigating = false;
      await refresh();
    } on Object {
      if (_current(request)) {
        library.invalidateWorkspaceRequests();
        reportError('无法打开文件夹，请重试。');
        _retry = () => changeWorkspace(useCloud: useCloud);
      }
    } finally {
      if (_current(request)) {
        _navigating = false;
        _notify();
        _scheduleCloudRefresh();
      }
    }
  }

  /// A burst of native notifications produces at most one pending refresh.
  /// Only the selected document is read; listing never downloads other notes.
  void notifyCloudChange() {
    if (_disposed) return;
    sync.scheduleRefresh();
    _cloudRefreshPending = true;
    _scheduleCloudRefresh();
  }

  void _scheduleCloudRefresh() {
    if (_disposed ||
        !_cloudRefreshPending ||
        _cloudTimer != null ||
        _navigating ||
        _refreshFuture != null) {
      return;
    }
    _cloudTimer = Timer(cloudRefreshInterval, () {
      _cloudTimer = null;
      if (_disposed || !_cloudRefreshPending) return;
      if (_navigating || _refreshFuture != null) return;
      _cloudRefreshPending = false;
      unawaited(refresh());
    });
  }

  Future<void> refresh() {
    if (_disposed || _navigating) return Future.value();
    sync.scheduleRefresh();
    if (_refreshFuture case final pending?) return pending;
    _cloudTimer?.cancel();
    _cloudTimer = null;
    _cloudRefreshPending = false;
    final token = Object();
    _refreshToken = token;
    busy = true;
    error = null;
    _retry = null;
    _notify();
    final future = _refresh(token, _request);
    _refreshFuture = future;
    return future;
  }

  Future<void> _refresh(Object token, int request) async {
    var scope = library.workspaceGeneration;
    final path = activePath;
    bool current() =>
        _current(request, scope) && identical(_refreshToken, token);
    try {
      // A fallback root may recover only while displaying the library. Changing
      // roots under an active reader must not reinterpret its existing path.
      if (path == null && library.workspace?.notice != null) {
        await _bounded(library.useDefaultWorkspace());
        if (!_current(request) || !identical(_refreshToken, token)) return;
        scope = library.workspaceGeneration;
      }
      final failures = <String>[];
      void failed(String target, Object failure) {
        if (!current()) return;
        final reason = failure is TimeoutException
            ? '刷新超时'
            : failure is PlatformException && failure.code == 'workspace_busy'
            ? '读取繁忙'
            : '刷新失败';
        failures.add('$target$reason');
        error = '${failures.join('；')}，已保留当前内容，请稍后重试。';
        _retry = refresh;
        _notify();
      }

      Future<void> refreshBody() async {
        try {
          final text = await _bounded(library.refreshContent(path!));
          if (!current()) return;
          contents = text;
          _notify();
        } on Object catch (failure) {
          failed('正文', failure);
        }
      }

      Future<void> refreshList() async {
        try {
          final recent = await _bounded(library.list());
          if (!current()) return;
          documents = recent;
          _notify();
        } on Object catch (failure) {
          failed('列表', failure);
        }
      }

      // A missing/offline active note must not hide new library entries, and a
      // slow folder listing must not delay a readable active note. Each result
      // has the same scope fence but its own deadline and failure boundary.
      await Future.wait([if (path != null) refreshBody(), refreshList()]);
    } on Object catch (failure) {
      if (!current()) return;
      library.invalidateWorkspaceRequests();
      error = failure is TimeoutException
          ? '刷新超时，已保留当前内容，请重试。'
          : '无法刷新文档，已保留当前内容，请检查网络或重新选择文件夹。';
      _retry = refresh;
    } finally {
      if (!_disposed && identical(_refreshToken, token)) {
        _refreshToken = null;
        _refreshFuture = null;
        busy = false;
        _notify();
        _scheduleCloudRefresh();
      }
    }
  }

  Future<void> retry() async {
    if (canRetry) await _retry!();
  }

  /// Invalidates Dart results, not native reads or picker side effects.
  void cancelPendingOperation() {
    sync.invalidate();
    _beginIntent();
    _notify();
  }

  void showLibrary() {
    _beginIntent();
    activePath = null;
    activeRoot = null;
    activeWorkspaceGeneration = null;
    contents = null;
    error = null;
    _notify();
  }

  void reportError(String message) {
    if (_disposed) return;
    error = message;
    _notify();
  }

  void clearError() {
    error = null;
    _retry = null;
    _notify();
  }

  @override
  void dispose() {
    _beginIntent();
    _disposed = true;
    sync.dispose();
    super.dispose();
  }
}
