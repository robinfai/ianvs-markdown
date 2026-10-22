import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/document_sync_status.dart';
import 'package:linefold/src/services/workspace_session_store.dart';

import 'support/fakes.dart';

void main() {
  test(
    'saved locally, draft backup, failed save and save A while typing B stay distinct',
    () async {
      final files = _DelayedFiles()..files['/notes/a.md'] = 'Original';
      final recovery = MemoryWorkspaceSessionStore();
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: recovery,
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      final draft = workspace.activeDocument!;
      expect(
        workspace.persistenceStatus(draft).local,
        LocalDocumentState.draft,
      );
      await workspace.flushSession();
      expect(
        workspace.persistenceStatus(draft).recovery,
        RecoveryCopyState.saved,
      );
      draft.controller.text = 'New draft';
      expect(
        workspace.persistenceStatus(draft).recovery,
        RecoveryCopyState.pending,
      );
      final document = (await workspace.openPath('/notes/a.md'))!;
      expect(workspace.persistenceStatus(document).label, 'Saved locally');
      document.controller.text = 'Save A';
      final writing = workspace.saveDocument(document);
      await Future<void>.delayed(Duration.zero);
      expect(
        workspace.persistenceStatus(document).local,
        LocalDocumentState.saving,
      );
      document.controller.text = 'Typed B';
      files.pending.complete();
      expect(await writing, isTrue);
      expect(document.persistedText, 'Save A');
      expect(document.controller.text, 'Typed B');
      expect(
        workspace.persistenceStatus(document).local,
        LocalDocumentState.edited,
      );
      expect(
        workspace.persistenceStatus(document).recovery,
        RecoveryCopyState.saved,
      );
      files.pending = Completer<void>();
      final failed = workspace.saveDocument(document);
      final expectation = expectLater(failed, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      files.pending.completeError(StateError('Local disk unavailable'));
      await expectation;
      expect(
        workspace.persistenceStatus(document).local,
        LocalDocumentState.failed,
      );
      expect(document.persistedText, 'Save A');
      expect(document.controller.isDirty, isTrue);
      files.pending = Completer<void>()..complete();
      expect(await workspace.saveDocument(document), isTrue);
      expect(workspace.persistenceStatus(document).label, 'Saved locally');
    },
  );

  test('recovery pending and failed never claim draft saved', () async {
    final files = MemoryMarkdownFileService();
    final sessions = _RecoveryStore();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: sessions,
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    await workspace.initialize();
    workspace.activeDocument!.controller.text = 'Important draft';
    expect(
      workspace.persistenceStatus(workspace.activeDocument!).label,
      'Draft · recovery pending',
    );
    sessions.fail = true;
    await expectLater(workspace.flushSession(), throwsStateError);
    expect(
      workspace.persistenceStatus(workspace.activeDocument!).label,
      'Draft · recovery failed',
    );
    sessions.fail = false;
    await workspace.flushSession();
    expect(
      workspace.persistenceStatus(workspace.activeDocument!).label,
      'Draft · recovery saved',
    );
  });

  test(
    'metadata reads only active paths and never trigger full-text reads',
    () async {
      final files = _MetadataFiles()
        ..files['/notes/a.md'] = 'A'
        ..files['/notes/b.md'] = 'B';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      await workspace.openPath('/notes/a.md');
      await Future<void>.delayed(Duration.zero);
      final a = workspace.activeIndex;
      await workspace.openPath('/notes/b.md');
      await Future<void>.delayed(Duration.zero);
      final before = List<String>.from(files.metadataPaths);
      expect(before, ['/notes/a.md', '/notes/b.md']);
      await workspace.sync.refresh();
      expect(files.metadataPaths, [...before, '/notes/b.md']);
      workspace.selectDocument(a);
      await Future<void>.delayed(Duration.zero);
      expect(files.metadataPaths.last, '/notes/a.md');
      expect(files.metadataPaths, isNot(contains('/notes/unopened.md')));
    },
  );
}

class _DelayedFiles extends MemoryMarkdownFileService {
  Completer<void> pending = Completer<void>();
  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    await pending.future;
    files[path] = contents;
  }
}

class _RecoveryStore extends MemoryWorkspaceSessionStore {
  bool fail = false;
  @override
  Future<void> save(WorkspaceSnapshot snapshot) async {
    if (fail) throw StateError('Recovery unavailable');
    await super.save(snapshot);
  }
}

class _MetadataFiles extends MemoryMarkdownFileService
    implements DocumentSyncSource {
  final metadataPaths = <String>[];
  @override
  Future<DocumentSyncMetadata> readSyncMetadata(String path) async {
    metadataPaths.add(path);
    return const DocumentSyncMetadata();
  }
}
