import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:linefold/src/services/file_association_service.dart';
import 'package:linefold/src/services/incoming_files_service.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/services/workspace_session_store.dart';

class MemoryMarkdownFileService implements MarkdownFileService {
  final Map<String, String> files = <String, String>{};
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
