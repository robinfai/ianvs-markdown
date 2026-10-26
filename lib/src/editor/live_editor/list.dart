part of '../live_editor.dart';

bool _isListBlock(IanvsMarkdownBlock block) => switch (block.type) {
  IanvsMarkdownBlockType.taskList ||
  IanvsMarkdownBlockType.unorderedList ||
  IanvsMarkdownBlockType.orderedList => true,
  _ => false,
};

class _LiveListFoldFrame extends StatefulWidget {
  const _LiveListFoldFrame({
    required this.blockStart,
    required this.colors,
    required this.foldable,
    required this.collapsed,
    required this.onToggle,
    required this.child,
  });

  final int blockStart;
  final IanvsMarkdownThemeData colors;
  final bool foldable;
  final bool collapsed;
  final VoidCallback onToggle;
  final Widget child;

  @override
  State<_LiveListFoldFrame> createState() => _LiveListFoldFrameState();
}

class _LiveListFoldFrameState extends State<_LiveListFoldFrame> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final mobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final visible = _hovering || widget.collapsed || mobile;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 20),
              child: widget.collapsed
                  ? _ListFoldEllipsis(
                      color: widget.colors.textTertiary,
                      child: IanvsMarkdownListMarkerColor(
                        color: widget.colors.accent,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 24),
                          child: widget.child,
                        ),
                      ),
                    )
                  : widget.child,
            ),
            if (widget.foldable)
              PositionedDirectional(
                start: 20,
                top: 3,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  alwaysIncludeSemantics: true,
                  child: IconButton(
                    key: ValueKey(
                      'ianvs-markdown-list-fold-${widget.blockStart}',
                    ),
                    tooltip:
                        (widget.collapsed
                                ? IanvsMarkdownMessage.expandList
                                : IanvsMarkdownMessage.collapseList)
                            .resolve(context),
                    onPressed: widget.onToggle,
                    style: const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    color: widget.collapsed
                        ? widget.colors.accent
                        : widget.colors.textTertiary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 20,
                      height: 23,
                    ),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      widget.collapsed
                          ? (Directionality.of(context) == TextDirection.rtl
                                ? Icons.keyboard_arrow_left_rounded
                                : Icons.keyboard_arrow_right_rounded)
                          : Icons.keyboard_arrow_down_rounded,
                      size: 17,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListFoldEllipsis extends SingleChildRenderObjectWidget {
  const _ListFoldEllipsis({required this.color, required super.child});
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderListFoldEllipsis(
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
          color: color,
          fontSize: 14,
        ),
        Directionality.of(context),
        MediaQuery.textScalerOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderListFoldEllipsis renderObject,
  ) {
    renderObject
      ..textStyle =
          (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
              .copyWith(color: color, fontSize: 14)
      ..textScaler = MediaQuery.textScalerOf(context)
      ..direction = Directionality.of(context)
      ..markNeedsPaint();
  }
}

class _RenderListFoldEllipsis extends RenderProxyBox {
  _RenderListFoldEllipsis(this.textStyle, this.direction, this.textScaler);
  TextStyle textStyle;
  TextScaler textScaler;
  TextDirection direction;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    Offset? end;
    double lineHeight = 20;
    void visit(RenderObject object) {
      if (object is RenderBox && object.hasSize) {
        Rect? caret;
        if (object is RenderEditable) {
          caret = object.getLocalRectForCaret(
            TextPosition(offset: object.text?.toPlainText().length ?? 0),
          );
        } else if (object is RenderParagraph) {
          final text = object.text.toPlainText();
          if (text.isNotEmpty) {
            final boxes = object.getBoxesForSelection(
              TextSelection(
                baseOffset: text.length - 1,
                extentOffset: text.length,
              ),
            );
            if (boxes.isNotEmpty) {
              final box = boxes.last;
              caret = Rect.fromLTWH(
                direction == TextDirection.ltr ? box.right : box.left,
                box.top,
                0,
                box.bottom - box.top,
              );
            }
          }
        }
        if (caret != null) {
          end = object.localToGlobal(caret.topLeft, ancestor: this);
          lineHeight = caret.height;
        }
      }
      object.visitChildren(visit);
    }

    if (child != null) visit(child!);
    if (end == null) return;
    final painter = TextPainter(
      text: TextSpan(text: '…', style: textStyle),
      textDirection: direction,
      textScaler: textScaler,
    )..layout();
    final x = direction == TextDirection.ltr
        ? end!.dx + 8
        : end!.dx - painter.width - 8;
    painter.paint(
      context.canvas,
      offset +
          Offset(
            x.clamp(0, math.max(0, size.width - painter.width)),
            end!.dy + (lineHeight - painter.height) / 2,
          ),
    );
    painter.dispose();
  }
}
