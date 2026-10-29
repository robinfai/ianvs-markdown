import 'package:linefold/src/models/document_session.dart';
import 'package:linefold/src/widgets/floating_outline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'wiki_note_navigation_test.dart' show WikiFiles, wikiWorkspace;
import 'package:linefold/src/services/outline_operations.dart';
import 'package:linefold/src/services/note_content_transfer.dart';
import 'package:linefold/src/services/markdown_file_service.dart';

void main() {
  test('standalone block IDs move with their preceding structured block', () {
    const source = '> Quoted content\n\n^quote\n\n[jump](#^quote)\n';
    expect(
      extractedNoteContent(
        source,
        0,
        source.length,
        originRelativePath: 'source.md',
      ),
      source,
    );
    expect(
      extractedNoteContent(
        source,
        source.indexOf('[jump]'),
        source.length,
        originRelativePath: 'source.md',
      ),
      '[jump](source.md#^quote)\n',
    );
    expect(
      () => extractedNoteContent(
        source,
        source.indexOf('^quote'),
        source.length,
        originRelativePath: 'source.md',
      ),
      throwsFormatException,
    );
  });

  test(
    'extraction keeps wiki heading names and original note destinations',
    () {
      const source = '# Intro Words\n\n[[#Intro Words|jump]]\n';
      expect(
        extractedNoteContent(
          source,
          source.indexOf('[['),
          source.length,
          originRelativePath: 'chapters/source.md',
        ),
        '[[/chapters/source.md#Intro Words|jump]]\n',
      );
      expect(
        extractedNoteContent(
          source,
          0,
          source.length,
          originRelativePath: 'chapters/source.md',
        ),
        source,
      );
    },
  );

  test(
    'extraction preserves fragments targeting headings left in the source',
    () {
      const source = '# Intro\n\n[intro](#intro)\n';
      final start = source.indexOf('[intro]');
      expect(
        extractedNoteContent(
          source,
          start,
          source.length,
          originRelativePath: 'chapters/source.md',
        ),
        '[intro](source.md#intro)\n',
      );
      expect(
        extractedNoteContent(
          source,
          0,
          source.length,
          originRelativePath: 'chapters/source.md',
        ),
        source,
      );
    },
  );

  test('extraction remaps duplicate heading anchors moved with the link', () {
    const source =
        '# Intro\n\nOld\n\n# Intro\n\n[new](#intro-1) [old](#intro)\n';
    final start = source.indexOf('# Intro', 1);
    expect(
      extractedNoteContent(
        source,
        start,
        source.length,
        originRelativePath: 'source.md',
      ),
      '# Intro\n\n[new](#intro) [old](source.md#intro)\n',
    );
  });

  test(
    'extraction preserves fragment reference definitions and block identities',
    () {
      const definition = '# Intro\n\n[intro][id]\n\n[id]: #intro "Title"\n';
      final start = definition.indexOf('[intro]');
      final extracted = extractedNoteContent(
        definition,
        start,
        start + 11,
        originRelativePath: 'source.md',
      );
      expect(extracted, contains('[id]: source.md#intro "Title"'));
      const block = 'Paragraph ^block\n\n[jump](#^block)\n';
      final linkStart = block.indexOf('[jump]');
      expect(
        extractedNoteContent(
          block,
          linkStart,
          block.length,
          originRelativePath: 'source.md',
        ),
        '[jump](source.md#^block)\n',
      );
      expect(
        extractedNoteContent(
          block,
          0,
          block.length,
          originRelativePath: 'source.md',
        ),
        block,
      );
    },
  );

  test(
    'extraction refuses unsupported or partially moved fragment targets',
    () {
      const unsupported = '<a id="intro"></a>\n\n[jump](#intro)';
      expect(
        () => extractedNoteContent(
          unsupported,
          unsupported.indexOf('[jump]'),
          unsupported.length,
          originRelativePath: 'source.md',
        ),
        throwsFormatException,
      );
      const partial = '# Intro\n\n[jump](#intro)';
      expect(
        () => extractedNoteContent(
          partial,
          2,
          partial.length,
          originRelativePath: 'source.md',
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets('outline drag and chapter menu edit the live document', (
    tester,
  ) async {
    final document = DocumentSession(
      id: 'outline',
      name: 'Chapters.md',
      text: '# A\nA body\n## Child\nChild body\n# B\nB body\n',
    );
    addTearDown(document.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FloatingOutline(document: document)),
      ),
    );
    final handles = find.byType(ReorderableDragStartListener);
    final gesture = await tester.startGesture(tester.getCenter(handles.last));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.moveTo(Offset(tester.getCenter(handles.first).dx, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      document.controller.text,
      '# B\nB body\n# A\nA body\n## Child\nChild body\n',
    );
    await tester.tap(find.byTooltip('Chapter actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demote chapter'));
    await tester.pumpAndSettle();
    expect(document.controller.text, startsWith('## B\nB body\n# A'));
    document.controller.undo();
    expect(document.controller.text, startsWith('# B\nB body\n# A'));
    await tester.pumpWidget(const SizedBox());
  });

  test('extraction carries reference definitions outside the selection', () {
    const source = '[x][target]\n\n[target]: sibling.md#part "Title"\n';
    final extracted = extractedNoteContent(source, 0, 11);
    final references = parseIanvsMarkdownNoteSemantics(extracted).references;
    expect(
      references.any((r) => r.target == 'sibling.md' && r.fragment == 'part'),
      isTrue,
    );
    expect(extracted, contains('[target]: sibling.md#part "Title"'));
  });

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
          '[x](sibling.md#heading "Title") ![](assets/a.png)\n[x][id]\n\n[id]: sibling.md#part\n[heading](#chapter)\n`[code](same.md)`';
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
      files.directories['/vault']!.add(
        const WorkspaceEntry(
          path: '/vault/chapters',
          name: 'chapters',
          isDirectory: true,
        ),
      );
      files.directories['/vault/chapters'] = [
        const WorkspaceEntry(
          path: '/vault/chapters/source.md',
          name: 'source.md',
          isDirectory: false,
        ),
      ];
      await workspace.openPath('/vault/chapters/source.md');
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      final origin = workspace.activeDocument!;
      origin.controller.mode = IanvsMarkdownEditorMode.source;
      origin.controller.selection = TextSelection(
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
