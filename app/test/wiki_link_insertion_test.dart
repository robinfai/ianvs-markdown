import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/services/wiki_link_insertion.dart';
import 'package:linefold/src/services/wiki_note_resolver.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'wiki_note_resolver_test.dart' show WikiCatalogSource, note;

void main() {
  IanvsMarkdownController controller(String text, int offset) {
    final result = IanvsMarkdownController(
      text: text,
      mode: IanvsMarkdownEditorMode.source,
    );
    result.selection = TextSelection.collapsed(offset: offset);
    addTearDown(result.dispose);
    return result;
  }

  for (final path in [
    'Report.md.md',
    'Report.MD.md',
    'Report .md',
    'Report\u00a0.md',
    '中文 .md',
    'Report%20.md',
  ]) {
    testWidgets(
      'inserted source parses and resolves to the selected filename: $path',
      (tester) async {
        final c = controller('', 0);
        expect(WikiLinkInsertion.capture(c)!.apply(c, path), isTrue);
        final taps = <IanvsMarkdownLinkTarget>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IanvsMarkdown(data: c.text, onTapLinkTarget: taps.add),
            ),
          ),
        );
        await tester.tap(
          find.textContaining(path.startsWith('中文') ? '中文' : 'Report').first,
        );
        expect(taps, hasLength(1));
        expect(taps.single.kind, IanvsMarkdownLinkKind.wiki);
        final source = WikiCatalogSource()
          ..directories[''] = WorkspaceDirectorySnapshot([
            for (final name in {path, 'Report.md', 'Report .md'}) note(name),
          ]);
        final index = WorkspaceIndex(source: source)..configure('/vault');
        addTearDown(index.dispose);
        final result = await tester.runAsync(
          () => WikiNoteResolver(
            index,
            normalize: (values) async =>
                values.map((s) => s.toLowerCase()).toList(),
          ).resolve(taps.single.href!, originPath: '/vault/Origin.md'),
        );
        expect(result!.status, WikiNoteStatus.resolved);
        expect(result.candidates.single.relativePath, path);
        expect(
          c.text,
          path == 'Report%20.md' ? '[[/Report%20]]' : '[[/$path]]',
        );
        c.undo();
        expect(c.text, '');
      },
    );
  }
  for (final path in ['Note#.md', 'Note|alias.md', 'Note[.md', 'Note].md']) {
    test(
      'unrepresentable literal Wiki delimiter refuses source mutation: $path',
      () {
        final c = controller('source', 6);
        final before = c.value;
        expect(WikiLinkInsertion.canRepresent(path), isFalse);
        expect(WikiLinkInsertion.capture(c)!.apply(c, path), isFalse);
        expect(c.value, before);
        expect(c.canUndo, isFalse);
      },
    );
  }
  test(
    'insert at UTF-16 offset preserves every unrelated source unit and undo',
    () {
      const text = '---\r\ntitle: 😀\r\n---\r\nBefore 😀 after\r\n';
      final offset = text.indexOf(' after');
      final c = controller(text, offset);
      expect(WikiLinkInsertion.capture(c)!.apply(c, '中文/笔记😀.md'), isTrue);
      expect(c.text, text.replaceRange(offset, offset, '[[/中文/笔记😀]]'));
      c.undo();
      expect(c.text, text);
      c.redo();
      expect(c.text, contains('[[/中文/笔记😀]]'));
    },
  );
  test('partial completion never consumes trailing prose', () {
    final c = controller('Before [[Un trailing prose', 11);
    expect(WikiLinkInsertion.capture(c)!.apply(c, 'notes/Unique.md'), isTrue);
    expect(c.text, 'Before [[/notes/Unique]] trailing prose');
  });
  test('closed link completion preserves fragment alias and delimiters', () {
    const text = '😀 [[Un#Heading|Display 名称]] tail';
    final c = controller(text, text.indexOf('#'));
    expect(WikiLinkInsertion.capture(c)!.apply(c, 'notes/Unique.md'), isTrue);
    expect(c.text, '😀 [[/notes/Unique#Heading|Display 名称]] tail');
  });
  test('programmatic selection cannot split a UTF-16 surrogate pair', () {
    final c = controller('😀 note', 1);
    expect(WikiLinkInsertion.capture(c), isNull);
    expect(c.text, '😀 note');
  });
  test('cancel only captures and never changes source or history', () {
    final c = controller('[[Un', 4);
    final before = c.value;
    WikiLinkInsertion.capture(c);
    expect(c.value, before);
    expect(c.canUndo, isFalse);
  });
  test('IME composition blocks capture and subsequent apply', () {
    final c = controller('hello', 5);
    final edit = WikiLinkInsertion.capture(c)!;
    c.value = c.value.copyWith(composing: const TextRange(start: 0, end: 5));
    expect(WikiLinkInsertion.capture(c), isNull);
    expect(edit.apply(c, 'Target.md'), isFalse);
  });
  test('late selection source and mode changes reject insertion', () {
    final c = controller('hello', 5);
    final edit = WikiLinkInsertion.capture(c)!;
    c.selection = const TextSelection.collapsed(offset: 0);
    expect(edit.apply(c, 'Target.md'), isFalse);
    c.selection = const TextSelection.collapsed(offset: 5);
    c.text = 'newer';
    expect(edit.apply(c, 'Target.md'), isFalse);
    c.value = edit.value;
    c.mode = IanvsMarkdownEditorMode.preview;
    expect(edit.apply(c, 'Target.md'), isFalse);
    expect(WikiLinkInsertion.capture(c), isNull);
  });
}
