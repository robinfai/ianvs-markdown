import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

typedef IanvsMarkdownHtmlUnorderedListBodyBuilder =
    Widget Function(BuildContext context, String markdown);

/// Parses Obsidian's simple line-delimited HTML unordered-list form.
///
/// In the sampled views the surrounding `ul`/`li` tags are hidden and items
/// use the ordinary Markdown bullet projection. The original HTML is never
/// rewritten: this conversion exists only for the passive rendered copy, so a
/// Live Preview click can enter the exact source block.
class IanvsMarkdownHtmlUnorderedListSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlUnorderedListSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<ul(?:\s[^>\n]*)?>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^ {0,3}</ul\s*>[ \t]*$',
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
    return md.Element.empty('ianvs-html-unordered-list')
      ..attributes['data-markdown'] = items.map((item) => '- $item').join('\n');
  }
}

class IanvsMarkdownHtmlUnorderedListBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlUnorderedListBuilder({required this.bodyBuilder});

  final IanvsMarkdownHtmlUnorderedListBodyBuilder bodyBuilder;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => KeyedSubtree(
    key: const ValueKey('ianvs-markdown-html-unordered-list'),
    child: bodyBuilder(context, element.attributes['data-markdown'] ?? ''),
  );
}
