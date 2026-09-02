import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

/// Parses a standalone HTML number input and its trailing visual label.
class IanvsMarkdownHtmlNumberInputSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlNumberInputSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<input\b([^>\n]*)/?>[ \t]*(.*)$',
    caseSensitive: false,
  );
  static final RegExp _typeNumber = RegExp(
    r'''\btype\s*=\s*(?:"number"|'number'|number)(?:\s|/|$)''',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final match = _line.firstMatch(parser.current.content);
    return match != null && _typeNumber.hasMatch(match.group(1) ?? '');
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    final attributes = match.group(1) ?? '';
    return md.Element.empty('ianvs-html-number-input')
      ..attributes.addAll({
        'data-label': match.group(2) ?? '',
        'min': _attribute(attributes, 'min') ?? '',
        'max': _attribute(attributes, 'max') ?? '',
        'step': _attribute(attributes, 'step') ?? '1',
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

class IanvsMarkdownHtmlNumberInputBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlNumberInputBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => IanvsMarkdownHtmlNumberInput(
    value: element.attributes['value'] ?? '',
    min: double.tryParse(element.attributes['min'] ?? ''),
    max: double.tryParse(element.attributes['max'] ?? ''),
    step: double.tryParse(element.attributes['step'] ?? '') ?? 1,
    label: element.attributes['data-label'] ?? '',
    theme: theme,
  );
}

/// Obsidian-style compact number stepper whose value is view-local state.
class IanvsMarkdownHtmlNumberInput extends StatefulWidget {
  const IanvsMarkdownHtmlNumberInput({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.label,
    this.theme,
  });

  final String value;
  final double? min;
  final double? max;
  final double step;
  final String label;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlNumberInput> createState() =>
      _IanvsMarkdownHtmlNumberInputState();
}

class _IanvsMarkdownHtmlNumberInputState
    extends State<IanvsMarkdownHtmlNumberInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'Ianvs Markdown HTML number input',
  );

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.value != widget.value ||
            oldWidget.min != widget.min ||
            oldWidget.max != widget.max ||
            oldWidget.step != widget.step) &&
        _controller.text != widget.value) {
      _setText(widget.value);
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
    final value = _numericValue;
    return Row(
      key: const ValueKey('ianvs-markdown-html-number-input-row'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Semantics(
          key: const ValueKey('ianvs-markdown-html-number-input'),
          container: true,
          explicitChildNodes: false,
          excludeSemantics: true,
          textField: true,
          value: _controller.text,
          minValue: widget.min == null ? null : _formatNumber(widget.min!),
          maxValue: widget.max == null ? null : _formatNumber(widget.max!),
          increasedValue: value == null
              ? null
              : _formatNumber(_stepped(value, 1)),
          decreasedValue: value == null
              ? null
              : _formatNumber(_stepped(value, -1)),
          onIncrease: _increase,
          onDecrease: _decrease,
          onSetText: _setText,
          onFocus: _focusNode.requestFocus,
          child: SizedBox(
            width: 35,
            height: 20,
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.arrowUp): _increase,
                const SingleActivator(LogicalKeyboardKey.arrowDown): _decrease,
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-.]')),
                ],
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  height: 1,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.fromLTRB(4, 4, 2, 3),
                  filled: true,
                  fillColor: colors.surfaceMuted,
                  border: _border(colors.taskCheckboxBorderColor),
                  enabledBorder: _border(colors.taskCheckboxBorderColor),
                  focusedBorder: _border(colors.accent),
                ),
              ),
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

  double? get _numericValue => double.tryParse(_controller.text);

  void _increase() => _step(1);

  void _decrease() => _step(-1);

  void _step(int direction) {
    final current = _numericValue;
    if (current == null) return;
    _setText(_formatNumber(_stepped(current, direction)));
  }

  double _stepped(double current, int direction) {
    final step = widget.step > 0 ? widget.step : 1;
    final base = widget.min ?? 0;
    final position = (current - base) / step;
    final rounded = position.roundToDouble();
    final aligned = (position - rounded).abs() < 1e-9;
    final targetPosition = aligned
        ? rounded + direction
        : direction > 0
        ? position.ceilToDouble()
        : position.floorToDouble();
    var target = base + targetPosition * step;
    final minimum = widget.min;
    final maximum = widget.max;
    if (minimum != null && target < minimum) target = minimum;
    if (maximum != null && target > maximum) target = maximum;
    return target;
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (mounted) setState(() {});
  }

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}
