import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

/// Builds an inline or display TeX expression.
///
/// The callback receives the expression without its `$` / `$$` delimiters.
/// Ianvs Markdown performs no file or network I/O before invoking it.
typedef IanvsMarkdownMathBuilder =
    Widget Function(
      BuildContext context,
      String expression, {
      required bool displayMode,
    });

/// Parses an Obsidian inline display expression such as `$$x^2$$`.
class IanvsMarkdownInlineDisplayMathSyntax extends md.InlineSyntax {
  IanvsMarkdownInlineDisplayMathSyntax()
    : super(
        r'\$\$(?!\s)((?:\\.|[^\\$`\n])*?(?:\\.|[^\s\\$`\n]))\$\$',
        startCharacter: 0x24,
      );

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    if (_openingDollarIsEscapedOrContinued(parser)) return false;
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.empty('ianvs-inline-display-math')
        ..attributes['data-expression'] = match.group(1)!,
    );
    return true;
  }
}

/// Parses Obsidian inline math while preserving currency and escaped dollars.
class IanvsMarkdownInlineMathSyntax extends md.InlineSyntax {
  IanvsMarkdownInlineMathSyntax()
    : super(
        r'\$(?!\$|\s)((?:\\.|[^\\$`\n])*?(?:\\.|[^\s\\$`\n]))\$(?!\$|\d)',
        startCharacter: 0x24,
      );

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    if (_openingDollarIsEscapedOrContinued(parser)) return false;
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.empty('ianvs-inline-math')
        ..attributes['data-expression'] = match.group(1)!,
    );
    return true;
  }
}

bool _openingDollarIsEscapedOrContinued(md.InlineParser parser) {
  if (parser.pos <= 0) return false;
  if (parser.source.codeUnitAt(parser.pos - 1) == 0x24) return true;
  var backslashes = 0;
  for (var index = parser.pos - 1; index >= 0; index -= 1) {
    if (parser.source.codeUnitAt(index) != 0x5c) break;
    backslashes += 1;
  }
  return backslashes.isOdd;
}

/// Parses a display expression fenced by standalone `$$` lines.
class IanvsMarkdownDisplayMathSyntax extends md.BlockSyntax {
  const IanvsMarkdownDisplayMathSyntax();

  static final RegExp _fence = RegExp(r'^ {0,3}\$\$[ \t]*$');

  @override
  RegExp get pattern => _fence;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    for (var offset = 1; ; offset += 1) {
      final line = parser.peek(offset);
      if (line == null) return false;
      if (_fence.hasMatch(line.content)) return true;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final lines = <String>[];
    while (!parser.isDone && !_fence.hasMatch(parser.current.content)) {
      lines.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    return md.Element.empty('ianvs-display-math')
      ..attributes['data-expression'] = lines.join('\n');
  }
}

/// Renders parsed TeX with a host override and a pure-Flutter default.
class IanvsMarkdownMathElementBuilder extends MarkdownElementBuilder {
  IanvsMarkdownMathElementBuilder({
    required this.displayMode,
    this.inline = false,
    this.mathBuilder,
    this.theme,
  });

  final bool displayMode;
  final bool inline;
  final IanvsMarkdownMathBuilder? mathBuilder;
  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => !inline;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return IanvsMarkdownMath(
      expression: element.attributes['data-expression'] ?? '',
      displayMode: displayMode,
      inline: inline,
      mathBuilder: mathBuilder,
      textStyle: parentStyle ?? preferredStyle,
      theme: theme,
    );
  }
}

class IanvsMarkdownMath extends StatelessWidget {
  const IanvsMarkdownMath({
    super.key,
    required this.expression,
    required this.displayMode,
    required this.inline,
    this.mathBuilder,
    this.textStyle,
    this.theme,
  });

  final String expression;
  final bool displayMode;
  final bool inline;
  final IanvsMarkdownMathBuilder? mathBuilder;
  final TextStyle? textStyle;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final effectiveStyle = (textStyle ?? DefaultTextStyle.of(context).style)
        .copyWith(color: colors.textPrimary);
    final formula =
        mathBuilder?.call(context, expression, displayMode: displayMode) ??
        Math.tex(
          expression,
          key: ValueKey(
            'ianvs-markdown-${inline ? 'inline' : 'display'}-math-formula',
          ),
          mathStyle: displayMode ? MathStyle.display : MathStyle.text,
          textStyle: effectiveStyle,
          onErrorFallback: (_) => DecoratedBox(
            key: const ValueKey('ianvs-markdown-math-error'),
            decoration: BoxDecoration(
              color: const Color(0xffffc107),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              expression,
              style: effectiveStyle.copyWith(
                color: const Color(0xff302900),
                fontFamily: colors.monoFontFamily,
                fontFamilyFallback: colors.monoFontFamilyFallback,
              ),
            ),
          ),
        );

    if (inline) {
      return Semantics(
        key: const ValueKey('ianvs-markdown-inline-math'),
        label: expression,
        child: formula,
      );
    }
    return Semantics(
      key: const ValueKey('ianvs-markdown-display-math'),
      label: expression,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : 1,
              ),
              child: Center(child: formula),
            ),
          ),
        ),
      ),
    );
  }
}
