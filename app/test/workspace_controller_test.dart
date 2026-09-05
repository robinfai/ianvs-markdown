import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown_app/src/controllers/workspace_controller.dart';
import 'package:ianvs_markdown_app/src/models/document_session.dart';
import 'package:ianvs_markdown_app/src/services/workspace_session_store.dart';

import 'support/fakes.dart';

void main() {
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
