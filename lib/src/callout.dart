import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

typedef IanvsMarkdownCalloutBodyBuilder =
    Widget Function(BuildContext context, String source);
typedef IanvsMarkdownCalloutTitleBuilder =
    Widget Function(BuildContext context, String source, Color accent);

/// Metadata parsed from an Obsidian Callout header.
@immutable
final class IanvsMarkdownCalloutHeader {
  const IanvsMarkdownCalloutHeader({
    required this.type,
    required this.fold,
    required this.explicitTitle,
  });

  /// Lowercase type used for Obsidian's case-insensitive style lookup.
  final String type;

  /// Tight `+` or `-` folding marker, or the empty string.
  final String fold;

  /// Trimmed custom title, or the empty string when the default is used.
  final String explicitTitle;

  String get title =>
      explicitTitle.isEmpty ? _defaultTitle(type) : explicitTitle;
}

final RegExp _ianvsMarkdownCalloutHeaderPattern = RegExp(
  r'^ {0,3}> ?\[!([^\]\r\n]+)\]([+-])?(?:[ \t]+(.*))?[ \t]*$',
);

/// Parses the first physical line of an Obsidian Callout.
///
/// Obsidian 1.13.7 accepts either no character or one literal space after
/// `>`. The type is any non-empty text before `]`; type matching is
/// case-insensitive, while two spaces or a Tab after `>` leave the marker as
/// an ordinary block quote.
IanvsMarkdownCalloutHeader? parseIanvsMarkdownCalloutHeader(String source) {
  final firstBreak = source.indexOf('\n');
  var firstLine = firstBreak < 0 ? source : source.substring(0, firstBreak);
  if (firstLine.endsWith('\r')) {
    firstLine = firstLine.substring(0, firstLine.length - 1);
  }
  final match = _ianvsMarkdownCalloutHeaderPattern.firstMatch(firstLine);
  if (match == null) return null;
  return IanvsMarkdownCalloutHeader(
    type: match.group(1)!.toLowerCase(),
    fold: match.group(2) ?? '',
    explicitTitle: match.group(3)?.trim() ?? '',
  );
}

/// Parses Obsidian callouts such as `> [!note] Title`.
class IanvsMarkdownCalloutSyntax extends md.BlockSyntax {
  const IanvsMarkdownCalloutSyntax();

  static final RegExp _quoteLine = RegExp(r'^ {0,3}>[ \t]?(.*)$');
  static final RegExp _unquotedBlockOpener = RegExp(
    r'^ {0,3}(?:#{1,6}(?:[ \t]+|$)|`{3,}|~{3,}|\$\$[ \t]*$|'
    r'[-+*][ \t]+|\d{1,9}[.)][ \t]+|<[A-Za-z!/])',
  );

  @override
  RegExp get pattern => _ianvsMarkdownCalloutHeaderPattern;

  @override
  md.Node parse(md.BlockParser parser) {
    final header = parseIanvsMarkdownCalloutHeader(parser.current.content)!;
    parser.advance();

    final bodyLines = <String>[];
    while (!parser.isDone) {
      final source = parser.current.content;
      final line = _quoteLine.firstMatch(source);
      if (line != null) {
        bodyLines.add(line.group(1) ?? '');
        parser.advance();
        continue;
      }
      if (source.trim().isEmpty || _startsUnquotedBlock(source)) break;
      // CommonMark lazy blockquote continuation remains inside an Obsidian
      // callout even though its physical source line omits `>`.
      bodyLines.add(source);
      parser.advance();
    }

    return md.Element('ianvs-callout', const <md.Node>[])
      ..attributes['data-type'] = header.type
      ..attributes['data-title'] = header.title
      ..attributes['data-fold'] = header.fold
      ..attributes['data-body'] = bodyLines.join('\n');
  }

  static bool _startsUnquotedBlock(String source) {
    if (_unquotedBlockOpener.hasMatch(source)) return true;
    final leadingSpaces = RegExp(r'^ *').firstMatch(source)!.group(0)!.length;
    if (leadingSpaces > 3) return false;
    final compact = source.trim().replaceAll(RegExp(r'[ \t]'), '');
    if (compact.length < 3) return false;
    return compact.codeUnits.every((unit) => unit == 0x2a) ||
        compact.codeUnits.every((unit) => unit == 0x2d) ||
        compact.codeUnits.every((unit) => unit == 0x5f);
  }
}

class IanvsMarkdownCalloutBuilder extends MarkdownElementBuilder {
  IanvsMarkdownCalloutBuilder({
    required this.bodyBuilder,
    this.titleBuilder,
    this.theme,
  });

  final IanvsMarkdownCalloutBodyBuilder bodyBuilder;
  final IanvsMarkdownCalloutTitleBuilder? titleBuilder;
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
    return IanvsMarkdownCallout(
      type: element.attributes['data-type'] ?? 'note',
      title: element.attributes['data-title'] ?? 'Note',
      body: element.attributes['data-body'] ?? '',
      fold: element.attributes['data-fold'] ?? '',
      bodyBuilder: bodyBuilder,
      titleBuilder: titleBuilder,
      theme: theme,
    );
  }
}

class IanvsMarkdownCallout extends StatefulWidget {
  const IanvsMarkdownCallout({
    super.key,
    required this.type,
    required this.title,
    required this.body,
    required this.fold,
    required this.bodyBuilder,
    this.titleBuilder,
    this.theme,
  });

  final String type;
  final String title;
  final String body;
  final String fold;
  final IanvsMarkdownCalloutBodyBuilder bodyBuilder;
  final IanvsMarkdownCalloutTitleBuilder? titleBuilder;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownCallout> createState() => _IanvsMarkdownCalloutState();
}

class _IanvsMarkdownCalloutState extends State<IanvsMarkdownCallout> {
  late bool _expanded;

  bool get _foldable => widget.fold == '+' || widget.fold == '-';

  @override
  void initState() {
    super.initState();
    _expanded = widget.fold != '-';
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownCallout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fold != widget.fold || oldWidget.body != widget.body) {
      _expanded = widget.fold != '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    final accent = _calloutColor(widget.type, colors);
    final hasBody = widget.body.trim().isNotEmpty;
    final showBody = hasBody && (!_foldable || _expanded);
    return AnimatedContainer(
      key: ValueKey<String>('ianvs-markdown-callout-${widget.type}'),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: accent.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .14 : .09,
        ),
        borderRadius: BorderRadius.circular(colors.smallRadius / 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey<String>(
                'ianvs-markdown-callout-toggle-${widget.type}',
              ),
              onTap: _foldable
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(colors.smallRadius / 2),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 11, 20, showBody ? 4 : 11),
                child: Row(
                  children: [
                    Icon(_calloutIcon(widget.type), size: 15, color: accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child:
                          widget.titleBuilder?.call(
                            context,
                            widget.title,
                            accent,
                          ) ??
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: accent,
                              fontSize: 14.5,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                    ),
                    if (_foldable)
                      AnimatedRotation(
                        turns: _expanded ? .25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: accent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: showBody
                ? Padding(
                    key: ValueKey<String>(
                      'ianvs-markdown-callout-body-${widget.type}',
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: widget.bodyBuilder(context, widget.body),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

String _defaultTitle(String type) {
  const titles = <String, String>{
    'abstract': 'Abstract',
    'summary': 'Summary',
    'tldr': 'TL;DR',
    'info': 'Info',
    'todo': 'Todo',
    'tip': 'Tip',
    'hint': 'Hint',
    'important': 'Important',
    'success': 'Success',
    'check': 'Check',
    'done': 'Done',
    'question': 'Question',
    'help': 'Help',
    'faq': 'FAQ',
    'warning': 'Warning',
    'caution': 'Caution',
    'attention': 'Attention',
    'failure': 'Failure',
    'fail': 'Failure',
    'missing': 'Missing',
    'danger': 'Danger',
    'error': 'Error',
    'bug': 'Bug',
    'example': 'Example',
    'quote': 'Quote',
    'cite': 'Quote',
  };
  return titles[type] ??
      (type.isEmpty ? 'Note' : '${type[0].toUpperCase()}${type.substring(1)}');
}

Color _calloutColor(String type, IanvsMarkdownThemeData colors) {
  return switch (type) {
    'abstract' || 'summary' || 'tldr' => colors.taskStatusCyan,
    'tip' || 'hint' || 'important' => colors.taskStatusCyan,
    'success' || 'check' || 'done' => colors.taskCheckboxColor,
    'question' || 'help' || 'faq' => colors.taskStatusYellow,
    'warning' || 'caution' || 'attention' => colors.taskStatusOrange,
    'failure' || 'fail' || 'missing' => colors.taskStatusRed,
    'danger' || 'error' || 'bug' => colors.taskStatusRed,
    'example' => colors.taskStatusPurple,
    'quote' || 'cite' => colors.textSecondary,
    _ => colors.taskStatusBlue,
  };
}

IconData _calloutIcon(String type) {
  return switch (type) {
    'abstract' || 'summary' || 'tldr' => Icons.content_copy_rounded,
    'info' => Icons.info_outline_rounded,
    'todo' => Icons.check_circle_outline_rounded,
    'tip' || 'hint' || 'important' => Icons.local_fire_department_outlined,
    'success' || 'check' || 'done' => Icons.check_rounded,
    'question' || 'help' || 'faq' => Icons.help_outline_rounded,
    'warning' || 'caution' || 'attention' => Icons.warning_amber_rounded,
    'failure' || 'fail' || 'missing' => Icons.close_rounded,
    'danger' || 'error' => Icons.bolt_rounded,
    'bug' => Icons.bug_report_outlined,
    'example' => Icons.list_rounded,
    'quote' || 'cite' => Icons.format_quote_rounded,
    _ => Icons.edit_outlined,
  };
}
