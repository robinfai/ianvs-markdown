import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Internal reading policy. Extending FixedColumnWidth keeps the upstream
/// Markdown renderer's horizontal-scroll path, without querying widget
/// intrinsics. Only already-built plain text is measured; embedded controls
/// retain the bounded fallback even after their first layout.
class ReadingTableColumnWidth extends FixedColumnWidth {
  const ReadingTableColumnWidth({
    required double maximum,
    required this.minimum,
  }) : super(maximum);

  final double minimum;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      maxIntrinsicWidth(cells, containerWidth);

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    var result = minimum;
    for (final cell in cells) {
      final measured = _width(cell);
      if (measured == null) return value;
      result = math.max(result, measured.ceilToDouble() + 1);
      if (result >= value) return value;
    }
    return result.clamp(minimum, value);
  }

  double? _width(RenderObject object) {
    // LayoutBuilder children can appear only after layout. Always fall back,
    // so links never collapse on the second frame or trigger intrinsic errors.
    if (object is RenderAbstractLayoutBuilderMixin) return null;
    if (object is RenderParagraph) {
      return _textWidth(
        object.text,
        object.textDirection,
        object.textScaler,
        object.locale,
      );
    }
    if (object is RenderEditable) {
      final text = object.text;
      if (text == null) return null;
      return _textWidth(
        text,
        object.textDirection,
        object.textScaler,
        object.locale,
      );
    }
    if (object is RenderPadding) {
      final child = object.child;
      if (child == null) return 0;
      final measured = _width(child);
      return measured == null
          ? null
          : measured + object.padding.resolve(object.textDirection).horizontal;
    }
    if (object is RenderWrap || object is RenderFlex) {
      final widths = <double>[];
      var unknown = false;
      object.visitChildren((child) {
        final measured = _width(child);
        if (measured == null) {
          unknown = true;
        } else {
          widths.add(measured);
        }
      });
      if (unknown) return null;
      if (widths.isEmpty) return 0;
      final axis = object is RenderWrap
          ? object.direction
          : (object as RenderFlex).direction;
      final spacing = object is RenderWrap
          ? object.spacing
          : (object as RenderFlex).spacing;
      return axis == Axis.horizontal
          ? widths.reduce((a, b) => a + b) + spacing * (widths.length - 1)
          : widths.reduce(math.max);
    }
    if (object is RenderConstrainedBox) {
      final child = object.child;
      if (child == null) return null;
      final measured = _width(child);
      return measured == null
          ? null
          : object.additionalConstraints.constrainWidth(measured);
    }
    if (object is RenderProxyBox) {
      final child = object.child;
      return child == null ? null : _width(child);
    }
    return null;
  }

  double? _textWidth(
    InlineSpan text,
    TextDirection direction,
    TextScaler scaler,
    Locale? locale,
  ) {
    var hasPlaceholder = text is PlaceholderSpan;
    text.visitChildren((span) {
      hasPlaceholder = hasPlaceholder || span is PlaceholderSpan;
      return !hasPlaceholder;
    });
    if (hasPlaceholder) return null;
    final painter = TextPainter(
      text: text,
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    )..layout();
    try {
      return painter.width;
    } finally {
      painter.dispose();
    }
  }
}
