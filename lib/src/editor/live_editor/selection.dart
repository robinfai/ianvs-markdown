part of '../live_editor.dart';

extension _LiveRenderedSelection on _IanvsMarkdownLiveEditorState {
  bool get _usesRenderedSelection {
    final selection = widget.controller.selection;
    if (!selection.isValid || _activeBlockStart == null) {
      return false;
    }
    if (_renderedDragSelection &&
        (_documentDragActive || !selection.isCollapsed)) {
      return true;
    }
    if (selection.isCollapsed) return false;
    return _blocks
            .where(
              (block) =>
                  block.start < selection.end && block.end > selection.start,
            )
            .take(2)
            .length ==
        2;
  }

  // Keep one source-backed input client for replacement, clipboard and IME.
  // Its layout is deliberately outside the document's scrollable geometry:
  // selecting multiple blocks must never merge their presentation into a field.
  Widget _buildSelectionInput(IanvsMarkdownThemeData colors) {
    _blockController
      ..sourceProjections = const []
      ..hiddenLeadingCharacters = 0
      ..collapsedLeadingCharacters = 0
      ..leadingMarkerCharacters = 0
      ..highlightFencedCode = false;
    return Focus(
      key: const ValueKey('ianvs-markdown-active-block'),
      canRequestFocus: false,
      skipTraversal: true,
      // ignore: deprecated_member_use
      onKey: (_, event) => _handleActiveBlockRawKey(event),
      child: TextField(
        key: _activeEditorKey,
        controller: _blockController,
        focusNode: _focusNode,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [_editingFormatter],
        decoration: const InputDecoration.collapsed(hintText: ''),
      ),
    );
  }

  Widget _paintRenderedSelection(IanvsMarkdownBlock block, Widget child) {
    if (!_usesRenderedSelection) return child;
    final selection = widget.controller.selection;
    final start = (selection.start - block.start).clamp(0, block.source.length);
    final end = (selection.end - block.start).clamp(0, block.source.length);
    if (start >= end) return child;
    return _RenderedSelectionSurface(
      source: block.source,
      range: TextRange(start: start, end: end),
      color:
          DefaultSelectionStyle.of(context).selectionColor ??
          Theme.of(context).colorScheme.primary.withValues(alpha: .3),
      child: child,
    );
  }
}

class _RenderedSelectionSurface extends SingleChildRenderObjectWidget {
  const _RenderedSelectionSurface({
    required this.source,
    required this.range,
    required this.color,
    required super.child,
  });
  final String source;
  final TextRange range;
  final Color color;
  @override
  _RenderSelectionSurface createRenderObject(BuildContext context) =>
      _RenderSelectionSurface(source, range, color);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectionSurface object,
  ) {
    object
      ..source = source
      ..range = range
      ..color = color
      ..markNeedsPaint();
  }
}

class _RenderSelectionSurface extends RenderProxyBox {
  _RenderSelectionSurface(this.source, this.range, this.color);
  String source;
  TextRange range;
  Color color;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    var cursor = 0;
    void visit(RenderObject object) {
      final String? text = switch (object) {
        RenderEditable e => e.text?.toPlainText(includeSemanticsLabels: false),
        RenderParagraph p => p.text.toPlainText(includeSemanticsLabels: false),
        _ => null,
      };
      if (text != null &&
          text.isNotEmpty &&
          object is RenderBox &&
          object.hasSize) {
        // Advance monotonically through repeated fragments, retaining Markdown
        // delimiters only in the source model. Selection never changes layout.
        var from = -1, to = -1;
        var position = cursor;
        for (var i = 0; i < text.length; i++) {
          final next = source.indexOf(text[i], position);
          if (next < 0) break;
          if (next >= range.start && next < range.end) {
            if (from < 0) from = i;
            to = i + 1;
          }
          position = next + 1;
        }
        cursor = position;
        if (from >= 0) {
          final selection = TextSelection(baseOffset: from, extentOffset: to);
          final boxes = switch (object) {
            RenderEditable e => e.getBoxesForSelection(selection),
            RenderParagraph p => p.getBoxesForSelection(selection),
            _ => const <TextBox>[],
          };
          for (final box in boxes) {
            var rect = MatrixUtils.transformRect(
              object.getTransformTo(this),
              box.toRect(),
            );
            RenderObject current = object;
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
            context.canvas.drawRect(rect.shift(offset), Paint()..color = color);
          }
        }
        return;
      }
      object.visitChildren(visit);
    }

    if (child != null) visit(child!);
  }
}
