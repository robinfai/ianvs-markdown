import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
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
