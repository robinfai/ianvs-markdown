import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'wiki_note_navigation_test.dart' show WikiFiles, wikiWorkspace;
import 'package:linefold/src/services/outline_operations.dart';
import 'package:linefold/src/services/note_content_transfer.dart';
import 'package:linefold/src/services/markdown_file_service.dart';

void main() {
  test(
    'extraction stays beside nested source and rejects another directory',
    () {
      expect(
        extractionRelativePath(
          'Excerpt',
          '/vault/chapters/source.md',
          '/vault',
        ),
        'chapters/Excerpt.md',
      );
      expect(
        () => extractionRelativePath(
          '../Excerpt',
          '/vault/chapters/source.md',
          '/vault',
        ),
        throwsFormatException,
      );
      const text = '[x](sibling.md#heading "Title") ![](assets/a.png)';
      expect(
        transferNoteContent(
          text,
          originPath: '/vault/chapters/source.md',
          destinationPath: '/vault/chapters/Excerpt.md',
        ),
        text,
      );
    },
  );

  test(
    'reference insertion rebases links images definitions and heading targets',
    () {
      const text =
          '[x](sibling.md#heading "Title") ![](assets/a.png)\n[x][id]\n[id]: sibling.md#part\n[heading](#chapter)\n`[code](same.md)`';
      final result = transferNoteContent(
        text,
        originPath: '/vault/chapters/source.md',
        destinationPath: '/vault/notes/draft.md',
      );
      expect(result, contains('../chapters/sibling.md#heading "Title"'));
      expect(result, contains('../chapters/assets/a.png'));
      expect(result, contains('[id]: ../chapters/sibling.md#part'));
      expect(result, contains('[heading](../chapters/source.md#chapter)'));
      expect(result, contains('`[code](same.md)`'));
    },
  );

  testWidgets(
    'extract selection saves the new note before linking the original',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = WikiFiles();
      files.files['/vault/Origin.md'] = 'Root';
    const selected = '[x](sibling.md#heading) ![](assets/a.png)';
    files.files['/vault/chapters/source.md'] = 'before $selected after';
      final workspace = await wikiWorkspace(files);
    files.directories['/vault']!.add(const WorkspaceEntry(
      path: '/vault/chapters', name: 'chapters', isDirectory: true,
    ));
    files.directories['/vault/chapters'] = [const WorkspaceEntry(
      path: '/vault/chapters/source.md', name: 'source.md', isDirectory: false,
    )];
    await workspace.openPath('/vault/chapters/source.md');
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      final origin = workspace.activeDocument!;
      origin.controller.mode = IanvsMarkdownEditorMode.source;
      origin.controller.selection = const TextSelection(
        baseOffset: 7,
        extentOffset: 7 + selected.length,
      );
      await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('command-palette-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workspace-palette-query')),
        'Extract selection',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('palette-entry-Extract selection to note')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New note filename'),
        'Extract',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Extract'));
      await tester.pumpAndSettle();
      expect(files.files['/vault/chapters/Extract.md'], selected);
      expect(origin.controller.text, 'before [[/chapters/Extract.md]] after');
      expect(workspace.activeDocument, same(origin));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  test('moving parent moves descendants and preserves fenced heading text', () {
    const source = '# A\na\n## Child\n```\n# fake\n```\n# B\nb\n';
    expect(
      moveChapter(source, 0, 3),
      '# B\nb\n# A\na\n## Child\n```\n# fake\n```\n',
    );
    expect(moveChapter(source, 0, 1), source);
    expect(
      moveChapter(source, 2, 0),
      '# B\nb\n# A\na\n## Child\n```\n# fake\n```\n',
    );
  });

  test('chapter levels include descendants without touching code and YAML', () {
    const source =
        '---\ntitle: Example\n---\n# A\n## Child\n```\n# fake\n```\n# B\n';
    expect(
      changeChapterLevel(source, 0, 1),
      '---\ntitle: Example\n---\n## A\n### Child\n```\n# fake\n```\n# B\n',
    );
    expect(changeChapterLevel(source, 0, -1), source);
  });

  test('moving final chapter without newline keeps headings separate', () {
    expect(moveChapter('# A\na\n# B\nb', 1, 0), '# B\nb\n# A\na\n');
  });
}
