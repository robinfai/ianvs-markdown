import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'package:linefold/src/widgets/wiki_note_picker.dart';
import 'wiki_note_navigation_test.dart'
    show WikiFiles, IdentityWikiFiles, wikiWorkspace;

void main() {
  late WikiFiles files;
  late WorkspaceController workspace;
  Future<void> open(
    WidgetTester tester, {
    String source = '[[Target]]',
    WikiFiles? filesystem,
  }) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    files = (filesystem ?? WikiFiles())
      ..files.addAll({
        '/vault/Origin.md': source,
        '/vault/Target.md': 'Target body',
      });
    workspace = await wikiWorkspace(files);
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    workspace.setMode(IanvsMarkdownEditorMode.preview);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(Brightness.light),
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

  Future<void> tapLink(WidgetTester tester, String href) async {
    final editor = tester.widget<IanvsMarkdownLiveEditor>(
      find.byType(IanvsMarkdownLiveEditor),
    );
    editor.onTapLinkTarget!(
      IanvsMarkdownLinkTarget(
        text: href,
        href: href,
        kind: IanvsMarkdownLinkKind.wiki,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets(
    'Wiki alias reuses dirty tab and its own mode through the shell',
    (tester) async {
      final identityFiles = IdentityWikiFiles()
        ..aliases['/vault/target.md'] = '/vault/Target.md';
      await open(tester, filesystem: identityFiles);
      final origin = workspace.activeDocument!;
      final dirty = (await workspace.openPath('/vault/target.md'))!;
      dirty.controller.text = 'dirty source';
      dirty.controller.mode = IanvsMarkdownEditorMode.source;
      workspace.selectDocument(workspace.documents.indexOf(origin));
      await tester.pumpAndSettle();
      await tapLink(tester, 'Target');
      expect(workspace.activeDocument, same(dirty));
      expect(dirty.controller.text, 'dirty source');
      expect(dirty.controller.mode, IanvsMarkdownEditorMode.source);
      await finish(tester);
    },
  );
  Future<void> shortcut(WidgetTester tester, {bool control = false}) async {
    final modifier = control
        ? LogicalKeyboardKey.controlLeft
        : LogicalKeyboardKey.metaLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  for (final control in [false, true]) {
    testWidgets(
      'actual ${control ? 'Control' : 'Command'} Shift K opens link completion',
      (tester) async {
        await open(tester, source: 'source');
        workspace.setMode(IanvsMarkdownEditorMode.source);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(EditableText).last);
        await tester.pump();
        await shortcut(tester, control: control);
        expect(find.byType(WikiNotePicker), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(workspace.activeDocument!.controller.text, 'source');
        await finish(tester);
      },
    );
  }
  testWidgets('shortcut does not match while Read or source IME is active', (
    tester,
  ) async {
    await open(tester, source: 'source');
    final shell = tester.widget<CallbackShortcuts>(
      find.byType(CallbackShortcuts).first,
    );
    final wikiBindings = shell.bindings.keys
        .whereType<SingleActivator>()
        .where((a) => a.trigger == LogicalKeyboardKey.keyK)
        .toList();
    expect(wikiBindings, hasLength(2));
    final event = const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyK,
      logicalKey: LogicalKeyboardKey.keyK,
      timeStamp: Duration.zero,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(
      wikiBindings.any((a) => a.accepts(event, HardwareKeyboard.instance)),
      isFalse,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    workspace.setMode(IanvsMarkdownEditorMode.source);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EditableText).last);
    await tester.pump();
    final c = workspace.activeDocument!.controller;
    c.value = const TextEditingValue(
      text: 'source',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 0, end: 6),
    );
    await tester.pump();
    final before = c.value;
    await shortcut(tester);
    expect(find.byType(WikiNotePicker), findsNothing);
    expect(c.value, before);
    await finish(tester);
  });
  testWidgets(
    'typed Wiki opens scoped note and preserves origin source and mode',
    (tester) async {
      await open(tester);
      final origin = workspace.activeDocument!;
      await tapLink(tester, 'Target');
      expect(workspace.activeDocument!.path, '/vault/Target.md');
      expect(
        workspace.activeDocument!.controller.mode,
        IanvsMarkdownEditorMode.preview,
      );
      expect(origin.controller.text, '[[Target]]');
      await finish(tester);
    },
  );
  testWidgets(
    'missing cancel is no write and explicit create opens empty note',
    (tester) async {
      await open(tester, source: '[[New]]');
      await tapLink(tester, 'New');
      expect(find.text('Note not found'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(files.creates, 0);
      await tapLink(tester, 'New');
      await tester.tap(find.byKey(const ValueKey('wiki-create-note')));
      await tester.pumpAndSettle();
      expect(files.creates, 1);
      expect(workspace.activeDocument!.path, '/vault/New.md');
      expect(workspace.activeDocument!.controller.text, '');
      await finish(tester);
    },
  );
  testWidgets(
    'racing create collision refreshes without replacing existing content',
    (tester) async {
      await open(tester, source: '[[New]]');
      await tapLink(tester, 'New');
      await files.createEntry(
        '/vault/New.md',
        directory: false,
        contents: 'another writer',
      );
      await tester.tap(find.byKey(const ValueKey('wiki-create-note')));
      await tester.pumpAndSettle();
      expect(files.creates, 0);
      expect(files.files['/vault/New.md'], 'another writer');
      expect(workspace.activeDocument!.path, '/vault/Origin.md');
      expect(find.textContaining('The target changed.'), findsOneWidget);
      await finish(tester);
    },
  );
  testWidgets('create failure is visible and does not open a pretend note', (
    tester,
  ) async {
    await open(tester, source: '[[New]]');
    files.failCreate = true;
    await tapLink(tester, 'New');
    await tester.tap(find.byKey(const ValueKey('wiki-create-note')));
    await tester.pumpAndSettle();
    expect(files.creates, 1);
    expect(files.files, isNot(contains('/vault/New.md')));
    expect(find.textContaining('Unable to create the note:'), findsOneWidget);
    expect(workspace.activeDocument!.path, '/vault/Origin.md');
    await finish(tester);
  });
  testWidgets('unsupported block target has explicit notice and no file open', (
    tester,
  ) async {
    await open(tester);
    await tapLink(tester, 'Target#^block');
    expect(
      find.textContaining('Wiki heading and block navigation is not available'),
      findsOneWidget,
    );
    expect(workspace.activeDocument!.path, '/vault/Origin.md');
    await finish(tester);
  });
  testWidgets(
    'picker cancellation and captured source insertion with single undo',
    (tester) async {
      await open(tester, source: '😀 [[Ta trailing');
      workspace.setMode(IanvsMarkdownEditorMode.source);
      await tester.pumpAndSettle();
      final document = workspace.activeDocument!;
      document.controller.selection = const TextSelection.collapsed(offset: 7);
      await tester.tap(find.byKey(const ValueKey('insert-wiki-link-button')));
      await tester.pumpAndSettle();
      expect(find.byType(WikiNotePicker), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(document.controller.text, '😀 [[Ta trailing');
      await tester.tap(find.byKey(const ValueKey('insert-wiki-link-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wiki-note-Target.md')));
      await tester.pumpAndSettle();
      expect(document.controller.text, '😀 [[/Target]] trailing');
      document.controller.undo();
      expect(document.controller.text, '😀 [[Ta trailing');
      await finish(tester);
    },
  );
  testWidgets('stale modal result cannot insert into another tab', (
    tester,
  ) async {
    await open(tester, source: 'origin');
    workspace.setMode(IanvsMarkdownEditorMode.source);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('insert-wiki-link-button')));
    await tester.pumpAndSettle();
    final origin = workspace.activeDocument!;
    await workspace.openPath('/vault/Target.md');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wiki-note-Target.md')));
    await tester.pumpAndSettle();
    expect(origin.controller.text, 'origin');
    expect(workspace.activeDocument!.controller.text, 'Target body');
    await finish(tester);
  });
}
