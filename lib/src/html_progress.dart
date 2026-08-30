import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

class IanvsMarkdownHtmlProgressSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlProgressSyntax();
  static final RegExp _line = RegExp(
    r'^ {0,3}<progress\s+([^>\n]*)>.*</progress\s*>[ \t]*$',
    caseSensitive: false,
  );
  @override
  RegExp get pattern => _line;
  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    final attrs = match.group(1) ?? '';
    final value =
        double.tryParse(
          RegExp(
                r'''\bvalue\s*=\s*["']?([0-9.]+)''',
                caseSensitive: false,
              ).firstMatch(attrs)?.group(1) ??
              '',
        ) ??
        0;
    final max =
        double.tryParse(
          RegExp(
                r'''\bmax\s*=\s*["']?([0-9.]+)''',
                caseSensitive: false,
              ).firstMatch(attrs)?.group(1) ??
              '',
        ) ??
        1;
    return md.Element.empty('ianvs-html-progress')
      ..attributes.addAll({'value': '$value', 'max': '$max'});
  }
}

class IanvsMarkdownHtmlProgressBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlProgressBuilder({this.theme});
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
    final max = double.tryParse(element.attributes['max'] ?? '') ?? 1;
    final value = double.tryParse(element.attributes['value'] ?? '') ?? 0;
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    return SizedBox(
      key: const ValueKey('ianvs-markdown-html-progress'),
      width: 112,
      height: 5,
      child: LinearProgressIndicator(
        value: max <= 0 ? 0 : (value / max).clamp(0, 1),
        backgroundColor: colors.borderSoft,
        color: colors.accent,
      ),
    );
  }
}
