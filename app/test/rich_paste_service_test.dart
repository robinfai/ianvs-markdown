import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'support/fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_clipboard/ianvs_markdown_clipboard.dart';
import 'package:linefold/src/services/rich_paste_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  IanvsMarkdownController document(String text, {int? offset}) {
    final controller = IanvsMarkdownController(text: text);
    controller.selection = TextSelection.collapsed(
      offset: offset ?? text.length,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  for (final mode in [
    IanvsMarkdownEditorMode.source,
    IanvsMarkdownEditorMode.livePreview,
  ]) {
    testWidgets('shell ordinary paste converts HTML in $mode', (tester) async {
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
      final files = MemoryMarkdownFileService()..files['/note.md'] = 'Before';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      await workspace.openPath('/note.md');
      workspace.setMode(mode);
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShell(
            workspace: workspace,
            dark: false,
            onToggleTheme: () {},
            enableFileDrop: false,
            readClipboardText: () async {
              reads++;
              return const IanvsMarkdownClipboardText(
                html: '<h2>Rich</h2>',
                plainText: 'Rich',
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (mode == IanvsMarkdownEditorMode.livePreview) {
        await tester.tap(find.text('Before').first);
        await tester.pumpAndSettle();
      }
      final field = mode == IanvsMarkdownEditorMode.source
          ? find.byKey(const ValueKey('ianvs-markdown-source-field'))
          : find.descendant(
              of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
              matching: find.byType(TextField),
            );
      await tester.tap(field);
      tester.widget<TextField>(field).controller!.selection =
          const TextSelection.collapsed(offset: 6);
      final controller = workspace.activeDocument!.controller;
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.paste,
        controller: controller,
      );
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(controller.text, 'Before\n\n## Rich');
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, 'Before');
      await workspace.flushSession();
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('HTML becomes one undoable Markdown insertion', () async {
    final controller = document('Before');
    final before = controller.value;
    expect(
      await pasteClipboardHtml(
        controller: controller,
        isCurrent: () => true,
        read: () async => const IanvsMarkdownClipboardText(
          html: '<h2>Title</h2><p><strong>Body</strong></p>',
          plainText: 'Title\nBody',
        ),
      ),
      isTrue,
    );
    expect(controller.text, contains('Before\n\n## Title'));
    expect(controller.text, contains('**Body**'));
    controller.undo();
    expect(controller.value, before);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(controller.text, contains('**Body**'));
  });
  test(
    'unsupported HTML and code contexts use same-item literal text',
    () async {
      for (final code in [false, true]) {
        final controller = document(
          code ? '```\ntext\n```' : '',
          offset: code ? 4 : 0,
        );
        await pasteClipboardHtml(
          controller: controller,
          isCurrent: () => true,
          read: () async => IanvsMarkdownClipboardText(
            html: code ? '<b>Bold</b>' : '<img src="x">',
            plainText: 'A\tB\n1\t2',
          ),
        );
        expect(controller.text, contains('A\tB\n1\t2'));
        expect(controller.text, isNot(contains('| --- |')));
      }
    },
  );
  test(
    'plain-only snapshot declines so ordinary image/text pipeline remains available',
    () async {
      final controller = document('Before');
      expect(
        await pasteClipboardHtml(
          controller: controller,
          isCurrent: () => true,
          read: () async =>
              const IanvsMarkdownClipboardText(plainText: 'plain'),
        ),
        isFalse,
      );
      expect(controller.text, 'Before');
    },
  );
  for (final change in ['selection restored', 'mode', 'document']) {
    test('late HTML is discarded after $change', () async {
      final controller = document('Before');
      final result = Completer<IanvsMarkdownClipboardText?>();
      var current = true;
      final pending = pasteClipboardHtml(
        controller: controller,
        isCurrent: () => current,
        read: () => result.future,
      );
      if (change == 'mode') {
        controller.mode = IanvsMarkdownEditorMode.source;
      } else if (change == 'document') {
        current = false;
      } else {
        final original = controller.selection;
        controller.selection = const TextSelection.collapsed(offset: 0);
        controller.selection = original;
      }
      result.complete(
        const IanvsMarkdownClipboardText(
          html: '<b>Late</b>',
          plainText: 'Late',
        ),
      );
      expect(await pending, isTrue);
      expect(controller.text, 'Before');
      expect(controller.canUndo, isFalse);
    });
  }
}
