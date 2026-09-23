import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/document_session.dart';

import 'support/fakes.dart';

void main() {
  group('workspace save snapshots', () {
    late _DelayedMarkdownFileService files;
    late MemoryWorkspaceSessionStore sessions;
    late WorkspaceController workspace;
    late DocumentSession document;

    setUp(() async {
      files = _DelayedMarkdownFileService()
        ..files['/notes/one.md'] = 'Original';
      sessions = MemoryWorkspaceSessionStore();
      workspace = WorkspaceController(
        fileService: files,
        sessionStore: sessions,
      );
      await workspace.initialize();
      document = (await workspace.openPath('/notes/one.md'))!;
    });

    tearDown(() async {
      workspace.dispose();
      await files.dispose();
    });

    test(
      'typing during save stays dirty against the written snapshot',
      () async {
        document.controller.text = 'Saved snapshot';
        final saving = workspace.saveDocument(document);
        final write = await files.nextWrite();
        const edited = TextEditingValue(
          text: 'Later typing',
          selection: TextSelection.collapsed(offset: 5),
        );
        document.controller.value = edited;
        write.complete();
        expect(await saving, isTrue);

        expect(files.files['/notes/one.md'], 'Saved snapshot');
        expect(document.controller.value, edited);
        expect(document.persistedText, 'Saved snapshot');
        expect(document.controller.isDirty, isTrue);
        final recovery = sessions.snapshot!.documents.singleWhere(
          (entry) => entry['id'] == document.id,
        );
        expect(recovery['text'], 'Later typing');
        expect(recovery['persistedText'], 'Saved snapshot');

        document.controller.undo();
        expect(document.controller.text, 'Saved snapshot');
        expect(document.controller.isDirty, isFalse);
        document.controller.redo();
        expect(document.controller.value, edited);
        expect(document.controller.isDirty, isTrue);
      },
    );

    test(
      'queued saves preserve request order and their own snapshots',
      () async {
        document.controller.text = 'First save';
        final firstSave = workspace.saveDocument(document);
        final firstWrite = await files.nextWrite();
        document.controller.text = 'Second save';
        final secondSave = workspace.saveDocument(document);
        await Future<void>.delayed(Duration.zero);
        expect(files.startedWrites, hasLength(1));

        firstWrite.complete();
        expect(await firstSave, isTrue);
        final secondWrite = await files.nextWrite();
        expect(secondWrite.contents, 'Second save');
        document.controller.text = 'Typing after both requests';
        secondWrite.complete();
        expect(await secondSave, isTrue);

        expect(files.files['/notes/one.md'], 'Second save');
        expect(document.persistedText, 'Second save');
        expect(document.controller.text, 'Typing after both requests');
        expect(document.controller.isDirty, isTrue);
        document.controller.undo();
        expect(document.controller.text, 'Second save');
        expect(document.controller.isDirty, isFalse);
      },
    );

    test('save after pending Save As follows the new path', () async {
      files.saveDialog = Completer<String?>();
      document.controller.text = 'Save As snapshot';
      final saveAs = workspace.saveDocument(document, saveAs: true);
      document.controller.text = 'Next save snapshot';
      final nextSave = workspace.saveDocument(document);
      files.saveDialog!.complete('/notes/renamed.md');

      final firstWrite = await files.nextWrite();
      expect(firstWrite.path, '/notes/renamed.md');
      expect(firstWrite.contents, 'Save As snapshot');
      firstWrite.complete();
      expect(await saveAs, isTrue);
      final secondWrite = await files.nextWrite();
      expect(secondWrite.path, '/notes/renamed.md');
      expect(secondWrite.contents, 'Next save snapshot');
      secondWrite.complete();
      expect(await nextSave, isTrue);

      expect(files.files['/notes/one.md'], 'Original');
      expect(files.files['/notes/renamed.md'], 'Next save snapshot');
      expect(document.path, '/notes/renamed.md');
      expect(document.name, 'renamed.md');
      expect(document.accessToken, 'access:/notes/renamed.md');
      expect(document.persistedText, 'Next save snapshot');
      expect(document.controller.isDirty, isFalse);
    });

    test(
      'failed write preserves baseline and does not block a retry',
      () async {
        document.controller.text = 'First save';
        final failedSave = workspace.saveDocument(document);
        final failedExpectation = expectLater(failedSave, throwsStateError);
        final firstWrite = await files.nextWrite();
        document.controller.text = 'Retry snapshot';
        final retry = workspace.saveDocument(document);
        firstWrite.fail(StateError('Disk unavailable'));
        await failedExpectation;
        expect(document.persistedText, 'Original');
        expect(document.controller.isDirty, isTrue);

        final retryWrite = await files.nextWrite();
        expect(retryWrite.contents, 'Retry snapshot');
        retryWrite.complete();
        expect(await retry, isTrue);
        expect(files.files['/notes/one.md'], 'Retry snapshot');
        expect(document.persistedText, 'Retry snapshot');
        expect(document.controller.isDirty, isFalse);
      },
    );

    test(
      'cancelled Save As preserves baseline, path, and later edits',
      () async {
        files.saveDialog = Completer<String?>();
        document.controller.text = 'Save As snapshot';
        final saving = workspace.saveDocument(document, saveAs: true);
        document.controller.text = 'Later typing';
        files.saveDialog!.complete(null);
        expect(await saving, isFalse);

        expect(files.startedWrites, isEmpty);
        expect(document.path, '/notes/one.md');
        expect(document.persistedText, 'Original');
        expect(document.controller.text, 'Later typing');
        expect(document.controller.isDirty, isTrue);

        final retry = workspace.saveDocument(document);
        final retryWrite = await files.nextWrite();
        retryWrite.complete();
        expect(await retry, isTrue);
        expect(document.persistedText, 'Later typing');
        expect(document.controller.isDirty, isFalse);
      },
    );
  });

  for (final useToolbar in [false, true]) {
    final entryPoint = useToolbar ? 'toolbar' : 'shortcut';
    testWidgets('$entryPoint save does not clear newer edits', (tester) async {
      final controller = IanvsMarkdownController(text: 'Original');
      addTearDown(controller.dispose);
      controller.text = 'Saved snapshot';
      final completion = Completer<void>();
      final saved = <String>[];

      await _pumpSaveEditor(tester, controller, (contents) async {
        saved.add(contents);
        await completion.future;
      }, useToolbar: useToolbar);
      await _requestSave(tester, useToolbar: useToolbar);
      expect(saved, ['Saved snapshot']);
      controller.text = 'Later typing';
      completion.complete();
      await tester.pump();

      expect(controller.text, 'Later typing');
      expect(controller.isDirty, isTrue);
      controller.undo();
      expect(controller.text, 'Saved snapshot');
      expect(controller.isDirty, isFalse);
      controller.redo();
      expect(controller.text, 'Later typing');
      expect(controller.isDirty, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$entryPoint cancellation leaves the baseline unchanged', (
      tester,
    ) async {
      final controller = IanvsMarkdownController(text: 'Original');
      addTearDown(controller.dispose);
      controller.text = 'Unsaved';
      await _pumpSaveEditor(tester, controller, (_) async {
        throw const IanvsMarkdownSaveCancelledException();
      }, useToolbar: useToolbar);
      await _requestSave(tester, useToolbar: useToolbar);
      expect(controller.isDirty, isTrue);
      controller.undo();
      expect(controller.text, 'Original');
      expect(controller.isDirty, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

Future<void> _pumpSaveEditor(
  WidgetTester tester,
  IanvsMarkdownController controller,
  IanvsMarkdownSaveCallback save, {
  required bool useToolbar,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            if (useToolbar)
              IanvsMarkdownEditorToolbar(
                controller: controller,
                onSaveRequested: save,
              ),
            IanvsMarkdownEditorShortcuts(
              controller: controller,
              onSaveRequested: save,
              child: TextField(controller: controller, autofocus: true),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _requestSave(
  WidgetTester tester, {
  required bool useToolbar,
}) async {
  if (useToolbar) {
    await tester.tap(find.byTooltip('保存'));
  } else {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  }
  await tester.pump();
}

class _DelayedMarkdownFileService extends MemoryMarkdownFileService {
  final List<_PendingWrite> startedWrites = [];
  final Map<int, Completer<_PendingWrite>> _waiting = {};
  int _nextWrite = 0;
  Completer<String?>? saveDialog;

  Future<_PendingWrite> nextWrite() {
    final index = _nextWrite++;
    if (index < startedWrites.length) {
      return Future.value(startedWrites[index]);
    }
    return (_waiting[index] ??= Completer<_PendingWrite>()).future;
  }

  @override
  Future<String?> chooseSavePath(String suggestedName) =>
      saveDialog?.future ?? super.chooseSavePath(suggestedName);

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    final write = _PendingWrite(path, contents);
    final index = startedWrites.length;
    startedWrites.add(write);
    _waiting.remove(index)?.complete(write);
    await write.completion.future;
    files[path] = contents;
  }
}

class _PendingWrite {
  _PendingWrite(this.path, this.contents);

  final String path;
  final String contents;
  final Completer<void> completion = Completer<void>();

  void complete() => completion.complete();
  void fail(Object error) => completion.completeError(error);
}
