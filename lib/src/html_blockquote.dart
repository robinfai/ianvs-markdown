import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

typedef IanvsMarkdownHtmlBlockquoteBodyBuilder =
    Widget Function(BuildContext context, String source);

/// Parses the line-delimited HTML blockquote form projected by Obsidian.
///
/// HTML blockquotes intentionally do not reuse the Markdown `>` renderer:
/// Obsidian displays their content with an inset, but without a Markdown quote
/// rail and without exposing the surrounding HTML tags.
class IanvsMarkdownHtmlBlockquoteSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlBlockquoteSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<blockquote(?:\s[^>\n]*)?>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^ {0,3}</blockquote\s*>[ \t]*$',
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
    return md.Element.empty('ianvs-html-blockquote')
      ..attributes['data-body'] = bodyLines.join('\n');
  }
}

class IanvsMarkdownHtmlBlockquoteBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlBlockquoteBuilder({required this.bodyBuilder, this.theme});

  final IanvsMarkdownHtmlBlockquoteBodyBuilder bodyBuilder;
  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return IanvsMarkdownHtmlBlockquote(
      body: element.attributes['data-body'] ?? '',
      bodyBuilder: bodyBuilder,
      theme: theme,
    );
  }
}

/// An inert, rail-free HTML blockquote projection matching Obsidian.
class IanvsMarkdownHtmlBlockquote extends StatelessWidget {
  const IanvsMarkdownHtmlBlockquote({
    super.key,
    required this.body,
    required this.bodyBuilder,
    this.theme,
  });

  final String body;
  final IanvsMarkdownHtmlBlockquoteBodyBuilder bodyBuilder;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    return Material(
      key: const ValueKey('ianvs-markdown-html-blockquote'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.only(left: 28, top: 3, bottom: 3),
          child: AbsorbPointer(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: colors.textPrimary),
              child: bodyBuilder(context, body),
            ),
          ),
        ),
      ),
    );
  }
}
