import 'dart:io';

// Repository-only opt-in instrumentation; intentionally not public package API.
// ignore: implementation_imports
import 'package:ianvs_markdown/src/diagnostics/local_performance/probe.dart';
import 'controllers/workspace_controller.dart';
import 'editor_commands.dart';
import 'services/apple_workspace_service.dart';
import 'services/markdown_file_service.dart';
import 'services/workspace_session_store.dart';

export 'package:ianvs_markdown/src/diagnostics/local_performance/probe.dart'
    show LocalPerformancePanel, localPerformanceEnabled;

class LocalPerformanceFiles extends DesktopMarkdownFileService {
  LocalPerformanceFiles() : super(workspace: const AppleWorkspaceService());
  double readMs = 0;
  double writeMs = 0;
  @override
  Future<MarkdownFileData> readMarkdownFile(String path) async {
    final watch = Stopwatch()..start();
    try {
      return await super.readMarkdownFile(path);
    } finally {
      readMs = watch.elapsedMicroseconds / 1000;
    }
  }

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    final watch = Stopwatch()..start();
    try {
      await super.writeMarkdownFileAtomic(path, contents);
    } finally {
      writeMs = watch.elapsedMicroseconds / 1000;
    }
  }

  @override
  Future<void> writeMarkdownFileGuarded(
    String path,
    String contents, {
    required String? expectedContents,
  }) async {
    final watch = Stopwatch()..start();
    try {
      await super.writeMarkdownFileGuarded(
        path,
        contents,
        expectedContents: expectedContents,
      );
    } finally {
      writeMs = watch.elapsedMicroseconds / 1000;
    }
  }
}

/// Counts recovery writes started during the measured save callback only.
/// Durations include IO waits and must not be interpreted as CPU time.
class LocalPerformanceSessionStore implements WorkspaceSessionStore {
  LocalPerformanceSessionStore(this.delegate);

  final WorkspaceSessionStore delegate;
  double saveMs = 0;
  int saveCount = 0;
  int? _capture;
  int _generation = 0;

  void beginSaveCapture() {
    saveMs = 0;
    saveCount = 0;
    _capture = ++_generation;
  }

  void endSaveCapture() => _capture = null;

  @override
  Future<WorkspaceSnapshot?> load() => delegate.load();

  @override
  Future<void> save(WorkspaceSnapshot snapshot) async {
    final capture = _capture;
    final watch = Stopwatch()..start();
    try {
      await delegate.save(snapshot);
    } finally {
      if (capture != null && capture == _capture) {
        saveMs += watch.elapsedMicroseconds / 1000;
        saveCount++;
      }
    }
  }
}

WorkspaceController localPerformanceWorkspace(LocalPerformanceFiles files) =>
    WorkspaceController(
      fileService: files,
      sessionStore: LocalPerformanceSessionStore(
        DesktopWorkspaceSessionStore(
          directory: Directory.systemTemp.createTempSync('ianvs-r402-session-'),
        ),
      ),
    );

LocalPerformanceHost localPerformanceHost(
  WorkspaceController workspace,
  LocalPerformanceFiles files,
) => LocalPerformanceHost(
  entry: 'app',
  controller: () => workspace.activeDocument!.controller,
  scroll: () => workspace.activeDocument!.scrollController,
  prepare: (path, source) async {
    await workspace.openPath(path);
    for (final document in workspace.documents.toList()) {
      if (document != workspace.activeDocument) {
        workspace.removeDocument(document);
      }
    }
    if (workspace.activeDocument!.controller.text != source) {
      throw StateError('File preparation mismatch');
    }
  },
  mode: (mode) => setEditorMode(workspace, mode),
  beforeOpen: () async {
    workspace.removeDocument(workspace.activeDocument!);
  },
  open: (path) async {
    await workspace.openPath(path);
    for (final document in workspace.documents.toList()) {
      if (document != workspace.activeDocument) {
        workspace.removeDocument(document);
      }
    }
  },
  save: () async {
    final store = workspace.sessionStore;
    if (store is LocalPerformanceSessionStore) store.beginSaveCapture();
    try {
      if (!await workspace.saveActive()) throw StateError('Save cancelled');
    } finally {
      if (store is LocalPerformanceSessionStore) store.endSaveCapture();
    }
  },
  flush: workspace.flushSession,
  ioMetrics: () => {
    'read': files.readMs,
    'write': files.writeMs,
    if (workspace.sessionStore
        case final LocalPerformanceSessionStore store) ...{
      'recoverySave': store.saveMs,
      'recoverySaveCount': store.saveCount.toDouble(),
    },
  },
);
