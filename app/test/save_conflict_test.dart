import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/document_session.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'package:linefold/src/widgets/save_conflict_diff_dialog.dart';

import 'support/fakes.dart';

void main() {
  late _SaveDialogFiles files;
  late WorkspaceController workspace;
  late MemoryWorkspaceSessionStore store;
  late DocumentSession document;

  setUp(() async {
    files = _SaveDialogFiles()..files['/notes/one.md'] = 'Original';
    store = MemoryWorkspaceSessionStore();
    workspace = WorkspaceController(fileService: files, sessionStore: store);
    await workspace.initialize();
    document = (await workspace.openPath('/notes/one.md'))!;
    document.controller.text = 'My edits';
  });

  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });

  test('save detects external bytes even without a watcher event', () async {
    files.files[document.path!] = 'External edits';
    expect(document.hasExternalChanges, isFalse);
    expect(await workspace.saveDocument(document), isFalse);
    expect(files.files[document.path], 'External edits');
    expect(document.persistedText, 'Original');
    expect(document.controller.isDirty, isTrue);
    expect(document.hasExternalChanges, isTrue);
  });

  test(
    'Keep Both preserves disk and saves the captured local version',
    () async {
      files.files[document.path!] = 'External edits';
      files.selectedFolder = '/notes';
      await workspace.chooseOperationFolder();
      files.files['/notes/one local copy.md'] = 'Existing copy';
      expect(
        await workspace.saveDocument(
          document,
          onConflict: (conflict) async {
            expect(conflict.localContents, 'My edits');
            document.controller.text = 'Newer typing';
            return SaveConflictChoice.keepBoth;
          },
        ),
        isTrue,
      );
      expect(files.files['/notes/one.md'], 'External edits');
      expect(files.files['/notes/one local copy.md'], 'Existing copy');
      expect(files.files['/notes/one local copy 2.md'], 'My edits');
      expect(files.suggestedNames, isEmpty);
      expect(document.path, '/notes/one local copy 2.md');
      expect(document.persistedText, 'My edits');
      expect(document.controller.text, 'Newer typing');
      expect(document.controller.isDirty, isTrue);
    },
  );

  test('single-file Keep Both requests a scoped save destination', () async {
    files.files[document.path!] = 'External edits';
    files.enforceSingleFileScope = true;
    files.savePath = '/picked/one local copy.md';
    expect(workspace.canManage('/notes'), isFalse);
    expect(
      await workspace.saveDocument(
        document,
        onConflict: (_) async => SaveConflictChoice.keepBoth,
      ),
      isTrue,
    );
    expect(files.suggestedNames, ['one local copy.md']);
    expect(files.files['/notes/one.md'], 'External edits');
    expect(files.files['/picked/one local copy.md'], 'My edits');
    expect(files.files.containsKey('/notes/one local copy.md'), isFalse);
    expect(document.path, '/picked/one local copy.md');
    expect(document.accessToken, 'access:/picked/one local copy.md');
    expect(workspace.canManage('/picked'), isFalse);
  });

  test(
    'cancelling the Keep Both save panel retains the original draft',
    () async {
      files.files[document.path!] = 'External edits';
      files.cancelSaveDialog = true;
      expect(
        await workspace.saveDocument(
          document,
          onConflict: (_) async => SaveConflictChoice.keepBoth,
        ),
        isFalse,
      );
      expect(files.suggestedNames, ['one local copy.md']);
      expect(files.files, {'/notes/one.md': 'External edits'});
      expect(document.path, '/notes/one.md');
      expect(document.persistedText, 'Original');
      expect(document.controller.text, 'My edits');
      expect(document.controller.isDirty, isTrue);
    },
  );

  test('Keep Both revalidates an occupied save-panel destination', () async {
    files.files[document.path!] = 'External edits';
    files.savePath = '/picked/existing.md';
    files.files[files.savePath] = 'Other note';
    final paths = <String>[];
    expect(
      await workspace.saveDocument(
        document,
        onConflict: (conflict) async {
          paths.add(conflict.path);
          return paths.length == 1
              ? SaveConflictChoice.keepBoth
              : SaveConflictChoice.cancel;
        },
      ),
      isFalse,
    );
    expect(paths, ['/notes/one.md', '/picked/existing.md']);
    expect(files.files['/notes/one.md'], 'External edits');
    expect(files.files[files.savePath], 'Other note');
    expect(document.path, '/notes/one.md');
    expect(document.persistedText, 'Original');
    expect(document.controller.isDirty, isTrue);
  });

  for (final keepBoth in [true, false]) {
    test(
      'new path never retains the old bookmark; Keep Both=$keepBoth',
      () async {
        expect(document.accessToken, 'access:/notes/one.md');
        files.savePath = '/picked/copy.md';
        files.failedBookmarkPaths.add(files.savePath);
        if (keepBoth) files.files[document.path!] = 'External edits';
        expect(
          await workspace.saveDocument(
            document,
            saveAs: !keepBoth,
            onConflict: (_) async => SaveConflictChoice.keepBoth,
          ),
          isTrue,
        );
        expect(document.path, files.savePath);
        expect(document.accessToken, isNull);
        await workspace.flushSession();
        final reopened = WorkspaceController(
          fileService: files,
          sessionStore: store,
        );
        try {
          await reopened.initialize();
          final copy = reopened.documents.firstWhere(
            (entry) => entry.id == document.id,
          );
          expect(copy.path, files.savePath);
          expect(copy.controller.text, 'My edits');
          expect(copy.accessToken, isNull);
          expect(
            files.files['/notes/one.md'],
            keepBoth ? 'External edits' : 'Original',
          );
        } finally {
          reopened.dispose();
        }
      },
    );
  }

  test('Save As to the same path keeps its valid existing bookmark', () async {
    files.savePath = '/notes/one.md';
    files.failedBookmarkPaths.add(files.savePath);
    expect(await workspace.saveDocument(document, saveAs: true), isTrue);
    expect(document.path, '/notes/one.md');
    expect(document.accessToken, 'access:/notes/one.md');
    expect(files.files[document.path], 'My edits');
  });

  test(
    'overwrite requires a new decision after another external edit',
    () async {
      files.files[document.path!] = 'External v1';
      final seen = <String?>[];
      expect(
        await workspace.saveDocument(
          document,
          onConflict: (conflict) async {
            seen.add(conflict.currentContents);
            if (seen.length == 1) {
              files.files[document.path!] = 'External v2';
              return SaveConflictChoice.overwrite;
            }
            return SaveConflictChoice.cancel;
          },
        ),
        isFalse,
      );
      expect(seen, ['External v1', 'External v2']);
      expect(files.files[document.path], 'External v2');
      expect(document.persistedText, 'Original');
    },
  );

  test('explicit overwrite updates baseline only after guarded save', () async {
    files.files[document.path!] = 'External edits';
    expect(
      await workspace.saveDocument(
        document,
        onConflict: (_) async => SaveConflictChoice.overwrite,
      ),
      isTrue,
    );
    expect(files.files[document.path], 'My edits');
    expect(document.persistedText, 'My edits');
    expect(document.controller.isDirty, isFalse);
  });

  test('external deletion is not silently recreated', () async {
    files.files.remove(document.path!);
    expect(await workspace.saveDocument(document), isFalse);
    expect(files.files.containsKey(document.path), isFalse);
    expect(
      await workspace.saveDocument(
        document,
        onConflict: (conflict) async {
          expect(conflict.currentContents, isNull);
          return SaveConflictChoice.overwrite;
        },
      ),
      isTrue,
    );
    expect(files.files[document.path], 'My edits');
  });

  test(
    'Save As cannot silently overwrite an unrelated existing file',
    () async {
      files.savePath = '/notes/other.md';
      files.files[files.savePath] = 'Other note';
      expect(await workspace.saveDocument(document, saveAs: true), isFalse);
      expect(files.files[files.savePath], 'Other note');
      expect(document.path, '/notes/one.md');
      expect(document.hasExternalChanges, isFalse);
    },
  );

  test(
    'queued save after conflict cancellation revalidates the disk',
    () async {
      files.files[document.path!] = 'External edits';
      final choice = Completer<SaveConflictChoice>();
      final first = workspace.saveDocument(
        document,
        onConflict: (_) => choice.future,
      );
      document.controller.text = 'Second save';
      final second = workspace.saveDocument(document);
      choice.complete(SaveConflictChoice.cancel);
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(files.files[document.path], 'External edits');
      expect(document.controller.text, 'Second save');
    },
  );

  testWidgets('conflict dialog cancel and Keep Both are routed from Save', (
    tester,
  ) async {
    files.selectedFolder = '/notes';
    await workspace.chooseOperationFolder();
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
    files.files[document.path!] = 'External edits';
    document.controller.mode = IanvsMarkdownEditorMode.source;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorShell(
          workspace: workspace,
          dark: false,
          onToggleTheme: () {},
          enableFileDrop: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-source-field')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Keep Both'), findsOneWidget);
    await tester.tap(find.text('Compare Changes'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SaveConflictDiffDialog),
        matching: find.text('Compare Changes'),
      ),
      findsOneWidget,
    );
    expect(find.text('External edits'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SaveConflictDiffDialog),
        matching: find.text('My edits'),
      ),
      findsOneWidget,
    );
    expect(files.files['/notes/one.md'], 'External edits');
    expect(document.controller.text, 'My edits');
    await tester.tap(find.text('Back to conflict'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(files.files['/notes/one.md'], 'External edits');
    expect(document.controller.isDirty, isTrue);
    await tester.tap(find.text('Resolve & Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep Both'));
    await tester.pumpAndSettle();
    expect(files.files['/notes/one.md'], 'External edits');
    expect(files.files['/notes/one local copy.md'], 'My edits');
    expect(find.text('Keep Both'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'close does not discard edits newer than the conflict save snapshot',
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
      files.files[document.path!] = 'External edits';
      document.controller.mode = IanvsMarkdownEditorMode.source;
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShell(
            workspace: workspace,
            dark: false,
            onToggleTheme: () {},
            enableFileDrop: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Keep Both'), findsOneWidget);
      document.controller.text = 'Newer edits while the decision was pending';
      await tester.tap(find.text('Overwrite'));
      await tester.pumpAndSettle();
      expect(workspace.documents, contains(document));
      expect(files.files[document.path], 'My edits');
      expect(
        document.controller.text,
        'Newer edits while the decision was pending',
      );
      expect(document.controller.isDirty, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}

class _SaveDialogFiles extends MemoryMarkdownFileService {
  final suggestedNames = <String>[];
  final scopedDestinations = <String>{};
  final failedBookmarkPaths = <String>{};
  bool cancelSaveDialog = false;
  bool enforceSingleFileScope = false;

  @override
  Future<String?> chooseSavePath(String suggestedName) async {
    suggestedNames.add(suggestedName);
    if (cancelSaveDialog) return null;
    scopedDestinations.add(savePath);
    return savePath;
  }

  @override
  Future<String?> createPersistentAccessToken(String path) async {
    if (failedBookmarkPaths.contains(path)) return null;
    return super.createPersistentAccessToken(path);
  }

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    if (enforceSingleFileScope &&
        path != '/notes/one.md' &&
        !scopedDestinations.contains(path)) {
      throw StateError('No permission for an unselected sibling');
    }
    await super.writeMarkdownFileAtomic(path, contents);
  }
}
