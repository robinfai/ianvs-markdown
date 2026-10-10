part of '../live_editor.dart';

enum _RenderedTapSelection { caret, word, line }

String _referenceDefinitionProjectionSource(
  MarkdownLinkReferenceDefinition definition,
) {
  final title = definition.title?.trim();
  final projection = StringBuffer()
    ..write(_escapeReferenceDefinitionText(definition.label))
    ..write(' [')
    ..write(_escapeReferenceDefinitionText(definition.destination))
    ..write('](<')
    ..write(_escapeReferenceDefinitionDestination(definition.destination))
    ..write('>)');
  if (title != null && title.isNotEmpty) {
    projection
      ..write(' ')
      ..write(_escapeReferenceDefinitionText(title));
  }
  return projection.toString();
}

String _escapeReferenceDefinitionText(String source) => source.replaceAllMapped(
  RegExp(r'([\\`*_\[\]{}()<>#+\-.!|~=])'),
  (match) => '\\${match.group(1)}',
);

String _escapeReferenceDefinitionDestination(String source) =>
    source.replaceAll(r'\', r'\\').replaceAll('>', r'\>');

extension _LiveEditorSourceProjection on _IanvsMarkdownLiveEditorState {
  int? _documentOffsetAtActivePoint(Offset globalPosition) {
    final editable = _activeRenderEditable();
    if (editable == null || !editable.attached || !editable.hasSize) {
      return null;
    }
    final local = editable.globalToLocal(globalPosition);
    if (local.dy < -1 || local.dy > editable.size.height + 1) return null;
    final position = editable.getPositionForPoint(globalPosition);
    return (_editingStart + position.offset).clamp(
      0,
      widget.controller.text.length,
    );
  }

  int? _indentedCodeDocumentOffsetAtRenderedPoint(
    IanvsMarkdownBlock block,
    Offset globalPosition,
  ) {
    final root = _renderedBlockTapKeys[block.start]?.currentContext
        ?.findRenderObject();
    if (root == null || !root.attached) return null;
    final editables = <RenderEditable>[];
    void collect(RenderObject child) {
      if (child is RenderEditable && child.readOnly) {
        editables.add(child);
        return;
      }
      child.visitChildren(collect);
    }

    root.visitChildren(collect);
    var editableIndex = 0;
    var lineStart = 0;
    for (final line in block.source.split('\n')) {
      if (line.isNotEmpty && editableIndex < editables.length) {
        final editable = editables[editableIndex];
        editableIndex += 1;
        if (editable.attached && editable.hasSize) {
          final local = editable.globalToLocal(globalPosition);
          if (local.dy >= -1 && local.dy <= editable.size.height + 1) {
            final content = _indentedCodeContentLine(line);
            final prefixLength = line.length - content.length;
            final position = editable.getPositionForPoint(globalPosition);
            final visibleOffset = position.offset.clamp(0, content.length);
            return block.start + lineStart + prefixLength + visibleOffset;
          }
        }
      }
      lineStart += line.length + 1;
    }
    return null;
  }

  int? _projectedDocumentOffsetAtRenderedPoint(
    IanvsMarkdownBlock block,
    Offset globalPosition,
  ) {
    final literalOffset = _literalProjectionDocumentOffsetAtRenderedPoint(
      block,
      globalPosition,
    );
    if (literalOffset != null) return literalOffset;
    if (block.type == IanvsMarkdownBlockType.indentedCode) {
      return _indentedCodeDocumentOffsetAtRenderedPoint(block, globalPosition);
    }
    if (block.type == IanvsMarkdownBlockType.blockquote ||
        block.type == IanvsMarkdownBlockType.heading) {
      return _markdownProjectionDocumentOffsetAtRenderedPoint(
        block,
        globalPosition,
      );
    }
    final definition = _livePreviewFootnoteDefinition(block.source);
    if (definition == null) return null;
    final root = _renderedBlockTapKeys[block.start]?.currentContext
        ?.findRenderObject();
    if (root == null || !root.attached) return null;
    final editables = <RenderEditable>[];
    void collect(RenderObject child) {
      if (child is RenderEditable && child.readOnly) {
        editables.add(child);
        return;
      }
      child.visitChildren(collect);
    }

    root.visitChildren(collect);
    for (final editable in editables) {
      if (!editable.attached || !editable.hasSize) continue;
      final local = editable.globalToLocal(globalPosition);
      if (local.dy < -1 || local.dy > editable.size.height + 1) continue;
      final visibleText = editable.text?.toPlainText() ?? '';
      final visibleOffset = editable
          .getPositionForPoint(globalPosition)
          .offset
          .clamp(0, visibleText.length);
      final localSourceOffset = definition.sourceOffsetForVisibleOffset(
        visibleText,
        visibleOffset,
      );
      if (localSourceOffset != null) {
        return block.start + localSourceOffset;
      }
    }
    return null;
  }

  int? _literalProjectionDocumentOffsetAtRenderedPoint(
    IanvsMarkdownBlock block,
    Offset globalPosition,
  ) {
    // Exact literal projection is needed for raw HTML that Obsidian leaves
    // visible in Live Preview. Plain paragraphs keep the native activation
    // path so their deferred caret and keyboard-selection ordering is intact.
    if (!block.source.contains('<') || !block.source.contains('>')) {
      return null;
    }
    final root = _renderedBlockTapKeys[block.start]?.currentContext
        ?.findRenderObject();
    if (root == null || !root.attached) return null;
    final editables = <RenderEditable>[];
    void collect(RenderObject child) {
      if (child is RenderEditable && child.readOnly) {
        editables.add(child);
        return;
      }
      child.visitChildren(collect);
    }

    root.visitChildren(collect);
    for (final editable in editables) {
      if (!editable.attached || !editable.hasSize) continue;
      final visibleText = editable.text?.toPlainText() ?? '';
      if (visibleText != block.source) continue;
      final local = editable.globalToLocal(globalPosition);
      if (local.dy < -1 || local.dy > editable.size.height + 1) continue;
      final visibleOffset = editable
          .getPositionForPoint(globalPosition)
          .offset
          .clamp(0, visibleText.length);
      return block.start + visibleOffset;
    }
    return null;
  }

  int? _markdownProjectionDocumentOffsetAtRenderedPoint(
    IanvsMarkdownBlock block,
    Offset globalPosition,
  ) {
    final root = _renderedBlockTapKeys[block.start]?.currentContext
        ?.findRenderObject();
    if (root == null || !root.attached) return null;
    final editables = <RenderEditable>[];
    void collect(RenderObject child) {
      if (child is RenderEditable && child.readOnly) {
        editables.add(child);
        return;
      }
      child.visitChildren(collect);
    }

    root.visitChildren(collect);
    var sourceSearchStart = 0;
    for (final editable in editables) {
      if (!editable.attached || !editable.hasSize) continue;
      final visibleText = editable.text?.toPlainText() ?? '';
      if (visibleText.isEmpty) continue;
      final visibleSourceStart = _markdownSourceOffsetForRenderedOffset(
        block.source,
        visibleText,
        0,
        sourceSearchStart: sourceSearchStart,
      );
      if (visibleSourceStart == null) continue;
      final visibleSourceEnd = _markdownSourceOffsetForRenderedOffset(
        block.source,
        visibleText,
        visibleText.length,
        sourceSearchStart: visibleSourceStart,
      );
      final local = editable.globalToLocal(globalPosition);
      if (local.dy >= -1 && local.dy <= editable.size.height + 1) {
        final visibleOffset = editable
            .getPositionForPoint(globalPosition)
            .offset
            .clamp(0, visibleText.length);
        final sourceOffset = _markdownSourceOffsetForRenderedOffset(
          block.source,
          visibleText,
          visibleOffset,
          sourceSearchStart: visibleSourceStart,
        );
        if (sourceOffset != null) return block.start + sourceOffset;
      }
      if (visibleSourceEnd != null) sourceSearchStart = visibleSourceEnd;
    }
    return null;
  }

  IanvsMarkdownBlock? _renderedBlockAtGlobalPoint(Offset globalPosition) {
    for (final block in _blocks) {
      final renderObject = _renderedBlockTapKeys[block.start]?.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        continue;
      }
      final local = renderObject.globalToLocal(globalPosition);
      if ((Offset.zero & renderObject.size).contains(local)) return block;
    }
    return null;
  }

  IanvsMarkdownBlock? _nearestRenderedBlock(Offset globalPosition) {
    IanvsMarkdownBlock? nearest;
    var nearestDistance = double.infinity;
    for (final block in _blocks) {
      final renderObject = _renderedBlockTapKeys[block.start]?.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize ||
          renderObject.size.height == 0) {
        continue;
      }
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      final distance = globalPosition.dy < top
          ? top - globalPosition.dy
          : globalPosition.dy > bottom
          ? globalPosition.dy - bottom
          : 0.0;
      if (distance < nearestDistance) {
        nearest = block;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  TextSelection _hardBreakCaretSelection(
    TextSelection selection,
    String source,
  ) {
    if (!selection.isCollapsed) return selection;
    for (final match in RegExp(r'(?: {2,}|\\)\r?\n').allMatches(source)) {
      if (selection.extentOffset != match.start) continue;
      final lineBreakStart =
          match.end >= 2 && source.codeUnitAt(match.end - 2) == 0x0d
          ? match.end - 2
          : match.end - 1;
      return TextSelection.collapsed(
        offset: lineBreakStart,
        affinity: TextAffinity.downstream,
      );
    }
    return selection;
  }

  TextSelection _escapedEmphasisCaretSelection(
    TextSelection selection,
    String source,
  ) {
    if (!selection.isCollapsed) return selection;
    final caret = selection.extentOffset;
    var hiddenBackslashes = 0;
    for (final match in RegExp(r'\\[*_]').allMatches(source)) {
      if (match.start >= caret) break;
      hiddenBackslashes += 1;
    }
    if (hiddenBackslashes == 0) return selection;
    return TextSelection.collapsed(
      offset: (caret + hiddenBackslashes).clamp(0, source.length),
      affinity: TextAffinity.downstream,
    );
  }

  TextSelection _selectionAtEditablePoint(
    RenderEditable editable,
    Offset globalPosition,
    _RenderedTapSelection selectionKind,
  ) {
    final position = editable.getPositionForPoint(globalPosition);
    return _selectionAtEditablePosition(editable, position, selectionKind);
  }

  TextSelection _selectionAtEditablePosition(
    RenderEditable editable,
    TextPosition position,
    _RenderedTapSelection selectionKind,
  ) {
    final offset = position.offset.clamp(0, _blockController.text.length);
    final TextRange range;
    switch (selectionKind) {
      case _RenderedTapSelection.caret:
        return TextSelection.collapsed(
          offset: offset,
          affinity: position.affinity,
        );
      case _RenderedTapSelection.word:
        final wordRange = editable.getWordBoundary(
          TextPosition(offset: offset),
        );
        final inlineSourceRange = ianvsMarkdownInlineSourceRangeAt(
          _blockController.text,
          wordRange,
          linkReferenceLabels: _linkReferences.labels,
        );
        range = inlineSourceRange ?? wordRange;
        break;
      case _RenderedTapSelection.line:
        range = TextRange(
          start: _lineStartAt(_blockController.text, offset),
          end: _lineEndAt(_blockController.text, offset),
        );
        break;
    }
    return TextSelection(
      baseOffset: range.start.clamp(0, _blockController.text.length),
      extentOffset: range.end.clamp(0, _blockController.text.length),
    );
  }

  int _quoteCaretOffsetForTap(
    IanvsMarkdownBlock block,
    Offset position,
    Size size,
  ) {
    final lines = _quoteLineLayouts(block.source);
    if (lines.isEmpty || size.height <= 0) return block.end;
    final normalizedY = position.dy.clamp(0.0, size.height);
    final index = ((normalizedY / size.height) * lines.length).floor().clamp(
      0,
      lines.length - 1,
    );
    return block.start + lines[index].line.end;
  }

  int? _quoteMarkerCaretOffsetForTap(
    IanvsMarkdownBlock block,
    Offset position,
    Size size,
  ) {
    // The rendered quote reserves ten outer pixels plus its 27 px rail and
    // inset. Obsidian treats a click in that marker gutter as the position
    // immediately before the raw `>` on the corresponding physical line,
    // including an inner marker for nested quote rails.
    const markerGutterWidth = 37.0;
    if (position.dx < 0 ||
        position.dx > markerGutterWidth ||
        size.height <= 0) {
      return null;
    }
    final lines = _quoteLineLayouts(block.source);
    if (lines.isEmpty) return null;
    final normalizedY = position.dy.clamp(0.0, size.height);
    final index = ((normalizedY / size.height) * lines.length).floor().clamp(
      0,
      lines.length - 1,
    );
    final markers = lines[index].markerRanges;
    if (markers.isEmpty) return block.start + lines[index].line.start;
    const firstRailX = 9.5;
    const nestedRailSpacing = 19.0;
    final markerIndex = ((position.dx - firstRailX) / nestedRailSpacing)
        .round()
        .clamp(0, markers.length - 1);
    return block.start + markers[markerIndex].start;
  }

  Widget _buildReferenceDefinitionProjection(
    List<MarkdownLinkReferenceDefinition> definitions,
    IanvsMarkdownThemeData colors, {
    VoidCallback? onTapText,
  }) {
    final styleSheet =
        widget.styleSheet ?? ianvsMarkdownStyleSheet(context, colors);
    return Column(
      key: const ValueKey('ianvs-markdown-reference-definitions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final definition in definitions)
          IanvsMarkdown(
            data: _referenceDefinitionProjectionSource(definition),
            selectable: true,
            documentSelection: false,
            styleSheet: styleSheet.copyWith(
              blockSpacing: 0,
              pPadding: EdgeInsets.zero,
            ),
            fitContent: true,
            onTapText: onTapText,
            showListIndentationGuides: false,
            softLineBreak: widget.softLineBreak,
            obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
            theme: colors,
          ),
      ],
    );
  }

  String _renderedBlockSource(IanvsMarkdownBlock block) {
    final footnoteReferences = _livePreviewFootnoteReferences
        .where(
          (reference) =>
              reference.sourceRange.start >= block.start &&
              reference.sourceRange.end <= block.end,
        )
        .toList(growable: false);
    final edits = <_LivePreviewRenderingEdit>[
      for (final range in _crossParagraphHighlightLiteralRuns)
        if (range.start >= block.start &&
            range.end <= block.end &&
            !footnoteReferences.any(
              (reference) =>
                  range.start >= reference.sourceRange.start &&
                  range.start < reference.sourceRange.end,
            ))
          _LivePreviewRenderingEdit(
            start: range.start - block.start,
            end: range.start - block.start,
            replacement: r'\',
          ),
    ]..sort((left, right) => right.start.compareTo(left.start));
    var projectedBlock = block.source;
    for (final edit in edits) {
      projectedBlock = projectedBlock.replaceRange(
        edit.start,
        edit.end,
        edit.replacement,
      );
    }
    var source =
        _livePreviewFootnoteDefinition(projectedBlock)?.renderedSource ??
        projectedBlock;
    if (_isEmptyAtxHeadingSource(source)) {
      // Obsidian keeps marker-only ATX prefixes literal in Live Preview. The
      // Markdown renderer otherwise interprets them as empty headings and
      // drops the hashes, so escape only the first marker for display.
      source = source.replaceFirst('#', r'\#');
    }
    source = source
        .split('\n')
        .map((line) {
          final task = RegExp(
            r'^((?:(?:[ \t]{0,3}>[ \t]?)+)?[ \t]*(?:[-+*]|\d{1,9}[.)])[ \t]+\[([^\r\n])\][ \t]+)(.*)$',
          ).firstMatch(line);
          final marker = task?.group(2);
          final content = task?.group(3) ?? '';
          if (task == null ||
              marker == null ||
              !ianvsMarkdownTaskMarkerUsesDoneText(marker) ||
              content.isEmpty ||
              content.startsWith('~~') && content.endsWith('~~')) {
            return line;
          }
          return '${task.group(1)}~~$content~~';
        })
        .join('\n');
    if (block.type == IanvsMarkdownBlockType.unorderedList ||
        block.type == IanvsMarkdownBlockType.orderedList ||
        block.type == IanvsMarkdownBlockType.taskList) {
      // Live Preview projects each nested source item as its own visual row.
      // Outer padding and listNestingOffset carry the structural depth; the
      // standalone Markdown renderer must therefore receive a root marker.
      source = source.replaceFirst(
        RegExp(r'^[ \t]+(?=(?:[-+*]|\d{1,9}[.)])[ \t]+)'),
        '',
      );
    }
    if (block.type == IanvsMarkdownBlockType.fencedCode ||
        block.type == IanvsMarkdownBlockType.indentedCode ||
        block.type == IanvsMarkdownBlockType.displayMath ||
        block.type == IanvsMarkdownBlockType.frontMatter ||
        block.type == IanvsMarkdownBlockType.html) {
      return source;
    }
    return _linkReferences.appendDefinitionsTo(source);
  }
}

final class _QuoteLineLayout {
  const _QuoteLineLayout({
    required this.line,
    required this.markerRanges,
    required this.depth,
  });

  final TextRange line;
  final List<TextRange> markerRanges;
  final int depth;
}

sealed class _SourceProjection {
  const _SourceProjection(this.range);

  final TextRange range;
}

final class _HiddenMarkerSpan extends _SourceProjection {
  const _HiddenMarkerSpan(super.range, this.style);

  final TextStyle style;
}

final class _InlineMathProjection extends _SourceProjection {
  const _InlineMathProjection({
    required TextRange range,
    required this.contentRange,
    required this.expression,
    required this.displayMode,
    required this.mathBuilder,
    required this.textStyle,
    required this.colors,
    required this.onTapOffset,
  }) : super(range);

  final TextRange contentRange;
  final String expression;
  final bool displayMode;
  final IanvsMarkdownMathBuilder? mathBuilder;
  final TextStyle textStyle;
  final IanvsMarkdownThemeData colors;
  final ValueChanged<int> onTapOffset;
}

final class _InlineLinkProjection extends _SourceProjection {
  const _InlineLinkProjection(super.range, this.span);

  final WidgetSpan span;
}

bool _selectionRevealsSourceRange(TextSelection selection, TextRange range) {
  if (!selection.isValid) return false;
  if (selection.isCollapsed) {
    return selection.extentOffset >= range.start &&
        selection.extentOffset < range.end;
  }
  return selection.start < range.end && selection.end > range.start;
}

List<_HiddenMarkerSpan> _hiddenBlockIdCaretRanges(String source) {
  final hidden = <_HiddenMarkerSpan>[];
  for (final range in ianvsMarkdownBlockIdRanges(source)) {
    final caret = source.indexOf('^', range.start);
    if (caret < range.start || caret >= range.end) continue;
    hidden.add(
      _HiddenMarkerSpan(
        TextRange(start: caret, end: caret + 1),
        _collapsedGapPrefixStyle,
      ),
    );
  }
  return List<_HiddenMarkerSpan>.unmodifiable(hidden);
}

List<_HiddenMarkerSpan> _hiddenAtxHeadingMarkerRanges(
  String source,
  TextSelection selection,
) {
  final opening = RegExp(r'^ {0,3}#{1,6}[ \t]+').firstMatch(source);
  if (opening == null || (selection.isValid && selection.start < opening.end)) {
    return const [];
  }
  final closing = RegExp(r'[ \t]+#+[ \t]*$').firstMatch(source);
  return [
    _HiddenMarkerSpan(
      TextRange(start: 0, end: opening.end),
      _collapsedGapPrefixStyle,
    ),
    if (closing != null &&
        (!selection.isValid || selection.end <= closing.start))
      _HiddenMarkerSpan(
        TextRange(start: closing.start, end: source.length),
        _collapsedGapPrefixStyle,
      ),
  ];
}

List<_HiddenMarkerSpan> _hiddenIndentedCodeMarkerRanges(String source) {
  final spans = <_HiddenMarkerSpan>[];
  for (final match in RegExp(
    r'^(?: {4}|\t)',
    multiLine: true,
  ).allMatches(source)) {
    spans.add(
      _HiddenMarkerSpan(
        TextRange(start: match.start, end: match.end),
        _collapsedGapPrefixStyle,
      ),
    );
  }
  return spans;
}

List<_QuoteLineLayout> _quoteLineLayouts(String source) {
  final result = <_QuoteLineLayout>[];
  var offset = 0;
  var inheritedDepth = 1;
  for (final text in source.split('\n')) {
    var cursor = 0;
    final markers = <TextRange>[];
    while (true) {
      final indentationStart = cursor;
      var indentation = 0;
      while (cursor < text.length && indentation < 3 && text[cursor] == ' ') {
        cursor += 1;
        indentation += 1;
      }
      if (cursor >= text.length || text[cursor] != '>') break;
      final markerStart = markers.isEmpty ? 0 : indentationStart;
      cursor += 1;
      if (cursor < text.length &&
          (text[cursor] == ' ' || text[cursor] == '\t')) {
        cursor += 1;
      }
      markers.add(TextRange(start: offset + markerStart, end: offset + cursor));
    }
    if (markers.isNotEmpty) inheritedDepth = markers.length;
    result.add(
      _QuoteLineLayout(
        line: TextRange(start: offset, end: offset + text.length),
        markerRanges: List<TextRange>.unmodifiable(markers),
        depth: inheritedDepth,
      ),
    );
    offset += text.length + 1;
  }
  return List<_QuoteLineLayout>.unmodifiable(result);
}

List<_HiddenMarkerSpan> _hiddenQuoteMarkerRanges(
  List<_QuoteLineLayout> lines,
  int insetDepth,
) {
  if (lines.isEmpty) return const <_HiddenMarkerSpan>[];
  final hidden = <_HiddenMarkerSpan>[];
  for (var index = 0; index < lines.length; index += 1) {
    final markers = lines[index].markerRanges;
    if (markers.isEmpty) continue;
    // The active line's syntax is painted in its reserved gutter rather than
    // occupying payload width and changing line wrapping on focus.
    hidden.addAll(
      markers
          .take(insetDepth)
          .map((range) => _HiddenMarkerSpan(range, _collapsedGapPrefixStyle)),
    );
    hidden.addAll(
      markers
          .skip(insetDepth)
          .map((range) => _HiddenMarkerSpan(range, _hiddenQuoteMarkerStyle)),
    );
  }
  return List<_HiddenMarkerSpan>.unmodifiable(hidden);
}

class _ActiveQuoteBlock extends StatelessWidget {
  const _ActiveQuoteBlock({
    required this.textSpan,
    required this.lines,
    required this.activeSourceOffset,
    required this.insetDepth,
    required this.textDirection,
    required this.textScaler,
    required this.colors,
    required this.child,
  });

  final TextSpan textSpan;
  final List<_QuoteLineLayout> lines;
  final int activeSourceOffset;
  final int insetDepth;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final IanvsMarkdownThemeData colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey('ianvs-markdown-active-quote-rails'),
            painter: _ActiveQuoteRailsPainter(
              textSpan: textSpan,
              lines: lines,
              textDirection: textDirection,
              textScaler: textScaler,
              color: colors.accent,
              markerColor: colors.textTertiary,
              activeSourceOffset: activeSourceOffset,
              insetDepth: insetDepth,
            ),
          ),
        ),
        PositionedDirectional(
          start: 8,
          top: 8,
          bottom: 8,
          child: Container(
            key: const ValueKey('ianvs-markdown-active-quote-rail'),
            width: 3,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ActiveQuoteRailsPainter extends CustomPainter {
  const _ActiveQuoteRailsPainter({
    required this.textSpan,
    required this.lines,
    required this.textDirection,
    required this.textScaler,
    required this.color,
    required this.markerColor,
    required this.activeSourceOffset,
    required this.insetDepth,
  });

  final TextSpan textSpan;
  final List<_QuoteLineLayout> lines;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Color color;
  final Color markerColor;
  final int activeSourceOffset;
  final int insetDepth;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty || size.isEmpty) return;
    final textPainter =
        TextPainter(
          text: textSpan,
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(
          maxWidth: (size.width - 35 * insetDepth).clamp(0.0, double.infinity),
        );
    final plainLength = textSpan.toPlainText().length;
    final fallbackHeight =
        (textSpan.style?.fontSize ?? 14.5) * (textSpan.style?.height ?? 1.58);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3;
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      final start = line.line.start.clamp(0, plainLength);
      var end = line.line.end.clamp(start, plainLength);
      if (end == start && end < plainLength) end += 1;
      final boxes = textPainter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
        boxHeightStyle: BoxHeightStyle.tight,
      );
      final top = boxes.isEmpty
          ? 8 * insetDepth + index * fallbackHeight
          : 8 * insetDepth +
                boxes.map((box) => box.top).reduce((a, b) => a < b ? a : b);
      final bottom = boxes.isEmpty
          ? top + fallbackHeight
          : 8 * insetDepth +
                boxes.map((box) => box.bottom).reduce((a, b) => a > b ? a : b);
      if (activeSourceOffset >= line.line.start &&
          activeSourceOffset <= line.line.end &&
          line.markerRanges.isNotEmpty) {
        final marker = TextPainter(
          text: TextSpan(
            text: '>',
            style: textSpan.style?.copyWith(color: markerColor),
          ),
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout();
        marker.paint(
          canvas,
          Offset(
            textDirection == TextDirection.rtl ? size.width - 26 : 12,
            top,
          ),
        );
        marker.dispose();
      }
      for (var depth = 1; depth < line.depth; depth += 1) {
        final logicalX = 9.5 + depth * 27.0;
        final x = textDirection == TextDirection.rtl
            ? size.width - logicalX
            : logicalX;
        canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
      }
    }
    textPainter.dispose();
  }

  @override
  bool shouldRepaint(covariant _ActiveQuoteRailsPainter oldDelegate) {
    return oldDelegate.textSpan != textSpan ||
        oldDelegate.lines != lines ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.activeSourceOffset != activeSourceOffset ||
        oldDelegate.insetDepth != insetDepth ||
        oldDelegate.markerColor != markerColor ||
        oldDelegate.color != color;
  }
}

final class _LivePreviewRenderingEdit {
  const _LivePreviewRenderingEdit({
    required this.start,
    required this.end,
    required this.replacement,
  });

  final int start;
  final int end;
  final String replacement;
}

final class _LivePreviewFootnoteDefinition {
  const _LivePreviewFootnoteDefinition({
    required this.label,
    required this.body,
    required this.labelStart,
    required this.bodyStart,
  });

  final String label;
  final String body;
  final int labelStart;
  final int bodyStart;

  String get renderedSource => body.isEmpty ? label : '$label $body';

  int? sourceOffsetForVisibleOffset(String visibleText, int visibleOffset) {
    final safeOffset = visibleOffset.clamp(0, visibleText.length);
    if (safeOffset <= label.length) return labelStart + safeOffset;
    if (body.isEmpty) return bodyStart;

    final visibleBodyStart = (label.length + 1).clamp(0, visibleText.length);
    if (safeOffset <= visibleBodyStart) return bodyStart;
    final visibleBody = visibleText.substring(visibleBodyStart);
    final bodyOffset = _markdownSourceOffsetForVisibleOffset(
      body,
      visibleBody,
      safeOffset - visibleBodyStart,
    );
    return bodyOffset == null ? null : bodyStart + bodyOffset;
  }
}

_LivePreviewFootnoteDefinition? _livePreviewFootnoteDefinition(String source) {
  final match = RegExp(
    r'^( {0,3}\[\^)([^\] \r\n\x00\t]+)(\]:[ \t]*)(.*)$',
    dotAll: true,
  ).firstMatch(source);
  if (match == null) return null;
  final prefix = match.group(1)!;
  final label = match.group(2)!;
  final separator = match.group(3)!;
  return _LivePreviewFootnoteDefinition(
    label: label,
    body: match.group(4) ?? '',
    labelStart: prefix.length,
    bodyStart: prefix.length + label.length + separator.length,
  );
}

int? _markdownSourceOffsetForVisibleOffset(
  String source,
  String visible,
  int visibleOffset,
) {
  final safeOffset = visibleOffset.clamp(0, visible.length);
  var sourceOffset = 0;
  for (var index = 0; index < safeOffset; index += 1) {
    final next = source.indexOf(visible[index], sourceOffset);
    if (next < 0) return null;
    sourceOffset = next + 1;
  }
  return sourceOffset;
}

int? _markdownSourceOffsetForRenderedOffset(
  String source,
  String visible,
  int visibleOffset, {
  required int sourceSearchStart,
}) {
  if (visible.isEmpty) return sourceSearchStart.clamp(0, source.length);
  final safeOffset = visibleOffset.clamp(0, visible.length);
  var sourceOffset = source.indexOf(
    visible[0],
    sourceSearchStart.clamp(0, source.length),
  );
  if (sourceOffset < 0) return null;
  if (safeOffset == 0) return sourceOffset;
  for (var index = 0; index < safeOffset; index += 1) {
    final next = source.indexOf(visible[index], sourceOffset);
    if (next < 0) return null;
    sourceOffset = next + 1;
  }
  return sourceOffset;
}

class _BlockEditingController extends TextEditingController {
  IanvsMarkdownSyntaxTheme? syntaxTheme;
  Set<String> linkReferenceLabels = const <String>{};
  List<TextRange> documentHighlightLiteralRuns = const <TextRange>[];
  int sourceOffset = 0;
  bool highlightFencedCode = false;
  int leadingMarkerCharacters = 0;
  bool revealLeadingMarker = false;
  int hiddenLeadingCharacters = 0;
  int collapsedLeadingCharacters = 0;
  List<_SourceProjection> sourceProjections = const <_SourceProjection>[];

  List<TextRange> get _localHighlightLiteralRanges =>
      documentHighlightLiteralRuns
          .where(
            (range) =>
                range.start >= sourceOffset &&
                range.end <= sourceOffset + value.text.length,
          )
          .map(
            (range) => TextRange(
              start: range.start - sourceOffset,
              end: range.end - sourceOffset,
            ),
          )
          .toList(growable: false);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final syntax = syntaxTheme;
    if (syntax == null) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final hasActiveComposing =
        withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed;
    if (highlightFencedCode && !hasActiveComposing) {
      return _buildHighlightedFencedCodeSpan(
        value.text,
        style: style ?? const TextStyle(),
        syntaxTheme: syntax,
        dark: Theme.of(context).brightness == Brightness.dark,
        fenceFontSize: _fenceMarkerFontSize(context),
      );
    }
    final collapsedCharacters = collapsedLeadingCharacters.clamp(
      0,
      value.text.length,
    );
    final localHighlightLiteralRanges = _localHighlightLiteralRanges;
    if (collapsedCharacters > 0) {
      final tailValue = TextEditingValue(
        text: value.text.substring(collapsedCharacters),
        selection: _shiftTextSelection(value.selection, -collapsedCharacters),
        composing: _shiftTextRange(value.composing, -collapsedCharacters),
      );
      return TextSpan(
        style: style,
        children: [
          TextSpan(
            text: String.fromCharCodes(
              List<int>.filled(collapsedCharacters, 0x200b),
            ),
            style: _collapsedGapPrefixStyle,
          ),
          if (tailValue.text.isNotEmpty)
            buildMarkdownSourceTextSpan(
              tailValue,
              style: style,
              syntaxTheme: syntax,
              withComposing: withComposing,
              hideInactiveInlineMarkers: true,
              linkReferenceLabels: linkReferenceLabels,
              highlightLiteralRanges: _sliceTextRanges(
                localHighlightLiteralRanges,
                collapsedCharacters,
                value.text.length,
              ),
            ),
        ],
      );
    }
    if (sourceProjections.isNotEmpty) {
      return _buildTextSpanWithSourceProjections(
        value,
        projections: sourceProjections,
        style: style,
        syntaxTheme: syntax,
        withComposing: withComposing,
        linkReferenceLabels: linkReferenceLabels,
        highlightLiteralRanges: localHighlightLiteralRanges,
      );
    }
    final hiddenCharacters = hiddenLeadingCharacters.clamp(
      0,
      value.text.length,
    );
    if (hiddenCharacters > 0) {
      final tailValue = TextEditingValue(
        text: value.text.substring(hiddenCharacters),
        selection: _shiftTextSelection(value.selection, -hiddenCharacters),
        composing: _shiftTextRange(value.composing, -hiddenCharacters),
      );
      return TextSpan(
        style: style,
        children: [
          TextSpan(
            text: value.text.substring(0, hiddenCharacters),
            style: _hiddenTaskMarkerStyle,
          ),
          if (tailValue.text.isNotEmpty)
            buildMarkdownSourceTextSpan(
              tailValue,
              style: style,
              syntaxTheme: syntax,
              withComposing: withComposing,
              hideInactiveInlineMarkers: true,
              linkReferenceLabels: linkReferenceLabels,
              highlightLiteralRanges: _sliceTextRanges(
                localHighlightLiteralRanges,
                hiddenCharacters,
                value.text.length,
              ),
            ),
        ],
      );
    }
    return buildMarkdownSourceTextSpan(
      value,
      style: style,
      syntaxTheme: syntax,
      withComposing: withComposing,
      hideInactiveInlineMarkers: true,
      linkReferenceLabels: linkReferenceLabels,
      highlightLiteralRanges: localHighlightLiteralRanges,
    );
  }
}

TextSpan _buildTextSpanWithSourceProjections(
  TextEditingValue value, {
  required List<_SourceProjection> projections,
  required TextStyle? style,
  required IanvsMarkdownSyntaxTheme syntaxTheme,
  required bool withComposing,
  required Set<String> linkReferenceLabels,
  required List<TextRange> highlightLiteralRanges,
}) {
  final children = <InlineSpan>[];
  var cursor = 0;
  for (final projection in projections) {
    final start = projection.range.start.clamp(cursor, value.text.length);
    final end = projection.range.end.clamp(start, value.text.length);
    if (start > cursor) {
      children.add(
        _buildMarkdownSegmentSpan(
          value,
          start: cursor,
          end: start,
          style: style,
          syntaxTheme: syntaxTheme,
          withComposing: withComposing,
          linkReferenceLabels: linkReferenceLabels,
          highlightLiteralRanges: highlightLiteralRanges,
        ),
      );
    }
    if (end > start) {
      switch (projection) {
        case _HiddenMarkerSpan(:final style):
          children.add(
            TextSpan(
              text: style.fontSize == 0
                  ? end == value.text.length
                        // A terminal zero-size glyph has no caret anchor in
                        // Flutter. Equal-length zero-width characters retain
                        // source offsets without an empty glyph assertion.
                        ? '\u200b' * (end - start)
                        : value.text
                              .substring(start, end)
                              .replaceAll('\n', '\u200b')
                  : value.text.substring(start, end),
              style: style,
            ),
          );
        case _InlineMathProjection():
          children.addAll(
            _buildInlineMathProjectionSpans(
              value.text,
              start: start,
              end: end,
              projection: projection,
            ),
          );
        case _InlineLinkProjection(:final span):
          children.add(span);
          if (end - start > 1) {
            children.add(
              TextSpan(
                // Keep one display code unit per source code unit. The widget
                // occupies the first; keyboard navigation can still enter the
                // full source range and reveal its original delimiters/URL.
                text: '\u200b' * (end - start - 1),
                style: _collapsedGapPrefixStyle,
              ),
            );
          }
      }
    }
    cursor = end;
  }
  if (cursor < value.text.length) {
    children.add(
      _buildMarkdownSegmentSpan(
        value,
        start: cursor,
        end: value.text.length,
        style: style,
        syntaxTheme: syntaxTheme,
        withComposing: withComposing,
        linkReferenceLabels: linkReferenceLabels,
        highlightLiteralRanges: highlightLiteralRanges,
      ),
    );
  }
  return TextSpan(style: style, children: children);
}

List<InlineSpan> _buildInlineMathProjectionSpans(
  String source, {
  required int start,
  required int end,
  required _InlineMathProjection projection,
}) {
  assert(end > start);
  return <InlineSpan>[
    WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _InlineMathTapTarget(
        contentRange: projection.contentRange,
        onTapOffset: projection.onTapOffset,
        child: IanvsMarkdownMath(
          key: ValueKey('ianvs-markdown-active-inline-math-$start'),
          expression: projection.expression,
          displayMode: projection.displayMode,
          inline: true,
          mathBuilder: projection.mathBuilder,
          textStyle: projection.textStyle,
          theme: projection.colors,
        ),
      ),
    ),
    if (end - start > 1)
      TextSpan(
        text: source.substring(start + 1, end),
        style: _collapsedGapPrefixStyle,
      ),
  ];
}

class _InlineMathTapTarget extends StatelessWidget {
  const _InlineMathTapTarget({
    required this.contentRange,
    required this.onTapOffset,
    required this.child,
  });

  final TextRange contentRange;
  final ValueChanged<int> onTapOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final box = context.findRenderObject();
        final width = box is RenderBox && box.hasSize ? box.size.width : 0.0;
        final fraction = width <= 0
            ? 0.0
            : (details.localPosition.dx / width).clamp(0.0, 1.0);
        final contentLength = contentRange.end - contentRange.start;
        final relativeOffset = (fraction * contentLength)
            .floor()
            .clamp(0, math.max(0, contentLength - 1))
            .toInt();
        onTapOffset(contentRange.start + relativeOffset);
      },
      child: child,
    );
  }
}

TextSpan _buildMarkdownSegmentSpan(
  TextEditingValue value, {
  required int start,
  required int end,
  required TextStyle? style,
  required IanvsMarkdownSyntaxTheme syntaxTheme,
  required bool withComposing,
  required Set<String> linkReferenceLabels,
  required List<TextRange> highlightLiteralRanges,
}) {
  final selection =
      value.selection.isValid &&
          value.selection.start >= start &&
          value.selection.end <= end
      ? TextSelection(
          baseOffset: value.selection.baseOffset - start,
          extentOffset: value.selection.extentOffset - start,
          affinity: value.selection.affinity,
          isDirectional: value.selection.isDirectional,
        )
      : const TextSelection.collapsed(offset: -1);
  final composing =
      value.composing.isValid &&
          value.composing.start >= start &&
          value.composing.end <= end
      ? TextRange(
          start: value.composing.start - start,
          end: value.composing.end - start,
        )
      : TextRange.empty;
  return buildMarkdownSourceTextSpan(
    TextEditingValue(
      text: value.text.substring(start, end),
      selection: selection,
      composing: composing,
    ),
    style: style,
    syntaxTheme: syntaxTheme,
    withComposing: withComposing,
    hideInactiveInlineMarkers: true,
    linkReferenceLabels: linkReferenceLabels,
    highlightLiteralRanges: _sliceTextRanges(
      highlightLiteralRanges,
      start,
      end,
    ),
  );
}

const _hiddenTaskMarkerStyle = TextStyle(
  color: Colors.transparent,
  fontSize: 4,
  height: 1,
  letterSpacing: -1,
);

const _hiddenQuoteMarkerStyle = TextStyle(color: Colors.transparent);

const _collapsedGapPrefixStyle = TextStyle(
  color: Colors.transparent,
  fontSize: 0,
  height: 0,
  letterSpacing: 0,
);

TextSelection _shiftTextSelection(TextSelection selection, int delta) {
  if (!selection.isValid) return const TextSelection.collapsed(offset: 0);
  return TextSelection(
    baseOffset: (selection.baseOffset + delta).clamp(0, 1 << 30),
    extentOffset: (selection.extentOffset + delta).clamp(0, 1 << 30),
    affinity: selection.affinity,
    isDirectional: selection.isDirectional,
  );
}

TextRange _shiftTextRange(TextRange range, int delta) {
  if (!range.isValid || range.isCollapsed) return TextRange.empty;
  return TextRange(
    start: (range.start + delta).clamp(0, 1 << 30),
    end: (range.end + delta).clamp(0, 1 << 30),
  );
}

List<TextRange> _sliceTextRanges(
  Iterable<TextRange> ranges,
  int start,
  int end,
) => ranges
    .where((range) => range.start >= start && range.end <= end)
    .map(
      (range) => TextRange(start: range.start - start, end: range.end - start),
    )
    .toList(growable: false);

// Fence syntax lives in the code surface's existing 12px vertical inset.
// Keep that inset fixed when the host scales document text.
double _fenceMarkerFontSize(BuildContext context) =>
    100 / MediaQuery.textScalerOf(context).scale(10);

double? _blankFencedCodeMinHeight(String source) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parseLines(source.split('\n'));
  if (nodes.length != 1 || nodes.single is! md.Element) return null;
  final block = nodes.single as md.Element;
  if (block.tag != 'pre') return null;
  var payload = block.textContent;
  if (payload.endsWith('\n')) {
    payload = payload.substring(0, payload.length - 1);
  }
  if (payload.codeUnits.any((unit) => unit != 0x0a && unit != 0x0d)) {
    return null;
  }
  return 58 + (markdownCodeLineCount(payload) - 1) * 20.0;
}

TextSpan _buildHighlightedFencedCodeSpan(
  String source, {
  required TextStyle style,
  required IanvsMarkdownSyntaxTheme syntaxTheme,
  required bool dark,
  required double fenceFontSize,
}) {
  final opening = RegExp(
    r'^ {0,3}((?:`{3,})|(?:~{3,}))(.*?)(?:\r?\n|$)',
  ).firstMatch(source);
  if (opening == null) return TextSpan(text: source, style: style);

  final fence = opening.group(1)!;
  final info = opening.group(2)?.trim() ?? '';
  final language = info.isEmpty ? null : info.split(RegExp(r'\s+')).first;
  final bodyStart = opening.end;
  var closingStart = source.length;
  final lastLineStart = source.lastIndexOf('\n') + 1;
  if (lastLineStart >= bodyStart && lastLineStart < source.length) {
    final lastLine = source.substring(lastLineStart).trim();
    final sameFence =
        lastLine.length >= fence.length &&
        lastLine.codeUnits.every((codeUnit) => codeUnit == fence.codeUnitAt(0));
    if (sameFence) closingStart = lastLineStart;
  }

  return TextSpan(
    style: style,
    children: [
      TextSpan(
        text: source.substring(0, bodyStart),
        style: syntaxTheme.marker.copyWith(
          fontSize: fenceFontSize,
          height: 1.2,
          letterSpacing: 0,
        ),
      ),
      markdownHighlightedCodeSpan(
        source.substring(bodyStart, closingStart),
        language: language,
        baseStyle: style,
        dark: dark,
      ),
      if (closingStart < source.length)
        TextSpan(
          text: source.substring(closingStart),
          style: syntaxTheme.marker.copyWith(
            fontSize: fenceFontSize,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
    ],
  );
}
