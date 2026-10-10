import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/apple_workspace_service.dart';
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
  });
  factory PreviewWorkspace.fromMap(Map<String, dynamic> map) =>
      PreviewWorkspace(
        path: map['path'] as String,
        name: map['name'] as String,
        isCloud: map['isCloud'] as bool,
        notice: map['notice'] as String?,
      );
  final String path;
  final String name;
  final bool isCloud;
  final String? notice;
}

class PreviewLibrary {
  PreviewLibrary({
    Future<Directory> Function()? documentsDirectory,
    this.workspaceService,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;
  final AppleWorkspaceService? workspaceService;
  PreviewWorkspace? workspace;
  Future<void> _historyWrite = Future.value();

  Future<Directory> _root() async => workspace == null
      ? Directory(p.join((await _documentsDirectory()).path, 'Imports'))
      : Directory(workspace!.path);

  Future<void> useDefaultWorkspace() async {
    if (workspaceService == null) return;
    final result = await PreviewPlatform.channel
        .invokeMapMethod<String, dynamic>('defaultWorkspace');
    workspace = PreviewWorkspace.fromMap(result!);
  }

  Future<bool> chooseWorkspace() async {
    if (workspaceService == null) return false;
    final result = await PreviewPlatform.channel
        .invokeMapMethod<String, dynamic>('chooseWorkspace');
    if (result == null) return false;
    workspace = PreviewWorkspace.fromMap(result);
    return true;
  }

  Future<Directory> _historyRoot(Directory root) async {
    if (workspaceService == null) return root;
    return Directory(
      p.join((await getApplicationSupportDirectory()).path, 'PreviewHistory'),
    )..createSync(recursive: true);
  }

  String _historyKey(String path, Directory root) => workspaceService == null
      ? p.relative(path, from: root.path)
      : '${workspace?.isCloud == true ? 'icloud' : root.path}/${p.relative(path, from: root.path)}';

  Future<List<PreviewDocument>> list() async {
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

  Future<void> _recordOpen(File file) {
    final next = _historyWrite.then((_) async {
      final root = await _root();
      final historyRoot = await _historyRoot(root);
      final history = await _readHistory(historyRoot);
      // Relative paths survive iOS changing the application container on update.
      final key = _historyKey(
        file.path,
        Directory(await root.resolveSymbolicLinks()),
      );
      history[key] = DateTime.now().microsecondsSinceEpoch;
      final target = File(p.join(historyRoot.path, '.recent.json'));
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(jsonEncode(history), flush: true);
      await temporary.rename(target.path);
    });
    // A history write failure must not make an otherwise readable file fail.
    _historyWrite = next.catchError((Object _) {});
    return _historyWrite;
  }

  Future<File> _ownedFile(String path) async {
    final root = await _root();
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

  Future<String> read(String path) async {
    final file = await _ownedFile(path);
    if (workspaceService != null) {
      final text = await workspaceService!.read(
        file.path,
        maximumBytes: previewMaximumBytes,
      );
      await _recordOpen(file);
      return text.startsWith('\uFEFF') ? text.substring(1) : text;
    }
    // Limit the actual read as well as the metadata, including files changed
    // through Files while they are being opened.
    final input = await file.open();
    try {
      final bytes = await input.read(previewMaximumBytes + 1);
      if (bytes.length > previewMaximumBytes) {
        throw const FormatException('文档超过 5 MB，暂时无法预览。');
      }
      final text = utf8.decode(bytes);
      await _recordOpen(file);
      return text.startsWith('\uFEFF') ? text.substring(1) : text;
    } on FormatException catch (error) {
      if (error.message.contains('5 MB')) rethrow;
      throw const FormatException('无法读取文档，请使用 UTF-8 编码的 Markdown 文件。');
    } finally {
      await input.close();
    }
  }
}
