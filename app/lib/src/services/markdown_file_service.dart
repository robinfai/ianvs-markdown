import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

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
  });

  final String path;
  final String name;
  final bool isDirectory;
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
}

class DesktopMarkdownFileService implements MarkdownFileService {
  const DesktopMarkdownFileService();

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
      canCreateDirectories: true,
    );
    return location?.path;
  }

  @override
  Future<String?> chooseWorkspaceFolder() =>
      getDirectoryPath(confirmButtonText: 'Open Folder');

  @override
  Future<MarkdownFileData> readMarkdownFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final contents = utf8.decode(bytes, allowMalformed: false);
    return MarkdownFileData(
      path: path,
      name: p.basename(path),
      contents: contents,
      lineEnding: contents.contains('\r\n') ? 'CRLF' : 'LF',
    );
  }

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    final temporary = File(
      p.join(
        target.parent.path,
        '.${p.basename(path)}.ianvs-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    await temporary.writeAsBytes(utf8.encode(contents), flush: true);
    try {
      await temporary.rename(path);
    } on FileSystemException {
      // Some filesystems do not allow rename-over-existing. Keep a flushed
      // fallback instead of leaving the user's document unsaved.
      await target.writeAsBytes(utf8.encode(contents), flush: true);
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<List<WorkspaceEntry>> listDirectory(String path) async {
    final entries = <WorkspaceEntry>[];
    await for (final entity in Directory(path).list(followLinks: false)) {
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.directory) {
        if (!p.basename(entity.path).startsWith('.')) {
          entries.add(
            WorkspaceEntry(
              path: entity.path,
              name: p.basename(entity.path),
              isDirectory: true,
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
  bool fileExists(String path) => File(path).existsSync();
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
