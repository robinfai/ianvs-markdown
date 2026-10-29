import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'support/fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/slash_insertion.dart';

void main() {
  testWidgets('slash menu inserts a task and cancellation preserves the slash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = MemoryMarkdownFileService();
    final workspace = WorkspaceController(fileService: files, sessionStore: MemoryWorkspaceSessionStore());
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    await workspace.initialize();
    final note = workspace.newDocument();
    note.controller.mode = IanvsMarkdownEditorMode.source;
    await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
    await tester.enterText(field, '/');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-entry-Task list')));
    await tester.pumpAndSettle();
    expect(note.controller.text, '- [ ] ');
    note.controller.text = '';
    await tester.pumpAndSettle();
    await tester.enterText(field, '/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(note.controller.text, '/');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

  TextEditingValue value(String text, {int? caret}) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret ?? text.length),
  );

  test('only a fresh slash on an empty body line opens insertion', () {
    expect(slashInsertionStart('', value('/')), 0);
    expect(slashInsertionStart('text\n', value('text\n/')), 5);
    expect(slashInsertionStart('text', value('text/')), isNull);
    expect(slashInsertionStart('', value('/path/to/note')), isNull);
    expect(slashInsertionStart('/', value('/')), isNull);
    expect(slashInsertionStart('suffix', value('/suffix', caret: 1)), isNull);
    expect(
      slashInsertionStart(
        '',
        value('/').copyWith(composing: const TextRange(start: 0, end: 1)),
      ),
      isNull,
    );
  });
}
