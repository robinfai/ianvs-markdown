import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'inline_code.dart';
import 'theme.dart';

/// Parses Obsidian-style highlights such as `==important==`.
class IanvsMarkdownHighlightSyntax extends md.InlineSyntax {
  IanvsMarkdownHighlightSyntax()
    : super(r'==([^=\n]+?)==', startCharacter: 0x3d);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(1)!;
    parser.addNode(md.Element('mark', parser.document.parseInline(content)));
    return true;
  }
}

class IanvsMarkdownHighlightBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHighlightBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final background = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff6b5b22)
        : const Color(0xffffe184);
    return Container(
      key: const ValueKey('ianvs-markdown-highlight'),
      child: Text.rich(
        TextSpan(
          style: (parentStyle ?? preferredStyle ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            backgroundColor: background,
          ),
          children: _highlightSpans(element.children, colors),
        ),
      ),
    );
  }
}

List<InlineSpan> _highlightSpans(
  List<md.Node>? nodes,
  IanvsMarkdownThemeData colors,
) {
  return <InlineSpan>[
    for (final node in nodes ?? const <md.Node>[])
      if (node is md.Text)
        TextSpan(text: node.text)
      else if (node is md.Element)
        TextSpan(
          style: _highlightElementStyle(node.tag, colors),
          children: _highlightSpans(node.children, colors),
        ),
  ];
}

TextStyle? _highlightElementStyle(String tag, IanvsMarkdownThemeData colors) {
  return switch (tag) {
    'strong' => const TextStyle(fontWeight: FontWeight.w700),
    'em' => const TextStyle(fontStyle: FontStyle.italic),
    'del' => const TextStyle(decoration: TextDecoration.lineThrough),
    'code' || 'ianvs-inline-code' => ianvsMarkdownInlineCodeStyle(colors),
    'a' => TextStyle(
      color: colors.accentDark,
      decoration: TextDecoration.underline,
    ),
    _ => null,
  };
}
