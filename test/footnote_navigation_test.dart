import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  test('inline IDs reuse expansion order, nesting and reserved labels', () {
    const source =
        'A^[ outer ^[inner] ] B^[last]\n\n[^ianvs-inline-footnote-1]: reserved';
    expect(
      ianvsMarkdownFootnoteSourceRange(source, 'fn-ianvs-inline-footnote-2'),
      TextRange(start: source.indexOf('^[ outer'), end: source.indexOf(' B')),
    );
    expect(
      ianvsMarkdownFootnoteSourceRange(source, 'fn-ianvs-inline-footnote-3'),
      TextRange(
        start: source.indexOf('^[inner]'),
        end: source.indexOf('^[inner]') + 8,
      ),
    );
    expect(
      ianvsMarkdownFootnoteSourceRange(source, 'fnref-ianvs-inline-footnote-4'),
      TextRange(
        start: source.indexOf('^[last]'),
        end: source.indexOf('^[last]') + 7,
      ),
    );
    expect(
      ianvsMarkdownFootnoteSourceRange(
        '`^[code]` %%^[comment]%% actual^[note]',
        'fn-ianvs-inline-footnote-1',
      )!.start,
      31,
    );
  });
  test('front matter footnote-like text is not a navigation target', () {
    const source =
        '---\ntext: |\n  [^hidden]: metadata\n---\n\nVisible[^shown]\n\n[^shown]: body';
    expect(ianvsMarkdownFootnoteSourceRange(source, 'fn-hidden'), isNull);
    expect(
      ianvsMarkdownFootnoteSourceRange(source, 'fn-shown')!.start,
      source.indexOf('[^shown]:'),
    );
  });
  test(
    'footnote definitions use last case-insensitive match outside code/comments',
    () {
      const source =
          'Ref[^Note]\n\n[^note]: old\n\n```\n[^note]: code\n```\n\n%%\n[^note]: hidden\n%%\n\n[^NOTE]: final';
      expect(
        ianvsMarkdownFootnoteSourceRange(source, 'fn-NOTE'),
        TextRange(
          start: source.lastIndexOf('[^NOTE]'),
          end: source.lastIndexOf('[^NOTE]') + 8,
        ),
      );
      expect(ianvsMarkdownFootnoteSourceRange(source, 'fn-missing'), isNull);
    },
  );
  for (final newline in ['\n', '\r\n', '\r']) {
    test('footnote references preserve offsets with ${newline.codeUnits}', () {
      final source =
          'a[^中文]$newline`[^中文]`$newline%%[^中文]%%${newline}b[^中文]$newline[^中文]: body';
      final first = source.indexOf('[^中文]');
      final second = source.indexOf('b[^中文]') + 1;
      expect(
        ianvsMarkdownFootnoteSourceRange(source, 'fnref-中文'),
        TextRange(start: first, end: first + 5),
      );
      expect(
        ianvsMarkdownFootnoteSourceRange(source, 'fnref-中文-2'),
        TextRange(start: second, end: second + 5),
      );
      expect(ianvsMarkdownFootnoteSourceRange(source, 'fnref-中文-3'), isNull);
    });
  }
  test('labels ending in digits are resolved before occurrence suffixes', () {
    const source =
        'a[^note-2] b[^note] c[^note]\n\n[^note]: one\n[^note-2]: two';
    expect(ianvsMarkdownFootnoteSourceRange(source, 'fnref-note-2')!.start, 1);
    expect(
      ianvsMarkdownFootnoteSourceRange(source, 'fn-ianvs-inline-footnote-1'),
      isNull,
    );
  });
}
