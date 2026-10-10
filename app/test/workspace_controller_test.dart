import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/document_session.dart';
import 'package:linefold/src/services/workspace_session_store.dart';

import 'support/fakes.dart';

void main() {
  test(
    'launch selects iCloud, external folders require selection, drafts survive',
    () async {
      final files = MemoryMarkdownFileService()..selectedFolder = '/manual';
      final clean = DocumentSession(
        id: 'document-1',
        name: 'clean.md',
        path: '/old/clean.md',
        text: '# Saved',
        persistedText: '# Saved',
        accessToken: 'access:/old/clean.md',
      );
      final dirty = DocumentSession(
        id: 'document-2',
        name: 'draft.md',
        path: '/old/draft.md',
        text: '# Unsaved',
        persistedText: '# Saved',
        accessToken: 'access:/old/draft.md',
      );
      final sessions = MemoryWorkspaceSessionStore()
        ..snapshot = WorkspaceSnapshot(
          documents: [clean.toJson(), dirty.toJson()],
          activeDocumentId: dirty.id,
          workspaceRoot: '/old',
          workspaceAccessToken: 'access:/old',
          sidebarVisible: true,
          outlineVisible: true,
        );
      clean.dispose();
      dirty.dispose();
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: sessions,
        defaultWorkspaceDirectory: () async => '/cloud/Linefold',
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      expect(workspace.workspaceRoot, '/cloud/Linefold');
      expect(workspace.isCloudWorkspace, isTrue);
      expect(workspace.documents, hasLength(1));
      expect(workspace.activeDocument!.path, isNull);
      expect(workspace.activeDocument!.accessToken, isNull);
      expect(workspace.activeDocument!.controller.text, '# Unsaved');
      expect(workspace.activeDocument!.controller.isDirty, isTrue);
      await workspace.chooseWorkspaceFolder();
      expect(workspace.workspaceRoot, '/manual');
      expect(workspace.isCloudWorkspace, isFalse);
      await workspace.useDefaultWorkspace();
      expect(workspace.workspaceRoot, '/cloud/Linefold');
    },
  );

  test(
    'unavailable iCloud does not silently restore a different workspace',
    () async {
      final files = MemoryMarkdownFileService()..selectedFolder = '/manual';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
        defaultWorkspaceDirectory: () async => throw StateError('Unavailable'),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      expect(workspace.workspaceRoot, isNull);
      expect(workspace.workspaceNotice, contains('iCloud'));
      await workspace.chooseWorkspaceFolder();
      expect(workspace.workspaceRoot, '/manual');
      expect(workspace.workspaceNotice, isNull);
    },
  );

  test('opens, saves, reorders, and restores document sessions', () async {
    final files = MemoryMarkdownFileService()
      ..files['/notes/one.md'] = '# One'
      ..files['/notes/two.md'] = '# Two';
    final sessions = MemoryWorkspaceSessionStore();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: sessions,
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);

    await workspace.initialize();
    expect(workspace.activeDocument?.name, 'Welcome.md');

    await workspace.openPaths(const <String>['/notes/one.md', '/notes/two.md']);
    expect(workspace.documents.map((document) => document.name), [
      'Welcome.md',
      'one.md',
      'two.md',
    ]);

    final two = workspace.activeDocument!;
    two.controller.text = '# Updated two';
    expect(two.controller.isDirty, isTrue);
    expect(await workspace.saveActive(), isTrue);
    expect(files.files['/notes/two.md'], '# Updated two');
    expect(two.controller.isDirty, isFalse);
    expect(two.accessToken, 'access:/notes/two.md');

    workspace.reorderDocument(2, 0);
    expect(workspace.documents.first, same(two));
    expect(workspace.activeDocument, same(two));
    expect(sessions.snapshot, isNotNull);
  });

  test('refreshes clean files from disk when restoring a session', () async {
    final files = MemoryMarkdownFileService()
      ..files['/notes/one.md'] = '# Changed while closed';
    final restored = DocumentSession(
      id: 'document-8',
      name: 'one.md',
      path: '/notes/one.md',
      text: '# Old',
      persistedText: '# Old',
    );
    final sessions = MemoryWorkspaceSessionStore()
      ..snapshot = WorkspaceSnapshot(
        documents: <Map<String, Object?>>[restored.toJson()],
        activeDocumentId: restored.id,
        workspaceRoot: '/notes',
        workspaceAccessToken: 'access:/notes',
        sidebarVisible: true,
        outlineVisible: true,
      );
    restored.dispose();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: sessions,
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);

    await workspace.initialize();

    expect(workspace.activeDocument?.controller.text, '# Changed while closed');
    expect(workspace.activeDocument?.controller.isDirty, isFalse);
  });

  test('keeps a recovered draft and flags an on-disk conflict', () async {
    final files = MemoryMarkdownFileService()
      ..files['/notes/one.md'] = '# Disk changed';
    final restored = DocumentSession(
      id: 'document-3',
      name: 'one.md',
      path: '/notes/one.md',
      text: '# Recovered draft',
      persistedText: '# Original disk',
    );
    final sessions = MemoryWorkspaceSessionStore()
      ..snapshot = WorkspaceSnapshot(
        documents: <Map<String, Object?>>[restored.toJson()],
        activeDocumentId: restored.id,
        workspaceRoot: '/notes',
        workspaceAccessToken: 'access:/notes',
        sidebarVisible: true,
        outlineVisible: true,
      );
    restored.dispose();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: sessions,
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);

    await workspace.initialize();

    expect(workspace.activeDocument?.controller.text, '# Recovered draft');
    expect(workspace.activeDocument?.controller.isDirty, isTrue);
    expect(workspace.activeDocument?.hasExternalChanges, isTrue);
  });

  test('never drops an inaccessible unsaved recovery draft', () async {
    final files = MemoryMarkdownFileService();
    final restored = DocumentSession(
      id: 'document-5',
      name: 'missing.md',
      path: '/notes/missing.md',
      text: '# Work in progress',
      persistedText: '# Last saved',
    );
    final sessions = MemoryWorkspaceSessionStore()
      ..snapshot = WorkspaceSnapshot(
        documents: <Map<String, Object?>>[restored.toJson()],
        activeDocumentId: restored.id,
        workspaceRoot: null,
        workspaceAccessToken: null,
        sidebarVisible: true,
        outlineVisible: true,
      );
    restored.dispose();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: sessions,
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);

    await workspace.initialize();

    expect(workspace.activeDocument?.name, 'missing.md');
    expect(workspace.activeDocument?.controller.text, '# Work in progress');
    expect(workspace.activeDocument?.controller.isDirty, isTrue);
    expect(workspace.activeDocument?.hasExternalChanges, isTrue);
  });
}
