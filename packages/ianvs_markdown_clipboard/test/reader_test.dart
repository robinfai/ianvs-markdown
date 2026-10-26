import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown_clipboard/src/reader.dart';
import 'package:super_clipboard/super_clipboard.dart';

class _Item extends Fake implements ClipboardDataReader {
  _Item({
    this.html,
    this.plain,
    this.htmlError = false,
    this.plainError = false,
  });
  final String? html;
  final String? plain;
  final bool htmlError;
  final bool plainError;
  int reads = 0;
  @override
  bool canProvide(DataFormat format) => identical(format, Formats.htmlText)
      ? html != null || htmlError
      : identical(format, Formats.plainText) && (plain != null || plainError);
  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async {
    reads++;
    if (identical(format, Formats.htmlText)) {
      if (htmlError) throw StateError('HTML unavailable');
      return html as T?;
    }
    if (plainError) throw StateError('Plain unavailable');
    return plain as T?;
  }
}

void main() {
  test('reads paired text from one snapshot and one item', () async {
    final first = _Item(html: '<p>First</p>', plain: 'First');
    final second = _Item(html: '<p>Other</p>', plain: 'Other');
    var snapshots = 0;
    final result = await readClipboardTextSnapshot(() async {
      snapshots++;
      return ClipboardReader([first, second]);
    });
    expect(snapshots, 1);
    expect(result!.html, '<p>First</p>');
    expect(result.plainText, 'First');
    expect(first.reads, 2);
    expect(second.reads, 0);
  });
  test('rich failures retain exact plain text including CRLF', () async {
    final result = await readClipboardTextSnapshot(
      () async =>
          ClipboardReader([_Item(htmlError: true, plain: '中文\r\n\tvalue')]),
    );
    expect(result!.plainText, '中文\r\n\tvalue');
    expect(result.html, isNull);
  });
  test('missing plain text is never borrowed from another item', () async {
    final other = _Item(plain: 'unrelated');
    final result = await readClipboardTextSnapshot(
      () async => ClipboardReader([
        _Item(html: '<b>Only</b>', plainError: true),
        other,
      ]),
    );
    expect(result!.html, '<b>Only</b>');
    expect(result.plainText, isNull);
    expect(other.reads, 0);
  });
  test(
    'oversized or empty HTML falls back without truncating plain text',
    () async {
      for (final html in ['', 'x' * (1024 * 1024 + 1)]) {
        final result = await readClipboardTextSnapshot(
          () async => ClipboardReader([_Item(html: html, plain: 'original')]),
        );
        expect(result!.plainText, 'original');
        expect(result.html, isNull);
      }
    },
  );
  test('unavailable plugins and textless snapshots return null', () async {
    expect(await readClipboardTextSnapshot(() async => null), isNull);
    expect(
      await readClipboardTextSnapshot(
        () async => throw StateError('plugin unavailable'),
      ),
      isNull,
    );
    expect(
      await readClipboardTextSnapshot(() async => ClipboardReader([])),
      isNull,
    );
    expect(
      await readClipboardTextSnapshot(() async => ClipboardReader([_Item()])),
      isNull,
    );
  });
}
