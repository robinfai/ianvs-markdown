import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

typedef IanvsMarkdownHtmlOrderedListBodyBuilder =
    Widget Function(BuildContext context, String markdown);

/// Parses Obsidian's simple line-delimited HTML ordered-list form.
///
/// Obsidian projects these items with normal `1.`/`2.` list markers while
/// hiding the HTML tags. The converted Markdown is only a rendered copy: the
/// parent Live Preview block continues to own the exact original HTML source.
class IanvsMarkdownHtmlOrderedListSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlOrderedListSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<ol(?:\s[^>\n]*)?>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^ {0,3}</ol\s*>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _item = RegExp(
    r'^ {0,3}<li(?:\s[^>\n]*)?>(.*?)</li\s*>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    var foundItem = false;
    for (var offset = 1; ; offset += 1) {
      final line = parser.peek(offset);
      if (line == null) return false;
      foundItem = foundItem || _item.hasMatch(line.content);
      if (_close.hasMatch(line.content)) return foundItem;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final items = <String>[];
    while (!parser.isDone && !_close.hasMatch(parser.current.content)) {
      final item = _item.firstMatch(parser.current.content);
      if (item != null) items.add((item.group(1) ?? '').trim());
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    return md.Element.empty('ianvs-html-ordered-list')
      ..attributes['data-markdown'] = items.indexed
          .map((entry) => '${entry.$1 + 1}. ${entry.$2}')
          .join('\n');
  }
}

class IanvsMarkdownHtmlOrderedListBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlOrderedListBuilder({required this.bodyBuilder});

  final IanvsMarkdownHtmlOrderedListBodyBuilder bodyBuilder;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => KeyedSubtree(
    key: const ValueKey('ianvs-markdown-html-ordered-list'),
    child: bodyBuilder(context, element.attributes['data-markdown'] ?? ''),
  );
}
