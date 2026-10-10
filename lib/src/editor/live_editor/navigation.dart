part of '../live_editor.dart';

extension _LiveEditorSelectionNavigation on _IanvsMarkdownLiveEditorState {
  KeyEventResult _handleAppleCharacterNavigation({required bool forward}) {
    final localSelection = _blockController.selection;
    if (!localSelection.isValid) return KeyEventResult.handled;

    final source = widget.controller.text;
    final documentSelection = _localSelectionToDocument(
      localSelection,
      _editingStart,
    );
    final int target;
    if (!documentSelection.isCollapsed) {
      target = forward ? documentSelection.end : documentSelection.start;
    } else {
      final head = documentSelection.extentOffset.clamp(0, source.length);
      if (forward) {
        if (head == source.length) return KeyEventResult.handled;
        target =
            CharacterBoundary(source).getTrailingTextBoundaryAt(head) ??
            source.length;
      } else {
        if (head == 0) return KeyEventResult.handled;
        target =
            CharacterBoundary(source).getLeadingTextBoundaryAt(head - 1) ?? 0;
      }
    }

    _verticalNavigationX = null;
    _activateDocumentCaret(target);
    return KeyEventResult.handled;
  }

  KeyEventResult _handleSelectAllDocument() {
    final source = widget.controller.text;
    if (source.isEmpty) return KeyEventResult.ignored;
    _foldedSelectionBridge = null;
    final selection = TextSelection(
      baseOffset: 0,
      extentOffset: source.length,
      isDirectional: true,
    );
    final surface = _selectionSurfaceFor(selection);
    if (surface == null) return KeyEventResult.ignored;
    _verticalNavigationX = null;
    _activateSelectionSurface(selection, surface);
    return KeyEventResult.handled;
  }

  KeyEventResult _handleDocumentBoundaryNavigation({
    required bool toEnd,
    required bool extendSelection,
  }) {
    final localSelection = _blockController.selection;
    if (!localSelection.isValid) return KeyEventResult.ignored;

    final documentSelection = _localSelectionToDocument(
      localSelection,
      _editingStart,
    );
    final target = toEnd ? widget.controller.text.length : 0;
    _verticalNavigationX = null;
    if (!extendSelection || documentSelection.baseOffset == target) {
      _activateDocumentCaret(target);
      return KeyEventResult.handled;
    }

    final selection = TextSelection(
      baseOffset: documentSelection.baseOffset,
      extentOffset: target,
      affinity: documentSelection.affinity,
      isDirectional: true,
    );
    final surface = _selectionSurfaceFor(selection);
    if (surface == null) return KeyEventResult.ignored;
    _activateSelectionSurface(selection, surface);
    return KeyEventResult.handled;
  }

  KeyEventResult _handlePhysicalLineBoundaryNavigation({required bool down}) {
    final localSelection = _blockController.selection;
    if (!localSelection.isValid || !localSelection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final source = widget.controller.text;
    final documentOffset = (_editingStart + localSelection.extentOffset).clamp(
      0,
      source.length,
    );
    final int target;
    if (down) {
      final lineEnd = _lineEndAt(source, documentOffset);
      target = documentOffset < lineEnd
          ? lineEnd
          : lineEnd < source.length
          ? _lineEndAt(source, lineEnd + 1)
          : source.length;
    } else {
      final lineStart = _lineStartAt(source, documentOffset);
      target = documentOffset > lineStart
          ? lineStart
          : lineStart > 0
          ? _lineStartAt(source, lineStart - 1)
          : 0;
    }

    _verticalNavigationX = null;
    _activateDocumentCaret(target);
    return KeyEventResult.handled;
  }

  KeyEventResult _handlePhysicalLineHorizontalBoundaryNavigation({
    required bool forward,
    required bool extendSelection,
  }) {
    final localSelection = _blockController.selection;
    if (!localSelection.isValid) return KeyEventResult.ignored;

    final source = widget.controller.text;
    final documentSelection = _localSelectionToDocument(
      localSelection,
      _editingStart,
    );
    final extent = documentSelection.extentOffset.clamp(0, source.length);
    final target = forward
        ? _lineEndAt(source, extent)
        : _lineStartAt(source, extent);
    final revealLeadingMarker =
        !forward &&
        _blockController.leadingMarkerCharacters > 0 &&
        target >= _editingStart &&
        target - _editingStart < _blockController.leadingMarkerCharacters;

    _verticalNavigationX = null;
    if (!extendSelection || documentSelection.baseOffset == target) {
      _activateDocumentCaret(target);
    } else {
      final selection = TextSelection(
        baseOffset: documentSelection.baseOffset,
        extentOffset: target,
        affinity: documentSelection.affinity,
        isDirectional: true,
      );
      final surface = _selectionSurfaceFor(selection);
      if (surface == null) return KeyEventResult.ignored;
      _activateSelectionSurface(selection, surface);
    }
    if (revealLeadingMarker) {
      _blockController.revealLeadingMarker = true;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _handleVisualLineBoundaryNavigation({
    required bool forward,
    required bool extendSelection,
  }) {
    final selection = _blockController.selection;
    if (!selection.isValid) return KeyEventResult.ignored;

    final text = _blockController.text;
    final extent = selection.extentOffset.clamp(0, text.length);
    final editable = _activeRenderEditable();
    var target = editable == null
        ? (forward ? _lineEndAt(text, extent) : _lineStartAt(text, extent))
        : (() {
            final line = editable.getLineAtOffset(
              TextPosition(offset: extent, affinity: selection.affinity),
            );
            return (forward ? line.end : line.start).clamp(0, text.length);
          })();
    final hiddenLeadingCharacters = _blockController.leadingMarkerCharacters
        .clamp(0, text.length);
    if (!forward &&
        target == 0 &&
        hiddenLeadingCharacters > 0 &&
        extent > hiddenLeadingCharacters) {
      target = hiddenLeadingCharacters;
    }
    _blockController.revealLeadingMarker =
        !forward &&
        hiddenLeadingCharacters > 0 &&
        target < hiddenLeadingCharacters;

    _verticalNavigationX = null;
    final nextSelection = extendSelection
        ? TextSelection(
            baseOffset: selection.baseOffset,
            extentOffset: target,
            affinity: selection.affinity,
            isDirectional: true,
          )
        : TextSelection.collapsed(offset: target, affinity: selection.affinity);
    _blockController.value = _blockController.value.copyWith(
      selection: nextSelection,
      composing: TextRange.empty,
    );
    // Consume the shortcut even when already at the visual boundary so the
    // outer document controller cannot reinterpret it as document navigation.
    return KeyEventResult.handled;
  }

  KeyEventResult _handleDocumentWordNavigation({
    required bool forward,
    required bool extendSelection,
  }) {
    final localSelection = _blockController.selection;
    if (!localSelection.isValid ||
        (!extendSelection && !localSelection.isCollapsed)) {
      return KeyEventResult.ignored;
    }
    final documentSelection = _localSelectionToDocument(
      localSelection,
      _editingStart,
    );
    final wordTarget = _documentWordBoundary(
      widget.controller.text,
      documentSelection.extentOffset,
      forward: forward,
    );
    if (extendSelection) {
      final foldedResult = _handleFoldedWordSelection(
        documentSelection,
        wordTarget,
        forward: forward,
      );
      if (foldedResult != null) return foldedResult;
    }
    final target = extendSelection
        ? wordTarget
        : _projectFoldedCaretTarget(wordTarget, forward: forward);
    if (target == documentSelection.extentOffset ||
        target >= _editingStart && target <= _editingEnd) {
      return KeyEventResult.ignored;
    }

    _verticalNavigationX = null;
    if (!extendSelection || documentSelection.baseOffset == target) {
      _activateDocumentCaret(target);
      return KeyEventResult.handled;
    }

    final selection = TextSelection(
      baseOffset: documentSelection.baseOffset,
      extentOffset: target,
      affinity: documentSelection.affinity,
      isDirectional: true,
    );
    final surface = _selectionSurfaceFor(selection);
    if (surface == null) return KeyEventResult.ignored;
    _activateSelectionSurface(selection, surface);
    return KeyEventResult.handled;
  }

  KeyEventResult? _handleFoldedWordSelection(
    TextSelection documentSelection,
    int wordTarget, {
    required bool forward,
  }) {
    if (!widget.enableHeadingFolding) return null;
    final hidden = _headingFoldModel.hiddenBlockIndices(_headingFoldController);
    final targetIndex = _verticalBlockIndexAt(wordTarget);
    if (targetIndex < 0 || !hidden.contains(targetIndex)) return null;

    final activeIndex = _blocks.indexWhere(
      (block) => block.start == _activeBlockStart,
    );
    if (activeIndex < 0) return KeyEventResult.handled;
    final visibleIndex = _adjacentVisibleBlockIndex(
      targetIndex,
      forward: forward,
    );
    if (visibleIndex == null) return KeyEventResult.handled;
    final visible = _blocks[visibleIndex];

    if (forward) {
      final localTarget = _documentWordBoundary(
        visible.source,
        0,
        forward: true,
      );
      _activateBlockHorizontally(visible, localOffset: 0);
      _foldedSelectionBridge = _FoldedSelectionBridge(
        originBlockStart: _blocks[activeIndex].start,
        targetBlockStart: visible.start,
        forward: true,
      );
      _blockController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: localTarget,
        isDirectional: true,
      );
      return KeyEventResult.handled;
    }

    final selection = TextSelection(
      baseOffset: documentSelection.baseOffset,
      extentOffset: visible.end,
      affinity: documentSelection.affinity,
      isDirectional: true,
    );
    final surface = _selectionSurfaceFor(selection);
    _foldedSelectionBridge = null;
    if (surface != null) _activateSelectionSurface(selection, surface);
    return KeyEventResult.handled;
  }

  KeyEventResult _handleVerticalSelection({required bool down}) {
    _foldedSelectionBridge = null;
    final localSelection = _blockController.selection;
    if (!localSelection.isValid) return KeyEventResult.ignored;

    final documentSelection = _localSelectionToDocument(
      localSelection,
      _editingStart,
    );
    final documentOffset = documentSelection.extentOffset;
    final blockIndex = _verticalBlockIndexAt(documentOffset);
    ({int offset, int lineStart, int lineEnd})? target;
    if (blockIndex >= 0) {
      final block = _blocks[blockIndex];
      final localBlockStart = block.start - _editingStart;
      final localBlockEnd = block.end - _editingStart;
      if (localBlockStart < 0 ||
          localBlockEnd > _blockController.text.length ||
          !_caretIsOnVisualRangeEdge(
            atStart: !down,
            rangeStart: localBlockStart,
            rangeEnd: localBlockEnd,
          )) {
        return KeyEventResult.ignored;
      }
      if (localSelection.isCollapsed || _verticalNavigationX == null) {
        _rememberVerticalNavigationPosition(localSelection.extentOffset);
      }
      target = _verticalTargetFromBlock(blockIndex, down: down);
    } else {
      if (_verticalNavigationX == null) {
        _rememberVerticalNavigationPosition(localSelection.extentOffset);
      }
      target = _verticalTargetFromGap(documentOffset, down: down);
    }
    if (target == null || target.offset == documentOffset) {
      return KeyEventResult.ignored;
    }

    final nextSelection = TextSelection(
      baseOffset: documentSelection.baseOffset,
      extentOffset: target.offset,
      affinity: documentSelection.affinity,
      isDirectional: true,
    );
    final surface = _selectionSurfaceFor(nextSelection);
    if (surface == null) return KeyEventResult.ignored;
    _activateVerticalSelection(nextSelection, surface, target);
    return KeyEventResult.handled;
  }

  int _verticalBlockIndexAt(int offset) {
    final exactStart = _blocks.indexWhere((block) => block.start == offset);
    if (exactStart >= 0) return exactStart;
    return _blocks.indexWhere(
      (block) => offset > block.start && offset <= block.end,
    );
  }

  int? _adjacentVisibleBlockIndex(int blockIndex, {required bool forward}) {
    final hiddenBlockIndices = widget.enableHeadingFolding
        ? _headingFoldModel.hiddenBlockIndices(_headingFoldController)
        : const <int>{};
    for (
      var index = blockIndex + (forward ? 1 : -1);
      index >= 0 && index < _blocks.length;
      index += forward ? 1 : -1
    ) {
      if (!hiddenBlockIndices.contains(index) &&
          !_isHiddenFrontMatter(_blocks[index])) {
        return index;
      }
    }
    return null;
  }

  int _projectFoldedCaretTarget(int target, {required bool forward}) {
    if (!widget.enableHeadingFolding) return target;
    final blockIndex = _verticalBlockIndexAt(target);
    if (blockIndex < 0 ||
        !_headingFoldModel
            .hiddenBlockIndices(_headingFoldController)
            .contains(blockIndex)) {
      return target;
    }
    final visibleIndex = _adjacentVisibleBlockIndex(
      blockIndex,
      forward: forward,
    );
    if (visibleIndex != null) {
      final visible = _blocks[visibleIndex];
      return forward ? visible.start : visible.end;
    }
    final fallbackIndex = _adjacentVisibleBlockIndex(
      blockIndex,
      forward: !forward,
    );
    if (fallbackIndex == null) return target;
    final fallback = _blocks[fallbackIndex];
    return forward ? fallback.end : fallback.start;
  }

  ({int offset, int lineStart, int lineEnd})? _verticalTargetFromBlock(
    int blockIndex, {
    required bool down,
  }) {
    final source = widget.controller.text;
    final block = _blocks[blockIndex];
    if (down) {
      final nextIndex = _adjacentVisibleBlockIndex(blockIndex, forward: true);
      final next = nextIndex == null ? null : _blocks[nextIndex];
      if (nextIndex != null && nextIndex > blockIndex + 1) {
        return _verticalTargetInBlock(_blocks[nextIndex], atStart: true);
      }
      if (nextIndex == null && blockIndex + 1 < _blocks.length) return null;
      final gapEnd = next?.start ?? source.length;
      final firstGapLineStart = block.end + 1;
      if (firstGapLineStart < gapEnd) {
        return _verticalTargetOnLine(
          firstGapLineStart,
          _lineEndAt(source, firstGapLineStart),
        );
      }
      return next == null ? null : _verticalTargetInBlock(next, atStart: true);
    }

    final previousIndex = _adjacentVisibleBlockIndex(
      blockIndex,
      forward: false,
    );
    if (previousIndex == null) {
      if (blockIndex != 0 || block.start == 0) return null;
      final previousLineOffset = block.start - 1;
      return _verticalTargetOnLine(
        _lineStartAt(source, previousLineOffset),
        _lineEndAt(source, previousLineOffset),
      );
    }
    final previous = _blocks[previousIndex];
    if (previousIndex < blockIndex - 1) {
      return _verticalTargetInBlock(previous, atStart: false);
    }
    if (previous.end + 1 < block.start) {
      final lastGapLineOffset = block.start - 1;
      return _verticalTargetOnLine(
        _lineStartAt(source, lastGapLineOffset),
        _lineEndAt(source, lastGapLineOffset),
      );
    }
    return _verticalTargetInBlock(previous, atStart: false);
  }

  ({int offset, int lineStart, int lineEnd})? _verticalTargetFromGap(
    int documentOffset, {
    required bool down,
  }) {
    final source = widget.controller.text;
    if (down) {
      final lineEnd = _lineEndAt(source, documentOffset);
      final nextLineStart = lineEnd < source.length
          ? lineEnd + 1
          : source.length;
      final nextIndex = _blocks.indexWhere(
        (block) => block.start >= nextLineStart,
      );
      if (nextIndex >= 0 && nextLineStart >= _blocks[nextIndex].start) {
        return _verticalTargetInBlock(_blocks[nextIndex], atStart: true);
      }
      if (nextLineStart >= source.length) return null;
      return _verticalTargetOnLine(
        nextLineStart,
        _lineEndAt(source, nextLineStart),
      );
    }

    final lineStart = _lineStartAt(source, documentOffset);
    var previousIndex = -1;
    for (var index = 0; index < _blocks.length; index += 1) {
      if (_blocks[index].end >= lineStart) break;
      previousIndex = index;
    }
    if (previousIndex < 0) return null;
    final previous = _blocks[previousIndex];
    if (lineStart <= previous.end + 1) {
      return _verticalTargetInBlock(previous, atStart: false);
    }
    final previousLineOffset = lineStart - 1;
    return _verticalTargetOnLine(
      _lineStartAt(source, previousLineOffset),
      previousLineOffset,
    );
  }

  ({int offset, int lineStart, int lineEnd}) _verticalTargetInBlock(
    IanvsMarkdownBlock block, {
    required bool atStart,
  }) {
    final source = widget.controller.text;
    final lineStart = atStart ? block.start : _lineStartAt(source, block.end);
    final lineEnd = atStart
        ? _lineEndAt(source, block.start).clamp(block.start, block.end)
        : block.end;
    return _verticalTargetOnLine(lineStart, lineEnd);
  }

  ({int offset, int lineStart, int lineEnd}) _verticalTargetOnLine(
    int lineStart,
    int lineEnd,
  ) {
    return (
      offset:
          lineStart + _verticalNavigationColumn.clamp(0, lineEnd - lineStart),
      lineStart: lineStart,
      lineEnd: lineEnd,
    );
  }

  KeyEventResult _handleFoldedSelectionCopy() {
    final bridge = _foldedSelectionBridge;
    if (bridge == null) return KeyEventResult.ignored;
    if (!_foldedSelectionBridgeIsActive(bridge)) {
      _foldedSelectionBridge = null;
      return KeyEventResult.ignored;
    }

    final localSelection = _blockController.selection;
    final selected = localSelection.textInside(_blockController.text);
    final copied = bridge.forward ? '\n$selected' : '$selected\n';
    unawaited(Clipboard.setData(ClipboardData(text: copied)));
    return KeyEventResult.handled;
  }

  bool _foldedSelectionBridgeIsActive(_FoldedSelectionBridge bridge) {
    final activeStart = bridge.forward
        ? bridge.targetBlockStart
        : bridge.originBlockStart;
    if (_activeBlockStart != activeStart) return false;
    final activeIndex = _blocks.indexWhere(
      (block) => block.start == activeStart,
    );
    final targetIndex = _blocks.indexWhere(
      (block) => block.start == bridge.targetBlockStart,
    );
    final originIndex = _blocks.indexWhere(
      (block) => block.start == bridge.originBlockStart,
    );
    if (activeIndex < 0 || targetIndex < 0 || originIndex < 0) return false;
    final active = _blocks[activeIndex];
    if (_blockController.text != active.source) return false;
    final selection = _blockController.selection;
    if (!selection.isValid) return false;
    if (selection.baseOffset != 0) return false;
    if (!bridge.forward && !selection.isCollapsed) return false;

    final hidden = _headingFoldModel.hiddenBlockIndices(_headingFoldController);
    final first = math.min(originIndex, targetIndex) + 1;
    final last = math.max(originIndex, targetIndex);
    return first < last &&
        Iterable<int>.generate(
          last - first,
          (offset) => first + offset,
        ).any(hidden.contains);
  }

  KeyEventResult? _handleFoldedHorizontalSelectionTransition({
    required bool right,
  }) {
    final selection = _blockController.selection;
    final bridge = _foldedSelectionBridge;
    if (bridge != null) {
      if (!_foldedSelectionBridgeIsActive(bridge)) {
        _foldedSelectionBridge = null;
      } else {
        if (!right && !bridge.forward) {
          final originIndex = _blocks.indexWhere(
            (block) => block.start == bridge.originBlockStart,
          );
          final targetIndex = _blocks.indexWhere(
            (block) => block.start == bridge.targetBlockStart,
          );
          if (originIndex < 0 || targetIndex < 0) {
            _foldedSelectionBridge = null;
            return KeyEventResult.handled;
          }
          final documentSelection = TextSelection(
            baseOffset: _blocks[originIndex].start,
            extentOffset: _blocks[targetIndex].end,
            isDirectional: true,
          );
          final surface = _selectionSurfaceFor(documentSelection);
          _foldedSelectionBridge = null;
          if (surface == null) return KeyEventResult.handled;
          _activateSelectionSurface(documentSelection, surface);
          return KeyEventResult.handled;
        }
        if (right != bridge.forward) {
          if (bridge.forward && !selection.isCollapsed) {
            return null;
          }
          if (!bridge.forward) {
            _foldedSelectionBridge = null;
            return KeyEventResult.handled;
          }
          final originIndex = _blocks.indexWhere(
            (block) => block.start == bridge.originBlockStart,
          );
          if (originIndex < 0) return KeyEventResult.handled;
          final origin = _blocks[originIndex];
          _foldedSelectionBridge = null;
          _activateBlockHorizontally(
            origin,
            localOffset: bridge.forward ? origin.source.length : 0,
          );
          return KeyEventResult.handled;
        }
      }
    }

    if (!selection.isCollapsed) return null;
    final activeIndex = _blocks.indexWhere(
      (block) => block.start == _activeBlockStart,
    );
    if (activeIndex < 0) return null;
    final boundary = right ? _blockController.text.length : 0;
    if (selection.extentOffset != boundary) return null;
    final visibleIndex = _adjacentVisibleBlockIndex(
      activeIndex,
      forward: right,
    );
    if (visibleIndex == null ||
        (right
            ? visibleIndex <= activeIndex + 1
            : visibleIndex >= activeIndex - 1)) {
      return null;
    }

    final origin = _blocks[activeIndex];
    final target = _blocks[visibleIndex];
    if (right) {
      _activateBlockHorizontally(target, localOffset: 0);
    }
    _foldedSelectionBridge = _FoldedSelectionBridge(
      originBlockStart: origin.start,
      targetBlockStart: target.start,
      forward: right,
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _handleHorizontalSelection({required bool right}) {
    final localSelection = _blockController.selection;
    final foldedTransition = _handleFoldedHorizontalSelectionTransition(
      right: right,
    );
    if (foldedTransition != null) return foldedTransition;
    if (!localSelection.isValid ||
        (right
            ? localSelection.extentOffset != _blockController.text.length
            : localSelection.extentOffset != 0)) {
      return KeyEventResult.ignored;
    }

    final source = widget.controller.text;
    final documentSelection = _localSelectionToDocument(
      localSelection,
      _editingStart,
    );
    final targetExtent = documentSelection.extentOffset + (right ? 1 : -1);
    if (targetExtent < 0 || targetExtent > source.length) {
      return KeyEventResult.ignored;
    }
    final nextSelection = TextSelection(
      baseOffset: documentSelection.baseOffset,
      extentOffset: targetExtent,
      affinity: documentSelection.affinity,
      isDirectional: true,
    );
    final surface = _selectionSurfaceFor(nextSelection);
    if (surface == null) return KeyEventResult.ignored;
    _activateSelectionSurface(nextSelection, surface);
    return KeyEventResult.handled;
  }

  KeyEventResult _handleHorizontalNavigation({required bool right}) {
    final selection = _blockController.selection;
    final activeIndex = _blocks.indexWhere(
      (block) => block.start == _activeBlockStart,
    );
    if (activeIndex < 0 || !selection.isValid || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final localOffset = selection.extentOffset;
    if (right) {
      if (localOffset != _blockController.text.length) {
        return KeyEventResult.ignored;
      }
      final source = widget.controller.text;
      final boundary = _editingEnd.clamp(0, source.length);
      if (boundary == source.length) return KeyEventResult.ignored;
      final targetOffset = boundary + 1;
      final nextIndex = _adjacentVisibleBlockIndex(activeIndex, forward: true);
      if (nextIndex != null && nextIndex > activeIndex + 1) {
        _activateBlockHorizontally(_blocks[nextIndex], localOffset: 0);
        return KeyEventResult.handled;
      }
      if (nextIndex == null && activeIndex + 1 < _blocks.length) {
        return KeyEventResult.handled;
      }
      final next = nextIndex == null ? null : _blocks[nextIndex];
      if (next != null && targetOffset >= next.start) {
        _activateBlockHorizontally(
          next,
          localOffset: targetOffset - next.start,
        );
        return KeyEventResult.handled;
      }
      _activateTrailingGapLine(
        _blocks[activeIndex],
        lineStart: _lineStartAt(source, targetOffset),
        lineEnd: _lineEndAt(source, targetOffset),
        caretOffset: targetOffset,
      );
      return KeyEventResult.handled;
    }

    if (localOffset != 0) return KeyEventResult.ignored;
    final source = widget.controller.text;
    final boundary = _editingStart.clamp(0, source.length);
    if (boundary == 0) return KeyEventResult.ignored;
    if (activeIndex == 0) {
      _activateDocumentCaret(boundary - 1);
      return KeyEventResult.handled;
    }
    final targetOffset = boundary - 1;
    final previousIndex = _adjacentVisibleBlockIndex(
      activeIndex,
      forward: false,
    );
    if (previousIndex != null && previousIndex < activeIndex - 1) {
      final previous = _blocks[previousIndex];
      _activateBlockHorizontally(previous, localOffset: previous.source.length);
      return KeyEventResult.handled;
    }
    if (previousIndex == null) return KeyEventResult.handled;
    final previous = _blocks[previousIndex];
    if (targetOffset <= previous.end) {
      _activateBlockHorizontally(
        previous,
        localOffset: targetOffset - previous.start,
      );
      return KeyEventResult.handled;
    }
    _activateTrailingGapLine(
      previous,
      lineStart: _lineStartAt(source, targetOffset),
      lineEnd: _lineEndAt(source, targetOffset),
      caretOffset: targetOffset,
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _handleVerticalNavigation({required bool down}) {
    final selection = _blockController.selection;
    final activeIndex = _blocks.indexWhere(
      (block) => block.start == _activeBlockStart,
    );
    if (activeIndex < 0 || !selection.isValid || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final active = _blocks[activeIndex];
    final localOffset = selection.extentOffset.clamp(
      0,
      _blockController.text.length,
    );
    final documentOffset = _editingStart + localOffset;
    final inTrailingGap = documentOffset > active.end;
    if (inTrailingGap) {
      return down
          ? _moveDownFromTrailingGap(activeIndex, documentOffset)
          : _moveUpFromTrailingGap(activeIndex, documentOffset);
    }

    if (!_caretIsOnVisualEdge(atStart: !down)) {
      return KeyEventResult.ignored;
    }
    _rememberVerticalNavigationPosition(localOffset);

    if (down) {
      final nextIndex = _adjacentVisibleBlockIndex(activeIndex, forward: true);
      final next = nextIndex == null ? null : _blocks[nextIndex];
      if (nextIndex != null && nextIndex > activeIndex + 1) {
        _activateBlockVertically(_blocks[nextIndex], atStart: true);
        return KeyEventResult.handled;
      }
      if (nextIndex == null && activeIndex + 1 < _blocks.length) {
        return KeyEventResult.handled;
      }
      final gapEnd = next?.start ?? widget.controller.text.length;
      final firstGapLineStart = active.end + 1;
      if (firstGapLineStart < gapEnd) {
        _activateTrailingGapLine(
          active,
          lineStart: firstGapLineStart,
          lineEnd: _lineEndAt(widget.controller.text, firstGapLineStart),
        );
        return KeyEventResult.handled;
      }
      if (next == null) return KeyEventResult.ignored;
      _activateBlockVertically(next, atStart: true);
      return KeyEventResult.handled;
    }

    final previousIndex = _adjacentVisibleBlockIndex(
      activeIndex,
      forward: false,
    );
    if (previousIndex == null) {
      final target = _verticalTargetFromBlock(activeIndex, down: false);
      if (target == null) return KeyEventResult.ignored;
      _activateDocumentCaret(target.offset);
      return KeyEventResult.handled;
    }
    final previous = _blocks[previousIndex];
    if (previousIndex < activeIndex - 1) {
      _activateBlockVertically(previous, atStart: false);
      return KeyEventResult.handled;
    }
    if (previous.end + 1 < active.start) {
      final lastGapLineStart = active.start - 1;
      _activateTrailingGapLine(
        previous,
        lineStart: lastGapLineStart,
        lineEnd: _lineEndAt(widget.controller.text, lastGapLineStart),
      );
    } else {
      _activateBlockVertically(previous, atStart: false);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _moveDownFromTrailingGap(int activeIndex, int documentOffset) {
    final source = widget.controller.text;
    final lineEnd = _lineEndAt(source, documentOffset);
    final nextLineStart = lineEnd < source.length ? lineEnd + 1 : source.length;
    final nextIndex = _adjacentVisibleBlockIndex(activeIndex, forward: true);
    final next = nextIndex == null ? null : _blocks[nextIndex];
    if (nextIndex != null && nextIndex > activeIndex + 1) {
      _activateBlockVertically(_blocks[nextIndex], atStart: true);
      return KeyEventResult.handled;
    }
    if (nextIndex == null && activeIndex + 1 < _blocks.length) {
      return KeyEventResult.handled;
    }
    if (next != null && nextLineStart >= next.start) {
      _activateBlockVertically(next, atStart: true);
      return KeyEventResult.handled;
    }
    final gapEnd = next?.start ?? source.length;
    if (nextLineStart >= gapEnd) return KeyEventResult.ignored;
    _activateTrailingGapLine(
      _blocks[activeIndex],
      lineStart: nextLineStart,
      lineEnd: _lineEndAt(source, nextLineStart),
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _moveUpFromTrailingGap(int activeIndex, int documentOffset) {
    final source = widget.controller.text;
    final active = _blocks[activeIndex];
    final lineStart = _lineStartAt(source, documentOffset);
    if (lineStart <= active.end + 1) {
      _activateBlockVertically(active, atStart: false);
      return KeyEventResult.handled;
    }
    final previousLineOffset = lineStart - 1;
    _activateTrailingGapLine(
      active,
      lineStart: _lineStartAt(source, previousLineOffset),
      lineEnd: previousLineOffset,
    );
    return KeyEventResult.handled;
  }

  void _rememberVerticalNavigationPosition(int localOffset) {
    final editable = _activeRenderEditable();
    _verticalNavigationX = editable
        ?.getLocalRectForCaret(TextPosition(offset: localOffset))
        .left;
    _verticalNavigationColumn =
        localOffset - _lineStartAt(_blockController.text, localOffset);
  }

  bool _caretIsOnVisualEdge({required bool atStart}) {
    return _caretIsOnVisualRangeEdge(
      atStart: atStart,
      rangeStart: 0,
      rangeEnd: _blockController.text.length,
    );
  }

  bool _caretIsOnVisualRangeEdge({
    required bool atStart,
    required int rangeStart,
    required int rangeEnd,
  }) {
    final selection = _blockController.selection;
    final editable = _activeRenderEditable();
    if (editable == null) {
      final offset = selection.extentOffset;
      return atStart
          ? !_blockController.text.substring(rangeStart, offset).contains('\n')
          : !_blockController.text.substring(offset, rangeEnd).contains('\n');
    }
    final caret = editable.getLocalRectForCaret(
      TextPosition(offset: selection.extentOffset),
    );
    final edge = editable.getLocalRectForCaret(
      TextPosition(offset: atStart ? rangeStart : rangeEnd),
    );
    return (caret.top - edge.top).abs() <= 1;
  }
}

class _FoldedSelectionBridge {
  const _FoldedSelectionBridge({
    required this.originBlockStart,
    required this.targetBlockStart,
    required this.forward,
  });

  final int originBlockStart;
  final int targetBlockStart;
  final bool forward;
}

final class _EditorNavigationHeading {
  const _EditorNavigationHeading({
    required this.blockStart,
    required this.level,
    required this.text,
  });

  final int blockStart;
  final int level;
  final String text;
}

class _EditorNavigationPane extends StatelessWidget {
  const _EditorNavigationPane({
    required this.mode,
    required this.headings,
    required this.activeHeadingStart,
    required this.colors,
    required this.onModeSelected,
    required this.onHeadingSelected,
  });

  final IanvsMarkdownEditorMode mode;
  final List<_EditorNavigationHeading> headings;
  final int? activeHeadingStart;
  final IanvsMarkdownThemeData colors;
  final ValueChanged<IanvsMarkdownEditorMode> onModeSelected;
  final ValueChanged<_EditorNavigationHeading> onHeadingSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('ianvs-markdown-navigation-pane'),
      color: colors.surfaceMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
              children: [
                _NavigationSectionLabel(
                  label: IanvsMarkdownMessage.modeSection.resolve(context),
                  colors: colors,
                ),
                const SizedBox(height: 10),
                _EditorModeTile(
                  tooltip: IanvsMarkdownMessage.livePreview.resolve(context),
                  label: IanvsMarkdownMessage.previewLabel.resolve(context),
                  shortcut: IanvsMarkdownShortcuts.labelOf(
                    context,
                    IanvsMarkdownCommand.livePreview,
                  ),
                  icon: Icons.visibility_outlined,
                  selected: mode == IanvsMarkdownEditorMode.livePreview,
                  colors: colors,
                  onTap: () =>
                      onModeSelected(IanvsMarkdownEditorMode.livePreview),
                ),
                _EditorModeTile(
                  tooltip: IanvsMarkdownMessage.sourceMode.resolve(context),
                  label: IanvsMarkdownMessage.sourceLabel.resolve(context),
                  shortcut: IanvsMarkdownShortcuts.labelOf(
                    context,
                    IanvsMarkdownCommand.source,
                  ),
                  icon: Icons.code_rounded,
                  selected: mode == IanvsMarkdownEditorMode.source,
                  colors: colors,
                  onTap: () => onModeSelected(IanvsMarkdownEditorMode.source),
                ),
                _EditorModeTile(
                  tooltip: IanvsMarkdownMessage.readingMode.resolve(context),
                  label: IanvsMarkdownMessage.readLabel.resolve(context),
                  shortcut: IanvsMarkdownShortcuts.labelOf(
                    context,
                    IanvsMarkdownCommand.reading,
                  ),
                  icon: Icons.menu_book_outlined,
                  selected: mode == IanvsMarkdownEditorMode.preview,
                  colors: colors,
                  onTap: () => onModeSelected(IanvsMarkdownEditorMode.preview),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1, color: colors.border),
                ),
                _NavigationSectionLabel(
                  label: IanvsMarkdownMessage.outlineSection.resolve(context),
                  colors: colors,
                ),
                const SizedBox(height: 10),
                for (final heading in headings)
                  _EditorOutlineTile(
                    heading: heading,
                    selected: heading.blockStart == activeHeadingStart,
                    colors: colors,
                    onTap: () => onHeadingSelected(heading),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 10, 28, 22),
            child: Text(
              '⌘1–3 switch modes  ·  ⌘E edit',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationSectionLabel extends StatelessWidget {
  const _NavigationSectionLabel({required this.label, required this.colors});

  final String label;
  final IanvsMarkdownThemeData colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Text(
        label,
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: .75,
        ),
      ),
    );
  }
}

class _EditorModeTile extends StatelessWidget {
  const _EditorModeTile({
    required this.tooltip,
    required this.label,
    required this.shortcut,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String tooltip;
  final String label;
  final String shortcut;
  final IconData icon;
  final bool selected;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedSurface = Color.alphaBlend(
      colors.textPrimary.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .075 : .045,
      ),
      colors.surfaceMuted,
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Material(
            color: selected ? selectedSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onTap,
              hoverColor: colors.textPrimary.withValues(alpha: .035),
              focusColor: colors.accentMist,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                constraints: const BoxConstraints(minHeight: 42),
                padding: const EdgeInsets.only(left: 11, right: 10),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: selected
                          ? colors.accentDark
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? colors.textPrimary
                              : colors.textSecondary,
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      shortcut,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorOutlineTile extends StatelessWidget {
  const _EditorOutlineTile({
    required this.heading,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final _EditorNavigationHeading heading;
  final bool selected;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final indent = (heading.level - 1).clamp(0, 3) * 16.0;
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.textPrimary.withValues(alpha: .035),
          focusColor: colors.accentMist,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.only(right: 8, top: 5, bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 10,
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 2,
                        height: 16,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    heading.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: selected || heading.level <= 1
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextSelection _localSelectionToDocument(TextSelection local, int start) {
  if (!local.isValid) return TextSelection.collapsed(offset: start);
  return TextSelection(
    baseOffset: start + local.baseOffset,
    extentOffset: start + local.extentOffset,
    affinity: local.affinity,
    isDirectional: local.isDirectional,
  );
}

int _documentWordBoundary(String text, int offset, {required bool forward}) {
  var target = offset.clamp(0, text.length);
  var skippedWhitespace = false;
  if (forward) {
    while (target < text.length && _isWordBoundaryWhitespace(text[target])) {
      target += 1;
      skippedWhitespace = true;
    }
    if (target == text.length ||
        skippedWhitespace && _isMarkdownWordPunctuation(text[target])) {
      return target;
    }
    final punctuation = _isMarkdownWordPunctuation(text[target]);
    while (target < text.length &&
        !_isWordBoundaryWhitespace(text[target]) &&
        _isMarkdownWordPunctuation(text[target]) == punctuation) {
      target += 1;
    }
    return target;
  }

  while (target > 0 && _isWordBoundaryWhitespace(text[target - 1])) {
    target -= 1;
    skippedWhitespace = true;
  }
  if (target == 0 ||
      skippedWhitespace && _isMarkdownWordPunctuation(text[target - 1])) {
    return target;
  }
  final punctuation = _isMarkdownWordPunctuation(text[target - 1]);
  while (target > 0 &&
      !_isWordBoundaryWhitespace(text[target - 1]) &&
      _isMarkdownWordPunctuation(text[target - 1]) == punctuation) {
    target -= 1;
  }
  return target;
}

bool _isWordBoundaryWhitespace(String character) =>
    RegExp(r'\s').hasMatch(character);

bool _isMarkdownWordPunctuation(String character) => switch (character) {
  '!' ||
  '"' ||
  '#' ||
  r'$' ||
  '%' ||
  '&' ||
  "'" ||
  '(' ||
  ')' ||
  '*' ||
  '+' ||
  ',' ||
  '-' ||
  '.' ||
  '/' ||
  ':' ||
  ';' ||
  '<' ||
  '=' ||
  '>' ||
  '?' ||
  '@' ||
  '[' ||
  r'\' ||
  ']' ||
  '^' ||
  '`' ||
  '{' ||
  '|' ||
  '}' ||
  '~' => true,
  _ => false,
};

TextRange _localComposingToDocument(TextRange local, int start) {
  if (!local.isValid || local.isCollapsed) return TextRange.empty;
  return TextRange(start: start + local.start, end: start + local.end);
}

TextSelection _documentSelectionToLocal(
  TextSelection document,
  int start,
  int end,
) {
  if (!document.isValid || document.start < start || document.end > end) {
    return TextSelection.collapsed(offset: end - start);
  }
  return TextSelection(
    baseOffset: document.baseOffset - start,
    extentOffset: document.extentOffset - start,
    affinity: document.affinity,
    isDirectional: document.isDirectional,
  );
}

TextRange _documentComposingToLocal(TextRange document, int start, int end) {
  if (!document.isValid ||
      document.isCollapsed ||
      document.start < start ||
      document.end > end) {
    return TextRange.empty;
  }
  return TextRange(start: document.start - start, end: document.end - start);
}
