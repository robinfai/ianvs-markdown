import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/document_export_service.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/services/markdown_bundle_service.dart';
import 'attachment_test_support.dart';

DocumentExportSnapshot snapshot(String text) => DocumentExportSnapshot(
  documentId: 'bundle',
  title: '中文.md',
  source: text,
  root: '/vault',
  documentPath: '/vault/notes/a.md',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('default bundle uses dedicated native asset methods', () async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
      call,
    ) async {
      calls.add(call.method);
      return switch (call.method) {
        'listBundleAssets' => [
          {
            'relativePath': 'assets/report.pdf',
            'comparisonPath': 'assets/report.pdf',
            'size': 3,
            'modified': 1,
          },
        ],
        'normalizeAttachmentPaths' => (call.arguments as Map)['values'],
        'readBundleAssetBytes' => Uint8List.fromList([0, 255, 128]),
        _ => throw StateError('Unexpected ${call.method}'),
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AppleWorkspaceService.channel,
        null,
      ),
    );
    final result = await const MarkdownBundleService().build(
      snapshot('[PDF](../assets/report.pdf)'),
      isCurrent: () => true,
    );
    expect(
      ZipDecoder().decodeBytes(result.bytes).findFile('assets/1.pdf')!.content,
      [0, 255, 128],
    );
    expect(calls, [
      'listBundleAssets',
      'normalizeAttachmentPaths',
      'readBundleAssetBytes',
    ]);
  });
  test(
    'parsed destinations relocate; shared assets retain exact bytes',
    () async {
      final source = FakeAttachmentSource();
      const text =
          '# 标题\n![one](../assets/image.png "title")\n'
          '![[image.png|200]]\n![two][pic]\n\n[pic]: ../assets/image.png\n\n'
          '`![code](../assets/image.png)`\n';
      final result = await MarkdownBundleService(
        source: source,
      ).build(snapshot(text), isCurrent: () => true);
      final zip = ZipDecoder().decodeBytes(result.bytes, verify: true);
      final markdown = utf8.decode(zip.findFile('document.md')!.content);
      expect(markdown, contains('![one](./assets/1.png "title")'));
      expect(markdown, contains('![[./assets/1.png|200]]'));
      expect(markdown, contains('[pic]: ./assets/1.png'));
      expect(markdown, contains('`![code](../assets/image.png)`'));
      expect(zip.findFile('assets/1.png')!.content, tinyPng);
      expect(source.reads, ['assets/image.png']);
      expect(zip.length, 3);
      expect(result.notices, isEmpty);
      final fixture = File('build/export-qa/bundle.zip');
      await fixture.parent.create(recursive: true);
      await fixture.writeAsBytes(result.bytes);
    },
  );
  test('same-name assets and literal percent paths remain distinct', () async {
    final source = FakeAttachmentSource()
      ..files.addAll({
        'other/image.png': tinyPng,
        'assets/literal%20.png': tinyPng,
      });
    final result = await MarkdownBundleService(source: source).build(
      snapshot(
        '![a](../assets/image.png)\n![b](../other/image.png)\n![c](../assets/literal%2520.png)',
      ),
      isCurrent: () => true,
    );
    final zip = ZipDecoder().decodeBytes(result.bytes, verify: true);
    expect(
      zip.files.map((file) => file.name),
      containsAll(['assets/1.png', 'assets/2.png', 'assets/3.png']),
    );
    expect(source.reads, contains('assets/literal%20.png'));
  });
  test('missing and unsupported resources reported; remote never read', () async {
    final source = FakeAttachmentSource();
    final result = await MarkdownBundleService(source: source).build(
      snapshot(
        '![missing](../lost.png)\n[note](../note.md)\n![web](https://example.org/image.png)\n![escape](../../outside.png)',
      ),
      isCurrent: () => true,
    );
    final zip = ZipDecoder().decodeBytes(result.bytes, verify: true);
    final manifest = utf8.decode(zip.findFile('manifest.json')!.content);
    for (final status in [
      'external-not-copied',
      'local-resource-not-copied',
      'missing',
      'invalid',
    ]) {
      expect(manifest, contains(status));
    }
    expect(source.reads, isEmpty);
    expect(result.notices.length, 3);
  });
  test(
    'PDF SVG binary and extensionless attachments retain original bytes',
    () async {
      final source = FakeAttachmentSource()
        ..files.addAll({
          'assets/report.pdf': Uint8List.fromList([37, 80, 68, 70, 0, 255]),
          'assets/diagram.svg': Uint8List.fromList(
            utf8.encode('<svg>source</svg>'),
          ),
          'assets/archive.zip': Uint8List.fromList([80, 75, 3, 4, 255]),
          'assets/LICENSE': Uint8List.fromList(utf8.encode('license')),
        });
      final result = await MarkdownBundleService(source: source).build(
        snapshot(
          '[report](../assets/report.pdf#page=2)\n![[diagram.svg]]\n'
          '[archive](../assets/archive.zip)\n[license](../assets/LICENSE)',
        ),
        isCurrent: () => true,
      );
      final zip = ZipDecoder().decodeBytes(result.bytes, verify: true);
      final markdown = utf8.decode(zip.findFile('document.md')!.content);
      expect(markdown, contains('./assets/1.pdf#page=2'));
      expect(markdown, contains('![[./assets/2.svg]]'));
      expect(
        zip.findFile('assets/1.pdf')!.content,
        source.files['assets/report.pdf'],
      );
      expect(
        zip.findFile('assets/2.svg')!.content,
        source.files['assets/diagram.svg'],
      );
      expect(
        zip.findFile('assets/3.zip')!.content,
        source.files['assets/archive.zip'],
      );
      expect(zip.findFile('assets/4')!.content, source.files['assets/LICENSE']);
      expect(result.notices, isEmpty);
      final fixture = File('build/export-qa/bundle-assets.zip');
      await fixture.parent.create(recursive: true);
      await fixture.writeAsBytes(result.bytes);
    },
  );
  test('unusual file extensions cannot inject Markdown syntax', () async {
    final source = FakeAttachmentSource()..files['assets/file.x)y'] = tinyPng;
    final result = await MarkdownBundleService(
      source: source,
    ).build(snapshot('[file](../assets/file.x%29y)'), isCurrent: () => true);
    final zip = ZipDecoder().decodeBytes(result.bytes, verify: true);
    expect(
      utf8.decode(zip.findFile('document.md')!.content),
      '[file](./assets/1)',
    );
    expect(zip.findFile('assets/1')!.content, tinyPng);
  });
  test('cancelled pending index cannot start asset reads', () async {
    var current = true;
    final pending = Completer<void>();
    final source = FakeAttachmentSource()..beforeList = pending.future;
    final future = MarkdownBundleService(
      source: source,
    ).build(snapshot('![x](../assets/image.png)'), isCurrent: () => current);
    final assertion = expectLater(
      future,
      throwsA(isA<DocumentExportFailure>()),
    );
    current = false;
    pending.complete();
    await assertion;
    expect(source.reads, isEmpty);
  });
  test('native denied reads become an explicit manifest failure', () async {
    final source = FakeAttachmentSource()
      ..imageError = PlatformException(code: 'attachment_denied');
    final result = await MarkdownBundleService(
      source: source,
    ).build(snapshot('![x](../assets/image.png)'), isCurrent: () => true);
    final zip = ZipDecoder().decodeBytes(result.bytes, verify: true);
    expect(
      utf8.decode(zip.findFile('manifest.json')!.content),
      contains('denied'),
    );
    expect(zip.findFile('assets/1.png'), isNull);
  });
  test('cancelled pending read cannot publish a bundle', () async {
    var current = true;
    final pending = Completer<void>();
    final source = FakeAttachmentSource()..beforeRead = pending.future;
    final future = MarkdownBundleService(
      source: source,
    ).build(snapshot('![x](../assets/image.png)'), isCurrent: () => current);
    final assertion = expectLater(
      future,
      throwsA(isA<DocumentExportFailure>()),
    );
    while (source.reads.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    current = false;
    pending.complete();
    await assertion;
  });
  test('attachment count and archive size budgets reject export', () async {
    for (final service in [
      MarkdownBundleService(
        source: FakeAttachmentSource(),
        maximumAttachments: 0,
      ),
      MarkdownBundleService(source: FakeAttachmentSource(), maximumBytes: 100),
    ]) {
      await expectLater(
        service.build(
          snapshot('![x](../assets/image.png)'),
          isCurrent: () => true,
        ),
        throwsA(isA<DocumentExportFailure>()),
      );
    }
  });
}
