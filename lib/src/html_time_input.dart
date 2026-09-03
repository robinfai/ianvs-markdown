import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

/// Parses a standalone HTML time input and its trailing visual label.
class IanvsMarkdownHtmlTimeInputSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlTimeInputSyntax();

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
    return match != null &&
        _attribute(match.group(1) ?? '', 'type')?.toLowerCase() == 'time';
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    final attributes = match.group(1) ?? '';
    return md.Element.empty('ianvs-html-time-input')
      ..attributes.addAll({
        'data-label': match.group(2) ?? '',
        'value': _attribute(attributes, 'value') ?? '',
        'min': _attribute(attributes, 'min') ?? '',
        'max': _attribute(attributes, 'max') ?? '',
        'step': _attribute(attributes, 'step') ?? '',
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

class IanvsMarkdownHtmlTimeInputBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlTimeInputBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => IanvsMarkdownHtmlTimeInput(
    value: element.attributes['value'] ?? '',
    min: element.attributes['min'] ?? '',
    max: element.attributes['max'] ?? '',
    step: element.attributes['step'] ?? '',
    label: element.attributes['data-label'] ?? '',
    theme: theme,
  );
}

/// Compact segmented HTML time control with source-preserving local state.
class IanvsMarkdownHtmlTimeInput extends StatefulWidget {
  const IanvsMarkdownHtmlTimeInput({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.label,
    this.theme,
  });

  final String value;
  final String min;
  final String max;
  final String step;
  final String label;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlTimeInput> createState() =>
      _IanvsMarkdownHtmlTimeInputState();
}

enum _TimeSegment { hour, minute }

class _IanvsMarkdownHtmlTimeInputState
    extends State<IanvsMarkdownHtmlTimeInput> {
  late int _minutes = _clamp(_parseTime(widget.value) ?? 0);
  late final Map<_TimeSegment, FocusNode> _focusNodes =
      <_TimeSegment, FocusNode>{
        for (final segment in _TimeSegment.values)
          segment: FocusNode(
            debugLabel: 'Ianvs Markdown HTML time ${segment.name}',
          ),
      };

  int? get _min => _parseTime(widget.min);
  int? get _max => _parseTime(widget.max);
  int get _minuteStep {
    final seconds = int.tryParse(widget.step);
    if (seconds == null || seconds <= 0) return 1;
    return (seconds / 60).ceil().clamp(1, 24 * 60);
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlTimeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.step != widget.step) {
      _minutes = _clamp(_parseTime(widget.value) ?? 0);
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
      key: const ValueKey('ianvs-markdown-html-time-input-row'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Time picker',
          value: _sourceTime(_minutes),
          child: Container(
            key: const ValueKey('ianvs-markdown-html-time-input'),
            width: 56,
            height: 20,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              border: Border.all(color: colors.taskCheckboxBorderColor),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: <Widget>[
                _segment(
                  segment: _TimeSegment.hour,
                  text: (_minutes ~/ 60).toString().padLeft(2, '0'),
                  colors: colors,
                ),
                SizedBox(
                  width: 4,
                  child: Text(
                    ':',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 10,
                      height: 1,
                    ),
                  ),
                ),
                _segment(
                  segment: _TimeSegment.minute,
                  text: (_minutes % 60).toString().padLeft(2, '0'),
                  colors: colors,
                ),
                SizedBox(
                  width: 20,
                  height: 18,
                  child: IconButton(
                    key: const ValueKey(
                      'ianvs-markdown-html-time-input-picker-button',
                    ),
                    tooltip: 'Show time picker',
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    splashRadius: 8,
                    iconSize: 11,
                    color: colors.textTertiary,
                    icon: const Icon(Icons.schedule_outlined),
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

  Widget _segment({
    required _TimeSegment segment,
    required String text,
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
        key: ValueKey('ianvs-markdown-html-time-${segment.name}'),
        width: 15,
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
            onFocusChange: (_) => setState(() {}),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: focusNode.requestFocus,
              child: ColoredBox(
                color: focusNode.hasFocus
                    ? colors.accentSoft
                    : Colors.transparent,
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
      ),
    );
  }

  String _segmentValue(_TimeSegment segment, int direction) => _sourceTime(
    _stepped(segment, direction),
  ).split(':')[segment == _TimeSegment.hour ? 0 : 1];

  void _step(_TimeSegment segment, int direction) {
    setState(() => _minutes = _stepped(segment, direction));
  }

  int _stepped(_TimeSegment segment, int direction) {
    final delta = segment == _TimeSegment.hour ? 60 : _minuteStep;
    return _clamp((_minutes + (delta * direction)) % (24 * 60));
  }

  void _focusAdjacent(_TimeSegment segment, int direction) {
    final index = _TimeSegment.values.indexOf(segment);
    final next = (index + direction).clamp(0, _TimeSegment.values.length - 1);
    _focusNodes[_TimeSegment.values[next]]!.requestFocus();
  }

  int _clamp(int value) {
    final minimum = _min;
    final maximum = _max;
    if (minimum != null && value < minimum) return minimum;
    if (maximum != null && value > maximum) return maximum;
    return value;
  }

  static int? _parseTime(String source) {
    final match = RegExp(
      r'^(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$',
    ).firstMatch(source);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static String _sourceTime(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}
