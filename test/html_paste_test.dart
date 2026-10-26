import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/src/editor/html_paste.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:html/parser.dart' as html;

void main() {
  test('inline code preserves empty and whitespace-only content', () {
    for (final value in ['', ' ', '  ', ' a ', 'a']) {
      final result = markdownFromClipboardHtml(
        '<p>before<code>$value</code>after</p>',
      )!;
      final rendered = html.parseFragment(md.markdownToHtml(result));
      if (value.isEmpty) {
        expect(rendered.querySelector('code'), isNull);
      } else {
        expect(rendered.querySelector('code')!.text, value);
      }
      expect(rendered.text!.trim(), 'before${value}after');
    }
  });
  test('link boundary whitespace remains between neighboring words', () {
    final result = markdownFromClipboardHtml(
      '<p>before<a href="https://example.test"> middle </a>after</p>',
    )!;
    final rendered = html.parseFragment(md.markdownToHtml(result));
    expect(rendered.text!.trim(), 'before middle after');
    expect(rendered.querySelector('a')!.text, 'middle');
  });

  test('inline code in tables cannot create extra columns', () {
    final result = markdownFromClipboardHtml(
      '<table><tr><th>A</th><th>B</th></tr><tr><td><code>a|b</code></td><td>x</td></tr></table>',
    )!;
    final rendered = html.parseFragment(
      md.markdownToHtml(result, extensionSet: md.ExtensionSet.gitHubFlavored),
    );
    expect(rendered.querySelectorAll('td').length, 2);
    expect(rendered.querySelector('code')!.text, 'a|b');
  });
  test('oversized and deeply nested fragments fall back', () {
    expect(markdownFromClipboardHtml('<p>${'x' * (1024 * 1024)}</p>'), isNull);
    expect(
      markdownFromClipboardHtml('${'<div>' * 110}text${'</div>' * 110}'),
      isNull,
    );
  });
  test('inline code chooses delimiters that preserve literal backticks', () {
    final result = markdownFromClipboardHtml('<p><code>a`b</code> tail</p>')!;
    final rendered = html.parseFragment(md.markdownToHtml(result));
    expect(rendered.querySelector('code')!.text, 'a`b');
    expect(rendered.text, contains(' tail'));
  });

  test('headings paragraphs emphasis and safe links become Markdown', () {
    final result = markdownFromClipboardHtml(
      '<h2>Title</h2><p>A <strong>bold</strong> and <em>italic</em> <a href="https://example.test/a?q=1&amp;b=2">link</a>.</p>',
    )!;
    final rendered = md.markdownToHtml(result);
    expect(rendered, contains('<h2>Title</h2>'));
    expect(rendered, contains('<strong>bold</strong>'));
    expect(rendered, contains('<em>italic</em>'));
    expect(
      html.parseFragment(rendered).querySelector('a')!.attributes['href'],
      'https://example.test/a?q=1&b=2',
    );
  });
  test('nested lists preserve hierarchy and ordered start', () {
    final result = markdownFromClipboardHtml(
      '<ol start="3"><li>First<ul><li>Nested</li></ul></li><li>Second</li></ol>',
    )!;
    final rendered = md.markdownToHtml(result);
    expect(rendered, contains('<ol start="3">'));
    expect(rendered, contains('<ul>'));
    expect(rendered, contains('Nested'));
    expect(rendered, contains('Second'));
  });
  test('preformatted code preserves whitespace and chooses safe fences', () {
    final result = markdownFromClipboardHtml(
      '<pre><code class="language-dart">  a\n```\n\tb &lt; c</code></pre>',
    )!;
    expect(result, '````dart\n  a\n```\n\tb < c\n````');
    expect(md.markdownToHtml(result), contains('  a\n```\n\tb &lt; c'));
  });
  test('rectangular tables preserve formatting, blanks and line breaks', () {
    final result = markdownFromClipboardHtml(
      '<table><tr><th>A</th><th>B</th></tr><tr><td><b>x</b>|y<br>z</td><td></td></tr></table>',
    )!;
    expect(result, '| A | B |\n| --- | --- |\n| **x**\\|y<br>z |  |');
    final rendered = md.markdownToHtml(
      result,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    expect(rendered, contains('<strong>x</strong>|y<br>z'));
  });
  test('active content is discarded and unsafe links become text', () {
    final result = markdownFromClipboardHtml(
      '<script>evil()</script><style>secret</style><p><a href="javascript:evil()">safe</a> &lt;img src=x&gt;</p>',
    )!;
    expect(result, 'safe &lt;img src=x&gt;');
    expect(result, isNot(contains('evil')));
  });
  test('unsupported images and spanning tables request plain fallback', () {
    for (final html in [
      '<p>Picture<img src="https://example.test/x.png"></p>',
      '<table><tr><td colspan="2">merged</td></tr></table>',
      '<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>',
      'just text',
    ]) {
      expect(markdownFromClipboardHtml(html), isNull);
    }
  });
}
