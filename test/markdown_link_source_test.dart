import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/src/markdown_link_source.dart';

void main() {
  group('inline Markdown source matching', () {
    test('accepts Obsidian destination and title forms', () {
      const valid = <String>[
        '[]()',
        '[empty](<>)',
        '[angle](<https://example.com/a b>)',
        '[balanced](https://example.com/a_(b))',
        r'[escaped](https://example.com/a\)tail)',
        '[double](https://example.com "double title")',
        "[single](https://example.com 'single title')",
        '[bracket](https://example.com (bracket title))',
        '[empty title](https://example.com "")',
        '[spaces](https://example.com   "spaces")',
        '[tab](https://example.com\t"tab")',
        '[tab destination](https://example.com\t"unclosed)',
        '[soft](https://example.com\n"soft title")',
      ];

      for (final source in valid) {
        final labelEnd = findIanvsMarkdownLinkLabelEnd(
          source,
          source.indexOf('['),
        );
        expect(labelEnd, isNotNull, reason: source);
        expect(
          findIanvsMarkdownInlineLinkEnd(source, labelEnd! + 1),
          source.length,
          reason: source,
        );
      }
    });

    test('rejects malformed destinations and titles', () {
      const invalid = <String>[
        '[unbalanced](https://example.com/a_(b)',
        '[unclosed](https://example.com "unclosed)',
        '[trailing](https://example.com "title" mystery)',
        '[angle newline](<https://example.com/a\nb>)',
        '[paragraph](https://example.com\n\n"title")',
      ];

      for (final source in invalid) {
        final labelEnd = findIanvsMarkdownLinkLabelEnd(source, 0);
        expect(labelEnd, isNotNull, reason: source);
        expect(
          findIanvsMarkdownInlineLinkEnd(source, labelEnd! + 1),
          isNull,
          reason: source,
        );
      }
    });

    test('labels can nest and soft-wrap but never cross paragraphs', () {
      const nested = '[nested [inner] label](target)';
      const soft = '[soft\nlabel](target)';
      const paragraph = '[first\n\nsecond](target)';

      expect(findIanvsMarkdownLinkLabelEnd(nested, 0), nested.indexOf(']('));
      expect(findIanvsMarkdownLinkLabelEnd(soft, 0), soft.indexOf(']('));
      expect(findIanvsMarkdownLinkLabelEnd(paragraph, 0), isNull);
    });
  });

  group('reference Markdown source matching', () {
    test('parses escaped secondary labels and rejects invalid forms', () {
      const escaped = r'[label][ref\]part]';
      final escapedStart = escaped.indexOf('[', 1);
      final match = findIanvsMarkdownReferenceLabel(escaped, escapedStart);
      expect(match?.label, 'ref]part');
      expect(match?.end, escaped.length);

      expect(findIanvsMarkdownReferenceLabel('[label][   ]', 7), isNull);
      expect(findIanvsMarkdownReferenceLabel('[label][a[b]]', 7), isNull);
      expect(findIanvsMarkdownReferenceLabel('[label][a\n\nb]', 7), isNull);
    });

    test(
      'collects references without mistaking inline links or definitions',
      () {
        const source =
            '[inline](target) [full][ref] [literal][  ref   name  ] '
            '[collapsed][] [shortcut]\n'
            r'[escaped][ref\]part]'
            '\n'
            '- [x] task\n'
            '[ref]: docs/ref.md';

        expect(findIanvsMarkdownReferencedLabels(source).toList(), <String>[
          'ref',
          'collapsed',
          'shortcut',
          'ref]part',
        ]);
      },
    );

    test('identifies Obsidian-literal reference whitespace', () {
      expect(hasIanvsMarkdownLiteralReferenceWhitespace('Ref A'), isFalse);
      expect(hasIanvsMarkdownLiteralReferenceWhitespace('ref a'), isFalse);
      expect(hasIanvsMarkdownLiteralReferenceWhitespace(' Ref A'), isFalse);
      expect(hasIanvsMarkdownLiteralReferenceWhitespace('Ref A '), isFalse);
      expect(hasIanvsMarkdownLiteralReferenceWhitespace('Ref   A'), isFalse);
      expect(hasIanvsMarkdownLiteralReferenceWhitespace('  Ref   A  '), isTrue);
      expect(
        hasIanvsMarkdownLiteralReferenceWhitespace('\tRef\t\tA\t'),
        isTrue,
      );
    });
  });
}
