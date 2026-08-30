import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

/// Parses the single-line HTML textarea form sampled from Obsidian.
///
/// Obsidian renders this as a real, editable text area in both views, but its
/// value is local UI state rather than a source mutation. Keeping this narrow
/// parser to a complete source line avoids claiming support for arbitrary HTML
/// form nesting while preserving the observed behavior exactly.
class IanvsMarkdownHtmlTextareaSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlTextareaSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<textarea(?:\s[^>\n]*)?>(.*?)</textarea\s*>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    return md.Element.empty('ianvs-html-textarea')
      ..attributes['data-value'] = match.group(1) ?? '';
  }
}

class IanvsMarkdownHtmlTextareaBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlTextareaBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => IanvsMarkdownHtmlTextarea(
    value: element.attributes['data-value'] ?? '',
    theme: theme,
  );
}

/// View-local editable HTML textarea projection.
class IanvsMarkdownHtmlTextarea extends StatefulWidget {
  const IanvsMarkdownHtmlTextarea({super.key, required this.value, this.theme});

  final String value;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlTextarea> createState() =>
      _IanvsMarkdownHtmlTextareaState();
}

class _IanvsMarkdownHtmlTextareaState extends State<IanvsMarkdownHtmlTextarea> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlTextarea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    return SizedBox(
      key: const ValueKey('ianvs-markdown-html-textarea'),
      width: 138,
      height: 32,
      child: TextField(
        controller: _controller,
        minLines: null,
        maxLines: null,
        expands: true,
        style: TextStyle(
          color: colors.codeForeground,
          fontFamily: colors.monoFontFamily,
          fontFamilyFallback: colors.monoFontFamilyFallback,
          fontSize: 12,
          height: 1.25,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 6,
          ),
          filled: true,
          fillColor: colors.surfaceMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide(color: colors.taskCheckboxBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide(color: colors.taskCheckboxBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide(color: colors.accent),
          ),
        ),
      ),
    );
  }
}
