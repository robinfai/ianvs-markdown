import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/src/editor/markdown_paste.dart';

void main() {
  test('rectangular TSV preserves empty cells and quoted spreadsheet values', () {
    expect(
      markdownTableFromTsv(
        'Name\tValue\r\n"a\tb"\t"line1\nline2"\r\nempty\t\r\n',
      ),
      '| Name | Value |\n| --- | --- |\n| a\tb | line1<br>line2 |\n| empty |  |',
    );
    expect(markdownTableFromTsv('A\tB\n"a""b"\tx'), contains('a"b'));
  });
  test('cell punctuation stays literal and malformed grids stay plain', () {
    expect(
      markdownTableFromTsv('A\tB\n*text*|x\t<script>&'),
      '| A | B |\n| --- | --- |\n| \\*text\\*\\|x | &lt;script&gt;&amp; |',
    );
    for (final text in [
      'one\ttwo',
      'a\tb\nx',
      'a\tb\n"unclosed\tx',
      'a\tb\n"a"x\ty',
    ]) {
      expect(markdownTableFromTsv(text), isNull);
    }
  });
  test('block insertion separates surrounding prose and preserves CRLF', () {
    final result = smartTablePasteValue(
      const TextEditingValue(
        text: 'BeforeAfter\r\n',
        selection: TextSelection.collapsed(offset: 6),
      ),
      'A\tB\n1\t2',
    )!;
    expect(
      result.text,
      'Before\r\n\r\n| A | B |\r\n| --- | --- |\r\n| 1 | 2 |\r\n\r\nAfter\r\n',
    );
    expect(result.selection.extentOffset, result.text.indexOf('After'));
  });
  test('code and existing tables retain native literal paste', () {
    for (final source in [
      '```\ncode\n```',
      '    code',
      '`code`',
      '| A | B |\n|---|---|\n| code | x |',
    ]) {
      final offset = source.indexOf('code') + 1;
      expect(
        smartTablePasteValue(
          TextEditingValue(
            text: source,
            selection: TextSelection.collapsed(offset: offset),
          ),
          'A\tB\n1\t2',
        ),
        isNull,
      );
    }
  });
}
