import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'package:linefold/src/widgets/desktop_menu_bar.dart';

import 'attachment_import_test.dart' show FakeImportPlatform, ImportSource;
import 'wiki_note_navigation_test.dart' show WikiFiles, wikiWorkspace;

void main() {
  late WikiFiles files;
  late WorkspaceController workspace;
  late FakeImportPlatform native;
  late ImportSource source;
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1100, 850),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    files = WikiFiles()
      ..files.addAll({
        '/vault/Origin.md': 'before after',
        '/vault/Target.md': 'other',
      });
    workspace = await wikiWorkspace(files);
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    native = FakeImportPlatform();
    source = ImportSource()
      ..settings = Uint8List.fromList(
        utf8.encode('{"attachmentFolderPath":"./附件"}'),
      );
    workspace.setMode(IanvsMarkdownEditorMode.source);
    workspace.activeDocument!.controller.selection =
        const TextSelection.collapsed(offset: 7);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: EditorShell(
          workspace: workspace,
          dark: false,
          onToggleTheme: () {},
          enableFileDrop: false,
          readClipboardText: () async => null,
          attachmentSource: source,
          attachmentImportPlatform: native,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(native.clipboardReads, 0);
    expect(native.picks, 0);
    expect(native.attempts, 0);
  }

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (done()) return;
    }
    fail(
      'Import did not reach the expected boundary: picks=${native.picks}, clipboard=${native.clipboardReads}, attempts=${native.attempts}, config=${source.reads}, texts=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}',
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> paste(WidgetTester tester, {bool keyboard = true}) async {
    await tester.tap(find.byType(EditableText).last);
    await tester.pump();
    if (keyboard) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    } else {
      expect(IanvsMarkdownShortcuts.invoke(IanvsMarkdownCommand.paste), isTrue);
    }
    await tester.pump();
  }

  Future<void> drop(WidgetTester tester, List<DropItem> items) async {
    tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
      DropDoneDetails(
        files: items,
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();
  }

  DropItemFile image([String path = '/outside/photo.PNG']) =>
      DropItemFile(path, extraAppleBookmark: Uint8List.fromList([1, 2, 3]));

  testWidgets(
    'single dropped image reuses attachment policy and undo preserves copy',
    (tester) async {
      await open(tester);
      final c = workspace.activeDocument!.controller;
      await drop(tester, [image()]);
      await waitFor(tester, () => c.text.contains('![]('));
      expect(native.droppedPaths, ['/outside/photo.PNG']);
      expect(native.droppedBookmarks.single, [1, 2, 3]);
      expect(native.picks, 0);
      expect(native.clipboardReads, 0);
      expect(native.files.keys.single, startsWith('附件/image-'));
      expect(c.text, startsWith('before ![](./%E9%99%84%E4%BB%B6/'));
      c.undo();
      expect(c.text, 'before after');
      expect(native.files, hasLength(1));
      await finish(tester);
    },
  );

  for (final kind in [
    'multiple',
    'mixed',
    'unsupported',
    'preview',
    'composition',
    'unsaved',
  ]) {
    testWidgets('image drop rejects $kind before source read or write', (
      tester,
    ) async {
      await open(tester);
      final c = workspace.activeDocument!.controller;
      var items = <DropItem>[image()];
      switch (kind) {
        case 'multiple':
          items.add(image('/outside/second.png'));
        case 'mixed':
          items.add(DropItemFile('/vault/Target.md'));
        case 'unsupported':
          items = [image('/outside/vector.svg')];
        case 'preview':
          c.mode = IanvsMarkdownEditorMode.preview;
        case 'composition':
          c.value = c.value.copyWith(
            composing: const TextRange(start: 0, end: 3),
          );
        case 'unsaved':
          workspace.newDocument();
      }
      await tester.pump();
      await drop(tester, items);
      await tester.pumpAndSettle();
      expect(native.droppedPaths, isEmpty);
      expect(native.attempts, 0);
      expect(c.text, 'before after');
      expect(
        workspace.documents.any((d) => d.path == '/vault/Target.md'),
        isFalse,
      );
      await finish(tester);
    });
  }

  testWidgets('Markdown-only drop retains ordinary open workflow', (
    tester,
  ) async {
    await open(tester);
    await drop(tester, [DropItemFile('/vault/Target.md')]);
    await waitFor(
      tester,
      () => workspace.activeDocument?.path == '/vault/Target.md',
    );
    expect(native.droppedPaths, isEmpty);
    expect(native.attempts, 0);
    await finish(tester);
  });

  for (final duringWrite in [false, true]) {
    testWidgets(
      'drop invalidated ${duringWrite ? 'during write retains copy' : 'during read writes nothing'}',
      (tester) async {
        await open(tester);
        final c = workspace.activeDocument!.controller;
        final gate = Completer<void>();
        if (duringWrite) {
          native.beforeWrite = gate.future;
        } else {
          native.beforeRead = gate.future;
        }
        await drop(tester, [image()]);
        await waitFor(
          tester,
          () => duringWrite
              ? native.attempts == 1
              : native.droppedPaths.isNotEmpty,
        );
        c.text = 'new content';
        gate.complete();
        if (duringWrite) {
          await waitFor(
            tester,
            () => find.text('Show link').evaluate().isNotEmpty,
          );
          expect(native.files, hasLength(1));
        } else {
          await tester.pumpAndSettle();
          expect(native.attempts, 0);
        }
        expect(c.text, 'new content');
        await finish(tester);
      },
    );
  }

  testWidgets('second image drop while import pending is not queued', (
    tester,
  ) async {
    await open(tester);
    final gate = Completer<void>();
    native.beforeRead = gate.future;
    await drop(tester, [image()]);
    await drop(tester, [image('/outside/second.png')]);
    expect(native.droppedPaths, ['/outside/photo.PNG']);
    expect(
      find.textContaining('Wait for the current image import'),
      findsOneWidget,
    );
    gate.complete();
    await waitFor(tester, () => native.attempts == 1);
    await waitFor(
      tester,
      () => workspace.activeDocument!.controller.text.contains('![]('),
    );
    expect(native.files, hasLength(1));
    await finish(tester);
  });

  testWidgets('image drop cannot insert after switching away and back', (
    tester,
  ) async {
    await open(tester);
    final original = workspace.activeDocument!;
    final gate = Completer<void>();
    native.beforeWrite = gate.future;
    await drop(tester, [image()]);
    await waitFor(tester, () => native.attempts == 1);
    await workspace.openPath('/vault/Target.md');
    workspace.selectDocument(workspace.documents.indexOf(original));
    gate.complete();
    await waitFor(tester, () => find.text('Show link').evaluate().isNotEmpty);
    expect(original.controller.text, 'before after');
    expect(native.files, hasLength(1));
    await finish(tester);
  });

  testWidgets('image drop from local table caret is rejected', (tester) async {
    await open(tester);
    final c = workspace.activeDocument!.controller;
    const content = '| H | I |\n| --- | --- |\n| Alpha | Beta |\n\nBody';
    c.text = content;
    c.selection = const TextSelection.collapsed(offset: content.length);
    workspace.setMode(IanvsMarkdownEditorMode.livePreview);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-table-1-0')));
    await tester.pumpAndSettle();
    await drop(tester, [image()]);
    await tester.pumpAndSettle();
    expect(native.droppedPaths, isEmpty);
    expect(native.attempts, 0);
    expect(c.text, content);
    expect(find.textContaining('Focus the note body'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'missing drop grant fails with explicit picker fallback and no write',
    (tester) async {
      await open(tester);
      native.dropReadError = PlatformException(code: 'attachment_invalid');
      await drop(tester, [DropItemFile('/outside/photo.png')]);
      await waitFor(
        tester,
        () => find
            .textContaining('use Import Image instead')
            .evaluate()
            .isNotEmpty,
      );
      expect(native.droppedBookmarks.single, isNull);
      expect(native.attempts, 0);
      expect(native.picks, 0);
      expect(workspace.activeDocument!.controller.text, 'before after');
      await finish(tester);
    },
  );

  testWidgets(
    'explicit import inserts relative Markdown and undo leaves image intact',
    (tester) async {
      await open(tester);
      final c = workspace.activeDocument!.controller;
      await tester.tap(find.byKey(const ValueKey('import-image-button')));
      await waitFor(tester, () => c.text.contains('![]('));
      expect(native.picks, 1);
      expect(native.clipboardReads, 0);
      expect(native.files, hasLength(1));
      expect(
        c.text,
        matches(
          r'^before !\[\]\(\./%E9%99%84%E4%BB%B6/image-[\w-]+\.png\)after$',
        ),
      );
      c.undo();
      expect(c.text, 'before after');
      expect(native.files, hasLength(1));
      await finish(tester);
    },
  );
  for (final keyboard in [true, false]) {
    testWidgets(
      '${keyboard ? 'Command-V' : 'explicit menu Paste'} imports only image payload',
      (tester) async {
        await open(tester);
        final c = workspace.activeDocument!.controller;
        await paste(tester, keyboard: keyboard);
        await waitFor(tester, () => c.text.contains('![]('));
        expect(native.clipboardReads, 1);
        expect(native.picks, 0);
        expect(native.files, hasLength(1));
        await finish(tester);
      },
    );
  }
  testWidgets(
    'text and smart URL paste preserve existing behavior and do not write files',
    (tester) async {
      await open(tester);
      native.payload = null;
      var text = 'plain text';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': text};
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final c = workspace.activeDocument!.controller;
      await paste(tester);
      await waitFor(tester, () => c.text.contains('plain text'));
      c.value = const TextEditingValue(
        text: 'label',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      text = 'https://example.test/path';
      expect(IanvsMarkdownShortcuts.invoke(IanvsMarkdownCommand.paste), isTrue);
      await waitFor(
        tester,
        () => c.text == '[label](https://example.test/path)',
      );
      expect(native.files, isEmpty);
      expect(native.attempts, 0);
      await finish(tester);
    },
  );
  for (final change in [
    'selection',
    'text',
    'tab',
    'away-back',
    'composition',
    'mode',
  ]) {
    testWidgets(
      'late write after $change keeps file and does not insert into changed document',
      (tester) async {
        await open(tester);
        final original = workspace.activeDocument!;
        final c = original.controller;
        final snapshot = c.value;
        final gate = Completer<void>();
        native.beforeWrite = gate.future;
        await tester.tap(find.byKey(const ValueKey('import-image-button')));
        await waitFor(tester, () => native.attempts == 1);
        switch (change) {
          case 'selection':
            c.selection = const TextSelection.collapsed(offset: 0);
          case 'text':
            c.text = 'new content';
          case 'tab':
            await workspace.openPath('/vault/Target.md');
          case 'away-back':
            await workspace.openPath('/vault/Target.md');
            workspace.selectDocument(workspace.documents.indexOf(original));
          case 'composition':
            c.value = snapshot.copyWith(
              composing: const TextRange(start: 0, end: 6),
            );
          case 'mode':
            c.mode = IanvsMarkdownEditorMode.preview;
        }
        gate.complete();
        await waitFor(
          tester,
          () => find.text('Show link').evaluate().isNotEmpty,
        );
        expect(native.files, hasLength(1));
        expect(c.text, change == 'text' ? 'new content' : 'before after');
        expect(
          workspace.activeDocument!.controller.text,
          isNot(contains('![](')),
        );
        await tester.tap(find.text('Show link'));
        await tester.pumpAndSettle();
        expect(find.text('Imported image kept'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SelectableText),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await finish(tester);
      },
    );
  }
  testWidgets(
    'change then undo while writing still invalidates captured insertion',
    (tester) async {
      await open(tester);
      final c = workspace.activeDocument!.controller;
      final before = c.value;
      final gate = Completer<void>();
      native.beforeWrite = gate.future;
      await tester.tap(find.byKey(const ValueKey('import-image-button')));
      await waitFor(tester, () => native.attempts == 1);
      c.value = before.copyWith(text: 'changed');
      c.value = before;
      gate.complete();
      await waitFor(tester, () => find.text('Show link').evaluate().isNotEmpty);
      expect(c.text, 'before after');
      await finish(tester);
    },
  );
  testWidgets(
    'write failure does not insert; repeated clicks never duplicate writes',
    (tester) async {
      await open(tester);
      final gate = Completer<void>();
      native.beforeWrite = gate.future;
      native.writeError = PlatformException(code: 'attachment_denied');
      await tester.tap(find.byKey(const ValueKey('import-image-button')));
      await waitFor(tester, () => native.attempts == 1);
      await tester.tap(find.byKey(const ValueKey('import-image-button')));
      gate.complete();
      await waitFor(
        tester,
        () => find.textContaining('Image import failed').evaluate().isNotEmpty,
      );
      expect(native.attempts, 1);
      expect(native.files, isEmpty);
      expect(workspace.activeDocument!.controller.text, 'before after');
      await finish(tester);
    },
  );
  testWidgets('unsaved note refuses picker but text paste still works', (
    tester,
  ) async {
    await open(tester);
    workspace.newDocument();
    workspace.setMode(IanvsMarkdownEditorMode.source);
    workspace.activeDocument!.controller.selection =
        const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-image-button')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Save this note inside an opened workspace folder'),
      findsOneWidget,
    );
    expect(native.picks, 0);
    await paste(tester);
    await waitFor(tester, () => native.clipboardReads == 1);
    expect(native.attempts, 0);
    expect(workspace.activeDocument!.controller.text, isEmpty);
    await finish(tester);
  });
  testWidgets(
    'pending picker cancelled by tab change performs no filesystem write',
    (tester) async {
      await open(tester);
      final gate = Completer<void>();
      native.beforeRead = gate.future;
      await tester.tap(find.byKey(const ValueKey('import-image-button')));
      await tester.pump();
      await workspace.openPath('/vault/Target.md');
      gate.complete();
      await tester.pumpAndSettle();
      expect(native.attempts, 0);
      expect(workspace.activeDocument!.controller.text, 'other');
      await finish(tester);
    },
  );
  testWidgets(
    'moving focus during image Paste keeps written file without changing note',
    (tester) async {
      await open(tester);
      final c = workspace.activeDocument!.controller;
      final before = c.text;
      final gate = Completer<void>();
      native.beforeWrite = gate.future;
      await paste(tester);
      await waitFor(tester, () => native.attempts == 1);
      await tester.tap(find.byType(EditableText).first);
      await tester.pump();
      gate.complete();
      await waitFor(tester, () => find.text('Show link').evaluate().isNotEmpty);
      expect(c.text, before);
      expect(native.files, hasLength(1));
      await finish(tester);
    },
  );
  testWidgets('read mode and IME do not invoke image picker or clipboard', (
    tester,
  ) async {
    await open(tester);
    final c = workspace.activeDocument!.controller;
    c.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-image-button')));
    await tester.pumpAndSettle();
    expect(native.picks, 0);
    c.mode = IanvsMarkdownEditorMode.source;
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EditableText).last);
    await tester.pump();
    c.value = const TextEditingValue(
      text: 'before after',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 0, end: 6),
    );
    expect(IanvsMarkdownShortcuts.invoke(IanvsMarkdownCommand.paste), isTrue);
    await tester.pump();
    expect(native.clipboardReads, 0);
    expect(native.attempts, 0);
    await finish(tester);
  });
  testWidgets('external single file does not obtain a parent-folder grant', (
    tester,
  ) async {
    await open(tester);
    files.files['/outside/Other.md'] = 'external';
    await workspace.openPath('/outside/Other.md');
    workspace.setMode(IanvsMarkdownEditorMode.source);
    workspace.activeDocument!.controller.selection =
        const TextSelection.collapsed(offset: 8);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-image-button')));
    await tester.pumpAndSettle();
    expect(native.picks, 0);
    expect(native.attempts, 0);
    expect(
      find.textContaining('separately opened file does not grant access'),
      findsOneWidget,
    );
    await finish(tester);
  });
  testWidgets(
    'post-create failure reports possible retained file and inserts nothing',
    (tester) async {
      await open(tester);
      native.writeError = PlatformException(
        code: 'attachment_unavailable',
        details: {
          'relativePath': 'assets/image-partial.png',
          'fileMayRemain': true,
        },
      );
      await tester.tap(find.byKey(const ValueKey('import-image-button')));
      await waitFor(
        tester,
        () => find
            .textContaining(
              'A file may remain at /vault/assets/image-partial.png',
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(workspace.activeDocument!.controller.text, 'before after');
      expect(native.attempts, 1);
      await finish(tester);
    },
  );
  testWidgets(
    'Live image Paste renders URL-encoded Unicode folder from original source',
    (tester) async {
      await open(tester);
      source.settings = Uint8List.fromList(
        utf8.encode(
          jsonEncode({'attachmentFolderPath': './附件 🧪 #100% (截图)[]!'}),
        ),
      );
      native.onCreate = (path, bytes) => source.files[path] = bytes;
      workspace.setMode(IanvsMarkdownEditorMode.livePreview);
      await tester.pumpAndSettle();
      await tester.tap(find.text('before after').last);
      await tester.pumpAndSettle();
      final c = workspace.activeDocument!.controller;
      await paste(tester);
      await waitFor(tester, () => c.text.contains('![]('));
      expect(c.mode, IanvsMarkdownEditorMode.livePreview);
      expect(native.files, hasLength(1));
      workspace.setMode(IanvsMarkdownEditorMode.preview);
      await waitFor(tester, () => find.byType(RawImage).evaluate().isNotEmpty);
      expect(
        tester.widget<RawImage>(find.byType(RawImage).last).image!.width,
        1,
      );
      c.undo();
      expect(c.text, 'before after');
      expect(native.files, hasLength(1));
      await finish(tester);
    },
  );
  testWidgets(
    'workspace changed during write retains old-vault file and never inserts',
    (tester) async {
      await open(tester);
      final c = workspace.activeDocument!.controller;
      final gate = Completer<void>();
      native.beforeWrite = gate.future;
      await tester.tap(find.byKey(const ValueKey('import-image-button')));
      await waitFor(tester, () => native.attempts == 1);
      files.selectedFolder = '/second';
      files.directories['/second'] = [];
      await workspace.chooseWorkspaceFolder();
      gate.complete();
      await waitFor(tester, () => find.text('Show link').evaluate().isNotEmpty);
      expect(native.roots, ['/vault']);
      expect(c.text, 'before after');
      expect(native.files, hasLength(1));
      await finish(tester);
    },
  );
  for (final (size, textScale) in [
    (const Size(840, 560), 2.0),
    (const Size(840, 480), 2.0),
    (const Size(840, 480), 3.0),
    (const Size(1200, 780), 3.0),
  ]) {
    testWidgets(
      'import action stays accessible at $size and ${textScale}x text',
      (tester) async {
        await open(tester, size: size, textScale: textScale);
        const path =
            '/vault/A very long document title 中文 with spaces and more words.md';
        files.files[path] = 'Body';
        await workspace.openPath(path);
        workspace.setMode(IanvsMarkdownEditorMode.source);
        final c = workspace.activeDocument!.controller;
        c.selection = TextSelection.collapsed(offset: c.text.length);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final action = find.byKey(const ValueKey('import-image-button'));
        final bounds = tester.getRect(action);
        final row = tester.getRect(
          find.byKey(const ValueKey('document-context-row')),
        );
        final wiki = tester.getRect(
          find.byKey(const ValueKey('insert-wiki-link-button')),
        );
        expect(bounds.width, greaterThanOrEqualTo(32));
        expect(bounds.height, greaterThanOrEqualTo(32));
        expect(row.contains(bounds.topLeft), isTrue);
        expect(row.contains(bounds.bottomRight), isTrue);
        expect(bounds.right, lessThanOrEqualTo(wiki.left));
        expect(bounds.center.dy, closeTo(row.center.dy, 0.5));
        expect(
          tester.getRect(find.byType(IanvsMarkdownLiveEditor)).top,
          closeTo(row.bottom, 0.5),
          reason: 'Import and Wiki actions must not add another toolbar row.',
        );
        final semantics = tester.ensureSemantics();
        await tester.pump();
        expect(find.bySemanticsLabel('Import image'), findsOneWidget);
        semantics.dispose();
        await tester.tap(action);
        await waitFor(tester, () => c.text.contains('![]('));
        expect(native.picks, 1);
        expect(native.files, hasLength(1));
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }

  for (final missing in [true, false]) {
    for (final toolbar in [true, false]) {
      testWidgets(
        '${missing ? 'missing table cell' : 'table cell'} local field blocks ${toolbar ? 'toolbar' : 'menu'} import without picker and Source recovers',
        (tester) async {
          await open(tester);
          final c = workspace.activeDocument!.controller;
          final content = missing
              ? '| H | I |\n| --- | --- |\n| Alpha |\n\nBody'
              : '| H | I |\n| --- | --- |\n| Alpha | Beta |\n\nBody';
          c.text = content;
          c.selection = TextSelection.collapsed(offset: content.length);
          workspace.setMode(IanvsMarkdownEditorMode.livePreview);
          await tester.pumpAndSettle();
          final field = find.byKey(
            ValueKey(
              missing ? 'ianvs-markdown-table-1-1' : 'ianvs-markdown-table-1-0',
            ),
          );
          await tester.tap(field);
          await tester.pumpAndSettle();
          final before = c.text;
          if (toolbar) {
            await tester.tap(find.byKey(const ValueKey('import-image-button')));
          } else {
            tester
                .widget<DesktopMenuBar>(find.byType(DesktopMenuBar))
                .onImportImage!();
          }
          await tester.pumpAndSettle();
          expect(native.picks, 0);
          expect(native.attempts, 0);
          expect(c.text, before);
          expect(find.textContaining('Focus the note body'), findsOneWidget);
          workspace.setMode(IanvsMarkdownEditorMode.source);
          await tester.pumpAndSettle();
          c.selection = TextSelection.collapsed(offset: c.text.length);
          await tester.tap(find.byKey(const ValueKey('import-image-button')));
          await waitFor(tester, () => c.text.contains('![]('));
          expect(native.picks, 1);
          await finish(tester);
        },
      );
    }
  }
  for (final returnToBody in [false, true]) {
    testWidgets(
      'missing cell focus invalidates file write even after return to body=$returnToBody',
      (tester) async {
        await open(tester);
        final c = workspace.activeDocument!.controller;
        c.text = '| H | I |\n| --- | --- |\n| Alpha |\n\nBody';
        c.selection = TextSelection.collapsed(offset: c.text.length);
        workspace.setMode(IanvsMarkdownEditorMode.livePreview);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Body').last);
        await tester.pumpAndSettle();
        c.selection = TextSelection.collapsed(offset: c.text.length);
        final before = c.text;
        final gate = Completer<void>();
        native.beforeWrite = gate.future;
        await tester.tap(find.byKey(const ValueKey('import-image-button')));
        await waitFor(tester, () => native.attempts == 1);
        await tester.tap(
          find.byKey(const ValueKey('ianvs-markdown-table-1-1')),
        );
        await tester.pumpAndSettle();
        if (returnToBody) {
          await tester.tap(find.text('Body').last);
          await tester.pumpAndSettle();
          c.selection = TextSelection.collapsed(offset: c.text.length);
        }
        gate.complete();
        await waitFor(
          tester,
          () => find.text('Show link').evaluate().isNotEmpty,
        );
        expect(c.text, before);
        expect(native.files, hasLength(1));
        await tester.tap(find.text('Body').last);
        await tester.pumpAndSettle();
        c.selection = TextSelection.collapsed(offset: c.text.length);
        await tester.tap(find.byKey(const ValueKey('import-image-button')));
        await waitFor(tester, () => c.text.contains('![]('));
        expect(native.files, hasLength(2));
        await finish(tester);
      },
    );
  }
}
