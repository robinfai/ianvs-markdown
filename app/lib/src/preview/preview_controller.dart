import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'preview_library.dart';

class PreviewController extends ChangeNotifier {
  PreviewController({required this.library});

  final PreviewLibrary library;
  List<PreviewDocument> documents = [];
  String? activePath;
  String? contents;
  String? error;
  bool busy = false;
  bool initialized = false;
  bool _disposed = false;
  int _request = 0;

  String get title => activePath == null ? 'Linefold' : p.basename(activePath!);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await library.useDefaultWorkspace();
      documents = await library.list();
    } on Object {
      error = '无法载入最近文档，请重新打开文件。';
    }
    initialized = true;
    _notify();
  }

  Future<void> open(String path) async {
    final request = ++_request;
    busy = true;
    error = null;
    _notify();
    try {
      final text = await library.read(path);
      final recent = await library.list();
      if (_disposed || request != _request) return;
      activePath = path;
      contents = text;
      documents = recent;
    } on Object catch (failure) {
      if (_disposed || request != _request) return;
      error = failure is FormatException
          ? failure.message
          : failure is PlatformException
          ? failure.message
          : '无法打开 ${p.basename(path)}，请重新分享或选择文件。';
    } finally {
      if (!_disposed && request == _request) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> receive(List<String> paths) async {
    await library.useDefaultWorkspace();
    final failures = <String>[];
    for (final path in paths) {
      if (_disposed) return;
      await open(path);
      if (error case final message?) {
        failures.add(
          message.contains(p.basename(path))
              ? message
              : '${p.basename(path)}：$message',
        );
      }
    }
    if (failures.isNotEmpty) reportError(failures.join('\n'));
  }

  Future<void> changeWorkspace({bool useCloud = false}) async {
    try {
      if (useCloud) {
        await library.useDefaultWorkspace();
      } else if (!await library.chooseWorkspace()) {
        return;
      }
      showLibrary();
      await refresh();
    } on Object {
      reportError('无法打开文件夹，请重试。');
    }
  }

  Future<void> refresh() async {
    final request = _request;
    try {
      if (library.workspace?.notice != null) {
        await library.useDefaultWorkspace();
      }
      final recent = await library.list();
      if (_disposed || request != _request) return;
      documents = recent;
      _notify();
    } on Object {
      if (!_disposed && request == _request) {
        reportError('无法刷新文档，请检查网络或重新选择文件夹。');
      }
    }
  }

  void showLibrary() {
    ++_request;
    activePath = null;
    contents = null;
    busy = false;
    _notify();
  }

  void reportError(String message) {
    error = message;
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    super.dispose();
  }
}
