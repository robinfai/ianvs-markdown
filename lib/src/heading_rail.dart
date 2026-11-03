import 'package:flutter/widgets.dart';

/// Paints the heading accent in the host's document margin without indenting
/// text or changing its line width. Hosts provide at least 10 logical px margin.
class MarkdownHeadingRail extends StatelessWidget {
  const MarkdownHeadingRail({
    super.key,
    required this.color,
    required this.child,
  });
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _HeadingRailPainter(color), child: child);
}

class _HeadingRailPainter extends CustomPainter {
  const _HeadingRailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(-10, 0, 2, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_HeadingRailPainter oldDelegate) =>
      oldDelegate.color != color;
}
