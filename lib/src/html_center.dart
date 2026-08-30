import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

typedef IanvsMarkdownHtmlCenterBodyBuilder =
    Widget Function(BuildContext context, String source);

/// Parses the line-delimited HTML `center` form projected by Obsidian.
///
/// Obsidian hides both tags, folds the contained physical source lines into
/// normal inline flow, then centers that flow. This widget keeps no gesture of
/// its own so a regular Live Preview click still selects the exact HTML block.
class IanvsMarkdownHtmlCenterSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlCenterSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<center(?:\s[^>\n]*)?>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^ {0,3}</center\s*>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    for (var offset = 1; ; offset += 1) {
      final line = parser.peek(offset);
      if (line == null) return false;
      if (_close.hasMatch(line.content)) return true;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final bodyLines = <String>[];
    while (!parser.isDone && !_close.hasMatch(parser.current.content)) {
      bodyLines.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    while (bodyLines.isNotEmpty && bodyLines.first.trim().isEmpty) {
      bodyLines.removeAt(0);
    }
    while (bodyLines.isNotEmpty && bodyLines.last.trim().isEmpty) {
      bodyLines.removeLast();
    }
    return md.Element.empty('ianvs-html-center')
      // Obsidian projects physical lines in a center block as inline flow.
      // This is presentation-only; Live Preview retains the original source.
      ..attributes['data-body'] = bodyLines.join(' ');
  }
}

class IanvsMarkdownHtmlCenterBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlCenterBuilder({required this.bodyBuilder});

  final IanvsMarkdownHtmlCenterBodyBuilder bodyBuilder;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => Center(
    key: const ValueKey('ianvs-markdown-html-center'),
    child: bodyBuilder(context, element.attributes['data-body'] ?? ''),
  );
}
