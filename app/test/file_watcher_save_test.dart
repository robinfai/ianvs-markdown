import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/document_session.dart';
import 'package:linefold/src/services/markdown_file_service.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('external write immediately after save still raises a conflict', (
    tester,
  ) async {
    await _withWorkspace(tester, (workspace, files, document) async {
      document.controller.text = 'Saved locally';
      expect(await workspace.saveDocument(document), isTrue);

      files.writeExternally(document.path!, 'External replacement');
      await tester.pump();

      expect(document.hasExternalChanges, isTrue);
      expect(document.controller.text, 'Saved locally');
      expect(document.persistedText, 'Saved locally');
      expect(document.controller.isDirty, isFalse);
    });
  });

  testWidgets('own save events compare with persisted text, not new typing', (
    tester,
  ) async {
    await _withWorkspace(tester, (workspace, files, document) async {
      document.controller.text = 'Saved locally';
      expect(await workspace.saveDocument(document), isTrue);
      document.controller.text = 'New unsaved typing';

      files.notifyModified(document.path!);
      await tester.pump();
      expect(document.hasExternalChanges, isFalse);
      expect(document.controller.isDirty, isTrue);

      // A delayed duplicate event is also our own unchanged disk snapshot.
      await tester.pump(const Duration(milliseconds: 601));
      files.notifyModified(document.path!);
      await tester.pump();
      expect(document.hasExternalChanges, isFalse);
      expect(document.controller.text, 'New unsaved typing');
    });
  });

  testWidgets(
    'external change during a pending save survives save completion',
    (tester) async {
      await _withWorkspace(tester, (workspace, files, document) async {
        files.writeCompletion = Completer<void>();
        document.controller.text = 'Saved locally';
        final saving = workspace.saveDocument(document);
        await tester.pump();

        files.writeExternally(document.path!, 'Changed before save completed');
        await tester.pump();
        files.writeCompletion!.complete();
        expect(await saving, isTrue);
        await tester.pump();

        expect(document.hasExternalChanges, isTrue);
        expect(document.persistedText, 'Saved locally');
        expect(document.controller.text, 'Saved locally');
      });
    },
  );

  testWidgets('deleting a file immediately after save raises a conflict', (
    tester,
  ) async {
    await _withWorkspace(tester, (workspace, files, document) async {
      expect(await workspace.saveDocument(document), isTrue);
      files.files.remove(document.path!);
      files.events.add(FileSystemDeleteEvent(document.path!, false));
      await tester.pump();

      expect(document.hasExternalChanges, isTrue);
      expect(document.controller.text, 'Original');
    });
  });

  test('Save As watches the new path without a suppression window', () async {
    await _withWorkspace(null, (workspace, files, document) async {
      files.savePath = '/notes/renamed.md';
      document.controller.text = 'Saved under a new name';
      expect(await workspace.saveDocument(document, saveAs: true), isTrue);

      files.writeExternally('/notes/one.md', 'Old file changed');
      await Future<void>.delayed(Duration.zero);
      expect(document.hasExternalChanges, isFalse);

      files.writeExternally('/notes/renamed.md', 'New file changed');
      await Future<void>.delayed(Duration.zero);
      expect(document.hasExternalChanges, isTrue);
      expect(document.path, '/notes/renamed.md');
      expect(document.persistedText, 'Saved under a new name');
    });
  });

  testWidgets('a failed save does not swallow an external change', (
    tester,
  ) async {
    await _withWorkspace(tester, (workspace, files, document) async {
      files.writeCompletion = Completer<void>();
      document.controller.text = 'Attempted save';
      final saving = workspace.saveDocument(document);
      final failure = expectLater(saving, throwsStateError);
      await tester.pump();
      files.writeExternally(document.path!, 'External text after write failed');
      await tester.pump();
      files.writeCompletion!.completeError(StateError('Flush failed'));
      await failure;
      await tester.pump();

      expect(document.hasExternalChanges, isTrue);
      expect(document.persistedText, 'Original');
      expect(document.controller.text, 'Attempted save');
      expect(document.controller.isDirty, isTrue);
    });
  });

  testWidgets('queued saves compare events with the final written snapshot', (
    tester,
  ) async {
    await _withWorkspace(tester, (workspace, files, document) async {
      final firstWrite = Completer<void>();
      files.writeCompletion = firstWrite;
      document.controller.text = 'First saved snapshot';
      final firstSave = workspace.saveDocument(document);
      await tester.pump();
      document.controller.text = 'Second saved snapshot';
      final secondSave = workspace.saveDocument(document);
      final secondWrite = Completer<void>();
      files.writeCompletion = secondWrite;
      firstWrite.complete();
      expect(await firstSave, isTrue);
      await tester.pump();
      expect(files.files[document.path], 'Second saved snapshot');

      files.writeExternally(document.path!, 'External after the second write');
      secondWrite.complete();
      expect(await secondSave, isTrue);
      await tester.pump();

      expect(document.hasExternalChanges, isTrue);
      expect(document.persistedText, 'Second saved snapshot');
      expect(document.controller.text, 'Second saved snapshot');
    });
  });

  testWidgets('a newer save invalidates a stale asynchronous disk read', (
    tester,
  ) async {
    await _withWorkspace(tester, (workspace, files, document) async {
      final delayedRead = Completer<MarkdownFileData>();
      files.nextRead = delayedRead;
      files.writeExternally(document.path!, 'External before our save');
      await tester.pump();
      expect(files.nextRead, isNull);

      // Re-saving identical text must invalidate the old read too.
      expect(await workspace.saveDocument(document), isTrue);
      await tester.pump();
      delayedRead.complete(
        MarkdownFileData(
          path: document.path!,
          name: document.name,
          contents: 'External before our save',
        ),
      );
      await tester.pump();

      expect(document.hasExternalChanges, isFalse);
      expect(files.files[document.path], 'Original');
    });
  });

  testWidgets('a pending disk read cannot notify a closed document', (
    tester,
  ) async {
    await _withWorkspace(tester, (workspace, files, document) async {
      final delayedRead = Completer<MarkdownFileData>();
      files.nextRead = delayedRead;
      files.writeExternally(document.path!, 'External before close');
      await tester.pump();
      workspace.removeDocument(document);
      var notifications = 0;
      workspace.addListener(() => notifications += 1);
      delayedRead.complete(
        MarkdownFileData(
          path: '/notes/one.md',
          name: 'one.md',
          contents: 'External before close',
        ),
      );
      await tester.pump();

      expect(notifications, 0);
      expect(workspace.activeDocument!.hasExternalChanges, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _withWorkspace(
  WidgetTester? tester,
  Future<void> Function(
    WorkspaceController workspace,
    _WatchingFiles files,
    DocumentSession document,
  )
  body,
) async {
  final files = _WatchingFiles()..files['/notes/one.md'] = 'Original';
  final workspace = WorkspaceController(
    fileService: files,
    sessionStore: MemoryWorkspaceSessionStore(),
  );
  try {
    await workspace.initialize();
    final document = (await workspace.openPath('/notes/one.md'))!;
    await body(workspace, files, document);
  } finally {
    workspace.dispose();
    await files.dispose();
    // Also drain the former suppression timer when running against old code.
    await tester?.pump(const Duration(milliseconds: 601));
  }
}

class _WatchingFiles extends MemoryMarkdownFileService {
  Completer<void>? writeCompletion;
  Completer<MarkdownFileData>? nextRead;

  @override
  Future<MarkdownFileData> readMarkdownFile(String path) async {
    final delayedRead = nextRead;
    nextRead = null;
    if (delayedRead != null) return delayedRead.future;
    if (!files.containsKey(path)) {
      throw FileSystemException('File no longer exists', path);
    }
    return super.readMarkdownFile(path);
  }

  void notifyModified(String path) {
    events.add(FileSystemModifyEvent(path, false, true));
  }

  void writeExternally(String path, String text) {
    files[path] = text;
    notifyModified(path);
  }

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    files[path] = contents;
    notifyModified(path);
    await writeCompletion?.future;
  }
}
