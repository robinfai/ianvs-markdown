import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/models/document_analysis.dart';
import 'package:linefold/src/models/document_session.dart';

void main() {
  test(
    'statistics retain the previous whitespace and Unicode scalar contract',
    () {
      final samples = [
        '',
        'hello 世界\r\nemoji 👩🏽‍💻 e\u0301',
        '\ud800 A\udc00\ud800\udc00',
        String.fromCharCodes(List.generate(65536, (i) => i)),
        [
          0x09,
          0x0a,
          0x0b,
          0x0c,
          0x0d,
          0x20,
          0xa0,
          0x85,
          0x1680,
          0x180e,
          0x2000,
          0x200a,
          0x200b,
          0x2028,
          0x2029,
          0x202f,
          0x205f,
          0x3000,
          0xfeff,
        ].map((v) => 'a${String.fromCharCode(v)}b').join(' '),
      ];
      for (final source in samples) {
        final result = DocumentStatistics.scan(source);
        expect(result.words, RegExp(r'\S+').allMatches(source).length);
        expect(result.characters, source.runes.length);
      }
    },
  );

  test(
    'outline matches existing block grammar across edits and offset shifts',
    () {
      final analysis = DocumentAnalysis();
      const source = '''---
title: Metadata
---
# **First** and [link](https://example.com)

```md
# not a heading
```

> # quoted

Title 中文
=====

<table>
# HTML
</table>

## Last 👩🏽‍💻
''';
      for (final text in [
        source,
        '\r\n$source',
        source.replaceFirst('```md', 'text'),
        source.replaceAll('\n', '\r\n'),
        source.replaceFirst('## Last', '# Changed'),
        '',
      ]) {
        final expected = [
          for (final block in parseMarkdownBlocks(text))
            if (block.type == IanvsMarkdownBlockType.heading)
              for (final label in parseMarkdownHeadings(block.source).take(1))
                (block.start, label.level, label.text),
        ];
        expect(
          analysis.headings(text).map((h) => (h.offset, h.level, h.text)),
          expected,
        );
      }
    },
  );

  test('unchanged titles reuse parsing while current offsets remain exact', () {
    final analysis = DocumentAnalysis();
    const source = '# First\n\nparagraph\n\n## **Unchanged**\n';
    final old = analysis.headings(source);
    final nextSource = source.replaceFirst('paragraph', '中文 👩🏽‍💻 paragraph');
    final next = analysis.headings(nextSource);
    expect(identical(old.last.label, next.last.label), isTrue);
    expect(next.last.offset, nextSource.indexOf('##'));
    expect(identical(next, analysis.headings(nextSource)), isTrue);
    expect(analysis.headings('# Completely new').single.text, 'Completely new');
    expect(analysis.headings(source).last.text, 'Unchanged');
  });

  test(
    'selection, composition and save reuse derived data without stale edits',
    () {
      final document = DocumentSession(
        id: 'analysis',
        name: 'a.md',
        text: '# 中文 👋\r\n',
      );
      addTearDown(document.dispose);
      final old = document.analysis.statistics(document.controller.text);
      final oldHeadings = document.analysis.headings(document.controller.text);
      document.controller.selection = const TextSelection.collapsed(offset: 2);
      document.controller.value = document.controller.value.copyWith(
        composing: const TextRange(start: 2, end: 4),
      );
      document.markSaved();
      expect(
        identical(document.analysis.statistics(document.controller.text), old),
        isTrue,
      );
      expect(
        identical(
          document.analysis.headings(document.controller.text),
          oldHeadings,
        ),
        isTrue,
      );
      document.controller.value = const TextEditingValue(
        text: '# 新标题\n\nnew words',
      );
      expect(
        document.analysis.headings(document.controller.text).single.text,
        '新标题',
      );
      expect(document.analysis.statistics(document.controller.text).words, 4);
      expect(document.controller.isDirty, isTrue);
    },
  );
}
