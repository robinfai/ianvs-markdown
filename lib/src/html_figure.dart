import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

typedef IanvsMarkdownHtmlFigureBodyBuilder =
    Widget Function(BuildContext context, String source);

/// Parses Obsidian's line-delimited HTML figure block.
///
/// The figure and figcaption tags are metadata-only in the sampled Obsidian
/// views: their content remains ordinary physical text lines inside one inset
/// block. The projection deliberately has no local tap handler so Live Preview
/// can enter the exact complete HTML source block when clicked.
class IanvsMarkdownHtmlFigureSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlFigureSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<figure(?:\s[^>\n]*)?>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^ {0,3}</figure\s*>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _figcaptionTag = RegExp(
    r'</?figcaption(?:\s[^>\n]*)?>',
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
      // Obsidian hides figcaption tags but retains the line's text without
      // applying a caption-specific style.
      bodyLines.add(parser.current.content.replaceAll(_figcaptionTag, ''));
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    while (bodyLines.isNotEmpty && bodyLines.first.trim().isEmpty) {
      bodyLines.removeAt(0);
    }
    while (bodyLines.isNotEmpty && bodyLines.last.trim().isEmpty) {
      bodyLines.removeLast();
    }
    return md.Element.empty('ianvs-html-figure')
      ..attributes['data-body'] = bodyLines.join('\n');
  }
}

class IanvsMarkdownHtmlFigureBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlFigureBuilder({required this.bodyBuilder});

  final IanvsMarkdownHtmlFigureBodyBuilder bodyBuilder;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Padding(
      key: const ValueKey('ianvs-markdown-html-figure'),
      padding: const EdgeInsets.only(left: 25),
      child: bodyBuilder(context, element.attributes['data-body'] ?? ''),
    );
  }
}
