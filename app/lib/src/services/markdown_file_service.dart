import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'apple_workspace_service.dart';
import 'markdown_text_codec.dart';
import '../models/document_sync_status.dart';

const markdownTypeGroup = XTypeGroup(
  label: 'Markdown',
  extensions: <String>['md', 'markdown', 'mdown', 'mkd', 'txt'],
);

class MarkdownFileData {
  const MarkdownFileData({
    required this.path,
    required this.name,
    required this.contents,
    this.encoding = 'UTF-8',
    this.lineEnding = 'LF',
  });

  final String path;
  final String name;
  final String contents;
  final String encoding;
  final String lineEnding;
}

class WorkspaceEntry {
  const WorkspaceEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.modified,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final DateTime? modified;
}

abstract class MarkdownFileService {
  Future<List<String>> chooseMarkdownFiles();

  Future<String?> chooseSavePath(String suggestedName);

  Future<String?> chooseWorkspaceFolder();

  Future<MarkdownFileData> readMarkdownFile(String path);

  Future<void> writeMarkdownFileAtomic(String path, String contents);

  Future<List<WorkspaceEntry>> listDirectory(String path);

  Stream<FileSystemEvent> watchDirectory(String path);

  Future<String?> createPersistentAccessToken(String path);

  Future<String?> restorePersistentAccess(String token);

  bool fileExists(String path);

  Future<void> createEntry(
    String path, {
    required bool directory,
    String contents = '',
  });
  Future<void> moveEntry(String source, String destination);
  Future<void> copyEntry(String source, String destination);
  Future<void> trashEntry(String path);
  Future<bool> entryExists(String path);
  Future<DateTime?> readModifiedTime(String path);
}

/// Optional save capability for services that can check the destination at the
/// write boundary. A null baseline means that the destination must not exist.
abstract class GuardedMarkdownFileService {
  Future<void> writeMarkdownFileGuarded(
    String path,
    String contents, {
    required String? expectedContents,
  });
}

/// A verified change to the destination, not a read or permission failure.
/// A null [currentContents] means that the destination has been removed.
class MarkdownSaveConflict implements Exception {
  const MarkdownSaveConflict({
    required this.path,
    required this.expectedContents,
    required this.currentContents,
  });

  final String path;
  final String? expectedContents;
  final String? currentContents;

  @override
  String toString() => 'The file changed on disk: $path';
}

class DesktopMarkdownFileService
    implements
        MarkdownFileService,
        GuardedMarkdownFileService,
        DocumentSyncSource {
  const DesktopMarkdownFileService({this.workspace});

  final AppleWorkspaceService? workspace;

  @override
  Future<DocumentSyncMetadata> readSyncMetadata(String path) async =>
      workspace == null
      ? const DocumentSyncMetadata()
      : workspace!.readSyncMetadata(path);

  static const _fileAccessChannel = MethodChannel(
    'work.ianvs.linefold/file_access',
  );

  @override
  Future<List<String>> chooseMarkdownFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[markdownTypeGroup],
    );
    return files.map((file) => file.path).toList(growable: false);
  }

  @override
  Future<String?> chooseSavePath(String suggestedName) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[markdownTypeGroup],
      suggestedName: suggestedName,
      initialDirectory: workspace == null
          ? null
          : AppleWorkspaceService.defaultPath,
      canCreateDirectories: true,
    );
    return location?.path;
  }

  @override
  Future<String?> chooseWorkspaceFolder() =>
      getDirectoryPath(confirmButtonText: 'Open Folder');

  @override
  Future<MarkdownFileData> readMarkdownFile(String path) async {
    final contents = workspace == null
        ? decodeMarkdownUtf8(await File(path).readAsBytes())
        : await workspace!.read(path);
    return MarkdownFileData(
      path: path,
      name: p.basename(path),
      contents: contents,
      lineEnding: contents.contains('\r\n') ? 'CRLF' : 'LF',
    );
  }

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    if (workspace != null) {
      await workspace!.write(path, contents);
      return;
    }
    await _writeLocalAtomic(path, contents);
  }

  @override
  Future<void> writeMarkdownFileGuarded(
    String path,
    String contents, {
    required String? expectedContents,
  }) async {
    if (workspace != null) {
      try {
        await workspace!.writeGuarded(
          path,
          contents,
          expectedContents: expectedContents,
        );
      } on PlatformException catch (error) {
        final details = error.details;
        // A malformed native response must fail closed, not authorize replacing
        // a destination whose current contents are unknown.
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
      return;
    }
    await _writeLocalAtomic(
      path,
      contents,
      checkDestination: () async {
        final currentContents = await _readCurrentContents(path);
        if (currentContents != expectedContents) {
          throw MarkdownSaveConflict(
            path: path,
            expectedContents: expectedContents,
            currentContents: currentContents,
          );
        }
      },
    );
  }

  Future<void> _writeLocalAtomic(
    String path,
    String contents, {
    Future<void> Function()? checkDestination,
  }) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    // A unique sibling staging directory keeps concurrent saves separate while
    // ensuring the final rename stays on the destination's filesystem.
    final staging = await target.parent.createTemp(
      '.${p.basename(path)}.ianvs-',
    );
    final temporary = File(p.join(staging.path, 'document.tmp'));
    try {
      await temporary.writeAsBytes(utf8.encode(contents), flush: true);
      await checkDestination?.call();
      // Portable Dart has no atomic compare-and-replace primitive. An
      // uncoordinated external writer can still change the destination between
      // this final comparison and rename. Apple workspace saves coordinate both
      // operations together; this fallback deliberately never truncates a file.
      await temporary.rename(path);
    } finally {
      // Preserve the original failure (or successful save) if cleanup fails.
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        // Best-effort removal of only this save's private staging directory.
      }
    }
  }

  Future<String?> _readCurrentContents(String path) async {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'The save destination is not a regular file',
          path,
        );
      }
      return decodeMarkdownUtf8(await File(path).readAsBytes());
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if ((code == 2 || (Platform.isWindows && code == 3)) &&
          await FileSystemEntity.type(path, followLinks: false) ==
              FileSystemEntityType.notFound) {
        return null;
      }
      // Do not mistake permission failures, directories, or dangling symlinks
      // for a deleted file, and do not convert decoding failures into conflicts.
      rethrow;
    }
  }

  @override
  Future<List<WorkspaceEntry>> listDirectory(String path) async {
    if (workspace != null) {
      final entries = await workspace!.list(path);
      return [
        for (final entry in entries)
          WorkspaceEntry(
            path: entry['path'] as String,
            name: entry['name'] as String,
            isDirectory: entry['isDirectory'] as bool,
            modified: DateTime.fromMillisecondsSinceEpoch(
              (entry['modified'] as num).toInt(),
            ),
          ),
      ]..sort(
        (a, b) => a.isDirectory != b.isDirectory
            ? (a.isDirectory ? -1 : 1)
            : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    final entries = <WorkspaceEntry>[];
    await for (final entity in Directory(path).list(followLinks: false)) {
      if (entity is Link) continue;
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.directory) {
        if (!p.basename(entity.path).startsWith('.')) {
          entries.add(
            WorkspaceEntry(
              path: entity.path,
              name: p.basename(entity.path),
              isDirectory: true,
              modified: stat.modified,
            ),
          );
        }
      } else if (stat.type == FileSystemEntityType.file &&
          isMarkdownFileName(entity.path)) {
        entries.add(
          WorkspaceEntry(
            path: entity.path,
            name: p.basename(entity.path),
            isDirectory: false,
            modified: stat.modified,
          ),
        );
      }
    }
    entries.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return entries;
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String path) =>
      Directory(path).watch(events: FileSystemEvent.all, recursive: false);

  @override
  Future<String?> createPersistentAccessToken(String path) async {
    if (!Platform.isMacOS) return null;
    try {
      return await _fileAccessChannel.invokeMethod<String>(
        'createBookmark',
        <String, Object?>{'path': path},
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String?> restorePersistentAccess(String token) async {
    if (!Platform.isMacOS) return null;
    try {
      return await _fileAccessChannel.invokeMethod<String>(
        'resolveBookmark',
        <String, Object?>{'token': token},
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<DateTime?> readModifiedTime(String path) async {
    final stat = await FileStat.stat(path);
    return stat.type == FileSystemEntityType.notFound ? null : stat.modified;
  }

  @override
  Future<bool> entryExists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  @override
  Future<void> createEntry(
    String path, {
    required bool directory,
    String contents = '',
  }) => _fileAccessChannel.invokeMethod<void>('createEntry', {
    'path': path,
    'directory': directory,
    'contents': contents,
  });

  @override
  Future<void> moveEntry(String source, String destination) =>
      _fileAccessChannel.invokeMethod<void>('moveEntry', {
        'path': source,
        'destination': destination,
      });

  @override
  Future<void> copyEntry(String source, String destination) =>
      _fileAccessChannel.invokeMethod<void>('copyEntry', {
        'path': source,
        'destination': destination,
      });

  @override
  Future<void> trashEntry(String path) =>
      _fileAccessChannel.invokeMethod<void>('trashEntry', {'path': path});

  @override
  bool fileExists(String path) =>
      File(path).existsSync() ||
      (workspace != null &&
          File(
            p.join(p.dirname(path), '.${p.basename(path)}.icloud'),
          ).existsSync());
}

bool isMarkdownFileName(String name) {
  final extension = p.extension(name).toLowerCase();
  return const <String>{
    '.md',
    '.markdown',
    '.mdown',
    '.mkd',
    '.txt',
  }.contains(extension);
}

String describeFileError(Object error) {
  if (error is FileSystemException &&
      (error.osError?.errorCode == 1 || error.osError?.errorCode == 13)) {
    return 'Access denied. Use File → Open Folder… to open the folder containing '
        'this document and its linked files, then try again.';
  }
  return error.toString();
}
