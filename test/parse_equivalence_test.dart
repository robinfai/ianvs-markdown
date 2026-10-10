import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/editor/reference_links.dart';
import 'package:markdown/markdown.dart' as md;

final _fixtures = <String>[
  '# [Forward][ref]\n\n[ref]: /first "title"\n[REF]: /ignored',
  '> [quoted]: /quote\n> # Nested heading\n\n# Outside [quoted]',
  '- [listed]: /list\n  # Nested\n\n# Outside [listed]',
  '```md\n[code]: /fake\n# Not a heading\n```\n\n# Real',
  '~~~\n[code]: /fake\n~~~\n\n    [indented]: /fake\n\n# Real',
  '<div>\n[html]: /fake\n# Fake\n</div>\n\n# Real',
  '[a]: <docs/a b>\n  "multiline\n  title"\n\n# [a]',
  '[a\nb]: /multi\n\n# [title][a b]',
  r'[escaped\]label]: /docs'
      '\n\n# [escaped\\]label]',
  '# A **bold** _emphasis_ `code` &amp; <em>HTML</em>',
  '# ![image alt](image.png) [inline](destination) <https://example.com>',
  '# 中文😀\r\n\r\nTitle\r\nwith break\r\n===\r\n',
  '#\n\n## \t\n\n### ** **\n\n###### Last\n\n####### Literal',
  'table | title\n--- | ---\n# Cell | [cell]: /fake\n\n# After table',
  '[ref]: /path (parenthesized title)\n\n## [ref][]',
  '[a]: /one\n[b]: /two\n\nText [b].\n\n# [a] and [b]',
  '# [missing] [empty]()\n\n[empty]: /fallback',
  '# A[^note]\n\n[^note]: body\n\n# B[^note]',
  '\n\n[only]: /definition\n\n',
  '[bad]: <unclosed\n\n# Real',
  'Body[^a].\n\n# Heading[^b]\n\n[^a]: First\n[^b]: Second',
  '###### Excluded[^a]\n\n# Included[^b]\n\n[^a]: First\n[^b]: Second',
  '# Repeat[^a] and missing[^missing]\n\n[^a]: First\n\n# Again[^a]',
  '> Quote[^a]\n\n# Heading[^b]\n\n[^a]: First\n[^b]: Second',
  '# [Forward][ref]\n\n[^unused]: [ref]: /inside-footnote',
  '```\n[^fake]: hidden\n```\n\n# [Forward][ref]\n\n[ref]: /real',
  '# Forward ![image][ref]\n\n[ref]: /image.png "Image title"',
  '# Escaped \\*marker\\* and &#x1f600;\n\n[ref]: /unused',
  'Setext [forward]\nand **bold**\n---\n\n[forward]: /destination',
  '\\[^escaped]: /ordinary-reference\n\n# [^undefined]',
];

Map<String, (String, String, String?)> _references(
  Map<String, md.LinkReference> references,
) => {
  for (final entry in references.entries)
    entry.key: (entry.value.label, entry.value.destination, entry.value.title),
};

List<(int, String)> _headings(String source, int maximumLevel) {
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  final nodes = document.parseLines(const LineSplitter().convert(source));
  return [
    for (final node in nodes)
      if (node is md.Element &&
          RegExp(r'^h[1-6]$').hasMatch(node.tag) &&
          int.parse(node.tag[1]) <= maximumLevel &&
          node.textContent.trim().isNotEmpty)
        (int.parse(node.tag[1]), node.textContent.trim()),
  ];
}

void main() {
  test('reference context retains full GFM definition semantics', () {
    for (final source in _fixtures) {
      final upstream = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
        ..parseLines(source.split('\n'));
      expect(
        _references(MarkdownLinkReferenceContext.parse(source).references),
        _references(upstream.linkReferences),
        reason: source,
      );
    }
  });

  test('outline matches complete GFM parsing and maximum heading level', () {
    for (final source in _fixtures) {
      for (final maximum in [1, 3, 6]) {
        expect(
          parseMarkdownHeadings(
            source,
            maximumLevel: maximum,
          ).map((heading) => (heading.level, heading.text)).toList(),
          _headings(source, maximum),
          reason: '$maximum / $source',
        );
      }
    }
  });

  test('cross-block edits and growing delimiters use the current source', () {
    const versions = [
      '# [Heading][ref]\n\n[ref]: /old',
      'Body[^a].\n\n# [Heading][ref][^b]\n\n[ref]: /old\n'
          '[^a]: First\n[^b]: Second',
      '# [Heading][ref][^b]\n\n[ref]: /old\n[^b]: Second',
      '# [Heading][ref]\n\n[ref]: /new',
      '# [Heading][ref]\n\n[ref]: /new "Changed"',
      '# [Heading][missing]\n\n[ref]: /new "Changed"',
      '```\n# [Heading][ref]\n\n[ref]: /new "Changed"',
      '```\n# [Heading][ref]\n```\n\n[ref]: /new "Changed"',
      '# [Heading][ref]\n\n[ref]: /old',
    ];
    for (final source in versions) {
      final upstream = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
        ..parseLines(source.split('\n'));
      expect(
        _references(MarkdownLinkReferenceContext.parse(source).references),
        _references(upstream.linkReferences),
      );
      expect(
        parseMarkdownHeadings(
          source,
        ).map((heading) => (heading.level, heading.text)).toList(),
        _headings(source, 6),
      );
    }
  });

  test('reference extraction keeps definitions around dense inline syntax', () {
    final paragraph = List.filled(
      120,
      '**bold** [link][target] ![image](asset.png) `code` &amp;',
    ).join(' ');
    final source =
        '# [Title][target]\n\n$paragraph\n\n'
        '[target]: <docs/a b> "first"\n[TARGET]: /ignored';
    final upstream = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
      ..parseLines(source.split('\n'));
    expect(
      _references(
        MarkdownLinkReferenceContext.parse(source, budget: null).references,
      ),
      _references(upstream.linkReferences),
    );
    expect(
      parseMarkdownHeadings(
        source,
        budget: null,
      ).map((heading) => (heading.level, heading.text)).toList(),
      _headings(source, 6),
    );
  });
}
