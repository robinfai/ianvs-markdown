import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

typedef IanvsMarkdownHtmlDetailsBodyBuilder =
    Widget Function(BuildContext context, String source);

/// Parses the block HTML details form rendered by Obsidian.
///
/// The deliberately narrow grammar keeps the safe HTML surface inert: details
/// and summary tags must each occupy their own physical line, and a summary is
/// required before the matching close tag. Other HTML blocks continue through
/// the Markdown package's normal handling.
class IanvsMarkdownHtmlDetailsSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlDetailsSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<details\b([^>\n]*)>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^ {0,3}</details\s*>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _summary = RegExp(
    r'^ {0,3}<summary(?:\s[^>\n]*)?>(.*?)</summary\s*>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    var foundSummary = false;
    for (var offset = 1; ; offset += 1) {
      final line = parser.peek(offset);
      if (line == null) return false;
      foundSummary = foundSummary || _summary.hasMatch(line.content);
      if (_close.hasMatch(line.content)) return foundSummary;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final openMatch = _open.firstMatch(parser.current.content)!;
    final attributes = openMatch.group(1) ?? '';
    final initiallyExpanded = RegExp(
      r'(?:^|\s)open(?:\s|=|$)',
      caseSensitive: false,
    ).hasMatch(attributes);
    parser.advance();
    String? summary;
    final bodyLines = <String>[];
    while (!parser.isDone && !_close.hasMatch(parser.current.content)) {
      final line = parser.current.content;
      final match = _summary.firstMatch(line);
      if (match != null && summary == null) {
        summary = match.group(1)!.trim();
      } else {
        bodyLines.add(line);
      }
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    while (bodyLines.isNotEmpty && bodyLines.first.trim().isEmpty) {
      bodyLines.removeAt(0);
    }
    while (bodyLines.isNotEmpty && bodyLines.last.trim().isEmpty) {
      bodyLines.removeLast();
    }
    return md.Element.empty('ianvs-html-details')
      ..attributes['data-summary'] = summary ?? ''
      ..attributes['data-body'] = bodyLines.join('\n')
      ..attributes['data-open'] = initiallyExpanded ? 'true' : 'false';
  }
}

class IanvsMarkdownHtmlDetailsBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlDetailsBuilder({required this.bodyBuilder, this.theme});

  final IanvsMarkdownHtmlDetailsBodyBuilder bodyBuilder;
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
    return IanvsMarkdownHtmlDetails(
      summary: element.attributes['data-summary'] ?? '',
      body: element.attributes['data-body'] ?? '',
      initiallyExpanded: element.attributes['data-open'] == 'true',
      bodyBuilder: bodyBuilder,
      textStyle: parentStyle ?? preferredStyle,
      theme: theme,
    );
  }
}

/// Obsidian-like inert disclosure control for block HTML details.
class IanvsMarkdownHtmlDetails extends StatefulWidget {
  const IanvsMarkdownHtmlDetails({
    super.key,
    required this.summary,
    required this.body,
    required this.initiallyExpanded,
    required this.bodyBuilder,
    this.textStyle,
    this.theme,
  });

  final String summary;
  final String body;
  final bool initiallyExpanded;
  final IanvsMarkdownHtmlDetailsBodyBuilder bodyBuilder;
  final TextStyle? textStyle;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlDetails> createState() =>
      _IanvsMarkdownHtmlDetailsState();
}

class _IanvsMarkdownHtmlDetailsState extends State<IanvsMarkdownHtmlDetails> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary != widget.summary ||
        oldWidget.body != widget.body ||
        oldWidget.initiallyExpanded != widget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    final summaryStyle = (widget.textStyle ?? const TextStyle()).copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    );
    return Column(
      key: const ValueKey('ianvs-markdown-html-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('ianvs-markdown-html-details-toggle'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  AnimatedRotation(
                    turns: _expanded ? .25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(child: Text(widget.summary, style: summaryStyle)),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded && widget.body.trim().isNotEmpty
              ? Padding(
                  key: const ValueKey('ianvs-markdown-html-details-body'),
                  padding: const EdgeInsets.only(left: 20, top: 4, bottom: 4),
                  child: widget.bodyBuilder(context, widget.body),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
