import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'markdown_text_codec.dart';
import 'package:path/path.dart' as p;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'attachment_import_service.dart';
import 'attachment_resolver.dart';

import '../preview/preview_library.dart';
import '../preview/preview_platform.dart';
import 'apple_workspace_service.dart';
import 'markdown_file_service.dart';
import 'workspace_index_source.dart';

/// Uses the iOS picker and its native workspace capability for guarded writes.
class MobileMarkdownFileService extends DesktopMarkdownFileService
    implements WorkspaceOperationFolderPicker, WorkspaceDisplaySource {
  MobileMarkdownFileService() : super(workspace: const AppleWorkspaceService());

  final library = PreviewLibrary(
    workspaceService: const AppleWorkspaceService(),
  );
  Future<String?> Function(String)? requestName;
  late final indexSource = MobileWorkspaceIndexSource(library);

  Future<String> defaultDirectory() async {
    if (kDebugMode && const bool.fromEnvironment('LINEFOLD_SIMULATOR_QA')) {
      final fixture = await PreviewPlatform.channel
          .invokeMapMethod<String, dynamic>('prepareSimulatorAudit');
      library.workspace = PreviewWorkspace.fromMap(fixture!);
    } else {
      await library.useDefaultWorkspace();
    }
    return AppleWorkspaceService.defaultPath = library.workspace!.path;
  }

  final _refreshes = StreamController<void>.broadcast();
  void refreshExternalChanges() => _refreshes.add(null);

  @override
  Stream<FileSystemEvent> watchDirectory(String path) => Stream.multi((events) {
    void changed(void _) => events.add(FileSystemModifyEvent(path, true, true));
    final native = const AppleWorkspaceService().changes.listen(changed);
    final resumed = _refreshes.stream.listen(changed);
    events.onCancel = () async {
      await native.cancel();
      await resumed.cancel();
    };
  });

  @override
  String? workspaceName(String path) =>
      library.workspace?.path == path ? library.workspace?.name : null;
  @override
  bool isCloudPath(String path) =>
      library.workspace?.path == path && library.workspace?.isCloud == true;

  @override
  Future<List<String>> chooseMarkdownFiles() async {
    // Imported documents arrive through the native pending-file queue.
    await PreviewPlatform.channel.invokeMethod<void>('chooseFiles');
    return [];
  }

  @override
  Future<String?> chooseWorkspaceFolder() async =>
      await library.chooseWorkspace() ? library.workspace!.path : null;

  final _operationGrants = <String, String>{};
  @override
  Future<String?> chooseOperationFolder() async {
    final result = await PreviewPlatform.channel
        .invokeMapMethod<String, dynamic>('chooseOperationFolder');
    if (result == null) return null;
    _operationGrants[result['path'] as String] =
        result['workspaceToken'] as String;
    return result['path'] as String;
  }

  ({String root, String token}) scopeForDocument(String path) =>
      _scopeFor(path);

  ({String root, String token}) _scopeFor(String path) {
    final selected = library.workspace;
    if (library.canWrite &&
        selected != null &&
        p.isWithin(selected.path, path)) {
      return (root: selected.path, token: selected.workspaceToken!);
    }
    final roots =
        _operationGrants.keys.where((root) => p.isWithin(root, path)).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    if (roots.isEmpty) throw StateError('请重新选择文件所在的文件夹；文件未修改。');
    return (root: roots.first, token: _operationGrants[roots.first]!);
  }

  @override
  Future<String?> chooseSavePath(String suggestedName) async {
    final root = library.workspace?.path;
    if (root == null || !library.canWrite) {
      throw StateError('请先选择可写入的工作区；草稿仍保留。');
    }
    final name = await requestName?.call(suggestedName);
    if (name == null) return null;
    if (name.trim().isEmpty ||
        name != p.basename(name) ||
        name.contains('\\')) {
      throw const FormatException('请输入有效的文件名。');
    }
    return p.join(root, name.endsWith('.md') ? name : '$name.md');
  }

  @override
  Future<void> writeMarkdownFileGuarded(
    String path,
    String contents, {
    required String? expectedContents,
  }) async {
    final scope = _scopeFor(path);
    try {
      final result = await AppleWorkspaceService.channel
          .invokeMethod<bool>('writeWorkspaceNoteGuarded', {
            'path': scope.root,
            'workspaceToken': scope.token,
            'relativePath': p.relative(path, from: scope.root),
            'contentsBytes': Uint8List.fromList(utf8.encode(contents)),
            'expectedContentsBytes': expectedContents == null
                ? null
                : Uint8List.fromList(utf8.encode(expectedContents)),
          });
      if (result != true) throw StateError('无法确认保存结果；草稿仍保留。');
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

  @override
  Future<void> createEntry(
    String path, {
    required bool directory,
    String contents = '',
  }) async {
    if (directory) {
      await _manage('createDirectory', path);
      return;
    }
    await writeMarkdownFileGuarded(path, contents, expectedContents: null);
  }

  Future<void> _manage(
    String operation,
    String path, {
    String? destination,
  }) async {
    final source = _scopeFor(path);
    final target = destination == null ? source : _scopeFor(destination);
    final completed = await AppleWorkspaceService.channel.invokeMethod<bool>(
      'manageWorkspaceEntry',
      {
        'path': source.root,
        'workspaceToken': source.token,
        'operation': operation,
        'relativePath': p.relative(path, from: source.root),
        if (destination != null) ...{
          'destination': p.relative(destination, from: target.root),
          'destinationRoot': target.root,
          'destinationToken': target.token,
        },
      },
    );
    if (completed != true) throw StateError('无法确认操作结果，请刷新目录后检查。');
  }

  @override
  Future<void> moveEntry(String source, String destination) =>
      _manage('move', source, destination: destination);
  @override
  Future<void> copyEntry(String source, String destination) =>
      _manage('copy', source, destination: destination);
  @override
  Future<void> trashEntry(String path) async {
    // iOS trashItem can create a hidden .Trash without registering it with
    // Files' Recently Deleted provider. Keep recovery inside the granted root
    // and visible in our browser instead; restore uses the ordinary move flow.
    final scope = _scopeFor(path);
    final recovery = p.join(scope.root, '最近删除');
    if (path == recovery || p.isWithin(recovery, path)) {
      throw StateError('项目已在最近删除中；可选择“Move to…”恢复到其他目录。');
    }
    if (!await Directory(recovery).exists()) {
      await _manage('createDirectory', recovery);
    }
    final suffix = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll('T', ' ')
        .replaceAll(':', '-');
    final bucket = p.join(recovery, '$timestamp-$suffix');
    await _manage('createDirectory', bucket);
    await _manage('move', path, destination: p.join(bucket, p.basename(path)));
    refreshExternalChanges();
  }

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    // Never downgrade mobile writes to an unguarded absolute-path operation.
    throw UnsupportedError('Use guarded workspace writes on iOS.');
  }
}

class MobileWorkspaceIndexSource extends AppleWorkspaceIndexSource {
  MobileWorkspaceIndexSource(this.library);
  final PreviewLibrary library;

  @override
  Future<void> createWorkspaceNote(String root, String relativePath) async {
    if (root != library.workspace?.path) {
      throw StateError('工作区已改变，请重新选择。');
    }
    await library.createNote(
      relativePath,
      generation: library.workspaceGeneration,
    );
  }
}

class MobileAttachmentImportPlatform extends AppleAttachmentImportPlatform {
  MobileAttachmentImportPlatform(this.library);
  final PreviewLibrary library;

  @override
  Future<AttachmentImportPayload?> pickImage() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', uniformTypeIdentifiers: ['public.image']),
      ],
    );
    if (file == null) return null;
    if (await file.length() > attachmentMaximumBytes) {
      throw const AttachmentImportFailure('图片超过大小限制。');
    }
    return AttachmentImportPayload(await file.readAsBytes());
  }

  @override
  Future<AttachmentImportPayload?> readClipboardImage() async {
    final bytes = await PreviewPlatform.channel.invokeMethod<Uint8List>(
      'clipboardImage',
    );
    return bytes == null ? null : AttachmentImportPayload(bytes);
  }

  @override
  Future<String> create({
    required String root,
    required String relativeDirectory,
    required String filename,
    required Uint8List bytes,
  }) async {
    if (!library.canWrite || library.workspace?.path != root) {
      throw const AttachmentImportFailure('工作区权限已改变，请重新选择。');
    }
    final result = await AppleWorkspaceService.channel
        .invokeMapMethod<String, dynamic>('createWorkspaceAttachment', {
          'path': root,
          'workspaceToken': library.workspace!.workspaceToken,
          'relativeDirectory': relativeDirectory,
          'filename': filename,
          'bytes': bytes,
        });
    final expected = relativeDirectory.isEmpty
        ? filename
        : '$relativeDirectory/$filename';
    if (result?['relativePath'] != expected) {
      throw const AttachmentImportFailure('无法确认图片保存结果，请检查附件目录。');
    }
    return expected;
  }
}
