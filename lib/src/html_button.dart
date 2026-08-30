import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

class IanvsMarkdownHtmlButtonSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlButtonSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<button(?:\s[^>\n]*)?>(.*?)</button\s*>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    return md.Element.empty('ianvs-html-button')
      ..attributes['data-label'] = match.group(1) ?? '';
  }
}

class IanvsMarkdownHtmlButtonBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlButtonBuilder({this.theme});
  final IanvsMarkdownThemeData? theme;
  @override
  bool isBlockElement() => true;
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => IanvsMarkdownHtmlButton(
    label: element.attributes['data-label'] ?? '',
    theme: theme,
  );
}

/// View-local button projection; HTML has no event handler in this safe subset.
class IanvsMarkdownHtmlButton extends StatelessWidget {
  const IanvsMarkdownHtmlButton({super.key, required this.label, this.theme});
  final String label;
  final IanvsMarkdownThemeData? theme;
  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    return SizedBox(
      key: const ValueKey('ianvs-markdown-html-button'),
      height: 21,
      child: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          backgroundColor: colors.surfaceMuted,
          minimumSize: const Size(0, 21),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          side: BorderSide(color: colors.taskCheckboxBorderColor),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text(label),
      ),
    );
  }
}
