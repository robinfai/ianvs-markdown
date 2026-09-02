import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

typedef IanvsMarkdownHtmlFieldsetContentBuilder =
    Widget Function(BuildContext context, String source);

enum IanvsMarkdownHtmlFieldsetPresentation { reading, editing }

class IanvsMarkdownHtmlFieldsetSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlFieldsetSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<fieldset(?:\s[^>\n]*)?>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^ {0,3}</fieldset\s*>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _legend = RegExp(
    r'^ {0,3}<legend(?:\s[^>\n]*)?>(.*?)</legend\s*>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    var foundLegend = false;
    for (var offset = 1; ; offset += 1) {
      final line = parser.peek(offset);
      if (line == null) return false;
      foundLegend = foundLegend || _legend.hasMatch(line.content);
      if (_close.hasMatch(line.content)) return foundLegend;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final sourceLines = <String>[parser.current.content];
    parser.advance();
    String? legend;
    final bodyLines = <String>[];
    while (!parser.isDone && !_close.hasMatch(parser.current.content)) {
      final line = parser.current.content;
      sourceLines.add(line);
      final legendMatch = _legend.firstMatch(line);
      if (legend == null && legendMatch != null) {
        legend = legendMatch.group(1)?.trim() ?? '';
      } else {
        bodyLines.add(line);
      }
      parser.advance();
    }
    if (!parser.isDone) {
      sourceLines.add(parser.current.content);
      parser.advance();
    }
    while (bodyLines.isNotEmpty && bodyLines.first.trim().isEmpty) {
      bodyLines.removeAt(0);
    }
    while (bodyLines.isNotEmpty && bodyLines.last.trim().isEmpty) {
      bodyLines.removeLast();
    }
    return md.Element.empty('ianvs-html-fieldset')
      ..attributes.addAll({
        'data-source': sourceLines.join('\n'),
        'data-legend': legend ?? '',
        'data-body': bodyLines.join('\n'),
      });
  }
}

class IanvsMarkdownHtmlFieldsetBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlFieldsetBuilder({
    required this.presentation,
    required this.contentBuilder,
    this.onTap,
    this.theme,
  });

  final IanvsMarkdownHtmlFieldsetPresentation presentation;
  final IanvsMarkdownHtmlFieldsetContentBuilder contentBuilder;
  final VoidCallback? onTap;
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
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    if (presentation == IanvsMarkdownHtmlFieldsetPresentation.editing) {
      return SelectableText(
        element.attributes['data-source'] ?? '',
        key: const ValueKey('ianvs-markdown-html-fieldset-source'),
        onTap: onTap,
        style: TextStyle(
          color: colors.textPrimary,
          fontFamily: colors.monoFontFamily,
          fontFamilyFallback: colors.monoFontFamilyFallback,
          fontSize: 13,
          height: 1.55,
        ),
      );
    }
    return IanvsMarkdownHtmlFieldset(
      legend: element.attributes['data-legend'] ?? '',
      body: element.attributes['data-body'] ?? '',
      contentBuilder: contentBuilder,
      theme: colors,
    );
  }
}

class IanvsMarkdownHtmlFieldset extends StatelessWidget {
  const IanvsMarkdownHtmlFieldset({
    super.key,
    required this.legend,
    required this.body,
    required this.contentBuilder,
    this.theme,
  });

  final String legend;
  final String body;
  final IanvsMarkdownHtmlFieldsetContentBuilder contentBuilder;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    return Semantics(
      key: const ValueKey('ianvs-markdown-html-fieldset'),
      container: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            key: const ValueKey('ianvs-markdown-html-fieldset-border'),
            width: double.infinity,
            margin: const EdgeInsets.only(top: 9),
            padding: const EdgeInsets.fromLTRB(12, 15, 12, 10),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: contentBuilder(context, body),
          ),
          PositionedDirectional(
            start: 9,
            top: 0,
            child: Container(
              key: const ValueKey('ianvs-markdown-html-fieldset-legend'),
              color: colors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: contentBuilder(context, legend),
            ),
          ),
        ],
      ),
    );
  }
}
