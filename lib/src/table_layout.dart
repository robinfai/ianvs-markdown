import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Internal marker for the default adaptive policy. Explicit host policies are
/// still passed through to Flutter's Table unchanged.
final class AdaptiveMarkdownColumnWidth extends IntrinsicColumnWidth {
  const AdaptiveMarkdownColumnWidth();
}

/// A bounded, source-independent snapshot, shared by reading and live tables.
/// Width allocation needs no text measurement when a viewport resizes.
final class MarkdownTableMetrics {
  const MarkdownTableMetrics(this.minimumWidths, this.preferredWidths);

  final List<double> minimumWidths;
  final List<double> preferredWidths;

  /// Measures visible labels, not Markdown delimiters or link destinations.
  /// Call only when content, typography, text scaling or direction changes.
  /// Duplicate labels are measured once; long cells are capped before shaping.
  factory MarkdownTableMetrics.measure({
    required List<List<String>> rows,
    required TextStyle bodyStyle,
    required TextStyle headerStyle,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required double horizontalPadding,
    double? headerHorizontalPadding,
    Locale? locale,
    List<List<InlineSpan>>? spans,
    List<List<double>>? extraWidths,
  }) {
    if (rows.isEmpty) return const MarkdownTableMetrics([], []);
    final columns = rows.first.length;
    final fontSize = textScaler.scale(bodyStyle.fontSize ?? 14);
    final headerFontSize = textScaler.scale(headerStyle.fontSize ?? 14);
    final em = math.max(fontSize, headerFontSize);
    final padding = math.max(
      horizontalPadding,
      headerHorizontalPadding ?? horizontalPadding,
    );
    // Keep short fields compact, but provide a readable floor for prose before
    // opting into horizontal scrolling. Scale text, not fixed cell padding.
    final compact = math.max(44.0, 2.5 * em + padding);
    final readable = math.max(compact, 8 * em + padding);
    final cap = math.max(compact, 36 * em + padding);
    final preferred = List<double>.filled(columns, compact);
    final cache = <(String, bool, InlineSpan?, double), double>{};
    for (var row = 0; row < rows.length; row++) {
      final header = row == 0;
      final style = header ? headerStyle : bodyStyle;
      final cellPadding = header
          ? headerHorizontalPadding ?? horizontalPadding
          : horizontalPadding;
      for (var column = 0; column < columns; column++) {
        if (preferred[column] >= cap) continue;
        final text = column < rows[row].length ? rows[row][column] : '';
        final span = spans?[row][column];
        final extra = extraWidths?[row][column] ?? 0;
        // A pathological URL must not require shaping megabytes to decide
        // that its column should wrap. This does not truncate rendered text.
        var width = cap;
        if (text.length <= 256) {
          final key = (text, header, span, extra);
          width =
              cache[key] ??
              (() {
                final painter = TextPainter(
                  text: span == null
                      ? TextSpan(text: text, style: style)
                      : TextSpan(style: style, children: [span]),
                  textDirection: textDirection,
                  locale: locale,
                  textScaler: textScaler,
                  maxLines: 1,
                )..layout(maxWidth: cap - cellPadding);
                final measured = math.min(
                  cap,
                  painter.maxIntrinsicWidth.ceilToDouble() +
                      cellPadding +
                      extra +
                      2,
                );
                painter.dispose();
                // The cache is local and bounded even for very tall tables.
                if (cache.length < 256) cache[key] = measured;
                return measured;
              })();
        }
        preferred[column] = math.max(preferred[column], width);
      }
    }
    return MarkdownTableMetrics([
      for (final width in preferred) math.min(width, readable),
    ], preferred);
  }

  /// Shrink only columns with spare space; compact columns never subsidize
  /// prose by becoming one-character-wide. If the floors do not fit, callers
  /// place the resulting table in a horizontal scroll view.
  List<double> resolve(double availableWidth) {
    final preferred = preferredWidths.fold(0.0, (sum, width) => sum + width);
    if (!availableWidth.isFinite || availableWidth >= preferred) {
      return List<double>.of(preferredWidths);
    }
    // At very large text scales even one readable floor can exceed the
    // viewport. Let that column fit on screen so focus can reveal it in full;
    // the other columns still remain horizontally scrollable.
    final minimums = [
      for (final width in minimumWidths)
        math.min(width, math.max(44.0, availableWidth)),
    ];
    final minimum = minimums.fold(0.0, (sum, width) => sum + width);
    if (availableWidth <= minimum) return minimums;
    final fraction = (availableWidth - minimum) / (preferred - minimum);
    return [
      for (var column = 0; column < preferredWidths.length; column++)
        minimums[column] +
            (preferredWidths[column] - minimums[column]) * fraction,
    ];
  }
}

/// Retains measurements across parent rebuilds and viewport changes. The
/// renderer may reconstruct AST labels without changing visible table content.
final class MarkdownTableLayout extends StatefulWidget {
  const MarkdownTableLayout({
    super.key,
    required this.rows,
    required this.bodyStyle,
    required this.headerStyle,
    required this.textScaler,
    required this.textDirection,
    required this.horizontalPadding,
    required this.builder,
    this.headerHorizontalPadding,
    this.locale,
    this.spans,
    this.extraWidths,
    this.horizontalInset = 0,
  });

  final List<List<String>> rows;
  final TextStyle bodyStyle;
  final TextStyle headerStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final double horizontalPadding;
  final double? headerHorizontalPadding;
  final Locale? locale;
  final List<List<InlineSpan>>? spans;
  final List<List<double>>? extraWidths;
  final double horizontalInset;
  final Widget Function(BuildContext context, List<double> widths) builder;

  @override
  State<MarkdownTableLayout> createState() => _MarkdownTableLayoutState();
}

final class _MarkdownTableLayoutState extends State<MarkdownTableLayout> {
  late MarkdownTableMetrics _metrics;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(MarkdownTableLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bodyStyle != widget.bodyStyle ||
        oldWidget.headerStyle != widget.headerStyle ||
        oldWidget.textScaler != widget.textScaler ||
        oldWidget.textDirection != widget.textDirection ||
        oldWidget.locale != widget.locale ||
        oldWidget.horizontalPadding != widget.horizontalPadding ||
        oldWidget.headerHorizontalPadding != widget.headerHorizontalPadding ||
        !_sameRows(oldWidget.rows, widget.rows) ||
        !_sameRows(oldWidget.spans, widget.spans) ||
        !_sameRows(oldWidget.extraWidths, widget.extraWidths)) {
      _measure();
    }
  }

  void _measure() {
    _metrics = MarkdownTableMetrics.measure(
      rows: widget.rows,
      bodyStyle: widget.bodyStyle,
      headerStyle: widget.headerStyle,
      textScaler: widget.textScaler,
      textDirection: widget.textDirection,
      horizontalPadding: widget.horizontalPadding,
      headerHorizontalPadding: widget.headerHorizontalPadding,
      locale: widget.locale,
      spans: widget.spans,
      extraWidths: widget.extraWidths,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => widget.builder(
      context,
      _metrics.resolve(constraints.maxWidth - widget.horizontalInset),
    ),
  );
}

bool _sameRows<T>(List<List<T>>? left, List<List<T>>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var row = 0; row < left.length; row++) {
    if (!listEquals(left[row], right[row])) return false;
  }
  return true;
}
