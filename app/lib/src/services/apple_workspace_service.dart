import 'dart:async';

import 'package:flutter/services.dart';

/// Shared native iCloud access for macOS and iOS. Native file coordination also
/// materializes an evicted document before exposing its contents to Dart.
class AppleWorkspaceService {
  const AppleWorkspaceService();

  static const channel = MethodChannel('work.ianvs.linefold/workspace');
  static final _changes = StreamController<void>.broadcast();
  static bool _listening = false;
  static String? defaultPath;

  Stream<void> get changes {
    if (!_listening) {
      _listening = true;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'workspaceChanged') _changes.add(null);
      });
    }
    return _changes.stream;
  }

  Future<String> defaultDirectory() async {
    final path = await channel.invokeMethod<String>('defaultDirectory');
    if (path == null) throw StateError('iCloud Drive 暂不可用。');
    defaultPath = path;
    return path;
  }

  Future<List<Map<String, dynamic>>> list(
    String path, {
    bool recursive = false,
  }) async {
    final entries = await channel.invokeListMethod<dynamic>('listDirectory', {
      'path': path,
      'recursive': recursive,
    });
    return [
      for (final entry in entries ?? [])
        Map<String, dynamic>.from(entry as Map),
    ];
  }

  Future<String> read(String path, {int? maximumBytes}) async =>
      (await channel.invokeMethod<String>('readDocument', {
        'path': path,
        'maximumBytes': maximumBytes,
      }))!;

  Future<void> write(String path, String contents) async {
    await channel.invokeMethod<bool>('writeDocument', {
      'path': path,
      'contents': contents,
    });
  }
}
