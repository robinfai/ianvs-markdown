import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/apple_workspace_service.dart';
import '../services/markdown_file_service.dart';
import '../services/markdown_text_codec.dart';
import '../services/workspace_index_source.dart';
import '../models/document_sync_status.dart';
import 'preview_platform.dart';

const previewExtensions = {'.md', '.markdown', '.mdown', '.mkd', '.txt'};
const previewMaximumBytes = 5 * 1024 * 1024;

class PreviewDocument {
  const PreviewDocument({
    required this.path,
    required this.name,
    required this.openedAt,
  });

  final String path;
  final String name;
  final DateTime openedAt;
}

class PreviewWorkspace {
  const PreviewWorkspace({
    required this.path,
    required this.name,
    required this.isCloud,
    this.notice,
    this.workspaceToken,
  });
  factory PreviewWorkspace.fromMap(Map<String, dynamic> map) =>
      PreviewWorkspace(
        path: map['path'] as String,
        name: map['name'] as String,
        isCloud: map['isCloud'] as bool,
        notice: map['notice'] as String?,
        workspaceToken: map['workspaceToken'] as String?,
      );
  final String path;
  final String name;
  final bool isCloud;
  final String? notice;
  final String? workspaceToken;
}

class PreviewLibrary {
  PreviewLibrary({
    Future<Directory> Function()? documentsDirectory,
    this.workspaceService,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;
  final AppleWorkspaceService? workspaceService;
  PreviewWorkspace? _workspace;
  int _workspaceGeneration = 0;
  // One native authority is shared by the preview bridge. Keep its handoffs
  // serialized even when a view/controller is disposed and recreated. Once
  // issued, an activation result must be consumed, not discarded as a read.
  static Future<void>? _selectionTail;
  static int _pendingSelections = 0;
  bool get selectingWorkspace => _pendingSelections != 0;

  Future<T> _selectWorkspace<T>(Future<T> Function() action) {
    ++_pendingSelections;
    final next = _selectionTail == null
        ? Future<T>.sync(action)
        : _selectionTail!.then((_) => action());
    _selectionTail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next.whenComplete(() {
      if (--_pendingSelections == 0) _selectionTail = null;
    });
  }

  PreviewWorkspace? get workspace => _workspace;
  set workspace(PreviewWorkspace? value) {
    _workspace = value;
    ++_workspaceGeneration;
  }

  // Monotonic even when changing A → B → A, unlike a path equality check.
  int get workspaceGeneration => _workspaceGeneration;

  Future<void> _historyWrite = Future.value();

  Future<Directory> _root() async => workspace == null
      ? Directory(p.join((await _documentsDirectory()).path, 'Imports'))
      : Directory(workspace!.path);

  Future<void> useDefaultWorkspace() async {
    if (workspaceService == null) return;
    await _selectWorkspace(() async {
      final result = await PreviewPlatform.channel
          .invokeMapMethod<String, dynamic>('defaultWorkspace');
      if (result == null) {
        throw StateError('The default workspace is unavailable.');
      }
      workspace = PreviewWorkspace.fromMap(result);
    });
  }

  Future<bool> chooseWorkspace() async {
    if (workspaceService == null) return false;
    return _selectWorkspace(() async {
      final result = await PreviewPlatform.channel
          .invokeMapMethod<String, dynamic>('chooseWorkspace');
      if (result == null) return false;
      workspace = PreviewWorkspace.fromMap(result);
      return true;
    });
  }

  Future<Directory> _historyRoot(Directory root) async {
    if (workspaceService == null) return root;
    return Directory(
      p.join((await getApplicationSupportDirectory()).path, 'PreviewHistory'),
    )..createSync(recursive: true);
  }

  String _historyKey(String path, Directory root, bool isCloud) =>
      workspaceService == null
      ? p.relative(path, from: root.path)
      : '${isCloud ? 'icloud' : root.path}/${p.relative(path, from: root.path)}';

  Future<List<PreviewDocument>> list() async {
    final isCloud = workspace?.isCloud == true;
    final root = await _root();
    final history = await _readHistory(await _historyRoot(root));
    if (workspaceService != null) {
      final entries = await workspaceService!.list(root.path, recursive: true);
      return [
        for (final entry in entries)
          PreviewDocument(
            path: entry['path'] as String,
            name: entry['name'] as String,
            openedAt: switch (history[_historyKey(
              entry['path'] as String,
              root,
              isCloud,
            )]) {
              final time? => DateTime.fromMicrosecondsSinceEpoch(time),
              null => DateTime.fromMillisecondsSinceEpoch(
                (entry['modified'] as num).toInt(),
              ),
            },
          ),
      ]..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    }
    if (!await root.exists()) return [];
    final documents = <PreviewDocument>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File ||
          !previewExtensions.contains(p.extension(entity.path).toLowerCase())) {
        continue;
      }
      final stat = await entity.stat();
      documents.add(
        PreviewDocument(
          path: entity.path,
          name: p.basename(entity.path),
          openedAt: history[p.relative(entity.path, from: root.path)] == null
              ? stat.modified
              : DateTime.fromMicrosecondsSinceEpoch(
                  history[p.relative(entity.path, from: root.path)]!,
                ),
        ),
      );
    }
    documents.sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return documents;
  }

  Future<Map<String, int>> _readHistory(Directory root) async {
    final file = File(p.join(root.path, '.recent.json'));
    try {
      if (!await file.exists() || await file.length() > 1024 * 1024) return {};
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return {};
      return {
        for (final entry in json.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      };
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _recordOpen(File file, Directory root, int scope, bool isCloud) {
    final next = _historyWrite.then((_) async {
      if (scope != workspaceGeneration) return;
      final historyRoot = await _historyRoot(root);
      final history = await _readHistory(historyRoot);
      // Relative paths survive iOS changing the application container on update.
      final key = _historyKey(
        file.path,
        Directory(await root.resolveSymbolicLinks()),
        isCloud,
      );
      history[key] = DateTime.now().microsecondsSinceEpoch;
      if (scope != workspaceGeneration) return;
      final target = File(p.join(historyRoot.path, '.recent.json'));
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(jsonEncode(history), flush: true);
      await temporary.rename(target.path);
    });
    // A history write failure must not make an otherwise readable file fail.
    _historyWrite = next.catchError((Object _) {});
    return _historyWrite;
  }

  Future<File> _ownedFile(String path, Directory root) async {
    final file = File(path);
    final resolved = await file.exists()
        ? await file.resolveSymbolicLinks()
        : p.join(await file.parent.resolveSymbolicLinks(), p.basename(path));
    if (!p.isWithin(await root.resolveSymbolicLinks(), resolved) ||
        !previewExtensions.contains(p.extension(resolved).toLowerCase())) {
      throw const FormatException('请从当前文件夹选择文档，或使用“打开文件”导入。');
    }
    return File(resolved);
  }

  /// Metadata-only, scoped to the same already selected folder as content reads.
  /// This never reads text, updates recent history, or requests a download.
  Future<DocumentSyncMetadata> readSyncMetadata(String path) async {
    if (workspaceService == null) return const DocumentSyncMetadata();
    final scope = workspaceGeneration;
    final root = await _root();
    final file = await _ownedFile(path, root);
    if (scope != workspaceGeneration) return const DocumentSyncMetadata();
    return workspaceService!.readSyncMetadata(file.path);
  }

  bool get canWrite =>
      !selectingWorkspace &&
      workspaceService != null &&
      workspace?.workspaceToken != null;

  /// Source is never normalized: BOM, CRLF and Unicode are save baselines.
  Future<String> readSource(String path) =>
      _read(path, recordOpen: false, preserveBom: true);

  String _writeRelative(String path, int generation) {
    final root = workspace?.path;
    if (!canWrite ||
        generation != workspaceGeneration ||
        root == null ||
        !p.isWithin(root, path)) {
      throw const FormatException('文件夹权限已改变，请重新选择；草稿仍保留。');
    }
    final relative = p.relative(path, from: root);
    if (!safeWorkspaceRelativePath(relative) ||
        !previewExtensions.contains(p.extension(relative).toLowerCase())) {
      throw const FormatException('只能编辑当前文件夹内的 Markdown 文档。');
    }
    return relative;
  }

  Future<void> writeSource(
    String path,
    String text, {
    required String? expectedContents,
    required int generation,
  }) async {
    final relative = _writeRelative(path, generation);
    if (utf8.encode(text).length > previewMaximumBytes) {
      throw const FormatException('文档超过 5 MB，草稿未写入原文件。');
    }
    try {
      final success = await AppleWorkspaceService.channel
          .invokeMethod<bool>('writeWorkspaceNoteGuarded', {
            'path': workspace!.path,
            'workspaceToken': workspace!.workspaceToken,
            'relativePath': relative,
            'contentsBytes': Uint8List.fromList(utf8.encode(text)),
            'expectedContentsBytes': expectedContents == null
                ? null
                : Uint8List.fromList(utf8.encode(expectedContents)),
          });
      if (success != true) {
        throw StateError('The native write outcome is unknown.');
      }
    } on PlatformException catch (error) {
      final details = error.details;
      if (error.code == 'workspace_save_conflict' &&
          details is Map &&
          details['path'] == path &&
          details.containsKey('currentContentsBytes') &&
          (details['currentContentsBytes'] == null ||
              details['currentContentsBytes'] is Uint8List)) {
        final bytes = details['currentContentsBytes'] as Uint8List?;
        throw MarkdownSaveConflict(
          path: path,
          expectedContents: expectedContents,
          currentContents: bytes == null ? null : decodeMarkdownUtf8(bytes),
        );
      }
      rethrow;
    }
  }

  /// No parent creation and no replacement. The native boundary uses O_EXCL.
  Future<String> createNote(String relative, {required int generation}) async {
    final root = workspace?.path;
    if (root == null ||
        !safeWorkspaceRelativePath(relative) ||
        !relative.toLowerCase().endsWith('.md')) {
      throw const FormatException('请输入有效的 Markdown 文件名。');
    }
    final path = p.join(root, relative);
    _writeRelative(path, generation);
    final success = await AppleWorkspaceService.channel
        .invokeMethod<bool>('createWorkspaceNote', {
          'path': root,
          'workspaceToken': workspace!.workspaceToken,
          'relativePath': relative,
        });
    if (success != true) {
      throw StateError('The native create outcome is unknown.');
    }
    return path;
  }

  Future<String> read(String path) => _read(path, recordOpen: true);

  /// Refreshes only the selected body, without changing recent-open history.
  Future<String> refreshContent(String path) => _read(path, recordOpen: false);

  Future<String> _read(
    String path, {
    required bool recordOpen,
    bool preserveBom = false,
  }) async {
    final scope = workspaceGeneration;
    final isCloud = workspace?.isCloud == true;
    final root = await _root();
    final file = await _ownedFile(path, root);
    if (scope != workspaceGeneration) {
      throw StateError('The preview workspace changed.');
    }
    if (workspaceService != null) {
      final text = await workspaceService!.read(
        file.path,
        maximumBytes: previewMaximumBytes,
      );
      if (recordOpen) await _recordOpen(file, root, scope, isCloud);
      return !preserveBom && text.startsWith('\uFEFF')
          ? text.substring(1)
          : text;
    }
    // Limit the actual read as well as the metadata, including files changed
    // through Files while they are being opened.
    final input = await file.open();
    try {
      final bytes = await input.read(previewMaximumBytes + 1);
      if (bytes.length > previewMaximumBytes) {
        throw const FormatException('文档超过 5 MB，暂时无法预览。');
      }
      final text = decodeMarkdownUtf8(bytes);
      if (recordOpen) await _recordOpen(file, root, scope, isCloud);
      return !preserveBom && text.startsWith('\uFEFF')
          ? text.substring(1)
          : text;
    } on FormatException catch (error) {
      if (error.message.contains('5 MB')) rethrow;
      throw const FormatException('无法读取文档，请使用 UTF-8 编码的 Markdown 文件。');
    } finally {
      await input.close();
    }
  }
}
