import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/file_association_controller.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/document_session.dart';
import 'package:linefold/src/services/workspace_session_store.dart';

import 'support/fakes.dart';

class _ControlledStore extends MemoryWorkspaceSessionStore {
  bool hold = false;
  bool fail = false;
  final writes = <WorkspaceSnapshot>[];
  final pending = <Completer<void>>[];

  @override
  Future<void> save(WorkspaceSnapshot snapshot) async {
    writes.add(snapshot);
    if (hold) {
      final barrier = Completer<void>();
      pending.add(barrier);
      await barrier.future;
    }
    if (fail) throw StateError('Recovery storage unavailable');
    await super.save(snapshot);
  }

  void release() {
    pending.firstWhere((barrier) => !barrier.isCompleted).complete();
  }

  void releaseAll() {
    hold = false;
    for (final barrier in pending) {
      if (!barrier.isCompleted) barrier.complete();
    }
  }
}

void main() {
  testWidgets('mode-only changes are persisted after the previous snapshot', (
    tester,
  ) async {
    final files = MemoryMarkdownFileService();
    final store = MemoryWorkspaceSessionStore();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: store,
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    await workspace.initialize();
    await tester.pump(const Duration(milliseconds: 400));
    workspace.activeDocument!.controller.mode = IanvsMarkdownEditorMode.source;
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.snapshot!.documents.single['mode'], 'source');
  });

  testWidgets(
    'slow recovery writes cannot overlap and overwrite a newer draft',
    (tester) async {
      final files = MemoryMarkdownFileService();
      final store = _ControlledStore()..hold = true;
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: store,
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      addTearDown(store.releaseAll);
      await workspace.initialize();
      final draft = workspace.newDocument();
      draft.controller.text = 'first 中文😀\r\n';
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.writes, hasLength(1));
      draft.controller.text = 'second 中文😀\r\n';
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        store.writes,
        hasLength(1),
        reason: 'one writer owns the session file',
      );
      store.release();
      await tester.pump();
      expect(store.writes, hasLength(2));
      store.release();
      await tester.pump();
      expect(store.snapshot!.documents.last['text'], 'second 中文😀\r\n');
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('exit flush includes edits made while recovery storage is busy', (
    tester,
  ) async {
    final files = MemoryMarkdownFileService();
    final store = _ControlledStore()..hold = true;
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: store,
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    addTearDown(store.releaseAll);
    await workspace.initialize();
    final draft = workspace.newDocument();
    draft.controller.text = 'before exit';
    var finished = false;
    final flushing = workspace.flushSession().then((_) => finished = true);
    await tester.pump();
    draft.controller.text = 'typed while waiting 中文😀';
    store.release();
    await tester.pump();
    expect(finished, isFalse);
    expect(store.writes, hasLength(2));
    expect(store.writes.last.documents.last['text'], draft.controller.text);
    store.release();
    await tester.pump();
    await flushing;
    expect(finished, isTrue);
    expect(store.snapshot!.documents.last['text'], draft.controller.text);
    await tester.pump(const Duration(milliseconds: 600));
  });

  for (final fail in [false, true]) {
    testWidgets(
      'main app exit waits for recovery; storage failure=$fail',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.menu,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.menu,
            null,
          ),
        );
        final files = MemoryMarkdownFileService();
        final store = _ControlledStore();
        final workspace = WorkspaceController(
          fileService: files,
          sessionStore: store,
        );
        final association = FileAssociationController(
          service: MemoryFileAssociationService()..preference = false,
        );
        addTearDown(workspace.dispose);
        addTearDown(files.dispose);
        addTearDown(association.dispose);
        addTearDown(store.releaseAll);
        await tester.pumpWidget(
          LinefoldApp(
            workspaceController: workspace,
            fileAssociationController: association,
            incomingFilesService: MemoryIncomingFilesService(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        store
          ..hold = true
          ..fail = fail;
        final draft = workspace.newDocument();
        draft.controller.text = 'last keystroke 中文😀\r\n';
        await tester.pump(); // Mount the new document before dispatching exit.
        AppExitResponse? response;
        final exit = tester.binding.handleRequestAppExit().then((value) {
          response = value;
        });
        await tester.pump();
        expect(
          response,
          isNull,
          reason: 'exit must await the pending recovery write',
        );
        expect(store.writes.last.documents.last['text'], draft.controller.text);
        store.release();
        await tester.pumpAndSettle();
        await exit;
        expect(response, fail ? AppExitResponse.cancel : AppExitResponse.exit);
        if (fail) {
          expect(
            find.textContaining('Unable to save recovery'),
            findsOneWidget,
          );
          store
            ..hold = false
            ..fail = false;
          final retry = tester.binding.handleRequestAppExit();
          await tester.pumpAndSettle();
          expect(await retry, AppExitResponse.exit);
        }
        expect(store.snapshot!.documents.last['text'], draft.controller.text);
        await tester.pumpWidget(const SizedBox.shrink());
        store.releaseAll();
        await tester.pump(const Duration(milliseconds: 600));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  test(
    'local files and unnamed drafts recover when iCloud is unavailable',
    () async {
      const source = '---\r\ntitle: 中文😀\r\n---\r\n# Saved\r\n';
      final files = MemoryMarkdownFileService()
        ..files['/local/saved.md'] = '$source\r\nUpdated on disk'
        ..files['/local/dirty.md'] = source;
      final originals = [
        DocumentSession(
          id: 'document-10',
          name: 'saved.md',
          path: '/local/saved.md',
          text: source,
          accessToken: 'access:/local/saved.md',
        ),
        DocumentSession(
          id: 'document-11',
          name: 'dirty.md',
          path: '/local/dirty.md',
          text: '${source}unsaved',
          persistedText: source,
          accessToken: 'access:/local/dirty.md',
          mode: IanvsMarkdownEditorMode.source,
        ),
        DocumentSession(
          id: 'document-12',
          name: 'Untitled-12.md',
          text: 'unnamed 中文😀\r\n',
          persistedText: '',
          mode: IanvsMarkdownEditorMode.preview,
        ),
      ];
      final store = MemoryWorkspaceSessionStore()
        ..snapshot = WorkspaceSnapshot(
          documents: originals.map((d) => d.toJson()).toList(),
          activeDocumentId: 'document-12',
          workspaceRoot: '/local',
          workspaceAccessToken: 'access:/local',
          sidebarVisible: true,
          outlineVisible: true,
        );
      for (final document in originals) {
        document.dispose();
      }
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: store,
        defaultWorkspaceDirectory: () async => throw StateError('No iCloud'),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      expect(workspace.workspaceRoot, '/local');
      expect(workspace.documents, hasLength(3));
      expect(
        workspace.documents[0].controller.text,
        '$source\r\nUpdated on disk',
      );
      expect(workspace.documents[0].controller.isDirty, isFalse);
      expect(workspace.documents[1].path, '/local/dirty.md');
      expect(workspace.documents[1].controller.text, '${source}unsaved');
      expect(workspace.documents[1].persistedText, source);
      expect(workspace.documents[1].controller.isDirty, isTrue);
      expect(
        workspace.documents[1].controller.mode,
        IanvsMarkdownEditorMode.source,
      );
      expect(workspace.activeDocument!.id, 'document-12');
      expect(workspace.activeDocument!.path, isNull);
      expect(workspace.activeDocument!.controller.text, 'unnamed 中文😀\r\n');
      expect(workspace.activeDocument!.controller.isDirty, isTrue);
      expect(
        workspace.activeDocument!.controller.mode,
        IanvsMarkdownEditorMode.preview,
      );
      expect(
        files.files['/local/dirty.md'],
        source,
        reason: 'recovery never saves over disk',
      );
      expect(workspace.newDocument().id, 'document-13');
    },
  );
}
