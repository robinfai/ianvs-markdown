import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:linefold/src/services/file_association_service.dart';
import 'package:linefold/src/services/incoming_files_service.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/services/workspace_session_store.dart';

class MemoryMarkdownFileService implements MarkdownFileService {
  final Map<String, String> files = <String, String>{};
  final modifiedTimes = <String, DateTime>{};
  @override
  Future<DateTime?> readModifiedTime(String path) async => modifiedTimes[path];
  final Map<String, List<WorkspaceEntry>> directories =
      <String, List<WorkspaceEntry>>{};
  final StreamController<FileSystemEvent> events =
      StreamController<FileSystemEvent>.broadcast();
  List<String> selectedFiles = const <String>[];
  String? selectedFolder;
  String savePath = '/notes/Untitled.md';

  @override
  Future<List<String>> chooseMarkdownFiles() async => selectedFiles;

  @override
  Future<String?> chooseSavePath(String suggestedName) async => savePath;

  @override
  Future<String?> chooseWorkspaceFolder() async => selectedFolder;

  @override
  bool fileExists(String path) => files.containsKey(path);

  @override
  Future<List<WorkspaceEntry>> listDirectory(String path) async =>
      directories[path] ?? const <WorkspaceEntry>[];

  @override
  Future<MarkdownFileData> readMarkdownFile(String path) async {
    return MarkdownFileData(
      path: path,
      name: path.split('/').last,
      contents: files[path]!,
    );
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String path) => events.stream;

  @override
  Future<String?> createPersistentAccessToken(String path) async =>
      'access:$path';

  @override
  Future<String?> restorePersistentAccess(String token) async =>
      token.startsWith('access:') ? token.substring(7) : null;

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    files[path] = contents;
  }

  @override
  Future<bool> entryExists(String path) async =>
      files.containsKey(path) ||
      directories.containsKey(path) ||
      files.keys.any((file) => p.isWithin(path, file));

  @override
  Future<void> createEntry(
    String path, {
    required bool directory,
    String contents = '',
  }) async {
    if (await entryExists(path)) throw StateError('Already exists');
    if (directory) {
      directories[path] = [];
    } else {
      files[path] = contents;
    }
    _relistParent(path);
  }

  void _relistParent(String path) {
    final parent = p.dirname(path);
    final entries = directories.putIfAbsent(parent, () => []);
    entries.removeWhere((entry) => entry.path == path);
    if (files.containsKey(path) || directories.containsKey(path)) {
      entries.add(
        WorkspaceEntry(
          path: path,
          name: p.basename(path),
          isDirectory: directories.containsKey(path),
        ),
      );
    }
    events.add(FileSystemCreateEvent(path, directories.containsKey(path)));
  }

  @override
  Future<void> moveEntry(String source, String destination) async {
    if (await entryExists(destination)) throw StateError('Already exists');
    if (!await entryExists(source)) throw StateError('Missing source');
    for (final path
        in files.keys
            .where((path) => path == source || p.isWithin(source, path))
            .toList()) {
      files[path == source
          ? destination
          : p.join(destination, p.relative(path, from: source))] = files.remove(
        path,
      )!;
    }
    for (final path
        in directories.keys
            .where((path) => path == source || p.isWithin(source, path))
            .toList()) {
      final target = path == source
          ? destination
          : p.join(destination, p.relative(path, from: source));
      directories[target] = directories
          .remove(path)!
          .map(
            (e) => WorkspaceEntry(
              path: p.join(destination, p.relative(e.path, from: source)),
              name: e.name,
              isDirectory: e.isDirectory,
            ),
          )
          .toList();
    }
    _relistParent(source);
    _relistParent(destination);
  }

  @override
  Future<void> copyEntry(String source, String destination) async {
    if (await entryExists(destination)) throw StateError('Already exists');
    if (!await entryExists(source)) throw StateError('Missing source');
    for (final path
        in files.keys
            .where((path) => path == source || p.isWithin(source, path))
            .toList()) {
      files[path == source
              ? destination
              : p.join(destination, p.relative(path, from: source))] =
          files[path]!;
    }
    for (final path
        in directories.keys
            .where((path) => path == source || p.isWithin(source, path))
            .toList()) {
      final target = path == source
          ? destination
          : p.join(destination, p.relative(path, from: source));
      directories[target] = directories[path]!
          .map(
            (e) => WorkspaceEntry(
              path: p.join(destination, p.relative(e.path, from: source)),
              name: e.name,
              isDirectory: e.isDirectory,
            ),
          )
          .toList();
    }
    _relistParent(destination);
  }

  final trashed = <String>[];
  @override
  Future<void> trashEntry(String path) async {
    if (!await entryExists(path)) throw StateError('Missing source');
    trashed.add(path);
    files.removeWhere((key, _) => key == path || p.isWithin(path, key));
    directories.removeWhere((key, _) => key == path || p.isWithin(path, key));
    _relistParent(path);
  }

  Future<void> dispose() => events.close();
}

class MemoryWorkspaceSessionStore implements WorkspaceSessionStore {
  WorkspaceSnapshot? snapshot;

  @override
  Future<WorkspaceSnapshot?> load() async => snapshot;

  @override
  Future<void> save(WorkspaceSnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}

class MemoryFileAssociationService implements FileAssociationService {
  bool? preference;
  bool isDefault = false;
  bool rejectChange = false;
  Completer<void>? pendingChange;
  final changes = <bool>[];

  @override
  Future<FileAssociationState> load() async => FileAssociationState(
    preferLinefold: preference,
    isDefault: isDefault,
    currentApplicationName: isDefault ? 'Linefold' : 'Other Editor',
    previousApplicationName: isDefault ? 'Other Editor' : null,
  );

  @override
  Future<FileAssociationState> setPreference(bool preferLinefold) async {
    changes.add(preferLinefold);
    preference = preferLinefold;
    if (pendingChange case final pending?) await pending.future;
    if (rejectChange) {
      throw PlatformException(
        code: 'association_failed',
        message:
            'Your preference was saved, but macOS did not change the default application.',
      );
    }
    isDefault = preferLinefold;
    return load();
  }
}

class MemoryIncomingFilesService implements IncomingFilesService {
  List<String> initialPaths = [];
  OpenIncomingFiles? onOpen;

  @override
  Future<void> start(OpenIncomingFiles onOpen) async {
    this.onOpen = onOpen;
    if (initialPaths.isNotEmpty) await onOpen(initialPaths);
  }

  Future<void> deliver(List<String> paths) async => onOpen?.call(paths);

  @override
  void dispose() => onOpen = null;
}
