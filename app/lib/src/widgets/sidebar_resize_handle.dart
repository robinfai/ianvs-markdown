import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/workspace_layout.dart';

class SidebarResizeHandle extends StatefulWidget {
  const SidebarResizeHandle({
    super.key,
    required this.width,
    required this.maxWidth,
    required this.onResize,
  });

  final double width;
  final double maxWidth;
  final ValueChanged<double> onResize;

  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle> {
  var _hovered = false;
  var _dragging = false;
  var _dragStartX = 0.0;
  var _dragStartWidth = 0.0;

  double _clamp(double width) =>
      width.clamp(WorkspaceLayout.minSidebarWidth, widget.maxWidth);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Resize sidebar',
      slider: true,
      value: '${widget.width.round()} points',
      increasedValue: '${_clamp(widget.width + 20).round()} points',
      decreasedValue: '${_clamp(widget.width - 20).round()} points',
      onIncrease: widget.width < widget.maxWidth
          ? () => widget.onResize(_clamp(widget.width + 20))
          : null,
      onDecrease: widget.width > WorkspaceLayout.minSidebarWidth
          ? () => widget.onResize(_clamp(widget.width - 20))
          : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: 'Drag to resize sidebar',
          excludeFromSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (details) {
              _dragStartX = details.globalPosition.dx;
              _dragStartWidth = widget.width;
              setState(() => _dragging = true);
            },
            onHorizontalDragUpdate: (details) => widget.onResize(
              _clamp(_dragStartWidth + details.globalPosition.dx - _dragStartX),
            ),
            onHorizontalDragEnd: (_) => setState(() => _dragging = false),
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 2,
                color: _hovered || _dragging
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
