import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/controllers/document_find_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/editor_commands.dart';
import 'package:linefold/src/widgets/desktop_menu_bar.dart';
import 'package:linefold/src/widgets/editor_shell.dart';

import 'support/fakes.dart';
import '../../test/fixtures/native_menu_harness.dart';

const queryKey = ValueKey('document-find-query');
const replacementKey = ValueKey('document-find-replacement');
const sourceKey = ValueKey('ianvs-markdown-source-field');
const barKey = ValueKey('document-find-bar');

void main() {
  Future<WorkspaceController> open(
    WidgetTester tester, {
    IanvsMarkdownEditorMode mode = IanvsMarkdownEditorMode.source,
    String text = 'one two one',
    Size size = const Size(1000, 800),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = MemoryMarkdownFileService()..files['/notes/find.md'] = text;
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    await workspace.initialize();
    await workspace.openPath('/notes/find.md');
    workspace.setMode(mode);
    workspace.toggleSidebar();
    workspace.toggleOutline();
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: EditorShell(
            workspace: workspace,
            dark: false,
            onToggleTheme: () {},
            enableFileDrop: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return workspace;
  }

  Future<void> showFind(WidgetTester tester) async {
    tester.widget<DesktopMenuBar>(find.byType(DesktopMenuBar)).onFind!();
    await tester.pumpAndSettle();
    expect(find.byKey(barKey), findsOneWidget);
  }

  Future<void> chooseSource(WidgetTester tester) async {
    tester
        .widget<DropdownButton<DocumentFindScope>>(
          find.byKey(const ValueKey('document-find-scope')),
        )
        .onChanged!(DocumentFindScope.source);
    await tester.pumpAndSettle();
  }

  Future<void> command(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
    bool control = false,
  }) async {
    final modifier = control
        ? LogicalKeyboardKey.controlLeft
        : LogicalKeyboardKey.metaLeft;
    await tester.sendKeyDownEvent(modifier);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets(
    'Command F and G search the unsaved buffer without stealing query focus',
    (tester) async {
      final workspace = await open(tester);
      final document = workspace.activeDocument!.controller;
      await tester.enterText(find.byKey(sourceKey), 'draft two draft');
      await command(tester, LogicalKeyboardKey.keyF);
      expect(find.byKey(barKey), findsOneWidget);
      await tester.enterText(find.byKey(queryKey), 'draft');
      await tester.pumpAndSettle();
      expect(find.text('1 of 2'), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(queryKey));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        document.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await command(tester, LogicalKeyboardKey.keyG);
      expect(find.text('2 of 2'), findsOneWidget);
      expect(
        document.selection,
        const TextSelection(baseOffset: 10, extentOffset: 15),
      );
      await command(tester, LogicalKeyboardKey.keyG, shift: true);
      expect(find.text('1 of 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(document.text, 'draft two draft');
      await finish(tester);
    },
  );

  testWidgets('Replace All is undoable as one source edit and never saves', (
    tester,
  ) async {
    final workspace = await open(tester);
    final document = workspace.activeDocument!.controller;
    await showFind(tester);
    await tester.enterText(find.byKey(queryKey), 'one');
    await tester.enterText(find.byKey(replacementKey), '🙂中文');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace All'));
    await tester.pumpAndSettle();
    expect(document.text, '🙂中文 two 🙂中文');
    expect(document.isDirty, isTrue);
    expect(
      (workspace.fileService as MemoryMarkdownFileService)
          .files['/notes/find.md'],
      'one two one',
    );
    await tester.tap(find.byKey(sourceKey));
    await command(tester, LogicalKeyboardKey.keyZ);
    expect(document.text, 'one two one');
    expect(document.canUndo, isFalse);
    await finish(tester);
  });

  for (final backwards in [false, true]) {
    testWidgets('closed Find resumes G navigation backwards=$backwards', (
      tester,
    ) async {
      final workspace = await open(tester);
      await showFind(tester);
      await tester.enterText(find.byKey(queryKey), 'one');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await command(tester, LogicalKeyboardKey.keyG, shift: backwards);
      expect(
        workspace.activeDocument!.controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 11),
      );
      await finish(tester);
    });
  }

  testWidgets('closed Find G uses caret without skipping the nearest match', (
    tester,
  ) async {
    final workspace = await open(tester);
    await showFind(tester);
    await tester.enterText(find.byKey(queryKey), 'one');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    workspace.activeDocument!.controller.selection =
        const TextSelection.collapsed(offset: 4);
    await command(tester, LogicalKeyboardKey.keyG);
    expect(
      workspace.activeDocument!.controller.selection,
      const TextSelection(baseOffset: 8, extentOffset: 11),
    );
    await finish(tester);
  });

  testWidgets('empty Source Find preserves scroll across both surface swaps', (
    tester,
  ) async {
    final workspace = await open(
      tester,
      text: List.generate(
        200,
        (i) => 'Line $i has some source text.',
      ).join('\n'),
    );
    final scroll = workspace.activeDocument!.scrollController;
    scroll.jumpTo(1000);
    await tester.pumpAndSettle();
    await showFind(tester);
    expect(scroll.offset, 1000);
    await tester.enterText(find.byKey(queryKey), 'missing query');
    await tester.pumpAndSettle();
    expect(scroll.offset, 1000);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(scroll.offset, 1000);
    await finish(tester);
  });

  testWidgets('no-match Find restores a scrolled focused Source viewport', (
    tester,
  ) async {
    final workspace = await open(
      tester,
      text: List.generate(200, (i) => 'Line $i has source text.').join('\n'),
    );
    await tester.tap(find.byKey(sourceKey));
    await tester.pumpAndSettle();
    final scroll = workspace.activeDocument!.scrollController;
    scroll.jumpTo(1000);
    await tester.pumpAndSettle();
    await command(tester, LogicalKeyboardKey.keyF);
    await tester.enterText(find.byKey(queryKey), 'missing query');
    await tester.pumpAndSettle();
    expect(scroll.offset, 1000);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(scroll.offset, 1000);
    await finish(tester);
  });

  testWidgets('Live Find Escape restores an editable selection and shortcuts', (
    tester,
  ) async {
    final workspace = await open(
      tester,
      mode: IanvsMarkdownEditorMode.livePreview,
      text: 'First paragraph.\n\nSecond paragraph.',
    );
    final document = workspace.activeDocument!.controller;
    await tester.tap(find.text('Second paragraph.'));
    await tester.pumpAndSettle();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    final start = document.text.indexOf('Second');
    final editingBefore = tester
        .widget<EditableText>(
          find.descendant(of: active, matching: find.byType(EditableText)),
        )
        .controller
        .value;
    final beforeFind = document.value;
    await command(tester, LogicalKeyboardKey.keyF);
    await tester.enterText(find.byKey(queryKey), 'Second');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(barKey), findsNothing);
    expect(document.value, beforeFind);
    expect(active, findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: active, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    final value = editable.controller.value;
    expect(value, editingBefore);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(
          value.selection.start,
          value.selection.end,
          'Next',
        ),
        selection: TextSelection.collapsed(offset: value.selection.start + 4),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      document.text,
      beforeFind.text.replaceRange(
        start + value.selection.start,
        start + value.selection.end,
        'Next',
      ),
    );
    await command(tester, LogicalKeyboardKey.keyZ);
    expect(document.text, beforeFind.text);
    await command(tester, LogicalKeyboardKey.keyF);
    expect(find.byKey(barKey), findsOneWidget);
    await finish(tester);
  });

  testWidgets('pending Live focus restoration cannot leak into the next tab', (
    tester,
  ) async {
    final workspace = await open(
      tester,
      mode: IanvsMarkdownEditorMode.livePreview,
    );
    await showFind(tester);
    await tester.enterText(find.byKey(queryKey), 'one');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    workspace.newDocument();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IanvsMarkdownLiveEditor>(find.byType(IanvsMarkdownLiveEditor))
          .autofocus,
      isFalse,
    );
    await finish(tester);
  });

  testWidgets('large-buffer pending search is visible and Escape cancels it', (
    tester,
  ) async {
    final source = 'line with target\n' * 5000;
    final workspace = await open(tester, text: source);
    await showFind(tester);
    await tester.enterText(find.byKey(queryKey), 'target');
    await tester.pump();
    expect(find.text('Searching…'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Replace All'))
          .onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(barKey), findsNothing);
    expect(workspace.activeDocument!.controller.text, source);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('closed G preserves its skip intent through an async search', (
    tester,
  ) async {
    final source = 'one\n${'plain text\n' * 6500}one';
    final workspace = await open(tester, text: source);
    final document = workspace.activeDocument!.controller;
    await showFind(tester);
    await tester.enterText(find.byKey(queryKey), 'one');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(
      document.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await command(tester, LogicalKeyboardKey.keyG);
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(
      document.selection,
      TextSelection(baseOffset: source.length - 3, extentOffset: source.length),
    );
    await finish(tester);
  });

  for (final remove in [false, true]) {
    testWidgets('pending paste cancels before tab rebuild remove=$remove', (
      tester,
    ) async {
      final clipboard = Completer<Map<String, String>>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') return clipboard.future;
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final workspace = await open(tester);
      final session = workspace.activeDocument!;
      final document = session.controller;
      await tester.tap(find.byKey(sourceKey));
      document.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      expect(
        IanvsMarkdownShortcuts.invoke(
          IanvsMarkdownCommand.paste,
          controller: document,
        ),
        isTrue,
      );
      if (remove) {
        workspace.removeDocument(session);
      } else {
        workspace.newDocument();
      }
      clipboard.complete({'text': 'https://example.com'});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(document.text, 'one two one');
      await finish(tester);
    });
  }

  testWidgets(
    'remembered YAML match is not redirected by the old Live surface',
    (tester) async {
      final workspace = await open(
        tester,
        mode: IanvsMarkdownEditorMode.livePreview,
        text: '---\ntitle: secret\n---\n\nBody paragraph.',
      );
      final document = workspace.activeDocument!.controller;
      await tester.tap(find.text('Body paragraph.'));
      await tester.pumpAndSettle();
      await command(tester, LogicalKeyboardKey.keyF);
      await chooseSource(tester);
      await tester.enterText(find.byKey(queryKey), 'secret');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await command(tester, LogicalKeyboardKey.keyF);
      await chooseSource(tester);
      expect(
        document.selection,
        const TextSelection(baseOffset: 11, extentOffset: 17),
      );
      expect(
        tester.widget<TextField>(find.byKey(queryKey)).focusNode!.hasFocus,
        isTrue,
      );
      await finish(tester);
    },
  );

  for (final mode in [
    IanvsMarkdownEditorMode.livePreview,
    IanvsMarkdownEditorMode.preview,
  ]) {
    testWidgets('temporary source search returns to ${mode.name} on Escape', (
      tester,
    ) async {
      final workspace = await open(tester, mode: mode);
      final document = workspace.activeDocument!.controller;
      await showFind(tester);
      await chooseSource(tester);
      await tester.enterText(find.byKey(queryKey), 'one');
      await tester.pumpAndSettle();
      expect(find.byKey(sourceKey), findsOneWidget);
      expect(document.mode, mode);
      expect(
        tester.widget<TextField>(find.byKey(sourceKey)).readOnly,
        mode == IanvsMarkdownEditorMode.preview,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(barKey), findsNothing);
      expect(document.mode, mode);
      expect(document.text, 'one two one');
      expect(document.isDirty, isFalse);
      expect(document.canUndo, isFalse);
      await finish(tester);
    });
  }

  testWidgets(
    'Read searches in place without changing selection or remounting',
    (tester) async {
      final workspace = await open(
        tester,
        mode: IanvsMarkdownEditorMode.preview,
        text: 'one **two** [label](hidden)\n\none two',
      );
      final document = workspace.activeDocument!.controller;
      final before = document.value;
      final readingElement = tester.element(find.byType(IanvsMarkdownView));
      await showFind(tester);
      expect(
        tester.element(find.byType(IanvsMarkdownView)),
        same(readingElement),
      );
      expect(find.byKey(sourceKey), findsNothing);
      await tester.enterText(find.byKey(queryKey), 'one two');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      var view = tester.widget<IanvsMarkdownView>(
        find.byType(IanvsMarkdownView),
      );
      expect(view.readingHighlights!.matches.length, 2);
      expect(view.readingHighlights!.activeIndex, 0);
      expect(document.value, before);
      await tester.tap(find.byTooltip('Next match (⌘G)'));
      await tester.pumpAndSettle();
      view = tester.widget<IanvsMarkdownView>(find.byType(IanvsMarkdownView));
      expect(view.readingHighlights!.activeIndex, 1);
      expect(document.value, before);
      await tester.enterText(find.byKey(queryKey), 'hidden');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IanvsMarkdownView>(find.byType(IanvsMarkdownView))
            .readingHighlights!
            .matches,
        isEmpty,
      );
      await tester.tap(find.byTooltip('Close find (Esc)'));
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(IanvsMarkdownView)),
        same(readingElement),
      );
      expect(document.value, before);
      expect(document.canUndo, isFalse);
      await finish(tester);
    },
  );

  testWidgets(
    'Live body search retains its component and reaches repeated list hits',
    (tester) async {
      final workspace = await open(
        tester,
        mode: IanvsMarkdownEditorMode.livePreview,
        text: '- same **phrase**\n- same phrase',
      );
      final document = workspace.activeDocument!.controller;
      final before = document.value;
      final element = tester.element(find.byType(IanvsMarkdownLiveEditor));
      await showFind(tester);
      expect(find.byKey(sourceKey), findsNothing);
      expect(
        tester.element(find.byType(IanvsMarkdownLiveEditor)),
        same(element),
      );
      await tester.enterText(find.byKey(queryKey), 'same phrase');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      var live = tester.widget<IanvsMarkdownLiveEditor>(
        find.byType(IanvsMarkdownLiveEditor),
      );
      expect(live.readingHighlights!.matches.length, 2);
      expect(live.readingHighlights!.activeIndex, 0);
      await tester.tap(find.byTooltip('Next match (⌘G)'));
      await tester.pumpAndSettle();
      live = tester.widget<IanvsMarkdownLiveEditor>(
        find.byType(IanvsMarkdownLiveEditor),
      );
      expect(live.readingHighlights!.activeIndex, 1);
      expect(live.readingHighlights!.matches.last.navigationRange.start, 18);
      expect(document.value, before);
      expect(
        tester.widget<TextField>(find.byKey(queryKey)).focusNode!.hasFocus,
        isTrue,
      );
      await tester.tap(find.byTooltip('Close find (Esc)'));
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(IanvsMarkdownLiveEditor)),
        same(element),
      );
      expect(document.value, before);
      expect(document.canUndo, isFalse);
      await finish(tester);
    },
  );

  testWidgets('Read find requires explicit edit action before replacement', (
    tester,
  ) async {
    final workspace = await open(tester, mode: IanvsMarkdownEditorMode.preview);
    final document = workspace.activeDocument!.controller;
    await showFind(tester);
    await tester.enterText(find.byKey(queryKey), 'one');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(replacementKey), findsNothing);
    expect(find.text('Replace All'), findsNothing);
    await tester.tap(find.text('Edit source to replace'));
    await tester.pumpAndSettle();
    expect(document.mode, IanvsMarkdownEditorMode.source);
    await tester.enterText(find.byKey(replacementKey), 'two');
    expect(tester.widget<TextField>(find.byKey(sourceKey)).readOnly, isFalse);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(document.text, 'two two one');
    await tester.tap(find.byTooltip('Close find (Esc)'));
    await tester.pumpAndSettle();
    expect(document.mode, IanvsMarkdownEditorMode.source);
    expect(document.text, 'two two one');
    await finish(tester);
  });

  testWidgets(
    'tab changes and explicit mode changes dismiss old search safely',
    (tester) async {
      final workspace = await open(tester);
      final first = workspace.activeDocument!.controller;
      await showFind(tester);
      await tester.enterText(find.byKey(queryKey), 'one');
      await tester.enterText(find.byKey(replacementKey), 'other');
      workspace.newDocument();
      await tester.pumpAndSettle();
      expect(find.byKey(barKey), findsNothing);
      expect(first.text, 'one two one');
      await showFind(tester);
      expect(
        tester.widget<TextField>(find.byKey(queryKey)).controller!.text,
        'one',
      );
      expect(find.text('0 of 0'), findsOneWidget);
      workspace.setMode(IanvsMarkdownEditorMode.preview);
      await tester.pumpAndSettle();
      expect(find.byKey(barKey), findsNothing);
      expect(
        workspace.activeDocument!.controller.mode,
        IanvsMarkdownEditorMode.preview,
      );
      await finish(tester);
    },
  );

  testWidgets('source composition is not interrupted when Find is requested', (
    tester,
  ) async {
    final workspace = await open(tester);
    await tester.tap(find.byKey(sourceKey));
    const composing = TextEditingValue(
      text: 'one ni',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 4, end: 6),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    await command(tester, LogicalKeyboardKey.keyF);
    expect(find.byKey(barKey), findsNothing);
    expect(workspace.activeDocument!.controller.value, composing);
    await finish(tester);
  });

  testWidgets(
    'query IME blocks navigation, close and replace until committed',
    (tester) async {
      final workspace = await open(tester, text: '你 你');
      await showFind(tester);
      await tester.enterText(find.byKey(queryKey), '你');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Finish composing'), findsOneWidget);
      await command(tester, LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(barKey), findsOneWidget);
      expect(workspace.activeDocument!.controller.text, '你 你');
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Replace All'))
            .onPressed,
        isNull,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '你',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 2'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('find controls wrap in a narrow large-text window', (
    tester,
  ) async {
    await open(tester, size: const Size(480, 1000), scale: 1.7);
    await showFind(tester);
    await tester.enterText(find.byKey(queryKey), 'one');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Replace All'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'removing the searched tab detaches disposed controller listeners',
    (tester) async {
      final workspace = await open(tester);
      await showFind(tester);
      await tester.enterText(find.byKey(queryKey), 'one');
      workspace.removeDocument(workspace.activeDocument!);
      await tester.pumpAndSettle();
      expect(find.byKey(barKey), findsNothing);
      expect(tester.takeException(), isNull);
      await showFind(tester);
      await finish(tester);
    },
  );

  testWidgets('Find does not change the underlying editor behind a dialog', (
    tester,
  ) async {
    await open(tester);
    final context = tester.element(find.byType(EditorShell));
    final dialog = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('Modal content')),
    );
    await tester.pumpAndSettle();
    tester.widget<DesktopMenuBar>(find.byType(DesktopMenuBar)).onFind!();
    await tester.pumpAndSettle();
    expect(find.byKey(barKey), findsNothing);
    Navigator.of(context).pop();
    await dialog;
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets(
    'focused Read search still permits Save and explicit mode menus',
    (tester) async {
      final workspace = await open(
        tester,
        mode: IanvsMarkdownEditorMode.preview,
      );
      final document = workspace.activeDocument!.controller;
      document.text = 'unsaved one';
      await showFind(tester);
      await tester.enterText(find.byKey(queryKey), 'one');
      await tester.tap(find.byKey(queryKey));
      await tester.pumpAndSettle();
      tester.widget<DesktopMenuBar>(find.byType(DesktopMenuBar)).onSave();
      await tester.pumpAndSettle();
      expect(
        (workspace.fileService as MemoryMarkdownFileService)
            .files['/notes/find.md'],
        'unsaved one',
      );
      expect(document.isDirty, isFalse);
      document.text = 'newer one';
      await tester.pumpAndSettle();
      await command(tester, LogicalKeyboardKey.keyS);
      expect(
        (workspace.fileService as MemoryMarkdownFileService)
            .files['/notes/find.md'],
        'newer one',
      );
      setEditorMode(workspace, IanvsMarkdownEditorMode.livePreview);
      await tester.pumpAndSettle();
      expect(find.byKey(barKey), findsNothing);
      expect(document.mode, IanvsMarkdownEditorMode.livePreview);
      expect(document.text, 'newer one');
      await finish(tester);
    },
  );

  testWidgets(
    'native Find menu uses the same current-buffer navigation',
    (tester) async {
      final menu = NativeMenuHarness(tester);
      final workspace = await open(tester);
      await menu.select('Find…');
      await tester.enterText(find.byKey(queryKey), 'one');
      await tester.pumpAndSettle();
      await menu.select('Find Next');
      expect(
        workspace.activeDocument!.controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 11),
      );
      await menu.select('Find Previous');
      expect(
        workspace.activeDocument!.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    skip: !Platform.isMacOS,
  );
}
