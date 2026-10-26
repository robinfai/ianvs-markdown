import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:ianvs_markdown/src/renderer/source_mapped_document.dart';

void main() {
  final contract =
      jsonDecode(
            File(
              'test/fixtures/standard_syntax_contract.json',
            ).readAsStringSync(),
          )
          as Map;
  final samples = <String>[
    for (final fixture in contract['fixtures'] as List)
      fixture['source'] as String,
    '# Heading\n\nParagraph **strong** and [ref][link].\n\n[link]: /test "title"',
    'setext\ncontinued\n===\n\nnext\n---\n\nend',
    '- one\n  - nested\n\n  second paragraph\n\n- next\n\n> quote\n>\n> continued',
    'before[^a] and again[^a]\n\n[^b]: unused\n\n[^a]: note\n\n    more',
    '| A | B |\n|---|---|\n| x | y |\n\n|bad|\n|---|---|',
    '```dart\ncode\n```\n\n    indented\n\n<div>HTML</div>',
    '',
    '\n\n',
    '中文😀\r\n\r\n# second\r\n',
  ];
  for (var i = 0; i < samples.length; i++) {
    test('tracked parser preserves upstream AST for fixture $i', () {
      final source = samples[i];
      final standard = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      );
      final tracked = SourceMappedMarkdownDocument(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      );
      final lines = const LineSplitter().convert(source);
      final actual = tracked.parseLines(lines);
      expect(
        md.renderToHtml(actual),
        md.renderToHtml(standard.parseLines(lines)),
      );
      for (final range in tracked.ranges.values) {
        expect(range.start, greaterThanOrEqualTo(0));
        expect(range.end, lessThanOrEqualTo(lines.length));
        expect(range.end, greaterThan(range.start));
      }
    });
  }

  test(
    'source range includes all setext lines and excludes trailing blank lines',
    () {
      final document = SourceMappedMarkdownDocument(
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
      final nodes = document.parseLines([
        'first',
        'second',
        '===',
        '',
        'paragraph',
      ]);
      expect(document.ranges[nodes[0]]!.start, 0);
      expect(document.ranges[nodes[0]]!.end, 3);
      expect(document.ranges[nodes[1]]!.start, 4);
      expect(document.ranges[nodes[1]]!.end, 5);
    },
  );
}
