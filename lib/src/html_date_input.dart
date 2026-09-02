import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

/// Parses a standalone HTML date input and its trailing visual label.
class IanvsMarkdownHtmlDateInputSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlDateInputSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<input\b([^>\n]*)/?>[ \t]*(.*)$',
    caseSensitive: false,
  );
  static final RegExp _typeDate = RegExp(
    r'''\btype\s*=\s*(?:"date"|'date'|date)(?:\s|/|$)''',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final match = _line.firstMatch(parser.current.content);
    return match != null && _typeDate.hasMatch(match.group(1) ?? '');
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    final attributes = match.group(1) ?? '';
    return md.Element.empty('ianvs-html-date-input')
      ..attributes.addAll({
        'data-label': match.group(2) ?? '',
        'value': _attribute(attributes, 'value') ?? '',
        'min': _attribute(attributes, 'min') ?? '',
        'max': _attribute(attributes, 'max') ?? '',
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

class IanvsMarkdownHtmlDateInputBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlDateInputBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => IanvsMarkdownHtmlDateInput(
    value: element.attributes['value'] ?? '',
    min: element.attributes['min'] ?? '',
    max: element.attributes['max'] ?? '',
    label: element.attributes['data-label'] ?? '',
    theme: theme,
  );
}

/// Compact segmented HTML date control with view-local state.
class IanvsMarkdownHtmlDateInput extends StatefulWidget {
  const IanvsMarkdownHtmlDateInput({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    this.theme,
  });

  final String value;
  final String min;
  final String max;
  final String label;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlDateInput> createState() =>
      _IanvsMarkdownHtmlDateInputState();
}

enum _DateSegment { year, month, day }

class _IanvsMarkdownHtmlDateInputState
    extends State<IanvsMarkdownHtmlDateInput> {
  late DateTime _value = _parseDate(widget.value) ?? DateTime(1970);
  late final Map<_DateSegment, FocusNode> _focusNodes =
      <_DateSegment, FocusNode>{
        for (final segment in _DateSegment.values)
          segment: FocusNode(
            debugLabel: 'Ianvs Markdown HTML date ${segment.name}',
          ),
      };

  DateTime? get _min => _parseDate(widget.min);
  DateTime? get _max => _parseDate(widget.max);

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlDateInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max) {
      _value = _clamp(_parseDate(widget.value) ?? DateTime(1970));
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    return Row(
      key: const ValueKey('ianvs-markdown-html-date-input-row'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Date picker',
          value: _sourceDate(_value),
          child: Container(
            key: const ValueKey('ianvs-markdown-html-date-input'),
            width: 82,
            height: 20,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              border: Border.all(color: colors.taskCheckboxBorderColor),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: <Widget>[
                _segment(
                  segment: _DateSegment.year,
                  text: _value.year.toString().padLeft(4, '0'),
                  width: 26,
                  colors: colors,
                ),
                _separator('/', colors),
                _segment(
                  segment: _DateSegment.month,
                  text: _value.month.toString().padLeft(2, '0'),
                  width: 13,
                  colors: colors,
                ),
                _separator('/', colors),
                _segment(
                  segment: _DateSegment.day,
                  text: _value.day.toString().padLeft(2, '0'),
                  width: 13,
                  colors: colors,
                ),
                SizedBox(
                  width: 20,
                  height: 18,
                  child: IconButton(
                    key: const ValueKey(
                      'ianvs-markdown-html-date-input-picker-button',
                    ),
                    tooltip: 'Show date picker',
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    splashRadius: 8,
                    iconSize: 11,
                    color: colors.textTertiary,
                    icon: const Icon(Icons.calendar_month_outlined),
                  ),
                ),
              ],
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

  Widget _separator(String text, IanvsMarkdownThemeData colors) => SizedBox(
    width: 4,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: colors.textTertiary, fontSize: 10, height: 1),
    ),
  );

  Widget _segment({
    required _DateSegment segment,
    required String text,
    required double width,
    required IanvsMarkdownThemeData colors,
  }) {
    final focusNode = _focusNodes[segment]!;
    return Semantics(
      container: true,
      value: text,
      increasedValue: _segmentValue(segment, 1),
      decreasedValue: _segmentValue(segment, -1),
      onIncrease: () => _step(segment, 1),
      onDecrease: () => _step(segment, -1),
      onFocus: focusNode.requestFocus,
      child: SizedBox(
        key: ValueKey('ianvs-markdown-html-date-${segment.name}'),
        width: width,
        height: 18,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _step(segment, 1),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _step(segment, -1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _focusAdjacent(segment, -1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _focusAdjacent(segment, 1),
          },
          child: Focus(
            focusNode: focusNode,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: focusNode.requestFocus,
              child: Center(
                child: Text(
                  text,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 10,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _segmentValue(_DateSegment segment, int direction) {
    final date = _stepped(segment, direction);
    return switch (segment) {
      _DateSegment.year => date.year.toString().padLeft(4, '0'),
      _DateSegment.month => date.month.toString().padLeft(2, '0'),
      _DateSegment.day => date.day.toString().padLeft(2, '0'),
    };
  }

  void _step(_DateSegment segment, int direction) {
    setState(() => _value = _stepped(segment, direction));
  }

  DateTime _stepped(_DateSegment segment, int direction) {
    final next = switch (segment) {
      _DateSegment.year => _dateWith(
        year: _value.year + direction,
        month: _value.month,
        day: _value.day,
      ),
      _DateSegment.month => _dateWith(
        year: _value.year,
        month: _value.month + direction,
        day: _value.day,
      ),
      _DateSegment.day => _value.add(Duration(days: direction)),
    };
    return _clamp(next);
  }

  void _focusAdjacent(_DateSegment segment, int direction) {
    final index = _DateSegment.values.indexOf(segment);
    final next = (index + direction)
        .clamp(0, _DateSegment.values.length - 1)
        .toInt();
    _focusNodes[_DateSegment.values[next]]!.requestFocus();
  }

  DateTime _clamp(DateTime value) {
    final minimum = _min;
    final maximum = _max;
    if (minimum != null && value.isBefore(minimum)) return minimum;
    if (maximum != null && value.isAfter(maximum)) return maximum;
    return value;
  }

  static DateTime _dateWith({
    required int year,
    required int month,
    required int day,
  }) {
    final normalizedMonth = DateTime(year, month, 1);
    final lastDay = DateTime(
      normalizedMonth.year,
      normalizedMonth.month + 1,
      0,
    ).day;
    return DateTime(
      normalizedMonth.year,
      normalizedMonth.month,
      day.clamp(1, lastDay),
    );
  }

  static DateTime? _parseDate(String source) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(source);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static String _sourceDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
