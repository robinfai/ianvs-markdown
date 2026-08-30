import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Parses Obsidian's standalone HTML horizontal-rule form.
class IanvsMarkdownHtmlHorizontalRuleSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlHorizontalRuleSyntax();

  static final RegExp _pattern = RegExp(
    r'^ {0,3}<hr(?:\s[^>\n]*)?/?>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _pattern;

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    return md.Element.empty('ianvs-html-hr');
  }
}

/// Inert horizontal-rule projection for Obsidian Live Preview.
class IanvsMarkdownHtmlHorizontalRuleBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlHorizontalRuleBuilder({this.decoration});

  final Decoration? decoration;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Material(
      key: const ValueKey('ianvs-markdown-html-hr'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        child: Container(height: 2, decoration: decoration),
      ),
    );
  }
}
