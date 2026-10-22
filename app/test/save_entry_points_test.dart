import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/document_session.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'package:linefold/src/widgets/title_tabs_bar.dart';

import 'support/fakes.dart';

void main() {
  late _SaveEntryFiles files;
  late WorkspaceController workspace;
  late DocumentSession document;

  setUp(() async {
    files = _SaveEntryFiles()
      ..selectedFolder = '/notes'
      ..files['/notes/one.md'] = 'Original'
      ..files['/notes/two.md'] = 'Second note'
      ..directories['/notes'] = [
        const WorkspaceEntry(
          path: '/notes/one.md',
          name: 'one.md',
          isDirectory: false,
        ),
        const WorkspaceEntry(
          path: '/notes/two.md',
          name: 'two.md',
          isDirectory: false,
        ),
      ];
    workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
    document = (await workspace.openPath('/notes/one.md'))!;
    document.controller
      ..mode = IanvsMarkdownEditorMode.source
      ..text = 'My edits';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
  });

  tearDown(() async {
    workspace.dispose();
    await files.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, null);
  });

  Future<void> pumpShell(WidgetTester tester) async {
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
  }

  Future<void> settleSave(WidgetTester tester) async {
    await tester.pumpAndSettle();
    // Replacing a watched path awaits subscription cancellation. Those futures
    // may complete outside the widget test's fake-async zone.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  }

  Future<void> tabAction(WidgetTester tester, String action) async {
    await tester.tap(
      find.descendant(
        of: find.byType(TitleTabsBar),
        matching: find.text('one.md'),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  Future<void> saveAndTrash(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('workspace-file-/notes/one.md')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save and Trash'));
    await tester.pumpAndSettle();
  }

  for (final saveAs in [false, true]) {
    final action = saveAs ? 'Save As…' : 'Save';
    final destination = saveAs ? '/notes/existing.md' : '/notes/one.md';
    final copy = saveAs
        ? '/notes/existing local copy.md'
        : '/notes/one local copy.md';

    for (final choice in ['Cancel', 'Keep Both', 'Overwrite']) {
      testWidgets('tab $action resolves $choice on the clicked inactive tab', (
        tester,
      ) async {
        files.savePath = destination;
        files.files[destination] = 'External contents';
        // Keep Both must not repurpose a pre-existing local copy either.
        files.files[copy] = 'Existing copy';
        final active = (await workspace.openPath('/notes/two.md'))!;
        active.controller.mode = IanvsMarkdownEditorMode.source;
        await pumpShell(tester);
        await tabAction(tester, action);
        expect(find.text('Keep Both'), findsOneWidget);
        expect(find.text('Overwrite'), findsOneWidget);
        expect(files.files[destination], 'External contents');
        expect(document.persistedText, 'Original');
        await tester.tap(find.text(choice));
        await settleSave(tester);

        expect(workspace.activeDocument, same(active));
        expect(files.files[copy], 'Existing copy');
        if (choice == 'Cancel') {
          expect(files.files[destination], 'External contents');
          expect(document.path, '/notes/one.md');
          expect(document.persistedText, 'Original');
          expect(document.controller.isDirty, isTrue);
        } else {
          final savedPath = choice == 'Keep Both'
              ? copy.replaceFirst('.md', ' 2.md')
              : destination;
          expect(files.files[savedPath], 'My edits');
          expect(document.path, savedPath);
          expect(document.persistedText, 'My edits');
          expect(document.controller.isDirty, isFalse);
          if (choice == 'Keep Both') {
            expect(files.files[destination], 'External contents');
          }
        }
        if (saveAs) expect(files.files['/notes/one.md'], 'Original');
        expect(find.text('Keep Both'), findsNothing);
        await finish(tester);
      });
    }

    testWidgets('tab $action keeps newer edits after resolving a conflict', (
      tester,
    ) async {
      files.savePath = destination;
      files.files[destination] = 'External contents';
      await pumpShell(tester);
      await tabAction(tester, action);
      expect(find.text('Overwrite'), findsOneWidget);
      document.controller.text = 'Newer edits';
      await tester.tap(find.text('Overwrite'));
      await settleSave(tester);
      expect(files.files[destination], 'My edits');
      expect(document.persistedText, 'My edits');
      expect(document.controller.text, 'Newer edits');
      expect(document.controller.isDirty, isTrue);
      await finish(tester);
    });

    testWidgets(
      'tab $action reports failed conflict writes without losing draft',
      (tester) async {
        files.savePath = destination;
        files.files[destination] = 'External contents';
        await pumpShell(tester);
        await tabAction(tester, action);
        expect(find.text('Overwrite'), findsOneWidget);
        files.failWrites = true;
        await tester.tap(find.text('Overwrite'));
        await settleSave(tester);
        expect(find.textContaining('Disk unavailable'), findsOneWidget);
        expect(files.files[destination], 'External contents');
        expect(document.path, '/notes/one.md');
        expect(document.persistedText, 'Original');
        expect(document.controller.text, 'My edits');
        expect(document.controller.isDirty, isTrue);
        await finish(tester);
      },
    );
  }

  testWidgets('tab Save As panel cancellation leaves the draft unchanged', (
    tester,
  ) async {
    files.cancelSaveDialog = true;
    await pumpShell(tester);
    await tabAction(tester, 'Save As…');
    expect(find.text('Keep Both'), findsNothing);
    expect(files.files['/notes/one.md'], 'Original');
    expect(document.path, '/notes/one.md');
    expect(document.persistedText, 'Original');
    expect(document.controller.isDirty, isTrue);
    await finish(tester);
  });

  for (final choice in ['Cancel', 'Keep Both', 'Overwrite']) {
    testWidgets('sidebar Save and Trash resolves $choice before trashing', (
      tester,
    ) async {
      files.files['/notes/one.md'] = 'External contents';
      files.files['/notes/one local copy.md'] = 'Existing copy';
      await pumpShell(tester);
      await saveAndTrash(tester);
      expect(find.text('Keep Both'), findsOneWidget);
      expect(files.trashed, isEmpty);
      await tester.tap(find.text(choice));
      await settleSave(tester);

      expect(files.files['/notes/one local copy.md'], 'Existing copy');
      if (choice == 'Cancel') {
        expect(files.trashed, isEmpty);
        expect(files.files['/notes/one.md'], 'External contents');
        expect(workspace.documents, contains(document));
        expect(document.persistedText, 'Original');
        expect(document.controller.isDirty, isTrue);
      } else {
        expect(files.trashed, ['/notes/one.md']);
        expect(files.files.containsKey('/notes/one.md'), isFalse);
        if (choice == 'Keep Both') {
          expect(files.contentsAtTrash['/notes/one.md'], 'External contents');
          expect(files.files['/notes/one local copy 2.md'], 'My edits');
          expect(workspace.documents, contains(document));
          expect(document.path, '/notes/one local copy 2.md');
          expect(document.controller.isDirty, isFalse);
        } else {
          expect(files.contentsAtTrash['/notes/one.md'], 'My edits');
          expect(workspace.documents, isNot(contains(document)));
        }
      }
      await finish(tester);
    });
  }

  for (final choice in ['Keep Both', 'Overwrite']) {
    testWidgets('sidebar $choice never trashes edits newer than its save', (
      tester,
    ) async {
      files.files['/notes/one.md'] = 'External contents';
      await pumpShell(tester);
      await saveAndTrash(tester);
      expect(find.text('Keep Both'), findsOneWidget);
      document.controller.text = 'Newer edits';
      await tester.tap(find.text(choice));
      await settleSave(tester);

      expect(files.trashed, isEmpty);
      expect(workspace.documents, contains(document));
      expect(document.persistedText, 'My edits');
      expect(document.controller.text, 'Newer edits');
      expect(document.controller.isDirty, isTrue);
      if (choice == 'Keep Both') {
        expect(files.files['/notes/one.md'], 'External contents');
        expect(files.files['/notes/one local copy.md'], 'My edits');
      } else {
        expect(files.files['/notes/one.md'], 'My edits');
      }
      await finish(tester);
    });

    testWidgets('sidebar failed $choice save reports error and never trashes', (
      tester,
    ) async {
      files.files['/notes/one.md'] = 'External contents';
      await pumpShell(tester);
      await saveAndTrash(tester);
      expect(find.text('Keep Both'), findsOneWidget);
      files.failWrites = true;
      await tester.tap(find.text(choice));
      await settleSave(tester);

      expect(find.textContaining('Disk unavailable'), findsOneWidget);
      expect(files.trashed, isEmpty);
      expect(files.files['/notes/one.md'], 'External contents');
      expect(files.files.containsKey('/notes/one local copy.md'), isFalse);
      expect(document.path, '/notes/one.md');
      expect(document.persistedText, 'Original');
      expect(document.controller.text, 'My edits');
      expect(document.controller.isDirty, isTrue);
      await finish(tester);
    });
  }
}

class _SaveEntryFiles extends MemoryMarkdownFileService {
  final contentsAtTrash = <String, String?>{};
  bool failWrites = false;
  bool cancelSaveDialog = false;

  @override
  Future<String?> chooseSavePath(String suggestedName) async =>
      cancelSaveDialog ? null : savePath;

  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    if (failWrites) throw StateError('Disk unavailable');
    await super.writeMarkdownFileAtomic(path, contents);
  }

  @override
  Future<void> trashEntry(String path) async {
    contentsAtTrash[path] = files[path];
    await super.trashEntry(path);
  }
}
