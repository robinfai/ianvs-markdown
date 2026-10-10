import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default core writer sends complete Markdown through Flutter only',
    () async {
      const source = '---\r\ntitle: 中文\r\n---\r\n# **Exact** source\n';
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await writeIanvsMarkdownClipboard(
        const IanvsMarkdownClipboardData(
          markdown: source,
          html: '<h1>HTML remains available to an injected writer</h1>',
        ),
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'Clipboard.setData');
      expect(calls.single.arguments, {'text': source});
    },
  );

  test('default core writer reports platform write errors', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async {
          throw PlatformException(code: 'clipboard_denied');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await expectLater(
      writeIanvsMarkdownClipboard(
        const IanvsMarkdownClipboardData(markdown: '', html: ''),
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test('partial cross-block clipboard keeps Markdown and rich structure', () {
    const source = '''
# Render and edit together

Click any rendered block to edit it **without leaving live preview**. Use the
toolbar to switch between live preview, full source, and reading modes.

> The Markdown string remains the only source of truth. The host application
> decides how and when to save it.
''';
    const selected =
        'Render and edit together'
        'Click any rendered block to edit it without leaving live preview. Use the\n'
        'toolbar to switch between live preview, full source, and reading modes.'
        'The Markdown string remains the only source of truth. The host application\n'
        'decides how and when to save it.';

    final data = ianvsMarkdownSelectionClipboardData(source, selected);

    expect(data.markdown, startsWith('# Render and edit together'));
    expect(data.markdown, contains('**without leaving live preview**'));
    expect(
      data.markdown,
      contains('> The Markdown string remains the only source of truth.'),
    );
    expect(data.markdown, contains('> decides how and when to save it.'));
    expect(data.html, contains('<h1>Render and edit together</h1>'));
    expect(
      data.html,
      contains('<strong>without leaving live preview</strong>'),
    );
    expect(data.html, contains('<blockquote>'));
  });

  test('partial clipboard keeps meaningful spaces between inline styles', () {
    final data = ianvsMarkdownSelectionClipboardData(
      '**bold** *italic*',
      'bold italic',
    );

    expect(data.markdown, '**bold** *italic*');
    expect(data.html, '<p><strong>bold</strong> <em>italic</em></p>');
  });

  test('partial task-list clipboard keeps inline formatting on one line', () {
    const source = '''
## Everyday Markdown

- [x] GitHub-flavored Markdown
- [ ] Click this task block and edit it
- [ ] Try **bold**, *italic*, `inline code`, and [a link](docs/guide.md)
''';
    const selected =
        'Everyday Markdown'
        'GitHub-flavored Markdown'
        'Click this task block and edit it'
        'Try bold, italic, inline code, and a link';

    final data = ianvsMarkdownSelectionClipboardData(source, selected);
    expect(data.markdown, '''
## Everyday Markdown

- [x] GitHub-flavored Markdown
- [ ] Click this task block and edit it
- [ ] Try **bold**, *italic*, `inline code`, and [a link](docs/guide.md)''');
    expect(data.html, contains('<strong>bold</strong>'));
    expect(data.html, contains('<em>italic</em>'));
    expect(data.html, contains('<code>inline code</code>'));
    expect(data.html, contains('<a href="docs/guide.md">a link</a>'));
  });
}
