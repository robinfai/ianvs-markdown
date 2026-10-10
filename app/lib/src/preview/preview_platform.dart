import 'dart:async';

import 'package:flutter/services.dart';

typedef PreviewDelivery = Future<void> Function(List<String> paths);

class PreviewPlatform {
  static const channel = MethodChannel('work.ianvs.linefold/preview');
  Future<void> _pending = Future.value();
  bool _disposed = false;
  PreviewDelivery? _onFiles;
  void Function(String)? _onError;

  Future<void> start(
    PreviewDelivery onFiles,
    void Function(String) onError,
  ) async {
    _onFiles = onFiles;
    _onError = onError;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'filesAvailable') await refresh();
    });
    await refresh();
  }

  Future<void> refresh() {
    final next = _pending.then((_) async {
      if (_disposed) return;
      final result = await channel.invokeMapMethod<String, dynamic>(
        'takePendingFiles',
      );
      if (_disposed || result == null) return;
      final paths = List<String>.from(result['paths'] as List? ?? const []);
      if (paths.isNotEmpty) await _onFiles?.call(paths);
      if (_disposed) return;
      for (final error in result['errors'] as List? ?? const []) {
        _onError?.call(error.toString());
      }
    });
    _pending = next.catchError((Object error) {
      if (!_disposed) _onError?.call('接收文档失败：$error');
    });
    return _pending;
  }

  Future<void> chooseFiles() => channel.invokeMethod<void>('chooseFiles');

  Future<void> openExternal(Uri uri) =>
      channel.invokeMethod<void>('openExternal', uri.toString());

  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
  }
}
