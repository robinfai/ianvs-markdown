import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/editor/markdown_code_ranges.dart';

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

  test('table blocks retain pipe-less body rows until a real boundary', () {
    const source =
        '| abc | def |\n'
        '| --- | --- |\n'
        '| bar | baz |\n'
        'bar\n'
        '\n'
        'bar';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.table,
      IanvsMarkdownBlockType.paragraph,
    ]);
    expect(
      blocks.first.source,
      '| abc | def |\n| --- | --- |\n| bar | baz |\nbar',
    );
    expect(blocks.last.source, 'bar');

    const interrupted =
        '| abc | def |\n'
        '| --- | --- |\n'
        '2. still a row\n'
        '> quote';
    final interruptedBlocks = parseMarkdownBlocks(interrupted);
    expect(
      interruptedBlocks.map((block) => block.type),
      <IanvsMarkdownBlockType>[
        IanvsMarkdownBlockType.table,
        IanvsMarkdownBlockType.blockquote,
      ],
    );
    expect(interruptedBlocks.first.source, contains('2. still a row'));
    expect(interruptedBlocks.last.source, '> quote');
  });

  test('table HTML rows stop only for interrupting HTML blocks', () {
    const inlineHtml =
        '| A | B |\n'
        '| --- | --- |\n'
        '<em>one</em> | two';
    final inlineBlocks = parseMarkdownBlocks(inlineHtml);

    expect(inlineBlocks, hasLength(1));
    expect(inlineBlocks.single.type, IanvsMarkdownBlockType.table);
    expect(inlineBlocks.single.source, inlineHtml);

    const interrupted =
        '| A | B |\n'
        '| --- | --- |\n'
        '| one | two |\n'
        '<!-- stop -->\n'
        'After';
    final interruptedBlocks = parseMarkdownBlocks(interrupted);

    expect(interruptedBlocks.first.type, IanvsMarkdownBlockType.table);
    expect(
      interruptedBlocks.first.source,
      '| A | B |\n| --- | --- |\n| one | two |',
    );
    expect(
      interruptedBlocks.map((block) => block.type),
      <IanvsMarkdownBlockType>[
        IanvsMarkdownBlockType.table,
        IanvsMarkdownBlockType.html,
        IanvsMarkdownBlockType.paragraph,
      ],
    );
    expect(interruptedBlocks[1].source, '<!-- stop -->');
    expect(interruptedBlocks.last.source, 'After');
  });

  test('HTML blocks use their condition-specific end markers', () {
    const comment = '<!-- one line -->\nAfter';
    final commentBlocks = parseMarkdownBlocks(comment);
    expect(commentBlocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.html,
      IanvsMarkdownBlockType.paragraph,
    ]);
    expect(commentBlocks.first.source, '<!-- one line -->');
    expect(commentBlocks.last.source, 'After');

    const multilineComment = '<!--\nhidden\n-->\nAfter';
    final multilineBlocks = parseMarkdownBlocks(multilineComment);
    expect(multilineBlocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.html,
      IanvsMarkdownBlockType.paragraph,
    ]);
    expect(multilineBlocks.first.source, '<!--\nhidden\n-->');
    expect(multilineBlocks.last.source, 'After');

    for (final fixture in <(String, String)>[
      ('<script>\nraw\n</script>\nAfter', '<script>\nraw\n</script>'),
      ('<?target\nvalue\n?>\nAfter', '<?target\nvalue\n?>'),
      ('<!DOCTYPE html>\nAfter', '<!DOCTYPE html>'),
      ('<![CDATA[\nvalue\n]]>\nAfter', '<![CDATA[\nvalue\n]]>'),
    ]) {
      final blocks = parseMarkdownBlocks(fixture.$1);
      expect(blocks.map((block) => block.type), <IanvsMarkdownBlockType>[
        IanvsMarkdownBlockType.html,
        IanvsMarkdownBlockType.paragraph,
      ], reason: fixture.$1);
      expect(blocks.first.source, fixture.$2, reason: fixture.$1);
      expect(blocks.last.source, 'After', reason: fixture.$1);
    }

    const blockTag = '<div>\nbody\n</div>\nAfter';
    final blockTagBlocks = parseMarkdownBlocks(blockTag);
    expect(blockTagBlocks, hasLength(1));
    expect(blockTagBlocks.single.type, IanvsMarkdownBlockType.html);
    expect(blockTagBlocks.single.source, blockTag);

    const completeTag = '<custom data-x="1">\nbody\n\nAfter';
    final completeTagBlocks = parseMarkdownBlocks(completeTag);
    expect(
      completeTagBlocks.map((block) => block.type),
      <IanvsMarkdownBlockType>[
        IanvsMarkdownBlockType.html,
        IanvsMarkdownBlockType.paragraph,
      ],
    );
    expect(completeTagBlocks.first.source, '<custom data-x="1">\nbody');
    expect(completeTagBlocks.last.source, 'After');
  });

  test('adjacent HTML blocks share one exact live-preview range', () {
    const comments = '<!-- one -->\n<!-- two -->\nAfter';
    final commentBlocks = parseMarkdownBlocks(comments);
    expect(commentBlocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.html,
      IanvsMarkdownBlockType.paragraph,
    ]);
    expect(commentBlocks.first.source, '<!-- one -->\n<!-- two -->');
    expect(commentBlocks.last.source, 'After');

    const raw =
        '<script>\nfirst\n</script>\n'
        '<style>\nsecond\n</style>\n'
        'After';
    final rawBlocks = parseMarkdownBlocks(raw);
    expect(rawBlocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.html,
      IanvsMarkdownBlockType.paragraph,
    ]);
    expect(
      rawBlocks.first.source,
      '<script>\nfirst\n</script>\n<style>\nsecond\n</style>',
    );
    expect(rawBlocks.last.source, 'After');
  });

  test('inline HTML remains inside its surrounding paragraph', () {
    const paired = '<em>inline</em> continuation\nnext';
    final pairedBlocks = parseMarkdownBlocks(paired);
    expect(pairedBlocks, hasLength(1));
    expect(pairedBlocks.single.type, IanvsMarkdownBlockType.paragraph);
    expect(pairedBlocks.single.source, paired);

    const nonInterrupting = 'Before\n<em>\nAfter';
    final nonInterruptingBlocks = parseMarkdownBlocks(nonInterrupting);
    expect(nonInterruptingBlocks, hasLength(1));
    expect(nonInterruptingBlocks.single.type, IanvsMarkdownBlockType.paragraph);
    expect(nonInterruptingBlocks.single.source, nonInterrupting);
  });

  test('standalone block IDs extend supported blocks across blank lines', () {
    const source =
        '# Heading\n\n^heading-id\n\n'
        '---\n\n^rule-id\n\n'
        r'''$$
x^2
$$

^math-id

> Quote

> ^quote-id

- List item

  ^list-id

After.''';

    final blocks = parseMarkdownBlocks(source, splitListItems: true);

    expect(blocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.heading,
      IanvsMarkdownBlockType.thematicBreak,
      IanvsMarkdownBlockType.displayMath,
      IanvsMarkdownBlockType.blockquote,
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.paragraph,
    ]);
    expect(blocks.map((block) => block.source), <String>[
      '# Heading\n\n^heading-id',
      '---\n\n^rule-id',
      r'''$$
x^2
$$

^math-id''',
      '> Quote\n\n> ^quote-id',
      '- List item\n\n  ^list-id',
      'After.',
    ]);
    expect(
      blocks.every(
        (block) => source.substring(block.start, block.end) == block.source,
      ),
      isTrue,
    );
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

  test('requires table headers and delimiters to have equal cell counts', () {
    const narrowHeader =
        r'| A \| pipe | B |'
        '\n| --- | --- | --- |\n'
        '| one | two | three |';
    const wideHeader =
        '| A | B | C |\n'
        '| --- | --- |\n'
        '| one | two |';

    for (final source in <String>[narrowHeader, wideHeader]) {
      final blocks = parseMarkdownBlocks(source);
      expect(blocks, hasLength(1));
      expect(blocks.single.type, IanvsMarkdownBlockType.paragraph);
      expect(blocks.single.source, source);
    }

    const valid =
        r'| A \| pipe | B |'
        '\n| --- | --- |\n'
        '| one | two |';
    final validBlocks = parseMarkdownBlocks(valid);

    expect(validBlocks, hasLength(1));
    expect(validBlocks.single.type, IanvsMarkdownBlockType.table);
    expect(validBlocks.single.source, valid);
  });

  test('recognizes framed single-column tables', () {
    for (final source in <String>[
      '| A |\n| --- |\n| one |',
      '${r'| A \| pipe |'}\n| --- |\n| one |',
      'A\n| --- |\none',
    ]) {
      final blocks = parseMarkdownBlocks(source);

      expect(blocks, hasLength(1));
      expect(blocks.single.type, IanvsMarkdownBlockType.table);
      expect(blocks.single.source, source);
    }
  });

  test('rejects code-indented table delimiter rows', () {
    const valid =
        '| A | B |\n'
        '   | --- | --- |\n'
        '| one | two |';
    const codeIndented =
        '| A | B |\n'
        '    | --- | --- |\n'
        '| one | two |';
    const tabIndented =
        '| A | B |\n'
        '\t| --- | --- |\n'
        '| one | two |';

    expect(
      parseMarkdownBlocks(valid).single.type,
      IanvsMarkdownBlockType.table,
    );
    for (final source in <String>[codeIndented, tabIndented]) {
      final invalidBlocks = parseMarkdownBlocks(source);
      expect(invalidBlocks, hasLength(1));
      expect(invalidBlocks.single.type, IanvsMarkdownBlockType.paragraph);
      expect(invalidBlocks.single.source, source);
    }
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

  test('backtick fence info strings reject embedded backticks', () {
    const invalid = '```js`bad\ncode';
    final invalidBlocks = parseMarkdownBlocks(invalid);

    expect(invalidBlocks, hasLength(1));
    expect(invalidBlocks.single.type, IanvsMarkdownBlockType.paragraph);
    expect(invalidBlocks.single.source, invalid);

    const validTilde = '~~~js`allowed\ncode\n~~~';
    final tildeBlocks = parseMarkdownBlocks(validTilde);
    expect(tildeBlocks, hasLength(1));
    expect(tildeBlocks.single.type, IanvsMarkdownBlockType.fencedCode);
    expect(tildeBlocks.single.source, validTilde);
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

  test('code ranges map nested quoted blocks to original UTF-16 offsets', () {
    const source =
        'Before 😀.\r\n'
        '\r\n'
        '>     code 😀 ^[inside]\r\n'
        '>\r\n'
        '> ```md\r\n'
        '> \r\n'
        '> fenced [^inside]\r\n'
        '> ```\r\n'
        '>\r\n'
        '> >     nested %%inside%% ^inside-id\r\n'
        '\r\n'
        'After.';

    final ranges = ianvsMarkdownBlockCodeRanges(source);

    expect(ranges, hasLength(6));
    expect(ranges.map((range) => range.textInside(source)), <String>[
      '    code 😀 ^[inside]',
      '```md\r\n',
      '\r\n',
      'fenced [^inside]\r\n',
      '```',
      '    nested %%inside%% ^inside-id',
    ]);
    expect(
      ianvsMarkdownBlockCodeRanges('> paragraph\n>     indented continuation'),
      isEmpty,
    );
  });

  test('code ranges project list item containers and preserve prefixes', () {
    const source =
        'Before 😀.\r\n'
        '\r\n'
        '1.     ordered 😀 ^[one]\r\n'
        '-\r\n'
        '      empty ^[two]\r\n'
        '-\r\n'
        '  -\r\n'
        '        nested ^[three]\r\n'
        '- quote\r\n'
        '  >     quoted ^[four]\r\n'
        '-\t\tTabbed ^[five]\r\n'
        '- ```md\r\n'
        '  fenced ^[six]\r\n'
        '  ```\r\n'
        'After.';

    final ranges = ianvsMarkdownBlockCodeRanges(source);

    expect(ranges, hasLength(8));
    expect(ranges.map((range) => range.textInside(source)), <String>[
      '    ordered 😀 ^[one]',
      '    empty ^[two]',
      '    nested ^[three]',
      '    quoted ^[four]',
      '\tTabbed ^[five]',
      '```md\r\n',
      'fenced ^[six]\r\n',
      '```',
    ]);
    expect(
      ianvsMarkdownBlockCodeRanges(
        '- paragraph\n  continuation ^[outside]\n'
        '- item\n      indented continuation ^[outside]',
      ),
      isEmpty,
    );
  });

  test('partial tabs retain code indentation after container projection', () {
    for (final indentation in <String>[' \t', '  \t', '   \t']) {
      expect(
        parseMarkdownBlocks('${indentation}code').single.type,
        IanvsMarkdownBlockType.indentedCode,
      );
    }

    const source =
        '  \ttop-level ^[one]\r\n'
        '\r\n'
        '-\r\n'
        '\t\tlisted 😀 ^[two]\r\n'
        '\r\n'
        '>\t\tquoted ^[three]';

    final blocks = parseMarkdownBlocks(source);
    expect(blocks.first.type, IanvsMarkdownBlockType.indentedCode);
    expect(blocks.first.source, '  \ttop-level ^[one]');

    final ranges = ianvsMarkdownBlockCodeRanges(source);
    expect(ranges.map((range) => range.textInside(source)), <String>[
      '  \ttop-level ^[one]',
      '\t\tlisted 😀 ^[two]',
      '\tquoted ^[three]',
    ]);
  });

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

  test('syntax scans can expose code inside standalone comment grouping', () {
    const source = '''%%

    %%inside%%
%%
visible''';

    final grouped = parseMarkdownBlocks(source);
    final structural = parseMarkdownBlocks(
      source,
      groupStandaloneComments: false,
    );

    expect(grouped.first.source, '%%\n\n    %%inside%%\n%%');
    expect(structural.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.paragraph,
      IanvsMarkdownBlockType.indentedCode,
      IanvsMarkdownBlockType.paragraph,
    ]);
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

  test('front matter block boundaries require exact triple dashes', () {
    const sources = <String>[
      '---\ntitle: Ellipsis\n...\nBody',
      ' ---\ntitle: Opening prefix\n---\nBody',
      '--- \ntitle: Opening suffix\n---\nBody',
      '---\ntitle: Closing prefix\n ---\nBody',
      '---\ntitle: Closing suffix\n--- \nBody',
      '\ufeff---\ntitle: BOM\n---\nBody',
    ];

    for (final source in sources) {
      final blocks = parseMarkdownBlocks(source);
      expect(
        blocks.map((block) => block.type),
        isNot(contains(IanvsMarkdownBlockType.frontMatter)),
        reason: source,
      );
    }
  });

  test('front matter block ranges have no arbitrary 256-line boundary', () {
    final frontMatter = <String>[
      '---',
      for (var index = 0; index < 256; index += 1) 'key$index: value',
      '---',
    ].join('\n');
    final blocks = parseMarkdownBlocks('$frontMatter\nBody');

    expect(blocks, hasLength(2));
    expect(blocks.first.type, IanvsMarkdownBlockType.frontMatter);
    expect(blocks.first.source, frontMatter);
    expect(blocks.last.type, IanvsMarkdownBlockType.paragraph);
    expect(blocks.last.source, 'Body');
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

  test('multiline Setext headings consume the complete paragraph', () {
    const levelOne = 'First title line\nsecond title line\n===';
    const levelTwo = 'Another title line\ncontinued title line\n---';
    final blocks = parseMarkdownBlocks('$levelOne\n\n$levelTwo');

    expect(blocks, hasLength(2));
    expect(
      blocks.map((block) => block.type),
      everyElement(IanvsMarkdownBlockType.heading),
    );
    expect(blocks.map((block) => block.source), <String>[levelOne, levelTwo]);
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

  test(
    'list interruption requires non-empty content and ordered start one',
    () {
      for (final source in <String>[
        'Paragraph\n2. item',
        'Paragraph\n* ',
        'Paragraph\n1. ',
      ]) {
        final blocks = parseMarkdownBlocks(source);
        expect(blocks, hasLength(1), reason: source);
        expect(
          blocks.single.type,
          IanvsMarkdownBlockType.paragraph,
          reason: source,
        );
        expect(blocks.single.source, source, reason: source);
      }

      const valid = 'Paragraph\n1. item';
      final validBlocks = parseMarkdownBlocks(valid);
      expect(validBlocks.map((block) => block.type), <IanvsMarkdownBlockType>[
        IanvsMarkdownBlockType.paragraph,
        IanvsMarkdownBlockType.orderedList,
      ]);

      const lazyQuote = '> Paragraph\n2. item\n> tail';
      final quoteBlocks = parseMarkdownBlocks(lazyQuote);
      expect(quoteBlocks, hasLength(1));
      expect(quoteBlocks.single.type, IanvsMarkdownBlockType.blockquote);
      expect(quoteBlocks.single.source, lazyQuote);
    },
  );

  test('callouts retain code-indented lazy paragraph continuations', () {
    const source =
        '> [!note] Four-space boundary\n'
        '> before\n'
        '    lazy code-looking\n'
        '> after';

    final blocks = parseMarkdownBlocks(source);

    expect(blocks, hasLength(1));
    expect(blocks.single.type, IanvsMarkdownBlockType.blockquote);
    expect(blocks.single.source, source);
  });

  test('quotes retain code-indented lazy paragraph continuations', () {
    const lazyParagraph =
        '> paragraph\n'
        '    lazy code-looking\n'
        '> tail';
    final lazyBlocks = parseMarkdownBlocks(lazyParagraph);

    expect(lazyBlocks, hasLength(1));
    expect(lazyBlocks.single.type, IanvsMarkdownBlockType.blockquote);
    expect(lazyBlocks.single.source, lazyParagraph);

    const quotedCode =
        '>     code\n'
        '    outside code\n'
        '> tail';
    final codeBlocks = parseMarkdownBlocks(quotedCode);

    expect(codeBlocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.blockquote,
      IanvsMarkdownBlockType.indentedCode,
      IanvsMarkdownBlockType.blockquote,
    ]);
    expect(codeBlocks.map((block) => block.source), <String>[
      '>     code',
      '    outside code',
      '> tail',
    ]);
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

  test('whitespace-only input remains one exact editable block', () {
    const source = ' \t \n\n';
    final blocks = parseMarkdownBlocks(source);

    expect(blocks, hasLength(1));
    expect(blocks.single.source, source);
    expect(blocks.single.start, 0);
    expect(blocks.single.end, source.length);
    expect(blocks.single.firstLine, 0);
    expect(blocks.single.lastLine, 1);
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

  test('loose lists retain blank-separated items and child blocks', () {
    const source =
        '- one\n'
        '\n'
        '- two\n'
        '\n'
        '  continuation\n'
        '\n'
        'After.';

    final grouped = parseMarkdownBlocks(source);
    expect(grouped, hasLength(2));
    expect(grouped.first.type, IanvsMarkdownBlockType.unorderedList);
    expect(grouped.first.source, '- one\n\n- two\n\n  continuation');
    expect(grouped.last.source, 'After.');

    final split = parseMarkdownBlocks(source, splitListItems: true);
    expect(split.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.paragraph,
    ]);
    expect(split.map((block) => block.source), <String>[
      '- one',
      '- two\n\n  continuation',
      'After.',
    ]);
  });

  test('changing a list delimiter starts a new source block', () {
    const source =
        '- dash\n'
        '* star\n'
        '+ plus\n'
        '\n'
        '1. dot\n'
        '2) paren';

    final blocks = parseMarkdownBlocks(source);
    expect(blocks.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.orderedList,
      IanvsMarkdownBlockType.orderedList,
    ]);
    expect(blocks.map((block) => block.source), <String>[
      '- dash',
      '* star',
      '+ plus',
      '1. dot',
      '2) paren',
    ]);

    final sameDelimiter = parseMarkdownBlocks('- one\n- two');
    expect(sameDelimiter, hasLength(1));
    expect(sameDelimiter.single.source, '- one\n- two');
  });

  test('marker-only lists retain visual-column Tab continuations', () {
    const source =
        '-\n'
        ' \tcontinued\n'
        '- parent\n'
        '\n'
        '  - child';

    final grouped = parseMarkdownBlocks(source);
    expect(grouped, hasLength(1));
    expect(grouped.single.type, IanvsMarkdownBlockType.unorderedList);
    expect(grouped.single.source, source);

    final split = parseMarkdownBlocks(source, splitListItems: true);
    expect(
      split.map((block) => block.type),
      everyElement(IanvsMarkdownBlockType.unorderedList),
    );
    expect(split.map((block) => block.source), <String>[
      '-\n \tcontinued',
      '- parent',
      '  - child',
    ]);

    final ordered = parseMarkdownBlocks('1.\n \tcontinued');
    expect(ordered, hasLength(1));
    expect(ordered.single.type, IanvsMarkdownBlockType.orderedList);

    final emptyTask = parseMarkdownBlocks('- [ ]');
    expect(emptyTask.single.type, IanvsMarkdownBlockType.taskList);

    final emptyThenBlank = parseMarkdownBlocks('-\n\n  outside');
    expect(emptyThenBlank.map((block) => block.type), <IanvsMarkdownBlockType>[
      IanvsMarkdownBlockType.unorderedList,
      IanvsMarkdownBlockType.paragraph,
    ]);
    expect(emptyThenBlank.map((block) => block.source), <String>[
      '-',
      '  outside',
    ]);
  });
}
