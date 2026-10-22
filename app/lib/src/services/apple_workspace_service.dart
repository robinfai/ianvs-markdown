import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'markdown_text_codec.dart';
import '../models/document_sync_status.dart';

/// Shared native iCloud access for macOS and iOS. Native file coordination also
/// materializes an evicted document before exposing its contents to Dart.
class AppleWorkspaceService implements DocumentSyncSource {
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

  Future<String> read(String path, {int? maximumBytes}) async {
    // StandardMethodCodec decodes Strings with Utf8Decoder, which drops a BOM.
    // Transfer source bytes instead so the read baseline remains exact.
    final bytes = await channel.invokeMethod<Uint8List>('readDocumentBytes', {
      'path': path,
      'maximumBytes': maximumBytes,
    });
    if (bytes == null) throw StateError('The document bytes are unavailable.');
    return decodeMarkdownUtf8(bytes);
  }

  @override
  Future<DocumentSyncMetadata> readSyncMetadata(String path) async {
    try {
      final result = await channel.invokeMapMethod<Object?, Object?>(
        'readDocumentSyncMetadata',
        {'path': path},
      );
      return result == null
          ? const DocumentSyncMetadata()
          : DocumentSyncMetadata.fromMap(result);
    } on MissingPluginException {
      // Older native hosts and providers without this optional capability stay
      // usable. Absence of metadata never implies successful synchronization.
      return const DocumentSyncMetadata();
    }
  }

  Future<void> write(String path, String contents) async {
    await channel.invokeMethod<bool>('writeDocument', {
      'path': path,
      'contents': contents,
    });
  }

  Future<void> writeGuarded(
    String path,
    String contents, {
    required String? expectedContents,
  }) async {
    await channel.invokeMethod<bool>('writeDocumentGuarded', {
      'path': path,
      'contentsBytes': Uint8List.fromList(utf8.encode(contents)),
      'expectedContentsBytes': expectedContents == null
          ? null
          : Uint8List.fromList(utf8.encode(expectedContents)),
    });
  }
}
