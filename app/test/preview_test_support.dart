import 'package:linefold/src/preview/preview_reading_positions.dart';
import 'package:linefold/src/services/workspace_session_store.dart';
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_platform.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/preview/preview_draft_store.dart';

class MemoryPreviewDraftStore implements PreviewDraftStore {
  PreviewDraft? draft;
  bool failLoad = false;
  Completer<PreviewDraft?>? pendingLoad;
  Completer<void>? pendingSave;
  bool failSave = false;
  final snapshots = <PreviewDraft?>[];
  @override
  Future<PreviewDraft?> load() async {
    if (pendingLoad != null) return pendingLoad!.future;
    if (failLoad) throw StateError('unreadable recovery');
    return draft;
  }

  @override
  Future<void> save(PreviewDraft? value) async {
    await pendingSave?.future;
    if (failSave) throw StateError('unwritable recovery');
    snapshots.add(value);
    draft = value;
  }
}

class MemoryPreviewLibrary extends PreviewLibrary {
  MemoryPreviewLibrary() {
    workspace = const PreviewWorkspace(
      path: '/vault',
      name: 'Test vault',
      isCloud: false,
      workspaceToken: 'test-token',
    );
  }
  final files = <String, String>{'/vault/note.md': '# Note\r\n- [ ] Task\r\n'};
  final writes = <(String, String, String?)>[];
  final creates = <String>[];
  Completer<void>? pendingWrite;
  Completer<String>? pendingRead;
  Completer<String>? pendingRefresh;
  bool writeFailure = false;
  bool readFailure = false;
  int bodyRefreshes = 0;
  int defaultSelections = 0;
  Future<void> Function(String path, String text, String? expected)?
  beforeWrite;
  @override
  bool get canWrite => workspace?.workspaceToken != null;
  @override
  Future<void> useDefaultWorkspace() async {
    defaultSelections++;
  }

  @override
  Future<List<PreviewDocument>> list() async => [
    for (final file in files.keys)
      PreviewDocument(
        path: file,
        name: p.basename(file),
        openedAt: DateTime(2026),
      ),
  ];
  @override
  Future<String> read(String path) async {
    final raw = await readSource(path);
    return raw.startsWith('\ufeff') ? raw.substring(1) : raw;
  }

  @override
  Future<String> readSource(String path) async {
    if (pendingRead != null) return pendingRead!.future;
    if (readFailure || !files.containsKey(path)) {
      throw StateError('unavailable');
    }
    return files[path]!;
  }

  @override
  Future<String> refreshContent(String path) async {
    bodyRefreshes++;
    if (pendingRefresh != null) return pendingRefresh!.future;
    return read(path);
  }

  @override
  Future<void> writeSource(
    String path,
    String text, {
    required String? expectedContents,
    required int generation,
  }) async {
    if (generation != workspaceGeneration) throw StateError('stale');
    writes.add((path, text, expectedContents));
    await beforeWrite?.call(path, text, expectedContents);
    await pendingWrite?.future;
    if (writeFailure) throw StateError('denied');
    if (files[path] != expectedContents) {
      throw MarkdownSaveConflict(
        path: path,
        expectedContents: expectedContents,
        currentContents: files[path],
      );
    }
    files[path] = text;
  }

  @override
  Future<String> createNote(String relative, {required int generation}) async {
    if (generation != workspaceGeneration) throw StateError('stale');
    final path = p.join(workspace!.path, relative);
    if (files.containsKey(path)) throw StateError('occupied');
    creates.add(path);
    files[path] = '';
    return path;
  }
}

class MemoryPreviewPlatform extends PreviewPlatform {
  List<String> initial = ['/vault/note.md'];
  PreviewDelivery? onFiles;
  bool pickerOpened = false;
  @override
  Future<void> start(
    PreviewDelivery onFiles,
    void Function(String) onError,
  ) async {
    this.onFiles = onFiles;
    if (initial.isNotEmpty) await onFiles(initial);
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<void> chooseFiles() async {
    pickerOpened = true;
  }

  @override
  void dispose() {}
}

PreviewReadingPositions memoryPreviewReadingPositions() =>
    PreviewReadingPositions(store: _MemoryReadingStore());

class _MemoryReadingStore implements WorkspaceSessionStore {
  WorkspaceSnapshot? snapshot;
  @override
  Future<WorkspaceSnapshot?> load() async => snapshot;
  @override
  Future<void> save(WorkspaceSnapshot value) async {
    snapshot = value;
  }
}
