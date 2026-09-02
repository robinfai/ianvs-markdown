import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

class IanvsMarkdownHtmlRubyBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlRubyBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final baseText = element.textContent;
    final annotation = element.attributes['data-annotation'] ?? '';
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final baseStyle = (parentStyle ?? preferredStyle ?? const TextStyle())
        .copyWith(color: colors.textPrimary);
    final baseSize = baseStyle.fontSize ?? 14;
    final annotationStyle = baseStyle.copyWith(
      fontSize: baseSize * .55,
      height: 1,
    );

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Semantics(
              key: const ValueKey('ianvs-markdown-html-ruby'),
              label: baseText,
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ExcludeSemantics(
                    child: Text(annotation, style: annotationStyle),
                  ),
                  Text(baseText, style: baseStyle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
