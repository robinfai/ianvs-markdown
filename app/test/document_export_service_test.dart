import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/attachment_resolver.dart';
import 'package:linefold/src/services/document_export_service.dart';
import 'package:linefold/src/services/math_export_renderer.dart';

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
    'math export embeds inline and display results with source and offline assets',
    () async {
      final modes = <bool>[];
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final result =
          await DocumentExportService(
            renderMath: (source, display) async {
              modes.add(display);
              return MathExportImage(png, 20, 12);
            },
          ).build(
            snapshot(
              r'Inline $x^2$.'
              '\n\n'
              r'$$\frac{a}{b}$$',
            ),
            isCurrent: () => true,
          );
      expect(modes, [false, true]);
      expect('data:image/png;base64,'.allMatches(result.content).length, 2);
      expect(result.content, contains('alt="x^2"'));
      expect(result.content, contains('Formula source'));
      expect(result.content, isNot(contains('<script')));
      expect(
        result.content,
        isNot(contains('<span class="math-rendered"><details>')),
      );
    },
  );

  test(
    'math failures and shared resource limits preserve readable source',
    () async {
      for (final service in [
        DocumentExportService(
          renderMath: (_, _) async => throw StateError('failed'),
        ),
        DocumentExportService(
          maximumImages: 0,
          renderMath: (_, _) async => throw StateError('must not render'),
        ),
        DocumentExportService(
          maximumImageBytes: 0,
          renderMath: (_, _) async =>
              MathExportImage(base64Decode('AAAA'), 20, 12),
        ),
      ]) {
        final result = await service.build(
          snapshot(r'$x^2$'),
          isCurrent: () => true,
        );
        expect(result.content, contains('<code class="math-source">'));
        expect(result.content, isNot(contains('data:image/png;base64,')));
        expect(
          result.notices.any((notice) => notice.startsWith('Math:')),
          isTrue,
        );
      }
    },
  );

  test('math completion cannot publish an obsolete export', () async {
    var current = true;
    final service = DocumentExportService(
      renderMath: (_, _) async {
        current = false;
        return MathExportImage(base64Decode('AAAA'), 20, 12);
      },
    );
    await expectLater(
      service.build(snapshot(r'$x$'), isCurrent: () => current),
      throwsA(isA<DocumentExportFailure>()),
    );
  });

  test('Mermaid export embeds generated SVG and preserves source', () async {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><text x="0" y="20">Diagram</text></svg>';
    final output =
        await DocumentExportService(
          renderMermaid: (source) async {
            expect(source, contains('A-->B'));
            return svg;
          },
        ).build(
          snapshot('```mermaid\nflowchart LR; A-->B\n```'),
          isCurrent: () => true,
        );
    expect(
      output.content,
      contains('data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}'),
    );
    expect(output.content, contains('Diagram source'));
    expect(output.content, contains('A--&gt;B'));
  });
  test(
    'Mermaid render failure and external resources retain readable source',
    () async {
      for (final svg in [
        null,
        '<svg><image href="https://example.test/image.png"/></svg>',
        '<svg><use href="x#external"/></svg>',
      ]) {
        final output =
            await DocumentExportService(
              renderMermaid: (_) async {
                if (svg == null) throw StateError('render failed');
                return svg;
              },
            ).build(
              snapshot('```mermaid\nflowchart LR; A-->B\n```'),
              isCurrent: () => true,
            );
        expect(output.content, contains('mermaid-source'));
        expect(output.content, isNot(contains('data:image/svg+xml')));
        expect(
          output.notices.any((notice) => notice.contains('Source retained')),
          isTrue,
        );
      }
    },
  );
  test(
    'Mermaid budgets prevent embedding and cancelled render never exports',
    () async {
      final output = await DocumentExportService(
        maximumImages: 0,
        renderMermaid: (_) async => throw StateError('must not render'),
      ).build(snapshot('```mermaid\na-->b\n```'), isCurrent: () => true);
      expect(output.notices.any((n) => n.contains('count limit')), isTrue);
      var current = true;
      await expectLater(
        DocumentExportService(
          renderMermaid: (_) async {
            current = false;
            return '<svg/>';
          },
        ).build(snapshot('```mermaid\na-->b\n```'), isCurrent: () => current),
        throwsA(isA<DocumentExportFailure>()),
      );
    },
  );

  test(
    'Markdown copy preserves raw Unicode, CRLF, BOM and attachments without I/O',
    () {
      const source =
          '\ufeff---\r\ntitle: 中文😀\r\n---\r\n'
          '# 原稿\r\n![图](../attachments/image.png)\r\n'
          '<script>alert(1)</script>\r\n\r\n';
      final assets = FakeAttachmentSource();
      final output = DocumentExportService(
        attachmentSource: assets,
      ).buildMarkdown(snapshot(source), isCurrent: () => true);
      expect(output.content, source);
      expect(utf8.encode(output.content), utf8.encode(source));
      expect(output.notices, contains(documentExportMarkdownNotice));
      expect(assets.reads, isEmpty);
    },
  );

  test(
    'Markdown copy allows empty and unparsed content, but enforces byte budget and scope',
    () {
      const service = DocumentExportService(maximumOutputBytes: 6);
      expect(
        service.buildMarkdown(snapshot(''), isCurrent: () => true).content,
        '',
      );
      expect(
        service.buildMarkdown(snapshot('中文'), isCurrent: () => true).content,
        '中文',
      );
      expect(
        () => service.buildMarkdown(snapshot('中文a'), isCurrent: () => true),
        throwsA(isA<DocumentExportFailure>()),
      );
      expect(
        () => service.buildMarkdown(snapshot('ok'), isCurrent: () => false),
        throwsA(isA<DocumentExportFailure>()),
      );
      expect(
        () => service.buildMarkdown(snapshot('\ud800'), isCurrent: () => true),
        throwsA(isA<DocumentExportFailure>()),
      );
      final longLine = 'a' * 5000;
      expect(
        const DocumentExportService()
            .buildMarkdown(snapshot(longLine), isCurrent: () => true)
            .content,
        longLine,
      );
    },
  );

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
      expect(output.content, startsWith('<!doctype html>'));
      expect(output.content, contains('<meta charset="utf-8">'));
      expect(output.content, contains('<h1>文档标题</h1>'));
      expect(output.content, contains('<strong>加粗</strong>'));
      expect(output.content, contains('<em>斜体</em>'));
      expect(output.content, contains('<thead>'));
      expect(output.content, contains('<td class="align-right">123</td>'));
      expect(output.content, contains('☑'));
      expect(output.content, contains('☐'));
      expect(output.content, contains('title: 中文😀'));
      expect(output.content, contains('graph LR; A--&gt;B'));
      expect(output.content, contains('math-source'));
      expect(output.content, contains(documentExportFidelityNotice));
      expect(output.content, contains('table-layout: fixed'));
      expect(output.content, contains('table-header-group'));
      expect(output.content, contains('white-space: pre-wrap'));
      expect(sourceProvider.reads, isEmpty);
      expect(source, contains('**加粗**'));
    },
  );

  test('PDF limitation notice is visible and incrementally budgeted', () async {
    final value = snapshot('中文 source');
    final html = await const DocumentExportService().build(
      value,
      isCurrent: () => true,
    );
    final pdf = await const DocumentExportService().build(
      value,
      isCurrent: () => true,
      forPdf: true,
    );
    expect(html.notices, isNot(contains(documentExportPdfNotice)));
    expect(html.content, isNot(contains(documentExportPdfNotice)));
    expect(pdf.notices, contains(documentExportPdfNotice));
    expect(
      pdf.content,
      contains('<li>${htmlEscape.convert(documentExportPdfNotice)}</li>'),
    );
    final exactBytes = utf8.encode(pdf.content).length;
    expect(exactBytes, greaterThan(utf8.encode(html.content).length));
    expect(
      (await DocumentExportService(
        maximumOutputBytes: exactBytes,
      ).build(value, isCurrent: () => true, forPdf: true)).content,
      pdf.content,
    );
    await expectLater(
      DocumentExportService(
        maximumOutputBytes: exactBytes - 1,
      ).build(value, isCurrent: () => true, forPdf: true),
      throwsA(isA<DocumentExportFailure>()),
    );
    final emptyPdf = await const DocumentExportService().build(
      snapshot(''),
      isCurrent: () => true,
      forPdf: true,
    );
    final provider = FakeAttachmentSource();
    await expectLater(
      DocumentExportService(
        attachmentSource: provider,
        maximumOutputBytes: utf8.encode(emptyPdf.content).length - 1,
      ).build(
        snapshot('![not read](assets/image.png)'),
        isCurrent: () => true,
        forPdf: true,
      ),
      throwsA(isA<DocumentExportFailure>()),
    );
    expect(provider.listCalls, 0);
    expect(provider.reads, isEmpty);
  });

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
      ).build(value, isCurrent: () => true)).content;
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
        RegExp('<img src="data:image/png;base64,').allMatches(output.content),
        hasLength(3),
      );
      expect(output.content, isNot(contains('/vault/')));
      expect(output.content, isNot(contains('src="assets/')));
      final data = RegExp(
        r'data:image/png;base64,([^\"]+)',
      ).firstMatch(output.content)![1]!;
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
        expect(output.content, contains('image unavailable'));
        expect(output.notices.length, greaterThan(1));
        expect(output.content, isNot(contains('<img')));
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
      expect(output.content, isNot(contains('<img')));
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
        maximumOutputBytes: utf8.encode(baseline.content).length + 100,
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
      final fixedBytes = utf8.encode(empty.content).length;
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
      final exactBytes = utf8.encode(rendered.content).length;
      expect(
        (await DocumentExportService(
          maximumOutputBytes: exactBytes,
        ).build(unicode, isCurrent: () => true)).content,
        rendered.content,
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
        maximumOutputBytes: utf8.encode(empty.content).length + 20,
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
    'native final approval checks active scope and cancelled operation identity',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const platform = AppleDocumentExportPlatform();
      const codec = StandardMethodCodec();
      final calls = <MethodCall>[];
      final nativeResult = Completer<bool>();
      final captured = snapshot('# dirty');
      var current = true;
      messenger.setMockMethodCallHandler(AppleDocumentExportPlatform.channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'cancel' ? true : await nativeResult.future;
      });
      addTearDown(() {
        if (!nativeResult.isCompleted) nativeResult.complete(false);
        messenger.setMockMethodCallHandler(
          AppleDocumentExportPlatform.channel,
          null,
        );
      });
      final pending = platform.output(
        action: DocumentExportAction.markdown,
        document: const ExportedDocument('# dirty', []),
        snapshot: captured,
        isCurrent: () => current,
      );
      await Future<void>.delayed(Duration.zero);
      final id = (calls.single.arguments as Map)['operationId'] as String;
      expect(base64Url.decode(id.split(':').first), hasLength(16));
      Future<bool> approve(Object id) async {
        final bytes = await messenger.handlePlatformMessage(
          AppleDocumentExportPlatform.channel.name,
          codec.encodeMethodCall(
            MethodCall('approveCommit', {'operationId': id}),
          ),
          null,
        );
        return codec.decodeEnvelope(bytes!) == true;
      }

      expect(await approve(id), isTrue);
      expect(await approve('unknown'), isFalse);
      current = false;
      expect(await approve(id), isFalse);
      await platform.cancel(captured);
      expect(calls.last.method, 'cancel');
      expect((calls.last.arguments as Map)['operationId'], id);
      nativeResult.complete(false);
      expect(await pending, isFalse);
      expect(
        await approve(id),
        isFalse,
        reason: 'Late approval after completion must fail closed.',
      );
    },
  );

  test(
    'bundle platform channel carries binary bytes without text encoding',
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
      final bytes = Uint8List.fromList([0x50, 0x4b, 3, 4, 0, 255, 128]);
      await const AppleDocumentExportPlatform().output(
        action: DocumentExportAction.bundle,
        document: ExportedDocument.binary(bytes, const []),
        snapshot: snapshot('source'),
        isCurrent: () => true,
      );
      expect(received!.method, 'bundle');
      expect((received!.arguments as Map)['bytes'], bytes);
      expect((received!.arguments as Map).containsKey('content'), isFalse);
    },
  );

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
          action: DocumentExportAction.html,
          document: value,
          snapshot: snapshot('captured'),
          isCurrent: () => true,
        ),
        isFalse,
      );
      expect(received!.method, 'html');
      expect((received!.arguments as Map)['content'], value.content);
      expect((received!.arguments as Map).containsKey('source'), isFalse);
    },
  );

  test('emit variable-height and multiple-table production fixture', () async {
    final source = StringBuffer('# Mixed table pagination\n\n');
    for (final group in ['A', 'B']) {
      source.writeln(
        List.filled(8, 'Paragraph before table $group.').join('\n\n'),
      );
      source.writeln(
        '\n| ${group}_HEAD_ONE | ${group}_HEAD_TWO |\n| --- | --- |',
      );
      for (var i = 0; i < 40; i++) {
        source.writeln(
          '| ${group}_ROW_${i}_START | ${List.filled(2 + (i % 6) * 8, '变化高度文字').join(' ')} ${group}_ROW_${i}_END |',
        );
      }
      source.writeln('\nAfter table $group.\n');
      source.writeln(
        '| Short header | Value |\n| --- | --- |\n| SHORT_${group}_START | SHORT_${group}_END |\n',
      );
    }
    final document = await const DocumentExportService().build(
      snapshot(source.toString()),
      isCurrent: () => true,
      forPdf: true,
    );
    final directory = Directory('build/export-qa')..createSync(recursive: true);
    await File('${directory.path}/tables.html').writeAsString(document.content);
  });

  test(
    'emit complete synthetic HTML and Markdown fixtures from the actual generator',
    () async {
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
      // Preserve the original 150 x 4 CJK/table/long-code corpus verbatim.
      // Append a recognizable offline image, not the unrelated 1-pixel mock.
      source.writeln(
        '\n\nIMAGE_START\n\n![Synthetic four-color attachment](assets/acceptance-pattern.png)\n\nIMAGE_END',
      );
      final pattern = await _acceptancePatternPng();
      final provider = FakeAttachmentSource()
        ..files['assets/acceptance-pattern.png'] = pattern;
      // Keep the same production input and image budgets and AttachmentSource
      // authorization path. No external file, download or custom HTML is used.
      final output = await DocumentExportService(
        attachmentSource: provider,
      ).build(snapshot(source.toString()), isCurrent: () => true, forPdf: true);
      expect(output.notices, contains(documentExportPdfNotice));
      expect(
        output.content,
        contains(htmlEscape.convert(documentExportPdfNotice)),
      );
      expect(provider.roots, everyElement('/vault'));
      expect(
        provider.reads.where((path) => path == 'assets/acceptance-pattern.png'),
        hasLength(1),
      );
      final imageMatches = RegExp(
        r'<img src="data:image/png;base64,([^"]+)"',
      ).allMatches(output.content).toList();
      expect(imageMatches, hasLength(1));
      final embeddedPng = base64Decode(imageMatches.single[1]!);
      final codec = await ui.instantiateImageCodec(embeddedPng);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 192);
      expect(frame.image.height, 128);
      frame.image.dispose();
      codec.dispose();
      for (var row = 0; row < 150; row++) {
        for (final column in ['A', 'B', 'C', 'D']) {
          expect(
            RegExp('CELL_${row}_$column').allMatches(output.content),
            hasLength(1),
          );
        }
      }
      expect(output.content, contains('中文文档 CJK START 😀'));
      expect(output.content, contains('文档结束 CJK END'));
      expect(
        output.content,
        contains('${'长代码 ABCDEFGHIJKLMNOPQRSTUVWXYZ ' * 35}\nCODE_END'),
      );
      final directory = Directory('build/export-qa')
        ..createSync(recursive: true);
      File('${directory.path}/document.html').writeAsStringSync(output.content);
      File(
        '${directory.path}/document.md',
      ).writeAsStringSync(source.toString());
      File(
        '${directory.path}/attachment-pattern.png',
      ).writeAsBytesSync(pattern);
      File('${directory.path}/fixture.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'generator': 'production DocumentExportService.build(forPdf: true)',
          'rows': 150,
          'columns': 4,
          'cellMarkers': 600,
          'originalCjkAndLongCodeUnchanged': true,
          'attachment': {
            'path': 'assets/acceptance-pattern.png',
            'width': 192,
            'height': 128,
            'source':
                'offline dart:ui PictureRecorder through AttachmentSource',
            'appearance':
                'black border; red, green, blue, yellow quadrants; white center circle',
          },
        }),
      );
      expect(output.content, contains('CELL_149_D'));
    },
  );
}

Future<Uint8List> _acceptancePatternPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 192, 128),
    ui.Paint()..color = const ui.Color(0xff111111),
  );
  for (final (rect, color) in [
    (const ui.Rect.fromLTWH(8, 8, 88, 56), const ui.Color(0xffe53935)),
    (const ui.Rect.fromLTWH(96, 8, 88, 56), const ui.Color(0xff43a047)),
    (const ui.Rect.fromLTWH(8, 64, 88, 56), const ui.Color(0xff1e88e5)),
    (const ui.Rect.fromLTWH(96, 64, 88, 56), const ui.Color(0xfffdd835)),
  ]) {
    canvas.drawRect(rect, ui.Paint()..color = color);
  }
  canvas.drawCircle(
    const ui.Offset(96, 64),
    16,
    ui.Paint()..color = const ui.Color(0xffffffff),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(192, 128);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('Could not encode synthetic attachment');
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
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
