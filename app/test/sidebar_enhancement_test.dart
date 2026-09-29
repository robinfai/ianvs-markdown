import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/widgets/workspace_sidebar.dart';
import 'support/fakes.dart';

WorkspaceEntry file(String path, {bool folder = false}) =>
    WorkspaceEntry(path: path, name: path.split('/').last, isDirectory: folder);
void main() {
  late _FailingFiles files;
  late WorkspaceController workspace;
  late MemoryWorkspaceSessionStore store;
  final errors = <String>[];
  setUp(() async {
    files = _FailingFiles()..selectedFolder = '/vault';
    files.files.addAll({
      '/vault/a.md': '# A',
      '/vault/b.md': '# B',
      '/vault/docs/deep.md': '# Deep',
    });
    files.directories.addAll({
      '/vault': [
        file('/vault/docs', folder: true),
        file('/vault/a.md'),
        file('/vault/b.md'),
      ],
      '/vault/docs': [file('/vault/docs/deep.md')],
    });
    store = MemoryWorkspaceSessionStore();
    workspace = WorkspaceController(fileService: files, sessionStore: store);
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
    errors.clear();
  });
  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });
  Future<void> pump(WidgetTester tester, {double width = 248}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: WorkspaceSidebar(
              workspace: workspace,
              width: width,
              onError: errors.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  }

  Future<void> menu(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Workspace actions'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text(name),
        matching: find.byWidgetPredicate(
          (widget) => widget is PopupMenuEntry<String>,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> contextAction(
    WidgetTester tester,
    String path,
    String action, {
    bool folder = false,
  }) async {
    await tester.tap(
      find.byKey(ValueKey('workspace-${folder ? 'directory' : 'file'}-$path')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'macOS Control-click opens a menu without opening the file or toggling selection',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('a.md'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      // The parent context menu intentionally owns this modified click.
      await tester.tapAt(tester.getCenter(find.text('b.md')));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(workspace.activeDocument!.path, '/vault/a.md');
      expect(workspace.browser.selected, {'/vault/b.md'});
      expect(find.text('Copy Path'), findsOneWidget);
      expect(find.text('Move to Trash'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Move to Trash')).dy,
        greaterThan(tester.getTopLeft(find.text('Copy Path')).dy),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Copy Path'), findsNothing);
      await tester.tap(find.text('a.md'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.tap(find.text('b.md'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(workspace.browser.selected, {'/vault/a.md', '/vault/b.md'});
      expect(workspace.activeDocument!.path, '/vault/a.md');
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'batch partial failure reports exact count and keeps failed file intact',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('a.md'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.tap(find.text('b.md'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      files.failMoveSource = '/vault/b.md';
      await tester.tap(find.byTooltip('Move selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'docs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move Here'));
      await tester.pumpAndSettle();
      expect(files.files['/vault/docs/a.md'], '# A');
      expect(files.files['/vault/b.md'], '# B');
      expect(errors.single, contains('1 item(s) moved. b.md:'));
      await finish(tester);
    },
  );

  testWidgets('move collision preflight changes none of the selected files', (
    tester,
  ) async {
    files.files['/vault/docs/b.md'] = 'existing';
    await pump(tester);
    await tester.tap(find.text('a.md'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.text('b.md'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'docs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move Here'));
    await tester.pumpAndSettle();
    expect(files.files['/vault/a.md'], '# A');
    expect(files.files['/vault/b.md'], '# B');
    expect(files.files['/vault/docs/b.md'], 'existing');
    expect(errors.single, contains('Destination already exists'));
    await finish(tester);
  });

  testWidgets(
    'external create asks for containing-folder access and leaves workspace intact',
    (tester) async {
      files.files['/outside/open.md'] = 'outside';
      await workspace.openPath('/outside/open.md');
      files.selectedFolder = '/outside';
      await pump(tester);
      await contextAction(tester, '/outside', 'New Markdown', folder: true);
      expect(find.text('Folder access needed'), findsOneWidget);
      await tester.tap(find.text('Choose Folder'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'new note',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(files.files['/outside/new note.md'], '');
      expect(workspace.workspaceRoot, '/vault');
      expect(workspace.activeDocument?.path, '/outside/new note.md');
      expect(errors, isEmpty);
      await finish(tester);
    },
  );

  testWidgets('search result reveal and relative-path copy work', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('workspace-search-field')),
      'deep',
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    await contextAction(tester, '/vault/docs/deep.md', 'Copy Relative Path');
    expect(clipboard, 'docs/deep.md');
    await contextAction(tester, '/vault/docs/deep.md', 'Show in File Tree');
    expect(workspace.browser.query, isEmpty);
    expect(workspace.browser.focusedPath, '/vault/docs/deep.md');
    expect(find.text('deep.md'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'keyboard focus is independent, arrows traverse and Enter opens',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();
      expect(find.text('deep.md'), findsOneWidget);
      final active = workspace.activeDocument;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(workspace.browser.focusedPath, '/vault/docs/deep.md');
      expect(workspace.activeDocument, same(active));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(workspace.activeDocument?.path, '/vault/docs/deep.md');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(workspace.browser.focusedPath, '/vault/docs');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('deep.md'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('deep.md'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('reveal active, search paths/highlight and Escape restore tree', (
    tester,
  ) async {
    await workspace.openPath('/vault/docs/deep.md');
    await pump(tester);
    expect(find.text('deep.md'), findsNothing);
    await tester.tap(find.byTooltip('Reveal active file'));
    await tester.pumpAndSettle();
    expect(find.text('deep.md'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('workspace-search-field')),
      'docs/deep',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('deep.md', findRichText: true), findsOneWidget);
    expect(find.text('1 result'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('deep.md'), findsOneWidget);
    expect(workspace.browser.query, isEmpty);
    await finish(tester);
  });

  testWidgets(
    'inline create validates collision and rename preserves unsaved text',
    (tester) async {
      await pump(tester);
      await menu(tester, 'New Markdown');
      final editor = find.byKey(const ValueKey('file-name-editor'));
      await tester.enterText(editor, 'a');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(files.files['/vault/a.md'], '# A');
      await tester.enterText(editor, '新笔记');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(files.files['/vault/新笔记.md'], '');
      expect(workspace.activeDocument?.path, '/vault/新笔记.md');
      workspace.activeDocument!.controller.text = 'draft';
      await tester.pumpAndSettle();
      await contextAction(tester, '/vault/新笔记.md', 'Rename');
      expect(
        tester
            .widget<TextField>(editor)
            .controller!
            .selection
            .textInside('新笔记.md'),
        '新笔记',
      );
      await tester.enterText(editor, 'renamed.md');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(workspace.activeDocument?.path, '/vault/renamed.md');
      expect(workspace.activeDocument?.controller.text, 'draft');
      expect(workspace.activeDocument?.controller.isDirty, isTrue);
      expect(
        find.textContaining('Relative Markdown links were not updated'),
        findsOneWidget,
      );
      expect(errors, isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'inline folder create and Escape cancel; selection chooses parent',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();
      await menu(tester, 'New Folder');
      await tester.enterText(
        find.byKey(const ValueKey('file-name-editor')),
        'notes',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(files.directories, contains('/vault/docs/notes'));
      await menu(tester, 'New Markdown');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('file-name-editor')), findsNothing);
      expect(files.files.keys.where((p) => p.contains('Untitled')), isEmpty);
      await finish(tester);
    },
  );

  testWidgets('multi-select and move picker move only selected files', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('a.md'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.text('b.md'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(workspace.browser.selected, {'/vault/a.md', '/vault/b.md'});
    expect(workspace.activeDocument?.path, '/vault/a.md');
    await tester.tap(find.byTooltip('Move selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'docs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move Here'));
    await tester.pumpAndSettle();
    expect(files.files, containsPair('/vault/docs/a.md', '# A'));
    expect(files.files, containsPair('/vault/docs/b.md', '# B'));
    expect(files.files, contains('/vault/docs/deep.md'));
    expect(workspace.activeDocument?.path, '/vault/docs/a.md');
    expect(errors, isEmpty);
    await finish(tester);
  });

  testWidgets('shift selection, favorites persist and can be removed', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('a.md'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('b.md'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(workspace.browser.selected.length, 2);
    await contextAction(tester, '/vault/a.md', 'Add Favorite');
    expect(find.text('Favorites'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect((store.snapshot!.browserState['/vault'] as Map)['favorites'], {
      '/vault/a.md': false,
    });
    await contextAction(tester, '/vault/a.md', 'Remove Favorite');
    expect(find.text('Favorites'), findsNothing);
    await finish(tester);
  });

  testWidgets('Trash dirty descendants: cancel, then save and Trash', (
    tester,
  ) async {
    final doc = (await workspace.openPath('/vault/docs/deep.md'))!;
    doc.controller.text = 'unsaved';
    await pump(tester);
    await contextAction(tester, '/vault/docs', 'Move to Trash', folder: true);
    expect(find.textContaining('1 open document(s)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(files.trashed, isEmpty);
    expect(doc.controller.text, 'unsaved');
    await contextAction(tester, '/vault/docs', 'Move to Trash', folder: true);
    await tester.tap(find.text('Save and Trash'));
    await tester.pumpAndSettle();
    expect(files.trashed, ['/vault/docs']);
    expect(
      workspace.documents.any((d) => d.path == '/vault/docs/deep.md'),
      isFalse,
    );
    expect(errors, isEmpty);
    await finish(tester);
  });

  testWidgets('Trash discard and duplicate saved copy', (tester) async {
    final doc = (await workspace.openPath('/vault/a.md'))!;
    doc.controller.text = 'draft';
    await pump(tester);
    await contextAction(tester, '/vault/a.md', 'Duplicate Saved Copy');
    expect(files.files['/vault/a copy.md'], '# A');
    await contextAction(tester, '/vault/a.md', 'Move to Trash');
    await tester.tap(find.text('Discard and Trash'));
    await tester.pumpAndSettle();
    expect(files.trashed, ['/vault/a.md']);
    expect(errors, isEmpty);
    await finish(tester);
  });

  testWidgets('vertical mouse drag moves a child directly to the root title', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    final source = tester.getCenter(
      find.byKey(const ValueKey('workspace-file-/vault/docs/deep.md')),
    );
    final drag = await tester.startGesture(
      source,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(0, -24));
    await tester.pump();
    await drag.moveTo(
      Offset(source.dx, tester.getCenter(find.text('vault')).dy),
    );
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(files.files['/vault/deep.md'], '# Deep');
    expect(files.files, isNot(contains('/vault/docs/deep.md')));
    expect(errors, isEmpty);
    await finish(tester);
  });

  testWidgets('dropping a child in empty tree space moves it to the root', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    final source = tester.getCenter(
      find.byKey(const ValueKey('workspace-file-/vault/docs/deep.md')),
    );
    final drag = await tester.startGesture(
      source,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(24, 0));
    await tester.pump();
    final tree = tester.getRect(find.byType(ListView));
    await drag.moveTo(Offset(source.dx, tree.bottom - 30));
    await tester.pump();
    expect(find.text('Move to vault'), findsOneWidget);
    await drag.up();
    await tester.pumpAndSettle();
    expect(files.files['/vault/deep.md'], '# Deep');
    expect(files.files, isNot(contains('/vault/docs/deep.md')));
    expect(errors, isEmpty);
    await finish(tester);
  });

  testWidgets('root file row accepts a child and same-folder drop stays put', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    final source = tester.getCenter(
      find.byKey(const ValueKey('workspace-file-/vault/docs/deep.md')),
    );
    final sameFolder = await tester.startGesture(
      source,
      kind: PointerDeviceKind.mouse,
    );
    await sameFolder.moveBy(const Offset(24, 0));
    await tester.pump();
    await sameFolder.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('workspace-directory-/vault/docs')),
      ),
    );
    await tester.pump();
    await sameFolder.up();
    await tester.pumpAndSettle();
    expect(files.files['/vault/docs/deep.md'], '# Deep');
    expect(files.files, isNot(contains('/vault/deep.md')));
    final drag = await tester.startGesture(
      source,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(24, 0));
    await tester.pump();
    await drag.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('workspace-file-/vault/a.md')),
      ),
    );
    await tester.pump();
    expect(find.text('Move to vault'), findsOneWidget);
    await drag.up();
    await tester.pumpAndSettle();
    expect(files.files['/vault/deep.md'], '# Deep');
    expect(files.files['/vault/a.md'], '# A');
    expect(errors, isEmpty);
    await finish(tester);
  });

  testWidgets('folder drop in root space remaps an open dirty descendant', (
    tester,
  ) async {
    files.files['/vault/docs/nested/draft.md'] = 'saved';
    files.directories['/vault/docs']!.add(
      file('/vault/docs/nested', folder: true),
    );
    files.directories['/vault/docs/nested'] = [
      file('/vault/docs/nested/draft.md'),
    ];
    final document = (await workspace.openPath('/vault/docs/nested/draft.md'))!;
    document.controller.text = 'unsaved';
    await pump(tester);
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('workspace-directory-/vault/docs/nested')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(24, 0));
    await tester.pump();
    await drag.moveTo(
      tester.getCenter(find.byKey(const ValueKey('workspace-root-drop-space'))),
    );
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(document.path, '/vault/nested/draft.md');
    expect(document.controller.text, 'unsaved');
    expect(document.controller.isDirty, isTrue);
    expect(files.files['/vault/nested/draft.md'], 'saved');
    expect(errors, isEmpty);
    await finish(tester);
  });

  testWidgets('drag moves a file into folder and can move it back to root', (
    tester,
  ) async {
    await pump(tester);
    final source = find.byKey(const ValueKey('workspace-file-/vault/a.md'));
    final folder = find.byKey(
      const ValueKey('workspace-directory-/vault/docs'),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(source),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(folder));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(files.files, contains('/vault/docs/a.md'));
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    final back = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('workspace-file-/vault/docs/a.md')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await back.moveBy(const Offset(24, 0));
    await tester.pump();
    await back.moveTo(tester.getCenter(find.text('vault')));
    await tester.pump();
    await back.up();
    await tester.pumpAndSettle();
    expect(files.files, contains('/vault/a.md'));
    expect(errors, isEmpty);
    await finish(tester);
  });

  testWidgets(
    'virtualization, scrolling, search return and remount retain position',
    (tester) async {
      for (var i = 0; i < 1000; i++) {
        files.directories['/vault']!.add(file('/vault/note-$i.md'));
      }
      await workspace.browser.refresh();
      await pump(tester);
      expect(
        find.byType(Draggable<List<String>>).evaluate().length,
        lessThan(60),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      final offset = workspace.browser.preferences.scroll;
      expect(offset, greaterThan(0));
      await tester.enterText(
        find.byKey(const ValueKey('workspace-search-field')),
        'note-900',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(workspace.browser.preferences.scroll, offset);
      await finish(tester);
      await pump(tester);
      final scrolling = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      expect(scrolling.position.pixels, offset);
      await finish(tester);
      workspace.dispose();
      workspace = WorkspaceController(fileService: files, sessionStore: store);
      await workspace.initialize();
      await pump(tester);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .pixels,
        offset,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'minimum width keeps actions, deep paths and inline editor usable',
    (tester) async {
      await workspace.openPath('/vault/docs/deep.md');
      await pump(tester, width: 180);
      expect(find.byTooltip('Reveal active file'), findsNothing);
      await menu(tester, 'Reveal Active File');
      expect(find.text('deep.md'), findsOneWidget);
      await contextAction(tester, '/vault/docs/deep.md', 'Rename');
      expect(
        tester.getSize(find.byKey(const ValueKey('file-name-editor'))).width,
        greaterThan(60),
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('folder retry and optional follow work from workspace controls', (
    tester,
  ) async {
    files.failListPath = '/vault/docs';
    await pump(tester);
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to read folder — Retry'), findsOneWidget);
    files.failListPath = null;
    await tester.tap(find.text('Unable to read folder — Retry'));
    await tester.pumpAndSettle();
    expect(find.text('deep.md'), findsOneWidget);
    await menu(tester, 'Collapse All');
    expect(find.text('deep.md'), findsNothing);
    await menu(tester, 'Follow Active File');
    await workspace.openPath('/vault/docs/deep.md');
    await tester.pumpAndSettle();
    expect(find.text('deep.md'), findsOneWidget);
    expect(workspace.browser.preferences.follow, isTrue);
    await menu(tester, 'Sort by Modified Time');
    expect(workspace.browser.preferences.sort.name, 'modified');
    await finish(tester);
  });

  testWidgets('batch Trash of external groups touches only opened files', (
    tester,
  ) async {
    files.files.addAll({
      '/outside/open.md': 'opened',
      '/outside/private.md': 'unlisted',
    });
    await workspace.openPath('/outside/open.md');
    files.selectedFolder = '/outside';
    await workspace.chooseOperationFolder();
    await pump(tester);
    final directory = find.byKey(
      const ValueKey('workspace-directory-/outside'),
    );
    await tester.tap(directory, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Move to Trash'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(directory);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('Move 1 item(s) to Trash?'), findsOneWidget);
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    expect(files.trashed, ['/outside/open.md']);
    expect(files.files['/outside/private.md'], 'unlisted');
    expect(errors, isEmpty);
    await finish(tester);
  });

  testWidgets('external changes update visible folder and dirty indicator', (
    tester,
  ) async {
    await pump(tester);
    files.files['/vault/new.md'] = 'new';
    files.directories['/vault']!.add(file('/vault/new.md'));
    files.events.add(FileSystemCreateEvent('/vault/new.md', false));
    await tester.pump();
    // The watcher was registered during setUp, in the real async zone.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 180)),
    );
    await tester.pumpAndSettle();
    expect(find.text('new.md'), findsOneWidget);
    await tester.tap(find.text('a.md'));
    await tester.pumpAndSettle();
    workspace.activeDocument!.controller.text = 'dirty';
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.circle), findsOneWidget);
    await finish(tester);
  });
}

class _FailingFiles extends MemoryMarkdownFileService {
  String? failMoveSource;
  String? failListPath;
  @override
  Future<List<WorkspaceEntry>> listDirectory(String path) async {
    if (path == failListPath) throw StateError('Simulated unavailable folder');
    return super.listDirectory(path);
  }

  @override
  Future<void> moveEntry(String source, String destination) async {
    if (source == failMoveSource) throw StateError('Simulated disk failure');
    return super.moveEntry(source, destination);
  }
}
