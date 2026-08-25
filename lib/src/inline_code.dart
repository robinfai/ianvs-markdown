import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

/// The compact inline-code treatment shared by reading and editing surfaces.
///
/// A text background keeps code spans selectable and lets long spans wrap at
/// their natural character boundaries. The slightly taller line box supplies
/// the same visual breathing room as Obsidian without turning the span into an
/// atomic inline widget.
TextStyle ianvsMarkdownInlineCodeStyle(
  IanvsMarkdownThemeData colors, {
  double? fontSize = 12,
  double? height = 1.35,
}) {
  return TextStyle(
    color: colors.inlineCodeForeground,
    backgroundColor: colors.surfaceHover,
    fontFamily: colors.monoFontFamily,
    fontFamilyFallback: colors.monoFontFamilyFallback,
    fontSize: fontSize,
    height: height,
  );
}

/// Keeps inline code textual, selectable, and naturally wrappable while
/// retaining styles supplied by outer emphasis, strike, or highlight nodes.
class IanvsMarkdownInlineCodeBuilder extends MarkdownElementBuilder {
  IanvsMarkdownInlineCodeBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final code = ianvsMarkdownInlineCodeStyle(colors);
    final style = (parentStyle ?? preferredStyle ?? const TextStyle()).copyWith(
      color: code.color,
      backgroundColor: code.backgroundColor,
      fontFamily: code.fontFamily,
      fontFamilyFallback: code.fontFamilyFallback,
      fontSize: code.fontSize,
      height: code.height,
    );
    return Text.rich(TextSpan(text: element.textContent, style: style));
  }
}
