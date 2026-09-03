import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

/// Parses HTML month, week, and local date-time controls.
class IanvsMarkdownHtmlTemporalInputSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlTemporalInputSyntax();

  static const Set<String> _types = <String>{'month', 'week', 'datetime-local'};
  static final RegExp _line = RegExp(
    r'^ {0,3}<input\b([^>\n]*)/?>[ \t]*(.*)$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final match = _line.firstMatch(parser.current.content);
    final type = _attribute(match?.group(1) ?? '', 'type')?.toLowerCase();
    return match != null && type != null && _types.contains(type);
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    final attributes = match.group(1) ?? '';
    return md.Element.empty('ianvs-html-temporal-input')
      ..attributes.addAll({
        'data-label': match.group(2) ?? '',
        'type': _attribute(attributes, 'type')?.toLowerCase() ?? 'month',
        'value': _attribute(attributes, 'value') ?? '',
      });
  }

  static String? _attribute(String source, String name) {
    final match = RegExp(
      '''\\b${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>`]+))''',
      caseSensitive: false,
    ).firstMatch(source);
    return match?.group(1) ?? match?.group(2) ?? match?.group(3);
  }
}

class IanvsMarkdownHtmlTemporalInputBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlTemporalInputBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => IanvsMarkdownHtmlTemporalInput(
    inputType: element.attributes['type'] ?? 'month',
    value: element.attributes['value'] ?? '',
    label: element.attributes['data-label'] ?? '',
    theme: theme,
  );
}

/// Compact source-preserving projection of native temporal inputs.
class IanvsMarkdownHtmlTemporalInput extends StatefulWidget {
  const IanvsMarkdownHtmlTemporalInput({
    super.key,
    required this.inputType,
    required this.value,
    required this.label,
    this.theme,
  });

  final String inputType;
  final String value;
  final String label;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlTemporalInput> createState() =>
      _IanvsMarkdownHtmlTemporalInputState();
}

class _IanvsMarkdownHtmlTemporalInputState
    extends State<IanvsMarkdownHtmlTemporalInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'Ianvs Markdown HTML temporal input',
  );

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlTemporalInput oldWidget) {
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
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    return Row(
      key: ValueKey('ianvs-markdown-html-${widget.inputType}-input-row'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          key: ValueKey('ianvs-markdown-html-${widget.inputType}-input'),
          width: switch (widget.inputType) {
            'month' => 84,
            'week' => 96,
            _ => 142,
          },
          height: 20,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.datetime,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 10,
              height: 1,
            ),
            decoration: InputDecoration(
              isDense: true,
              isCollapsed: true,
              contentPadding: const EdgeInsets.fromLTRB(4, 4, 20, 3),
              filled: true,
              fillColor: colors.surfaceMuted,
              suffixIcon: Icon(
                Icons.calendar_month_outlined,
                size: 11,
                color: colors.textTertiary,
              ),
              suffixIconConstraints: const BoxConstraints.tightFor(
                width: 18,
                height: 18,
              ),
              border: _border(colors.taskCheckboxBorderColor),
              enabledBorder: _border(colors.taskCheckboxBorderColor),
              focusedBorder: _border(colors.accent),
            ),
          ),
        ),
        if (widget.label.isNotEmpty) ...<Widget>[
          const SizedBox(width: 4),
          Text(
            widget.label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(2),
    borderSide: BorderSide(color: color, width: 1),
  );
}
