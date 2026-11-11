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
    final selection = widget.controller.selection;
    final start = (selection.start - block.start).clamp(0, block.source.length);
    final end = (selection.end - block.start).clamp(0, block.source.length);
    // Keep this wrapper mounted while selection changes. Reparenting keyed
    // table fields during sliver layout can detach their selection overlays.
    return _RenderedSelectionSurface(
      source: block.source,
      linkReferenceLabels: _linkReferences.labels,
      range: _usesRenderedSelection
          ? TextRange(start: start, end: end)
          : TextRange.empty,
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
    required this.linkReferenceLabels,
    required this.color,
    required super.child,
  });
  final String source;
  final Set<String> linkReferenceLabels;
  final TextRange range;
  final Color color;
  @override
  _RenderSelectionSurface createRenderObject(BuildContext context) =>
      _RenderSelectionSurface(source, range, color, linkReferenceLabels);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectionSurface object,
  ) {
    object
      ..source = source
      ..linkReferenceLabels = linkReferenceLabels
      ..range = range
      ..color = color
      ..markNeedsPaint();
  }
}

class _RenderSelectionSurface extends RenderProxyBox {
  _RenderSelectionSurface(
    this.source,
    this.range,
    this.color,
    this.linkReferenceLabels,
  );
  String source;
  Set<String> linkReferenceLabels;
  String? _mappedSource;
  Set<String>? _mappedLabels;
  _RenderedSourceMapping? _mapping;
  TextRange range;
  Color color;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!range.isValid || range.isCollapsed) return;
    if (_mappedSource != source ||
        !setEquals(_mappedLabels, linkReferenceLabels)) {
      _mapping = _RenderedSourceMapping(
        source,
        linkReferenceLabels: linkReferenceLabels,
      );
      _mappedSource = source;
      _mappedLabels = Set.of(linkReferenceLabels);
    }
    final mapping = _mapping!..reset();
    void paintFragment(RenderBox object, String text, int textOffset) {
      final offsets = mapping.consume(text);
      var from = -1, to = -1;
      for (var i = 0; i < offsets.length; i++) {
        if (offsets[i] >= range.start && offsets[i] < range.end) {
          if (from < 0) from = i;
          to = i + 1;
        }
      }
      if (from >= 0) {
        final selection = TextSelection(
          baseOffset: textOffset + from,
          extentOffset: textOffset + to,
        );
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
    }

    if (child != null) {
      for (final fragment in _renderedTextFragments(child!)) {
        paintFragment(fragment.object, fragment.text, fragment.offset);
      }
    }
  }
}

// Visit WidgetSpan children in text order. Parent text contains only a single
// placeholder for these children, including links with their own text layout.
Iterable<_RenderedTextFragment> _renderedTextFragments(
  RenderObject object,
) sync* {
  final String? text = switch (object) {
    RenderEditable e => e.text?.toPlainText(includeSemanticsLabels: false),
    RenderParagraph p => p.text.toPlainText(includeSemanticsLabels: false),
    _ => null,
  };
  if (text != null && object is RenderBox && object.hasSize) {
    RenderBox? inlineChild = switch (object) {
      RenderEditable e => e.firstChild,
      RenderParagraph p => p.firstChild,
      _ => null,
    };
    var offset = 0;
    for (final fragment in text.split('\uFFFC')) {
      if (fragment.isNotEmpty) {
        yield _RenderedTextFragment(object, fragment, offset);
      }
      offset += fragment.length + 1;
      if (offset <= text.length && inlineChild != null) {
        yield* _renderedTextFragments(inlineChild);
        inlineChild = (inlineChild.parentData! as TextParentData).nextSibling;
      }
    }
    return;
  }
  final children = <RenderObject>[];
  object.visitChildren(children.add);
  for (final child in children) {
    yield* _renderedTextFragments(child);
  }
}

class _RenderedTextFragment {
  const _RenderedTextFragment(this.object, this.text, this.offset);
  final RenderBox object;
  final String text;
  final int offset;

  List<TextBox> get boxes {
    final selection = TextSelection(
      baseOffset: offset,
      extentOffset: offset + text.length,
    );
    return switch (object) {
      RenderEditable e => e.getBoxesForSelection(selection),
      RenderParagraph p => p.getBoxesForSelection(selection),
      _ => const [],
    };
  }

  int positionAt(Offset point) => switch (object) {
    RenderEditable e => e.getPositionForPoint(point).offset,
    RenderParagraph p => p.getPositionForOffset(p.globalToLocal(point)).offset,
    _ => offset,
  };
}

// Use the same recognized visible source ranges as the source editor. Hidden
// destinations, titles and formatting markers must never consume visible text.
class _RenderedSourceMapping {
  _RenderedSourceMapping(String source, {Set<String>? linkReferenceLabels}) {
    final visible = StringBuffer();
    for (final range in markdownInlineVisibleSourceRanges(
      source,
      linkReferenceLabels: linkReferenceLabels,
    )) {
      visible.write(range.textInside(source));
      for (var i = range.start; i < range.end; i++) {
        _offsets.add(i);
      }
    }
    _visible = visible.toString();
  }

  late final String _visible;
  final _offsets = <int>[];
  var _cursor = 0;

  void reset() => _cursor = 0;

  List<int> consume(String text) {
    final result = <int>[];
    var position = _cursor;
    for (var i = 0; i < text.length; i++) {
      final next = _visible.indexOf(text[i], position);
      if (next < 0) return const [];
      result.add(_offsets[next]);
      position = next + 1;
    }
    _cursor = position;
    return result;
  }
}
