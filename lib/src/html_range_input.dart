import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

enum IanvsMarkdownHtmlRangeInputPresentation { reading, editing }

class IanvsMarkdownHtmlRangeInputSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlRangeInputSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<input\b([^>\n]*)/?>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _typeRange = RegExp(
    r'''\btype\s*=\s*(?:"range"|'range'|range)(?:\s|/|$)''',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final match = _line.firstMatch(parser.current.content);
    return match != null && _typeRange.hasMatch(match.group(1) ?? '');
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final source = parser.current.content;
    final match = _line.firstMatch(source)!;
    parser.advance();
    final attributes = match.group(1) ?? '';
    final min = _numberAttribute(attributes, 'min') ?? 0;
    final parsedMax = _numberAttribute(attributes, 'max') ?? 100;
    final max = parsedMax > min ? parsedMax : min + 100;
    final step = _numberAttribute(attributes, 'step') ?? 1;
    final value =
        (_numberAttribute(attributes, 'value') ?? min + (max - min) / 2).clamp(
          min,
          max,
        );
    return md.Element.empty('ianvs-html-range-input')
      ..attributes.addAll({
        'data-source': source,
        'min': '$min',
        'max': '$max',
        'step': '$step',
        'value': '$value',
      });
  }

  static double? _numberAttribute(
    String source,
    String name,
  ) => double.tryParse(
    RegExp(
          '''\\b${RegExp.escape(name)}\\s*=\\s*["']?([+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+))''',
          caseSensitive: false,
        ).firstMatch(source)?.group(1) ??
        '',
  );
}

class IanvsMarkdownHtmlRangeInputBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlRangeInputBuilder({
    required this.presentation,
    this.onTap,
    this.theme,
  });

  final IanvsMarkdownHtmlRangeInputPresentation presentation;
  final VoidCallback? onTap;
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
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    if (presentation == IanvsMarkdownHtmlRangeInputPresentation.editing) {
      return SelectableText(
        element.attributes['data-source'] ?? '',
        key: const ValueKey('ianvs-markdown-html-range-input-source'),
        onTap: onTap,
        style: TextStyle(
          color: colors.textPrimary,
          fontFamily: colors.monoFontFamily,
          fontFamilyFallback: colors.monoFontFamilyFallback,
          fontSize: 13,
          height: 1.55,
        ),
      );
    }
    return IanvsMarkdownHtmlRangeInput(
      min: double.tryParse(element.attributes['min'] ?? '') ?? 0,
      max: double.tryParse(element.attributes['max'] ?? '') ?? 100,
      step: double.tryParse(element.attributes['step'] ?? '') ?? 1,
      value: double.tryParse(element.attributes['value'] ?? '') ?? 50,
      theme: colors,
    );
  }
}

class IanvsMarkdownHtmlRangeInput extends StatefulWidget {
  const IanvsMarkdownHtmlRangeInput({
    super.key,
    required this.min,
    required this.max,
    required this.step,
    required this.value,
    this.theme,
  });

  final double min;
  final double max;
  final double step;
  final double value;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlRangeInput> createState() =>
      _IanvsMarkdownHtmlRangeInputState();
}

class _IanvsMarkdownHtmlRangeInputState
    extends State<IanvsMarkdownHtmlRangeInput> {
  late double _value = widget.value;
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'Ianvs Markdown HTML range input',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlRangeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.step != widget.step ||
        oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        key: const ValueKey('ianvs-markdown-html-range-input'),
        width: 72,
        height: 10,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: colors.textTertiary,
            inactiveTrackColor: colors.borderSoft,
            thumbColor: colors.textTertiary,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focusNode.requestFocus();
              });
            },
            child: Slider(
              value: _value.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              divisions: _divisions,
              focusNode: _focusNode,
              semanticFormatterCallback: _formatNumber,
              onChanged: (value) => setState(() => _value = value),
            ),
          ),
        ),
      ),
    );
  }

  int? get _divisions {
    if (widget.step <= 0 || widget.max <= widget.min) return null;
    final count = (widget.max - widget.min) / widget.step;
    if (count < 1 || count > 10000 || (count - count.round()).abs() > 1e-9) {
      return null;
    }
    return count.round();
  }

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}
