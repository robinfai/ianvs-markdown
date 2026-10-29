import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/services/note_templates.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'support/fakes.dart';
import 'wiki_note_navigation_test.dart' show WikiFiles;
import 'package:linefold/src/widgets/note_template_dialog.dart';

void main() {
  testWidgets('daily command reuses the file and quick capture appends durably', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = WikiFiles();
    files.selectedFolder = '/vault';
    files.directories['/vault'] = [];
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
    await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
    await tester.pumpAndSettle();
    Future<void> command(String title) async {
      await tester.tap(find.byKey(const ValueKey('command-palette-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('workspace-palette-query')), title);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('palette-entry-$title')));
      await tester.pumpAndSettle();
    }
    await command('Open today’s note');
    final today = workspace.activeDocument;
    expect(today?.path, '/vault/${noteDate(DateTime.now())}.md');
    await command('Open today’s note');
    expect(workspace.activeDocument, same(today));
    expect(files.creates, 1);
    for (final text in ['First capture', 'Second capture']) {
      await command('Append to today');
      await tester.enterText(find.widgetWithText(TextField, 'Capture text'), text);
      await tester.tap(find.text('Append'));
      await tester.pumpAndSettle();
    }
    expect(files.files[today!.path], 'First capture\n\nSecond capture\n');
    expect(today.controller.isDirty, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

  test('templates expand one clock snapshot and quote YAML titles', () {
    final now = DateTime(2026, 10, 29, 9, 5);
    for (final source in noteTemplates.values) {
      final result = expandNoteTemplate(source, 'A: "title"', now);
      final parsed = parseMarkdownFrontMatter(result);
      expect(parsed.hasFrontMatter, isTrue);
      expect(
        parsed.entries.firstWhere((e) => e.key == 'title').value,
        'A: "title"',
      );
      expect(result, contains('2026-10-29'));
      expect(result, isNot(contains('{{')));
    }
    expect(
      expandNoteTemplate('{{time}} {{unknown}}', 'A', now),
      '09:05 {{unknown}}',
    );
  });

  test('template insertion is undoable and rejects changed source', () {
    final controller = IanvsMarkdownController(
      text: 'before after',
      mode: IanvsMarkdownEditorMode.source,
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 7);
    final edit = CapturedNoteInsertion(controller.value, controller.mode);
    expect(edit.apply(controller, 'template '), isTrue);
    expect(controller.text, 'before template after');
    expect(edit.apply(controller, 'duplicate '), isFalse);
    controller.undo();
    expect(controller.text, 'before after');
  });

  testWidgets('template dialog creates edited Markdown and cancels cleanly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    NoteTemplateResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<NoteTemplateResult>(
                context: context,
                builder: (_) => const NoteTemplateDialog(),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('template-title')),
      'Plan',
    );
    await tester.enterText(
      find.byKey(const ValueKey('template-source')),
      '# {{title}}\nCustom content',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(result?.text, '# Plan\nCustom content');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
