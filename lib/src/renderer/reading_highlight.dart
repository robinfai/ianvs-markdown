import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A semantic text flow and the literal ranges to paint within it.
class MarkdownReadingHighlightFlow {
  const MarkdownReadingHighlightFlow({
    required this.text,
    required this.ranges,
    this.activeRange,
  });
  final String text;
  final List<TextRange> ranges;
  final TextRange? activeRange;
}

/// Paint-only search decoration: leaves selection, focus and semantics intact.
class MarkdownReadingHighlightOverlay extends StatefulWidget {
  const MarkdownReadingHighlightOverlay({
    super.key,
    required this.flows,
    required this.child,
    this.sourceText,
    this.sourceRanges,
  });
  final List<MarkdownReadingHighlightFlow> flows;
  final Widget child;
  final String? sourceText;
  final List<TextRange>? sourceRanges;
  @override
  State<MarkdownReadingHighlightOverlay> createState() => _HighlightState();
}

class _HighlightState extends State<MarkdownReadingHighlightOverlay> {
  final _surfaceKey = GlobalKey();
  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _surfaceKey.currentContext?.findRenderObject()?.markNeedsPaint();
          return false;
        },
        child: _HighlightSurface(
          key: _surfaceKey,
          flows: widget.flows,
          sourceText: widget.sourceText,
          sourceRanges: widget.sourceRanges,
          child: widget.child,
        ),
      );
}

class _HighlightSurface extends SingleChildRenderObjectWidget {
  const _HighlightSurface({
    super.key,
    required this.flows,
    required super.child,
    this.sourceText,
    this.sourceRanges,
  });
  final List<MarkdownReadingHighlightFlow> flows;
  final String? sourceText;
  final List<TextRange>? sourceRanges;
  @override
  RenderMarkdownReadingHighlight createRenderObject(BuildContext context) =>
      RenderMarkdownReadingHighlight(flows)
        ..sourceText = sourceText
        ..sourceRanges = sourceRanges;
  @override
  void updateRenderObject(
    BuildContext context,
    RenderMarkdownReadingHighlight renderObject,
  ) {
    renderObject
      ..sourceText = sourceText
      ..sourceRanges = sourceRanges
      ..flows = flows;
  }
}

class RenderMarkdownReadingHighlight extends RenderProxyBox {
  RenderMarkdownReadingHighlight(this._flows);
  List<MarkdownReadingHighlightFlow> _flows;
  String? sourceText;
  List<TextRange>? sourceRanges;
  set flows(List<MarkdownReadingHighlightFlow> value) {
    if (identical(value, _flows)) return;
    _flows = value;
    markNeedsPaint();
  }

  /// Coordinates are local to this block; recomputed after layout/reflow.
  Rect? get activeRect {
    Rect? result;
    _visitBoxes((rect, active, target, localRect) {
      if (active) {
        result = result == null ? rect : result!.expandToInclude(rect);
      }
    });
    return result;
  }

  void _visitBoxes(
    void Function(Rect rect, bool active, RenderBox target, Rect localRect)
    visit,
  ) {
    final cursors = List<int>.filled(_flows.length, 0);
    void paintFragment(RenderBox paragraph, String text, int offset) {
      if (text.isEmpty) return;
      for (var i = 0; i < _flows.length; i++) {
        final flow = _flows[i];
        final start = flow.text.indexOf(text, cursors[i]);
        if (start < 0) continue;
        cursors[i] = start + text.length;
        for (final range in flow.ranges) {
          final from = (range.start - start).clamp(0, text.length);
          final to = (range.end - start).clamp(0, text.length);
          if (from >= to) continue;
          final selection = TextSelection(
            baseOffset: offset + from,
            extentOffset: offset + to,
          );
          final boxes = switch (paragraph) {
            RenderParagraph p => p.getBoxesForSelection(selection),
            RenderEditable e => e.getBoxesForSelection(selection),
            _ => const <TextBox>[],
          };
          for (final box in boxes) {
            final rect = MatrixUtils.transformRect(
              paragraph.getTransformTo(this),
              box.toRect(),
            );
            visit(rect, range == flow.activeRange, paragraph, box.toRect());
          }
        }
        break;
      }
    }

    void walk(RenderObject object) {
      if (object is RenderParagraph && object.hasSize && object.attached) {
        final text = object.text.toPlainText(includeSemanticsLabels: false);
        final children = <RenderObject>[];
        object.visitChildren(children.add);
        var offset = 0;
        var childIndex = 0;
        // WidgetSpan occupies one layout character but its child contributes
        // actual visible text. Visit it between the surrounding text fragments.
        for (final fragment in text.split('\uFFFC')) {
          paintFragment(object, fragment, offset);
          offset += fragment.length + 1;
          if (offset <= text.length && childIndex < children.length) {
            walk(children[childIndex++]);
          }
        }
        return;
      }
      if (object is RenderEditable && object.hasSize && object.attached) {
        final text =
            object.text?.toPlainText(includeSemanticsLabels: false) ?? '';
        if (text == sourceText && sourceRanges != null) {
          for (final range in sourceRanges!) {
            paintFragment(
              object,
              text.substring(range.start, range.end),
              range.start,
            );
          }
        } else {
          final children = <RenderObject>[];
          object.visitChildren(children.add);
          var offset = 0;
          var childIndex = 0;
          void span(InlineSpan inline, TextStyle inherited) {
            if (inline is WidgetSpan) {
              if (childIndex < children.length) walk(children[childIndex++]);
              offset++;
            } else if (inline is TextSpan) {
              final style = inherited.merge(inline.style);
              final value = inline.text ?? '';
              if (style.color?.a != 0) paintFragment(object, value, offset);
              offset += value.length;
              for (final child in inline.children ?? const <InlineSpan>[]) {
                span(child, style);
              }
            }
          }

          if (object.text != null) span(object.text!, const TextStyle());
        }
        return;
      }
      object.visitChildren(walk);
    }

    if (child != null) walk(child!);
  }

  /// Reveal text inside nested scrollable code surfaces as well as the page.
  void revealActiveText() {
    _visitBoxes((rect, active, target, localRect) {
      if (active) target.showOnScreen(rect: localRect, duration: Duration.zero);
    });
  }

  Rect _clipToAncestors(Rect rect, RenderBox target) {
    RenderObject current = target;
    while (current != this && current.parent != null) {
      final parent = current.parent!;
      final clip = parent.describeApproximatePaintClip(current);
      if (clip != null) {
        rect = rect.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(this), clip),
        );
      }
      current = parent;
    }
    return rect;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Foreground paint remains visible over opaque code/callout backgrounds.
    // Translucency preserves syntax colors and text selection underneath.
    super.paint(context, offset);
    _visitBoxes((rect, active, target, localRect) {
      final clipped = _clipToAncestors(rect, target);
      if (clipped.isEmpty) return;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(
          clipped.shift(offset),
          const Radius.circular(2),
        ),
        Paint()
          ..color = active ? const Color(0x99ff9800) : const Color(0x66ffdf00),
      );
    });
  }
}
