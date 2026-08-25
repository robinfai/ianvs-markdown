import 'package:flutter/material.dart';

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
