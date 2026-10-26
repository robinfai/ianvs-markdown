import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Controls visual wrapping of fenced and indented Markdown code blocks.
///
/// Applies to reading previews and Live's active code editor. The default is
/// wrapping, matching the renderer's historical behavior. Source text, line
/// breaks, copy payloads and undo history are unaffected.
class IanvsMarkdownCodeLayout extends InheritedWidget {
  const IanvsMarkdownCodeLayout({
    super.key,
    required super.child,
    this.softWrap = true,
  });

  final bool softWrap;

  static bool softWrapOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<IanvsMarkdownCodeLayout>()
          ?.softWrap ??
      true;

  @override
  bool updateShouldNotify(IanvsMarkdownCodeLayout oldWidget) =>
      oldWidget.softWrap != softWrap;
}

/// Keeps the text child's identity stable when the wrapping preference changes.
class MarkdownCodeViewport extends StatelessWidget {
  const MarkdownCodeViewport({
    super.key,
    required this.text,
    required this.child,
  });

  final InlineSpan text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wrap = IanvsMarkdownCodeLayout.softWrapOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var width = constraints.maxWidth;
        if (!wrap && constraints.hasBoundedWidth) {
          final painter = TextPainter(
            text: text,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          // Leave room for the editable caret at the end of the longest line.
          width = math.max(width, painter.width.ceilToDouble() + 4);
          painter.dispose();
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: wrap ? const NeverScrollableScrollPhysics() : null,
          child: SizedBox(width: width.isFinite ? width : null, child: child),
        );
      },
    );
  }
}
