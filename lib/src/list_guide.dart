import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Border-theme shapes used for unordered-list nesting levels.
enum IanvsMarkdownUnorderedListMarkerShape { circle, square, diamond, ring }

/// Paints the compact unordered-list marker used by Obsidian's Border theme.
///
/// Source markers (`-`, `*`, and `+`) share the same visual shape. The first
/// three nesting levels are a filled circle, square, and diamond; deeper
/// levels use Border's hollow circular fallback.
class IanvsMarkdownUnorderedListMarker extends StatelessWidget {
  const IanvsMarkdownUnorderedListMarker({
    super.key,
    required this.nestLevel,
    required this.color,
    this.fontSize = 14.5,
    this.height = 1.58,
  });

  final int nestLevel;
  final Color color;
  final double fontSize;
  final double height;

  IanvsMarkdownUnorderedListMarkerShape get shape => switch (nestLevel) {
    0 => IanvsMarkdownUnorderedListMarkerShape.circle,
    1 => IanvsMarkdownUnorderedListMarkerShape.square,
    2 => IanvsMarkdownUnorderedListMarkerShape.diamond,
    _ => IanvsMarkdownUnorderedListMarkerShape.ring,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fontSize,
      child: CustomPaint(
        painter: _IanvsMarkdownUnorderedListMarkerPainter(
          shape: shape,
          color: color,
          fontSize: fontSize,
        ),
        // Retain text-line metrics and a baseline for the Markdown list row.
        child: Text(
          '\u2007',
          style: TextStyle(
            color: const Color(0x00000000),
            fontSize: fontSize,
            height: height,
          ),
        ),
      ),
    );
  }
}

class _IanvsMarkdownUnorderedListMarkerPainter extends CustomPainter {
  const _IanvsMarkdownUnorderedListMarkerPainter({
    required this.shape,
    required this.color,
    required this.fontSize,
  });

  final IanvsMarkdownUnorderedListMarkerShape shape;
  final Color color;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final bulletSize = fontSize * .3;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    switch (shape) {
      case IanvsMarkdownUnorderedListMarkerShape.circle:
        canvas.drawCircle(center, bulletSize / 2, paint);
      case IanvsMarkdownUnorderedListMarkerShape.square:
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: bulletSize,
            height: bulletSize,
          ),
          paint,
        );
      case IanvsMarkdownUnorderedListMarkerShape.diamond:
        final radius = bulletSize / 1.4142135623730951;
        final path = Path()
          ..moveTo(center.dx, center.dy - radius)
          ..lineTo(center.dx + radius, center.dy)
          ..lineTo(center.dx, center.dy + radius)
          ..lineTo(center.dx - radius, center.dy)
          ..close();
        canvas.drawPath(path, paint);
      case IanvsMarkdownUnorderedListMarkerShape.ring:
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = bulletSize / 2;
        canvas.drawCircle(center, bulletSize / 2, paint);
    }
  }

  @override
  bool shouldRepaint(
    covariant _IanvsMarkdownUnorderedListMarkerPainter oldDelegate,
  ) {
    return shape != oldDelegate.shape ||
        color != oldDelegate.color ||
        fontSize != oldDelegate.fontSize;
  }
}

/// One painted Border/Obsidian indentation-guide segment.
typedef IanvsMarkdownListGuideSegment = ({Offset start, Offset end, int level});

/// Paints list indentation guides behind descendant list-marker anchors.
///
/// Obsidian positions a one-pixel guide on the parent marker gutter whenever a
/// list contains nested items. Keeping the guide at this shared render surface
/// lets it connect list items that Live Preview renders as separate blocks.
class IanvsMarkdownListGuideSurface extends SingleChildRenderObjectWidget {
  const IanvsMarkdownListGuideSurface({
    super.key,
    required this.color,
    required this.indent,
    required this.textDirection,
    this.width = 1,
    super.child,
  });

  final Color color;
  final double indent;
  final double width;
  final TextDirection textDirection;

  @override
  IanvsMarkdownListGuideRenderBox createRenderObject(BuildContext context) {
    return IanvsMarkdownListGuideRenderBox(color, indent, width, textDirection);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    IanvsMarkdownListGuideRenderBox renderObject,
  ) {
    renderObject
      ..color = color
      ..indent = indent
      ..width = width
      ..textDirection = textDirection;
  }
}

/// Marks the rendered list-marker gutter and its absolute nesting level.
class IanvsMarkdownListGuideAnchor extends SingleChildRenderObjectWidget {
  const IanvsMarkdownListGuideAnchor({
    super.key,
    required this.nestLevel,
    required super.child,
  });

  final int nestLevel;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return IanvsMarkdownListGuideAnchorRenderBox(nestLevel);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    IanvsMarkdownListGuideAnchorRenderBox renderObject,
  ) {
    renderObject.nestLevel = nestLevel;
  }
}

/// Render box exposed for geometry-focused widget tests.
class IanvsMarkdownListGuideRenderBox extends RenderProxyBox {
  IanvsMarkdownListGuideRenderBox(
    this._color,
    this._indent,
    this._width,
    this._textDirection,
  );

  Color _color;
  double _indent;
  double _width;
  TextDirection _textDirection;

  Color get color => _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  double get indent => _indent;
  set indent(double value) {
    if (value == _indent) return;
    _indent = value;
    markNeedsPaint();
  }

  double get width => _width;
  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsPaint();
  }

  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsPaint();
  }

  @visibleForTesting
  List<IanvsMarkdownListGuideSegment> debugGuideSegments() {
    if (child == null || !hasSize || indent <= 0) {
      return const <IanvsMarkdownListGuideSegment>[];
    }
    final anchors = <_MeasuredListGuideAnchor>[];
    void collect(RenderObject renderObject) {
      // A host-supplied embed can contain its own IanvsMarkdown. Its guide
      // surface owns that document boundary and must not be painted twice or
      // connected to markers in the surrounding document.
      if (renderObject is IanvsMarkdownListGuideRenderBox) return;
      if (renderObject is IanvsMarkdownListGuideAnchorRenderBox &&
          renderObject.hasSize) {
        final anchorRect = MatrixUtils.transformRect(
          renderObject.getTransformTo(this),
          Offset.zero & renderObject.size,
        );
        anchors.add(
          _MeasuredListGuideAnchor(
            nestLevel: renderObject.nestLevel,
            anchorRect: anchorRect,
            itemRect: _listItemRect(renderObject) ?? anchorRect,
          ),
        );
      }
      renderObject.visitChildren(collect);
    }

    child!.visitChildren(collect);
    anchors.sort((left, right) {
      final vertical = left.anchorRect.top.compareTo(right.anchorRect.top);
      if (vertical != 0) return vertical;
      return switch (textDirection) {
        TextDirection.ltr => left.anchorRect.left.compareTo(
          right.anchorRect.left,
        ),
        TextDirection.rtl => right.anchorRect.right.compareTo(
          left.anchorRect.right,
        ),
      };
    });
    if (anchors.length < 2 &&
        (anchors.isEmpty || anchors.single.nestLevel == 0)) {
      return const <IanvsMarkdownListGuideSegment>[];
    }

    final segments = <IanvsMarkdownListGuideSegment>[];
    double guideX(_MeasuredListGuideAnchor anchor, int level) {
      return switch (textDirection) {
        TextDirection.ltr =>
          anchor.itemRect.left +
              indent / 2 -
              indent * (anchor.nestLevel - level),
        TextDirection.rtl =>
          anchor.itemRect.right -
              indent / 2 +
              indent * (anchor.nestLevel - level),
      };
    }

    for (var index = 0; index < anchors.length; index += 1) {
      final anchor = anchors[index];
      for (var level = 0; level < anchor.nestLevel; level += 1) {
        final x = guideX(anchor, level);
        _appendSegment(
          segments,
          level: level,
          x: x,
          top: anchor.itemRect.top,
          bottom: anchor.itemRect.bottom,
        );
      }

      if (index + 1 >= anchors.length) continue;
      final next = anchors[index + 1];
      for (var level = 0; level < next.nestLevel; level += 1) {
        final double top;
        if (anchor.nestLevel > level) {
          top = anchor.itemRect.bottom;
        } else if (anchor.nestLevel == level) {
          top = anchor.anchorRect.bottom;
        } else {
          continue;
        }
        _appendSegment(
          segments,
          level: level,
          x: guideX(next, level),
          top: top,
          bottom: next.itemRect.top,
        );
      }
    }
    return List<IanvsMarkdownListGuideSegment>.unmodifiable(
      _mergeSegments(segments),
    );
  }

  Rect? _listItemRect(IanvsMarkdownListGuideAnchorRenderBox anchor) {
    RenderObject? candidate = anchor.parent;
    while (candidate != null && candidate != this) {
      if (candidate is RenderFlex && candidate.direction == Axis.horizontal) {
        return MatrixUtils.transformRect(
          candidate.getTransformTo(this),
          Offset.zero & candidate.size,
        );
      }
      candidate = candidate.parent;
    }
    return null;
  }

  static void _appendSegment(
    List<IanvsMarkdownListGuideSegment> segments, {
    required int level,
    required double x,
    required double top,
    required double bottom,
  }) {
    if (!x.isFinite || !top.isFinite || !bottom.isFinite) return;
    final start = math.min(top, bottom);
    final end = math.max(top, bottom);
    if (end - start < .5) return;
    segments.add((start: Offset(x, start), end: Offset(x, end), level: level));
  }

  static List<IanvsMarkdownListGuideSegment> _mergeSegments(
    List<IanvsMarkdownListGuideSegment> segments,
  ) {
    if (segments.length < 2) return segments;
    final sorted = List<IanvsMarkdownListGuideSegment>.of(segments)
      ..sort((left, right) {
        final level = left.level.compareTo(right.level);
        if (level != 0) return level;
        final horizontal = left.start.dx.compareTo(right.start.dx);
        if (horizontal != 0) return horizontal;
        return left.start.dy.compareTo(right.start.dy);
      });
    final merged = <IanvsMarkdownListGuideSegment>[];
    for (final segment in sorted) {
      if (merged.isEmpty) {
        merged.add(segment);
        continue;
      }
      final previous = merged.last;
      final sameGuide =
          previous.level == segment.level &&
          (previous.start.dx - segment.start.dx).abs() < .01;
      if (!sameGuide || segment.start.dy > previous.end.dy + .5) {
        merged.add(segment);
        continue;
      }
      merged[merged.length - 1] = (
        start: previous.start,
        end: Offset(previous.end.dx, math.max(previous.end.dy, segment.end.dy)),
        level: previous.level,
      );
    }
    return merged;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    for (final segment in debugGuideSegments()) {
      context.canvas.drawLine(
        offset + segment.start,
        offset + segment.end,
        paint,
      );
    }
    super.paint(context, offset);
  }
}

final class IanvsMarkdownListGuideAnchorRenderBox extends RenderProxyBox {
  IanvsMarkdownListGuideAnchorRenderBox(this._nestLevel);

  int _nestLevel;
  int get nestLevel => _nestLevel;
  set nestLevel(int value) {
    if (value == _nestLevel) return;
    _nestLevel = value;
    RenderObject? candidate = parent;
    while (candidate != null) {
      if (candidate is IanvsMarkdownListGuideRenderBox) {
        candidate.markNeedsPaint();
        break;
      }
      candidate = candidate.parent;
    }
  }
}

final class _MeasuredListGuideAnchor {
  const _MeasuredListGuideAnchor({
    required this.nestLevel,
    required this.anchorRect,
    required this.itemRect,
  });

  final int nestLevel;
  final Rect anchorRect;
  final Rect itemRect;
}
