import 'package:flutter/material.dart';

/// Border-theme 4px code-surface pattern.
///
/// The theme tiles two one-pixel squares on opposite corners of a 4x4 cell.
/// Keeping the pattern as paint instead of a bitmap preserves device-pixel
/// sharpness at every Flutter scale factor.
class IanvsMarkdownCodePatternPainter extends CustomPainter {
  const IanvsMarkdownCodePatternPainter({
    required this.color,
    this.tileSize = 4,
    this.dotSize = 1,
  });

  final Color color;
  final double tileSize;
  final double dotSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || tileSize <= 0 || dotSize <= 0) return;
    paintIanvsMarkdownCodePattern(
      canvas,
      Offset.zero & size,
      color: color,
      tileSize: tileSize,
      dotSize: dotSize,
    );
  }

  @override
  bool shouldRepaint(covariant IanvsMarkdownCodePatternPainter oldDelegate) {
    return color != oldDelegate.color ||
        tileSize != oldDelegate.tileSize ||
        dotSize != oldDelegate.dotSize;
  }
}

void paintIanvsMarkdownCodePattern(
  Canvas canvas,
  Rect rect, {
  required Color color,
  double tileSize = 4,
  double dotSize = 1,
}) {
  if (rect.isEmpty || tileSize <= 0 || dotSize <= 0) return;
  final visibleRect = rect.intersect(canvas.getLocalClipBounds());
  if (visibleRect.isEmpty) return;
  final paint = Paint()
    ..color = color
    ..isAntiAlias = false
    ..style = PaintingStyle.fill;
  final pattern = Path();
  final startX =
      rect.left +
      ((visibleRect.left - rect.left) / tileSize).floor() * tileSize;
  final startY =
      rect.top + ((visibleRect.top - rect.top) / tileSize).floor() * tileSize;
  canvas.save();
  canvas.clipRect(visibleRect);
  for (var y = startY; y < visibleRect.bottom; y += tileSize) {
    for (var x = startX; x < visibleRect.right; x += tileSize) {
      pattern.addRect(
        Rect.fromLTWH(x + dotSize, y + tileSize - dotSize, dotSize, dotSize),
      );
      pattern.addRect(
        Rect.fromLTWH(x + tileSize - dotSize, y + dotSize, dotSize, dotSize),
      );
    }
  }
  canvas.drawPath(pattern, paint);
  canvas.restore();
}

/// Obsidian Border-theme frame used around fenced-code surfaces.
class IanvsMarkdownDashedBorderDecoration extends Decoration {
  const IanvsMarkdownDashedBorderDecoration({
    required this.color,
    required this.radius,
    this.strokeWidth = 1,
    this.dashLength = 3,
    this.gapLength = 3,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _IanvsMarkdownDashedBorderBoxPainter(this);
  }
}

class _IanvsMarkdownDashedBorderBoxPainter extends BoxPainter {
  _IanvsMarkdownDashedBorderBoxPainter(this.decoration);

  final IanvsMarkdownDashedBorderDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final inset = decoration.strokeWidth / 2;
    final rect = (offset & size).deflate(inset);
    if (rect.isEmpty) return;
    final radius = (decoration.radius - inset)
        .clamp(0, double.infinity)
        .toDouble();
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint()
      ..color = decoration.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = decoration.strokeWidth
      ..strokeCap = StrokeCap.butt;
    paintIanvsMarkdownDashedRRect(
      canvas,
      rrect,
      paint,
      dashLength: decoration.dashLength,
      gapLength: decoration.gapLength,
    );
  }
}

void paintIanvsMarkdownDashedRRect(
  Canvas canvas,
  RRect rrect,
  Paint paint, {
  double dashLength = 3,
  double gapLength = 3,
}) {
  if (dashLength <= 0 || gapLength < 0) return;
  final path = Path()..addRRect(rrect);
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final candidateEnd = distance + dashLength;
      final end = candidateEnd < metric.length ? candidateEnd : metric.length;
      canvas.drawPath(metric.extractPath(distance, end), paint);
      distance += dashLength + gapLength;
    }
  }
}
