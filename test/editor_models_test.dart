import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  test(
    'block parser classifies live-preview Markdown without rewriting it',
    () {
      const source = r'''
---
title: Demo
---
# Heading

Paragraph line one
and line two.

> Quote one
> Quote two

- [x] Task
- [ ] Next

1. First
2. Second

$$
x^2 + y^2
$$

| A | B |
| --- | --- |
| 1 | 2 |

```dart
final value = 1;
```

---
''';

      final blocks = parseMarkdownBlocks(source);

      expect(blocks.map((block) => block.type), <IanvsMarkdownBlockType>[
        IanvsMarkdownBlockType.frontMatter,
        IanvsMarkdownBlockType.heading,
        IanvsMarkdownBlockType.paragraph,
        IanvsMarkdownBlockType.blockquote,
        IanvsMarkdownBlockType.taskList,
        IanvsMarkdownBlockType.orderedList,
        IanvsMarkdownBlockType.displayMath,
        IanvsMarkdownBlockType.table,
        IanvsMarkdownBlockType.fencedCode,
        IanvsMarkdownBlockType.thematicBreak,
      ]);

      var cursor = 0;
      final reconstructed = StringBuffer();
      for (final block in blocks) {
        reconstructed
          ..write(source.substring(cursor, block.start))
          ..write(block.source);
        expect(source.substring(block.start, block.end), block.source);
        cursor = block.end;
      }
      reconstructed.write(source.substring(cursor));
      expect(reconstructed.toString(), source);
    },
  );

  test('finds a block from source offsets and counts untouched gaps', () {
    const source = '# One\n\nParagraph\n\n## Two';
    final blocks = parseMarkdownBlocks(source);

    expect(
      markdownBlockAtOffset(blocks, source.indexOf('Paragraph'))?.type,
      IanvsMarkdownBlockType.paragraph,
    );
    expect(markdownBlockAtOffset(blocks, source.length)?.source, '## Two');
    expect(markdownGapLineCount(source, blocks.first, blocks[1]), 2);
  });

  test('keeps marker-only ATX prefixes as literal paragraphs', () {
    const source = '# \n\n###### \n\n#\n\n# #\n\n# Title';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks.map((block) => block.source), <String>[
      '# ',
      '###### ',
      '#',
      '# #',
      '# Title',
    ]);
    expect(
      blocks.take(4).map((block) => block.type),
      everyElement(IanvsMarkdownBlockType.paragraph),
    );
    expect(blocks.last.type, IanvsMarkdownBlockType.heading);
  });

  test('accepts the shortest alignment markers Obsidian emits', () {
    const source = '| A | B | C |\n| :-: | --: | :-- |\n| 1 | 2 | 3 |';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks, hasLength(1));
    expect(blocks.single.type, IanvsMarkdownBlockType.table);
    expect(blocks.single.source, source);
  });

  test('classifies alternate and ordered task states without rewriting', () {
    const source = '- [!] Important\n\n1. [/] In progress\n\n- [k] Unknown';

    final blocks = parseMarkdownBlocks(source);

    expect(
      blocks.map((block) => block.type),
      everyElement(IanvsMarkdownBlockType.taskList),
    );
    expect(blocks.map((block) => block.source), <String>[
      '- [!] Important',
      '1. [/] In progress',
      '- [k] Unknown',
    ]);
  });

  test('retains every intentional blank line between live blocks', () {
    const source = 'First paragraph.\n\n\n\nSecond paragraph.';
    final blocks = parseMarkdownBlocks(source);

    expect(blocks, hasLength(2));
    expect(markdownGapLineCount(source, blocks.first, blocks.last), 4);
    expect(blocks.first.source, 'First paragraph.');
    expect(blocks.last.source, 'Second paragraph.');
  });

  test('four-backtick fences keep inner triple fences in one source block', () {
    const fenced =
        '````markdown\n'
        '```dart\n'
        'final answer = 42;\n'
        '```\n'
        '````';
    const source = '$fenced\n\nAfter code.';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks, hasLength(2));
    expect(blocks.first.type, IanvsMarkdownBlockType.fencedCode);
    expect(blocks.first.source, fenced);
    expect(blocks.last.type, IanvsMarkdownBlockType.paragraph);
    expect(blocks.last.source, 'After code.');
  });

  test(
    'indented code requires a boundary and preserves internal blank lines',
    () {
      const source =
          'Paragraph line\n'
          '    indented continuation\n'
          '\tTabbed continuation\n'
          '\n'
          '    const first = 1;\n'
          '\n'
          '\treturn first;\n'
          '\n'
          'After code.';

      final blocks = parseMarkdownBlocks(source);

      expect(blocks, hasLength(3));
      expect(blocks.first.type, IanvsMarkdownBlockType.paragraph);
      expect(
        blocks.first.source,
        'Paragraph line\n    indented continuation\n\tTabbed continuation',
      );
      expect(blocks[1].type, IanvsMarkdownBlockType.indentedCode);
      expect(blocks[1].source, '    const first = 1;\n\n\treturn first;');
      expect(markdownGapLineCount(source, blocks.first, blocks[1]), 2);
      expect(markdownGapLineCount(source, blocks[1], blocks.last), 2);
      expect(blocks.last.source, 'After code.');
    },
  );

  test('paired standalone comments keep internal blank lines in one block', () {
    const comment = '%%\nhidden first\n\nhidden second\n%%';
    const source = 'Before.\n\n$comment\n\nAfter.';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks, hasLength(3));
    expect(blocks[1].type, IanvsMarkdownBlockType.paragraph);
    expect(blocks[1].source, comment);
    expect(markdownGapLineCount(source, blocks.first, blocks[1]), 2);
    expect(markdownGapLineCount(source, blocks[1], blocks.last), 2);
  });

  test('unclosed standalone comments remain ordinary source blocks', () {
    const source = 'Before.\n\n%%\nunclosed\n\nAfter.';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks.map((block) => block.source), <String>[
      'Before.',
      '%%\nunclosed',
      'After.',
    ]);
  });

  test('Setext dashes win after text while thematic variants stay rules', () {
    const source =
        'Setext level two\n'
        '---\n'
        '\n'
        '***\n'
        '\n'
        '___\n'
        '\n'
        '* * *\n'
        '\n'
        '_ _ _\n'
        '\n'
        '- - -';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks.first.type, IanvsMarkdownBlockType.heading);
    expect(blocks.first.source, 'Setext level two\n---');
    expect(
      blocks.skip(1).map((block) => block.type),
      everyElement(IanvsMarkdownBlockType.thematicBreak),
    );
    expect(blocks.skip(1).map((block) => block.source), <String>[
      '***',
      '___',
      '* * *',
      '_ _ _',
      '- - -',
    ]);
  });

  test('keeps lazy paragraph continuations inside block quotes', () {
    const source =
        '> Quoted first line\n'
        'Lazy continuation without a marker\n'
        '> Explicit quoted tail\n'
        '\n'
        'After quote.';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks, hasLength(2));
    expect(blocks.first.type, IanvsMarkdownBlockType.blockquote);
    expect(
      blocks.first.source,
      '> Quoted first line\n'
      'Lazy continuation without a marker\n'
      '> Explicit quoted tail',
    );
    expect(blocks.last.type, IanvsMarkdownBlockType.paragraph);
    expect(blocks.last.source, 'After quote.');
  });

  test('lazy quote continuations stop at blank lines and block openers', () {
    const source =
        '> # Quoted heading\n'
        'Unmarked heading continuation\n'
        '\n'
        '> - Quoted list item\n'
        'Lazy list continuation\n'
        '> Quoted tail\n'
        '\n'
        '> Paragraph before rule\n'
        '---\n'
        'After rule.';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.blockquote,
      IanvsMarkdownBlockType.blockquote,
      IanvsMarkdownBlockType.blockquote,
      IanvsMarkdownBlockType.thematicBreak,
      IanvsMarkdownBlockType.paragraph,
    ]);
    expect(
      blocks[0].source,
      '> # Quoted heading\nUnmarked heading continuation',
    );
    expect(
      blocks[1].source,
      '> - Quoted list item\nLazy list continuation\n> Quoted tail',
    );
    expect(blocks[2].source, '> Paragraph before rule');
    expect(blocks[3].source, '---');
    expect(blocks[4].source, 'After rule.');
  });

  test('empty input remains directly editable', () {
    final blocks = parseMarkdownBlocks('');

    expect(blocks, hasLength(1));
    expect(blocks.single.source, isEmpty);
    expect(blocks.single.start, 0);
    expect(blocks.single.end, 0);
  });

  test('live-preview projection can split contiguous lists into items', () {
    const source = '- first\n- [ ] second\n  - nested\n    - deep';

    final blocks = parseMarkdownBlocks(source, splitListItems: true);

    expect(blocks, hasLength(4));
    expect(blocks.map((block) => block.source), <String>[
      '- first',
      '- [ ] second',
      '  - nested',
      '    - deep',
    ]);
    expect(blocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.taskList,
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.unorderedList,
    ]);
  });

  test('tab-separated markers remain list blocks for rendering', () {
    const source = '-\tone\n\n1.\ttwo';

    final blocks = parseMarkdownBlocks(source, splitListItems: true);

    expect(blocks.map((block) => block.source), <String>['-\tone', '1.\ttwo']);
    expect(blocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.orderedList,
    ]);
  });
}
