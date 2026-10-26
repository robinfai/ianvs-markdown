import 'package:flutter/services.dart';
import 'package:ianvs_markdown/src/editor/editor_controller.dart'
    show markdownInlineVisibleSourceRanges;
import 'package:ianvs_markdown/src/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/syntax_preset.dart';
import 'package:ianvs_markdown/src/render_budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:ianvs_markdown/src/renderer/source_mapped_document.dart';
import 'package:ianvs_markdown/src/renderer/reading_text_index.dart';

MarkdownReadingTextIndex index(String source) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parseLines(source.split('\n'));
  return MarkdownReadingTextIndex.fromNodes(
    nodes,
    source: source,
    sourceRange: (node) =>
        nodes.contains(node) ? TextRange(start: 0, end: source.length) : null,
  );
}

void main() {
  test('list anchors cover ordered, task, loose, and continuation items', () {
    for (final source in [
      '1. same\n2. same',
      '- [ ] same\n- [x] same',
      '- same\n\n- same',
      '- same\n  continuation\n- same',
      '- parent\n    - same\n    - same',
    ]) {
      final matches = IanvsMarkdownReadingSearch.parse(source)!.find('same');
      expect(matches.length, 2, reason: source);
      expect(
        matches.first.navigationRange.start,
        lessThan(matches.last.navigationRange.start),
        reason: source,
      );
      expect(matches.last.navigationRange.textInside(source), contains('same'));
    }
  });

  test('repeated and nested list items retain separate navigation anchors', () {
    const source = '- same\n- same\n  - child\n- end';
    final search = IanvsMarkdownReadingSearch.parse(source)!;
    final matches = search.find('same');
    expect(matches.length, 2);
    expect(matches.first.sourceRange, matches.last.sourceRange);
    expect(matches.first.navigationRange.start, 0);
    expect(matches.last.navigationRange.start, source.indexOf('- same', 1));
    expect(
      search.find('child').single.navigationRange.start,
      source.indexOf('  - child'),
    );
    expect(
      search.find('end').single.navigationRange.start,
      source.indexOf('- end'),
    );
  });

  test('Live structural projection preserves literal code punctuation', () {
    for (final source in [
      '# target phrase',
      '- target phrase',
      '> target phrase',
    ]) {
      expect(
        markdownInlineVisibleSourceRanges(
          source,
        ).map((range) => range.textInside(source)).join(),
        'target phrase',
      );
    }
    const code = '```text\n# literal **symbols** [link](text)\n```';
    expect(
      markdownInlineVisibleSourceRanges(
        code,
      ).map((range) => range.textInside(code)).join().trim(),
      '# literal **symbols** [link](text)',
    );
  });

  test(
    'Live inline source projection excludes destinations even when words repeat',
    () {
      const source = 'target [phrase](phrase) **phrase** `code`';
      final ranges = markdownInlineVisibleSourceRanges(source);
      expect(
        ranges.map((range) => range.textInside(source)).join(),
        'target phrase phrase code',
      );
      final destination = source.indexOf('(phrase)');
      expect(
        ranges.any(
          (range) => range.start < destination + 8 && range.end > destination,
        ),
        isFalse,
      );
      expect(
        ranges.every((range) => range.isValid && range.end <= source.length),
        isTrue,
      );
    },
  );

  test(
    'Obsidian searches displayed words and preserves original block offsets',
    () {
      const source =
          '---\r\ntitle: hidden\r\n---\r\n'
          '%% secret %%\r\n\r\n'
          'Hello **world** [[Target|friend]] ==bright== ^block-id\r\n';
      final result = buildMarkdownReadingTextIndex(source)!;
      expect(result.find('Hello world friend bright').length, 1);
      for (final hidden in ['secret', 'hidden', 'Target', 'block-id']) {
        expect(result.find(hidden), isEmpty, reason: hidden);
      }
      expect(
        result.find('friend').single.sourceRange.start,
        source.indexOf('Hello'),
      );
    },
  );

  test('callout title and nested body retain the enclosing source anchor', () {
    const source =
        '> [!note] My **title**\n> Body [[Note|label]]\n>\n> - nested item';
    final result = buildMarkdownReadingTextIndex(source)!;
    expect(result.find('My title').length, 1);
    expect(result.find('Body label').length, 1);
    expect(result.find('nested item').single.sourceRange.start, 0);
    expect(result.find('[!note]'), isEmpty);
  });

  test(
    'standard preset keeps YAML-shaped Markdown and literal wiki syntax',
    () {
      const source = '---\ntitle: visible\n---\n\n[[Note|label]]';
      final result = buildMarkdownReadingTextIndex(
        source,
        syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
      )!;
      expect(result.find('visible').length, 1);
      expect(result.find('[[Note|label]]').length, 1);
    },
  );

  test(
    'render budget rejection is explicit, never an empty successful index',
    () {
      expect(
        buildMarkdownReadingTextIndex(
          'too long',
          budget: const IanvsMarkdownRenderBudget(maxSourceCodeUnits: 3),
        ),
        isNull,
      );
    },
  );

  test(
    'renderer line map disambiguates repeated text after hidden metadata',
    () {
      const prefix = '---\ntitle: hidden\n---\n';
      const body = 'same **word**\n\nsame word';
      const source = prefix + body;
      final document = SourceMappedMarkdownDocument(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      );
      final result = MarkdownReadingTextIndex.fromDocument(
        source: source,
        nodes: document.parseLines(body.split('\n')),
        document: document,
        lineOffsets: [prefix.length, prefix.length + 14, prefix.length + 15],
      );
      final matches = result.find('same word');
      expect(matches.length, 2);
      expect(matches.first.sourceRange.start, prefix.length);
      expect(matches.last.sourceRange.start, prefix.length + 15);
      expect(result.find('hidden'), isEmpty);
    },
  );

  test('joins inline formatting and searches visible link labels only', () {
    final result = index(
      'A **bold** [link](https://secret.example) and `code`.',
    );
    expect(result.find('bold link').length, 1);
    expect(result.find('secret'), isEmpty);
    expect(result.find('**'), isEmpty);
    expect(result.find('code').length, 1);
    final match = result.find('bold link').single;
    expect(
      result.segments[match.segmentIndex].text.substring(
        match.textRange.start,
        match.textRange.end,
      ),
      'bold link',
    );
  });

  test('paragraphs, list items and table cells are distinct flows', () {
    for (final source in [
      'alpha\n\nbeta',
      '- alpha\n- beta',
      '| alpha | beta |\n| --- | --- |\n| gamma | delta |',
    ]) {
      final result = index(source);
      expect(result.find('alphabeta'), isEmpty);
      expect(result.find('alpha beta'), isEmpty);
      expect(result.find('alpha').length, 1);
      expect(result.find('beta').length, 1);
    }
  });

  test(
    'code text is searchable, Mermaid source and image alt are excluded',
    () {
      final result = index(
        '```dart\nprint("visible");\n```\n\n'
        '```mermaid\ngraph secret\n```\n\n![hidden](image.png)',
      );
      expect(result.find('visible').length, 1);
      expect(result.find('secret'), isEmpty);
      expect(result.find('hidden'), isEmpty);
      expect(result.find('dart'), isEmpty);
    },
  );

  test('literal Unicode matches preserve UTF16 ranges and case choice', () {
    final result = index('中文😀 a.b A.B');
    expect(
      result.find('中文😀').single.textRange,
      const TextRange(start: 0, end: 4),
    );
    expect(result.find('a.b').length, 2);
    expect(result.find('a.b', matchCase: true).length, 1);
    expect(result.find('a?b'), isEmpty);
    expect(result.find(''), isEmpty);
    expect(result.find(String.fromCharCode(0xd83d)), isEmpty);
  });

  test('nested source ranges survive reordered nodes and unmapped text', () {
    final first = md.Element.text('p', 'first');
    final footnote = md.Element.text('li', 'note');
    final generated = md.Element.text('p', 'unmapped');
    final result = MarkdownReadingTextIndex.fromNodes(
      [
        first,
        md.Element('section', [footnote]),
        generated,
      ],
      source: 'note definition\nfirst paragraph',
      sourceRange: (node) => identical(node, first)
          ? const TextRange(start: 16, end: 31)
          : identical(node, footnote)
          ? const TextRange(start: 0, end: 15)
          : null,
    );
    expect(result.find('note').single.sourceRange.start, 0);
    expect(result.find('unmapped'), isEmpty);
  });
}
