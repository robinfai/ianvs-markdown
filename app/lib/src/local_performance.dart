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
}

WorkspaceController localPerformanceWorkspace(LocalPerformanceFiles files) =>
    WorkspaceController(
      fileService: files,
      sessionStore: DesktopWorkspaceSessionStore(
        directory: Directory.systemTemp.createTempSync('ianvs-r402-session-'),
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
    if (!await workspace.saveActive()) throw StateError('Save cancelled');
  },
  flush: workspace.flushSession,
  ioMetrics: () => {'read': files.readMs, 'write': files.writeMs},
);
