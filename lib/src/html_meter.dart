import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

class IanvsMarkdownHtmlMeterSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlMeterSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<meter\s+([^>\n]*)>.*</meter\s*>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    final attributes = match.group(1) ?? '';
    final min = _numberAttribute(attributes, 'min') ?? 0;
    final parsedMax = _numberAttribute(attributes, 'max') ?? 1;
    final max = parsedMax > min ? parsedMax : min + 1;
    final low = (_numberAttribute(attributes, 'low') ?? min).clamp(min, max);
    final high = (_numberAttribute(attributes, 'high') ?? max).clamp(low, max);
    final optimum =
        (_numberAttribute(attributes, 'optimum') ?? min + (max - min) / 2)
            .clamp(min, max);
    final value = (_numberAttribute(attributes, 'value') ?? min).clamp(
      min,
      max,
    );
    return md.Element.empty('ianvs-html-meter')
      ..attributes.addAll({
        'min': '$min',
        'max': '$max',
        'low': '$low',
        'high': '$high',
        'optimum': '$optimum',
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

class IanvsMarkdownHtmlMeterBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlMeterBuilder({this.theme});

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
    final min = double.tryParse(element.attributes['min'] ?? '') ?? 0;
    final max = double.tryParse(element.attributes['max'] ?? '') ?? 1;
    final low = double.tryParse(element.attributes['low'] ?? '') ?? min;
    final high = double.tryParse(element.attributes['high'] ?? '') ?? max;
    final optimum =
        double.tryParse(element.attributes['optimum'] ?? '') ??
        min + (max - min) / 2;
    final value = double.tryParse(element.attributes['value'] ?? '') ?? min;
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final optimumRange = _rangeFor(optimum, low: low, high: high);
    final valueRange = _rangeFor(value, low: low, high: high);
    final fillColor = valueRange == optimumRange
        ? colors.taskCheckboxColor
        : optimumRange == 0 || valueRange == 0
        ? colors.taskStatusYellow
        : colors.error;
    final fraction = max <= min
        ? 0.0
        : ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        key: const ValueKey('ianvs-markdown-html-meter'),
        width: 56,
        height: 6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: colors.borderSoft,
            color: fillColor,
            semanticsValue: _formatNumber(value),
          ),
        ),
      ),
    );
  }

  static int _rangeFor(
    double value, {
    required double low,
    required double high,
  }) {
    if (value < low) return -1;
    if (value > high) return 1;
    return 0;
  }

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}
