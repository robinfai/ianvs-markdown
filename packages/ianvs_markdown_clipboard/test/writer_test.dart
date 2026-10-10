import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown_clipboard/src/writer.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_native_extensions/raw_clipboard.dart' as raw;

class _NativeWriter implements ClipboardWriter {
  final items = <DataWriterItem>[];
  Object? error;

  @override
  Future<void> write(Iterable<DataWriterItem> value) async {
    if (error case final failure?) throw failure;
    items.addAll(value);
  }
}

void main() {
  const markdown = '---\r\ntitle: 中文\r\n---\r\n# **Exact** source\n';
  const html = '<h1><strong>Exact</strong> source</h1>';

  test(
    'missing HTML writes full plain text without initializing native writer',
    () async {
      final written = <String?>[];
      var nativeCalls = 0;
      await writeClipboardWithFallback(
        markdown: markdown,
        html: '',
        nativeClipboard: () {
          nativeCalls++;
          return null;
        },
        plainText: (data) async => written.add(data.text),
      );
      expect(written, [markdown]);
      expect(nativeCalls, 0);
    },
  );

  test(
    'native success writes both representations on exactly one item',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final native = _NativeWriter();
      await writeClipboardWithFallback(
        markdown: markdown,
        html: html,
        nativeClipboard: () => native,
        plainText: (_) async =>
            fail('Successful native output must not be overwritten'),
      );
      expect(native.items, hasLength(1));
      final representations = <String, Object?>{};
      for (final encoded in native.items.single.data) {
        for (final representation in (await encoded).representations) {
          final simple = representation as raw.DataRepresentationSimple;
          representations[simple.format] = simple.data;
        }
      }
      expect(representations, {'text/plain': markdown, 'text/html': html});
    },
  );

  for (final failure in ['unavailable', 'initialization', 'write']) {
    test('$failure falls back once to the complete Markdown', () async {
      final written = <String?>[];
      final native = _NativeWriter()..error = StateError('native write failed');
      await writeClipboardWithFallback(
        markdown: markdown,
        html: html,
        nativeClipboard: () {
          if (failure == 'initialization') throw StateError('missing plugin');
          return failure == 'unavailable' ? null : native;
        },
        plainText: (data) async => written.add(data.text),
      );
      expect(written, [markdown]);
    });
  }

  test('failure of the plain fallback remains visible to the host', () async {
    final error = PlatformException(code: 'clipboard_denied');
    await expectLater(
      writeClipboardWithFallback(
        markdown: markdown,
        html: html,
        nativeClipboard: () => null,
        plainText: (_) async => throw error,
      ),
      throwsA(same(error)),
    );
  });
}
