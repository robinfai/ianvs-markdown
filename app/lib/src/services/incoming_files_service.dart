import 'dart:io';

import 'package:flutter/services.dart';

typedef OpenIncomingFiles = Future<void> Function(List<String> paths);

abstract class IncomingFilesService {
  Future<void> start(OpenIncomingFiles onOpen);
  void dispose();
}

/// macOS queues Finder open requests until workspace recovery has completed.
class MacOSIncomingFilesService implements IncomingFilesService {
  static const channel = MethodChannel('work.ianvs.linefold/open_files');
  bool _disposed = false;
  Future<void> _pending = Future<void>.value();

  @override
  Future<void> start(OpenIncomingFiles onOpen) async {
    if (!Platform.isMacOS || _disposed) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'filesAvailable') await _drain(onOpen);
    });
    try {
      await _drain(onOpen);
    } on MissingPluginException {
      // The platform bridge is absent on other hosts and in widget tests.
    }
  }

  Future<void> _drain(OpenIncomingFiles onOpen) {
    final next = _pending.then((_) async {
      if (_disposed) return;
      final paths = await channel.invokeListMethod<String>('takePendingFiles');
      if (!_disposed && paths != null && paths.isNotEmpty) await onOpen(paths);
    });
    // One failed request must not prevent subsequent Finder opens.
    _pending = next.catchError((Object _) {});
    return next;
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
  }
}
