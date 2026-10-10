part of '../live_editor.dart';

final TextInputFormatter _tableCellInputFormatter =
    FilteringTextInputFormatter.deny(RegExp(r'[\r\n|]'));

TextEditingValue? _tablePlainPasteValue(
  TextEditingValue value,
  String pastedText,
) {
  final selection = value.selection;
  if (!selection.isValid) return null;
  final start = selection.start;
  final end = selection.end;
  if (start < 0 || end > value.text.length) return null;
  final replacement = value.copyWith(
    text: value.text.replaceRange(start, end, pastedText),
    selection: TextSelection.collapsed(offset: start + pastedText.length),
    composing: TextRange.empty,
  );
  return _tableCellInputFormatter.formatEditUpdate(value, replacement);
}

class _TablePasteAction extends ContextAction<PasteTextIntent> {
  _TablePasteAction({
    required this.controller,
    required this.commitHistoryGroup,
    required this.isCurrent,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback commitHistoryGroup;
  final bool Function() isCurrent;
  final ValueChanged<TextEditingValue> onChanged;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    final defaultAction = callingAction;
    final selection = controller.selection;
    if (!selection.isValid) {
      return defaultAction?.invoke(intent);
    }
    unawaited(_pasteSelectedText());
    return null;
  }

  Future<void> _pasteSelectedText() async {
    final data = await readPlainTextClipboardSafely();
    if (!isCurrent()) return;
    final pastedText = data?.text;
    if (pastedText == null) return;
    final replacement =
        smartUrlPasteValue(
          controller.value,
          pastedText,
          escapeTablePipes: true,
        ) ??
        _tablePlainPasteValue(controller.value, pastedText);
    if (replacement == null) return;
    commitHistoryGroup();
    controller.value = replacement;
    onChanged(replacement);
    commitHistoryGroup();
  }
}

TextEditingValue? _runTableMarkdownCommand(
  TextEditingValue value,
  bool Function(IanvsMarkdownController controller) command,
) {
  final commandController = IanvsMarkdownController(text: value.text)
    ..value = value.copyWith(composing: TextRange.empty);
  final handled = command(commandController);
  final replacement = handled ? commandController.value : null;
  commandController.dispose();
  return replacement;
}

class _TableWordDeletionAction
    extends ContextAction<DeleteToNextWordBoundaryIntent> {
  _TableWordDeletionAction({
    required this.controller,
    required this.commitHistoryGroup,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback commitHistoryGroup;
  final ValueChanged<TextEditingValue> onChanged;

  @override
  Object? invoke(
    DeleteToNextWordBoundaryIntent intent, [
    BuildContext? context,
  ]) {
    final replacement = _runTableMarkdownCommand(
      controller.value,
      (commandController) => commandController.deleteMarkdownPunctuationSegment(
        forward: intent.forward,
      ),
    );
    if (replacement == null) return callingAction?.invoke(intent);
    commitHistoryGroup();
    controller.value = replacement;
    onChanged(replacement);
    commitHistoryGroup();
    return null;
  }
}

class _TableWordMovementAction
    extends ContextAction<ExtendSelectionToNextWordBoundaryIntent> {
  _TableWordMovementAction(this.controller);

  final TextEditingController controller;

  @override
  Object? invoke(
    ExtendSelectionToNextWordBoundaryIntent intent, [
    BuildContext? context,
  ]) {
    final replacement = _runTableMarkdownCommand(
      controller.value,
      (commandController) => commandController.moveAcrossMarkdownPunctuation(
        forward: intent.forward,
        extendSelection: !intent.collapseSelection,
      ),
    );
    if (replacement == null) return callingAction?.invoke(intent);
    controller.value = replacement;
    return null;
  }
}

class _TableWordSelectionAction
    extends
        ContextAction<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent> {
  _TableWordSelectionAction(this.controller);

  final TextEditingController controller;

  @override
  Object? invoke(
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent intent, [
    BuildContext? context,
  ]) {
    final replacement = _runTableMarkdownCommand(
      controller.value,
      (commandController) => commandController.moveAcrossMarkdownPunctuation(
        forward: intent.forward,
        extendSelection: true,
      ),
    );
    if (replacement == null) return callingAction?.invoke(intent);
    controller.value = replacement;
    return null;
  }
}

class _EditableMarkdownTable extends StatefulWidget {
  const _EditableMarkdownTable({
    required this.block,
    required this.colors,
    required this.linkReferenceLabels,
    required this.onCommitHistoryGroup,
    required this.onCellChanged,
    required this.onCellFormatted,
    required this.onCellSelectionChanged,
    required this.onSelectAll,
    required this.onDeleteLine,
    required this.onAddRow,
    required this.onAddRowAbove,
    required this.onAddColumn,
    required this.onMoveRow,
    required this.onMoveColumn,
  });

  final IanvsMarkdownBlock block;
  final IanvsMarkdownThemeData colors;
  final Set<String> linkReferenceLabels;
  final VoidCallback onCommitHistoryGroup;
  final void Function(_EditableTableCell cell, TextEditingValue value)
  onCellChanged;
  final void Function(_EditableTableCell cell, TextEditingValue value)
  onCellFormatted;
  final void Function(_EditableTableCell cell, TextEditingValue value)
  onCellSelectionChanged;
  final VoidCallback onSelectAll;
  final ValueChanged<_EditableTableCell> onDeleteLine;
  final VoidCallback onAddRow;
  final VoidCallback onAddRowAbove;
  final VoidCallback onAddColumn;
  final void Function(int from, int to) onMoveRow;
  final void Function(int from, int to) onMoveColumn;

  @override
  State<_EditableMarkdownTable> createState() => _EditableMarkdownTableState();
}

class _EditableMarkdownTableState extends State<_EditableMarkdownTable> {
  static const double _handleExtent = 16;
  static const double _minimumCellHeight = 32;

  final GlobalKey _tableGeometryKey = GlobalKey(
    debugLabel: 'ianvs-markdown-table-geometry',
  );
  final Map<String, _TableCellEditingController> _controllers = {};
  final Set<String> _syncingControllerKeys = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, GlobalKey> _cellGeometryKeys = {};
  final Map<int, LayerLink> _rowHandleLinks = {};
  final Map<int, LayerLink> _columnHandleLinks = {};
  final Map<int, double> _rowHandleLengths = {};
  final Map<int, double> _columnHandleLengths = {};
  late _EditableTableModel _model;
  String? _pendingFocusKey;
  _TableFocusPlacement _pendingFocusPlacement = _TableFocusPlacement.start;
  _TableDragAxis? _dragAxis;
  int? _dragSourceIndex;
  int? _dragTargetIndex;
  int? _dragPointer;
  Offset? _dragStartPosition;
  Offset _dragOffset = Offset.zero;
  int? _selectedRow;
  int? _selectedColumn;

  @override
  void initState() {
    super.initState();
    _syncModel();
  }

  @override
  void didUpdateWidget(covariant _EditableMarkdownTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncModel();
  }

  void _syncModel() {
    _model = _parseEditableTable(widget.block);
    final keys = _model.rows
        .expand((row) => row)
        .map((cell) => cell.key)
        .toSet();
    for (final cell in _model.rows.expand((row) => row)) {
      _focusNodes.putIfAbsent(cell.key, () {
        final node = FocusNode();
        node.addListener(_handleCellFocusChanged);
        return node;
      });
      final controller = _controllers.putIfAbsent(cell.key, () {
        final controller = _TableCellEditingController(text: cell.text);
        controller.addListener(
          () => _handleCellControllerChanged(cell.key, controller),
        );
        return controller;
      });
      if (controller.text != cell.text) {
        _syncingControllerKeys.add(cell.key);
        try {
          controller.value = TextEditingValue(
            text: cell.text,
            selection: TextSelection.collapsed(
              offset: controller.selection.extentOffset.clamp(
                0,
                cell.text.length,
              ),
            ),
          );
        } finally {
          _syncingControllerKeys.remove(cell.key);
        }
      }
    }
    final removedControllers = _controllers.keys
        .where((key) => !keys.contains(key))
        .toList();
    for (final key in removedControllers) {
      _controllers.remove(key)?.dispose();
      final node = _focusNodes.remove(key);
      node?.removeListener(_handleCellFocusChanged);
      node?.dispose();
      _cellGeometryKeys.remove(key);
    }
    _rowHandleLinks.removeWhere((row, _) => row >= _model.rows.length);
    _rowHandleLengths.removeWhere((row, _) => row >= _model.rows.length);
    final columnCount = _model.rows.isEmpty ? 0 : _model.rows.first.length;
    _columnHandleLinks.removeWhere((column, _) => column >= columnCount);
    _columnHandleLengths.removeWhere((column, _) => column >= columnCount);
    if ((_selectedRow ?? -1) >= _model.rows.length) _selectedRow = null;
    if ((_selectedColumn ?? -1) >= columnCount) _selectedColumn = null;
    final pendingFocusKey = _pendingFocusKey;
    if (pendingFocusKey != null && _focusNodes.containsKey(pendingFocusKey)) {
      _pendingFocusKey = null;
      final placement = _pendingFocusPlacement;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusCell(pendingFocusKey, placement: placement);
      });
    }
  }

  void _handleCellFocusChanged() {
    if (mounted) setState(() {});
  }

  void _handleCellControllerChanged(
    String key,
    TextEditingController controller,
  ) {
    if (!mounted ||
        _syncingControllerKeys.contains(key) ||
        !identical(_controllers[key], controller)) {
      return;
    }
    final cell = _cellForKey(key);
    if (cell == null || controller.text != cell.text) return;
    widget.onCellSelectionChanged(cell, controller.value);
  }

  _EditableTableCell? _cellForKey(String key) {
    for (final row in _model.rows) {
      for (final cell in row) {
        if (cell.key == key) return cell;
      }
    }
    return null;
  }

  void _handleFormattedCellAction(
    String key,
    TextEditingController expectedController,
    TextEditingValue value,
  ) {
    if (!mounted || !identical(_controllers[key], expectedController)) return;
    final cell = _cellForKey(key);
    if (cell == null) return;
    widget.onCellFormatted(cell, value);
  }

  void _addRow({int column = 0}) {
    _pendingFocusKey = '${_model.rows.length}-$column';
    _pendingFocusPlacement = _TableFocusPlacement.start;
    widget.onAddRow();
  }

  void _addRowAbove() {
    _pendingFocusKey = '0-${_model.rows.first.length - 1}';
    _pendingFocusPlacement = _TableFocusPlacement.start;
    widget.onAddRowAbove();
  }

  void _addColumn() {
    _pendingFocusKey = '0-${_model.rows.first.length}';
    _pendingFocusPlacement = _TableFocusPlacement.start;
    widget.onAddColumn();
  }

  GlobalKey _cellGeometryKey(String key) => _cellGeometryKeys.putIfAbsent(
    key,
    () => GlobalKey(debugLabel: 'ianvs-markdown-table-cell-$key'),
  );

  LayerLink _rowHandleLink(int row) =>
      _rowHandleLinks.putIfAbsent(row, LayerLink.new);

  LayerLink _columnHandleLink(int column) =>
      _columnHandleLinks.putIfAbsent(column, LayerLink.new);

  void _syncTableHandleLengths() {
    if (!mounted) return;
    var changed = false;
    final tableRender = _tableGeometryKey.currentContext?.findRenderObject();
    // This callback runs after layout. debugNeedsLayout itself throws in
    // profile/release on supported Flutter versions; only read it in debug.
    if (tableRender is RenderTable &&
        tableRender.hasSize &&
        (!kDebugMode || !tableRender.debugNeedsLayout)) {
      for (var row = 0; row < tableRender.rows; row++) {
        final height = tableRender.getRowBox(row).height;
        if (_rowHandleLengths[row] != height) {
          _rowHandleLengths[row] = height;
          changed = true;
        }
      }
    }
    final columnCount = _model.rows.isEmpty ? 0 : _model.rows.first.length;
    for (var column = 0; column < columnCount; column++) {
      final renderObject = _cellGeometryKeys['0-$column']?.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final width = renderObject.size.width;
      if (_columnHandleLengths[column] != width) {
        _columnHandleLengths[column] = width;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  bool get _mobileTableControls => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  (int, int)? get _focusedCellCoordinates {
    for (final entry in _focusNodes.entries) {
      if (!entry.value.hasFocus) continue;
      final separator = entry.key.indexOf('-');
      if (separator <= 0) return null;
      final row = int.tryParse(entry.key.substring(0, separator));
      final column = int.tryParse(entry.key.substring(separator + 1));
      if (row != null && column != null) return (row, column);
    }
    return null;
  }

  void _startTableDrag(_TableDragAxis axis, int index, PointerDownEvent event) {
    if (_dragPointer != null || !event.down || event.buttons & 1 == 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _dragAxis = axis;
      _dragSourceIndex = index;
      _dragTargetIndex = index;
      _dragPointer = event.pointer;
      _dragStartPosition = event.position;
      _dragOffset = Offset.zero;
      if (axis == _TableDragAxis.row) {
        _selectedRow = index;
        _selectedColumn = null;
      } else {
        _selectedColumn = index;
        _selectedRow = null;
      }
    });
  }

  void _updateTableDrag(PointerMoveEvent event) {
    final axis = _dragAxis;
    if (axis == null || event.pointer != _dragPointer) return;
    final target = _tableDragTargetAt(axis, event.position);
    setState(() {
      _dragOffset = event.position - (_dragStartPosition ?? event.position);
      if (target != null) _dragTargetIndex = target;
    });
  }

  int? _tableDragTargetAt(_TableDragAxis axis, Offset globalPosition) {
    final count = axis == _TableDragAxis.row
        ? _model.rows.length
        : (_model.rows.isEmpty ? 0 : _model.rows.first.length);
    if (count == 0) return null;
    final coordinate = axis == _TableDragAxis.row
        ? globalPosition.dy
        : globalPosition.dx;
    double? smallestMinimum;
    double? largestMaximum;
    var smallestIndex = 0;
    var largestIndex = count - 1;
    for (var index = 0; index < count; index++) {
      final key = axis == _TableDragAxis.row ? '$index-0' : '0-$index';
      final renderObject = _cellGeometryKeys[key]?.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final origin = renderObject.localToGlobal(Offset.zero);
      final rect = origin & renderObject.size;
      final minimum = axis == _TableDragAxis.row ? rect.top : rect.left;
      final maximum = axis == _TableDragAxis.row ? rect.bottom : rect.right;
      if (smallestMinimum == null || minimum < smallestMinimum) {
        smallestMinimum = minimum;
        smallestIndex = index;
      }
      if (largestMaximum == null || maximum > largestMaximum) {
        largestMaximum = maximum;
        largestIndex = index;
      }
      if (coordinate >= minimum && coordinate <= maximum) return index;
    }
    if (smallestMinimum == null || largestMaximum == null) return null;
    return coordinate < smallestMinimum ? smallestIndex : largestIndex;
  }

  void _finishTableDrag(PointerUpEvent event) {
    if (event.pointer != _dragPointer) return;
    final axis = _dragAxis;
    final source = _dragSourceIndex;
    final target = _dragTargetIndex;
    setState(() {
      _dragAxis = null;
      _dragSourceIndex = null;
      _dragTargetIndex = null;
      _dragPointer = null;
      _dragStartPosition = null;
      _dragOffset = Offset.zero;
      if (axis == _TableDragAxis.row) {
        _selectedRow = target;
      } else if (axis == _TableDragAxis.column) {
        _selectedColumn = target;
      }
    });
    if (axis == null || source == null || target == null || source == target) {
      return;
    }
    if (axis == _TableDragAxis.row) {
      widget.onMoveRow(source, target);
    } else {
      widget.onMoveColumn(source, target);
    }
  }

  void _cancelTableDrag(PointerCancelEvent event) {
    if (event.pointer != _dragPointer) return;
    setState(() {
      _dragAxis = null;
      _dragSourceIndex = null;
      _dragTargetIndex = null;
      _dragPointer = null;
      _dragStartPosition = null;
      _dragOffset = Offset.zero;
    });
  }

  void _clearTableSelection() {
    if (_selectedRow == null && _selectedColumn == null) return;
    setState(() {
      _selectedRow = null;
      _selectedColumn = null;
    });
  }

  KeyEventResult _handleCellKey(_EditableTableCell cell, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final usesCommandModifier =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final selectAllModifier = usesCommandModifier
        ? HardwareKeyboard.instance.isMetaPressed &&
              !HardwareKeyboard.instance.isControlPressed
        : HardwareKeyboard.instance.isControlPressed &&
              !HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.keyA &&
        selectAllModifier &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onSelectAll();
      return KeyEventResult.handled;
    }
    final inlineCommand = _tableInlineCommandForKey(key);
    if (inlineCommand != null && _hasTableInlineCommandModifier(key)) {
      _applyTableInlineCommand(cell, inlineCommand);
      return KeyEventResult.handled;
    }
    final deleteLineModifier = usesCommandModifier
        ? HardwareKeyboard.instance.isMetaPressed &&
              !HardwareKeyboard.instance.isControlPressed
        : HardwareKeyboard.instance.isControlPressed &&
              !HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.keyD &&
        deleteLineModifier &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onDeleteLine(cell);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isAltPressed) {
        return KeyEventResult.ignored;
      }
      _moveTab(cell, backwards: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      final targetRow = cell.row + 1;
      if (targetRow < _model.rows.length) {
        _focusCell(
          _model.rows[targetRow][cell.column].key,
          placement: _TableFocusPlacement.selectAll,
        );
      } else {
        _addRow(column: cell.column);
      }
      return KeyEventResult.handled;
    }
    final directionalKey =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    if (directionalKey &&
        (HardwareKeyboard.instance.isAltPressed ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isShiftPressed)) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return _moveVertical(cell, -1);
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return _moveVertical(cell, 1);
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return _moveHorizontalAtBoundary(cell, -1);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return _moveHorizontalAtBoundary(cell, 1);
    }
    return KeyEventResult.ignored;
  }

  bool _handleConfiguredCellCommand(
    _EditableTableCell cell,
    IanvsMarkdownCommand command,
    BuildContext focused,
  ) {
    final inline = switch (command) {
      IanvsMarkdownCommand.bold => _TableInlineCommand.bold,
      IanvsMarkdownCommand.italic => _TableInlineCommand.italic,
      IanvsMarkdownCommand.insertLink => _TableInlineCommand.link,
      _ => null,
    };
    if (inline != null) {
      _applyTableInlineCommand(cell, inline);
      return true;
    }
    switch (command) {
      case IanvsMarkdownCommand.selectAll:
        widget.onSelectAll();
        return true;
      case IanvsMarkdownCommand.deleteLine:
        widget.onDeleteLine(cell);
        return true;
      case IanvsMarkdownCommand.indent:
      case IanvsMarkdownCommand.outdent:
        _moveTab(cell, backwards: command == IanvsMarkdownCommand.outdent);
        return true;
      default:
        return invokeMarkdownTextCommand(command, focused);
    }
  }

  bool _hasTableInlineCommandModifier(LogicalKeyboardKey key) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed || keyboard.isShiftPressed) return false;
    final usesCommandModifier =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (usesCommandModifier && key == LogicalKeyboardKey.keyI) {
      return keyboard.isMetaPressed != keyboard.isControlPressed;
    }
    return usesCommandModifier
        ? keyboard.isMetaPressed && !keyboard.isControlPressed
        : keyboard.isControlPressed && !keyboard.isMetaPressed;
  }

  void _applyTableInlineCommand(
    _EditableTableCell cell,
    _TableInlineCommand command,
  ) {
    final cellController = _controllers[cell.key];
    if (cellController == null) return;
    final commandController = IanvsMarkdownController(text: cellController.text)
      ..value = cellController.value.copyWith(composing: TextRange.empty);
    switch (command) {
      case _TableInlineCommand.bold:
        commandController.toggleInline('**');
        break;
      case _TableInlineCommand.italic:
        commandController.toggleInline('*');
        break;
      case _TableInlineCommand.link:
        commandController.insertLink();
        break;
    }
    final replacement = commandController.value;
    commandController.dispose();
    widget.onCommitHistoryGroup();
    cellController.value = replacement;
    widget.onCellFormatted(cell, replacement);
    widget.onCommitHistoryGroup();
  }

  void _moveTab(_EditableTableCell cell, {required bool backwards}) {
    final cells = _model.rows.expand((row) => row).toList();
    final index = cells.indexWhere((candidate) => candidate.key == cell.key);
    if (index < 0) return;
    final targetIndex = backwards ? index - 1 : index + 1;
    if (targetIndex >= 0 && targetIndex < cells.length) {
      _focusCell(
        cells[targetIndex].key,
        placement: _TableFocusPlacement.selectAll,
      );
    } else if (backwards) {
      _addRowAbove();
    } else {
      _addRow();
    }
  }

  KeyEventResult _moveVertical(_EditableTableCell cell, int delta) {
    final targetRow = cell.row + delta;
    if (targetRow < 0 || targetRow >= _model.rows.length) {
      return KeyEventResult.ignored;
    }
    final target = _model.rows[targetRow][cell.column];
    final controller = _controllers[cell.key];
    final offset = controller?.selection.isValid ?? false
        ? controller!.selection.extentOffset
        : 0;
    _focusCell(
      target.key,
      placement: _TableFocusPlacement.preserve,
      offset: offset,
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _moveHorizontalAtBoundary(_EditableTableCell cell, int delta) {
    final controller = _controllers[cell.key];
    if (controller == null || !controller.selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final atBoundary = delta < 0
        ? controller.selection.extentOffset == 0
        : controller.selection.extentOffset == controller.text.length;
    if (!atBoundary) return KeyEventResult.ignored;

    final cells = _model.rows.expand((row) => row).toList();
    final index = cells.indexWhere((candidate) => candidate.key == cell.key);
    final targetIndex = index + delta;
    if (index < 0 || targetIndex < 0 || targetIndex >= cells.length) {
      return KeyEventResult.ignored;
    }
    _focusCell(
      cells[targetIndex].key,
      placement: delta < 0
          ? _TableFocusPlacement.end
          : _TableFocusPlacement.start,
    );
    return KeyEventResult.handled;
  }

  void _focusCell(
    String key, {
    required _TableFocusPlacement placement,
    int offset = 0,
  }) {
    final controller = _controllers[key];
    final focusNode = _focusNodes[key];
    if (controller == null || focusNode == null) return;
    focusNode.requestFocus();
    controller.selection = switch (placement) {
      _TableFocusPlacement.selectAll => TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      ),
      _TableFocusPlacement.start => const TextSelection.collapsed(offset: 0),
      _TableFocusPlacement.end => TextSelection.collapsed(
        offset: controller.text.length,
      ),
      _TableFocusPlacement.preserve => TextSelection.collapsed(
        offset: offset.clamp(0, controller.text.length),
      ),
    };
  }

  BoxDecoration? _tableCellDecoration(
    _EditableTableCell cell,
    TextDirection direction,
  ) {
    final selected = cell.row == _selectedRow || cell.column == _selectedColumn;
    BorderSide? top;
    BorderSide? right;
    BorderSide? bottom;
    BorderSide? left;
    final source = _dragSourceIndex;
    final target = _dragTargetIndex;
    if (source != null && target != null && source != target) {
      final indicator = BorderSide(color: widget.colors.accent, width: 2);
      if (_dragAxis == _TableDragAxis.row && cell.row == target) {
        if (target < source) {
          top = indicator;
        } else {
          bottom = indicator;
        }
      } else if (_dragAxis == _TableDragAxis.column && cell.column == target) {
        final atLogicalStart = target < source;
        if ((direction == TextDirection.ltr && atLogicalStart) ||
            (direction == TextDirection.rtl && !atLogicalStart)) {
          left = indicator;
        } else {
          right = indicator;
        }
      }
    }
    if (!selected &&
        top == null &&
        right == null &&
        bottom == null &&
        left == null) {
      return null;
    }
    return BoxDecoration(
      color: selected ? widget.colors.accentMist.withValues(alpha: .72) : null,
      border: Border(
        top: top ?? BorderSide.none,
        right: right ?? BorderSide.none,
        bottom: bottom ?? BorderSide.none,
        left: left ?? BorderSide.none,
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.removeListener(_handleCellFocusChanged);
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_model.rows.isEmpty) return const SizedBox.shrink();
    final syntaxTheme = _tableCellSyntaxTheme(
      widget.colors,
      Theme.of(context).brightness,
    );
    final showControls =
        _mobileTableControls &&
        _focusNodes.values.any((focusNode) => focusNode.hasFocus);
    final focusedCell = _focusedCellCoordinates;
    final direction = Directionality.of(context);
    final rowCount = _model.rows.length;
    final columnCount = _model.rows.first.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTableHandleLengths();
    });
    return SizedBox(
      key: const ValueKey('ianvs-markdown-editable-table'),
      width: double.infinity,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: IanvsMarkdownMessage.editableTable.resolve(context),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(_handleExtent),
              child: Table(
                key: _tableGeometryKey,
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                defaultColumnWidth: const IntrinsicColumnWidth(),
                columnWidths: _obsidianTableColumnWidths(_model),
                border: TableBorder.all(color: widget.colors.borderSoft),
                children: [
                  for (final row in _model.rows)
                    TableRow(
                      decoration: row.first.isHeader
                          ? BoxDecoration(color: widget.colors.surfaceMuted)
                          : null,
                      children: [
                        for (final cell in row)
                          Builder(
                            builder: (context) {
                              final focusNode = _focusNodes[cell.key]!;
                              final controller = _controllers[cell.key]!
                                ..syntaxTheme = syntaxTheme
                                ..linkReferenceLabels =
                                    widget.linkReferenceLabels
                                ..revealSource = focusNode.hasFocus;
                              final editor = Focus(
                                onKeyEvent: (_, event) =>
                                    _handleCellKey(cell, event),
                                child: Actions(
                                  actions: <Type, Action<Intent>>{
                                    PasteTextIntent: _TablePasteAction(
                                      controller: controller,
                                      commitHistoryGroup:
                                          widget.onCommitHistoryGroup,
                                      isCurrent: () =>
                                          mounted &&
                                          identical(
                                            _controllers[cell.key],
                                            controller,
                                          ),
                                      onChanged: (value) =>
                                          _handleFormattedCellAction(
                                            cell.key,
                                            controller,
                                            value,
                                          ),
                                    ),
                                    DeleteToNextWordBoundaryIntent:
                                        _TableWordDeletionAction(
                                          controller: controller,
                                          commitHistoryGroup:
                                              widget.onCommitHistoryGroup,
                                          onChanged: (value) =>
                                              _handleFormattedCellAction(
                                                cell.key,
                                                controller,
                                                value,
                                              ),
                                        ),
                                    ExtendSelectionToNextWordBoundaryIntent:
                                        _TableWordMovementAction(controller),
                                    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
                                        _TableWordSelectionAction(controller),
                                  },
                                  child: Listener(
                                    behavior: HitTestBehavior.translucent,
                                    onPointerDown: (_) {
                                      _clearTableSelection();
                                    },
                                    child: MarkdownCommandTarget(
                                      kind: MarkdownCommandKind.table,
                                      onCommand: (command, focused) =>
                                          _handleConfiguredCellCommand(
                                            cell,
                                            command,
                                            focused,
                                          ),
                                      child: TextField(
                                        contextMenuBuilder: (_, state) =>
                                            buildMarkdownTextContextMenu(
                                              context,
                                              state,
                                            ),
                                        key: ValueKey(
                                          'ianvs-markdown-table-${cell.key}',
                                        ),
                                        controller: controller,
                                        focusNode: focusNode,
                                        maxLines: null,
                                        keyboardType: TextInputType.text,
                                        textInputAction: TextInputAction.next,
                                        smartDashesType:
                                            SmartDashesType.disabled,
                                        smartQuotesType:
                                            SmartQuotesType.disabled,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        inputFormatters: [
                                          _tableCellInputFormatter,
                                        ],
                                        textAlign: cell.alignment,
                                        style: TextStyle(
                                          color: widget.colors.textPrimary,
                                          fontSize: 13.5,
                                          height: 1.35,
                                          fontWeight: cell.isHeader
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                        cursorColor: widget.colors.accent,
                                        cursorWidth: 1.5,
                                        decoration: const InputDecoration(
                                          // The table owns cell backgrounds; host
                                          // form-field fills must not cover them.
                                          filled: false,
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          isCollapsed: true,
                                          visualDensity: VisualDensity.standard,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                        ),
                                        onChanged: (_) => widget.onCellChanged(
                                          cell,
                                          controller.value,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                              Widget surface = Semantics(
                                key: ValueKey(
                                  'ianvs-markdown-table-cell-semantics-${cell.key}',
                                ),
                                container: true,
                                explicitChildNodes: focusNode.hasFocus,
                                role: cell.isHeader
                                    ? SemanticsRole.columnHeader
                                    : SemanticsRole.cell,
                                label: focusNode.hasFocus
                                    ? null
                                    : _tableCellDisplayText(cell.text),
                                value: focusNode.hasFocus
                                    ? controller.text
                                    : null,
                                onTap: focusNode.hasFocus
                                    ? null
                                    : () => _focusCell(
                                        cell.key,
                                        placement:
                                            _TableFocusPlacement.selectAll,
                                      ),
                                child: focusNode.hasFocus
                                    ? editor
                                    : ExcludeSemantics(child: editor),
                              );
                              surface = Container(
                                key: ValueKey(
                                  'ianvs-markdown-table-cell-surface-${cell.key}',
                                ),
                                // Keep row sizing independent of InputDecorator's
                                // density and minimum-height text positioning.
                                constraints: const BoxConstraints(
                                  minHeight: _minimumCellHeight,
                                ),
                                alignment: Alignment.center,
                                decoration: _tableCellDecoration(
                                  cell,
                                  direction,
                                ),
                                child: surface,
                              );
                              surface = KeyedSubtree(
                                key: _cellGeometryKey(cell.key),
                                child: surface,
                              );
                              if (cell.column == 0) {
                                surface = CompositedTransformTarget(
                                  link: _rowHandleLink(cell.row),
                                  child: surface,
                                );
                              }
                              if (cell.row == 0) {
                                surface = CompositedTransformTarget(
                                  link: _columnHandleLink(cell.column),
                                  child: surface,
                                );
                              }
                              return surface;
                            },
                          ),
                      ],
                    ),
                ],
              ),
            ),
            for (var row = 0; row < rowCount; row++)
              CompositedTransformFollower(
                link: _rowHandleLink(row),
                showWhenUnlinked: false,
                targetAnchor: Alignment.centerLeft,
                followerAnchor: Alignment.centerRight,
                child: Transform.translate(
                  offset:
                      _dragAxis == _TableDragAxis.row && _dragSourceIndex == row
                      ? Offset(0, _dragOffset.dy)
                      : Offset.zero,
                  child: _TableDragHandle(
                    key: ValueKey('ianvs-markdown-table-row-drag-$row'),
                    axis: _TableDragAxis.row,
                    index: row,
                    length: _rowHandleLengths[row] ?? 24,
                    colors: widget.colors,
                    active:
                        _dragAxis == _TableDragAxis.row &&
                            _dragSourceIndex == row ||
                        _mobileTableControls &&
                            (focusedCell?.$1 == row || _selectedRow == row),
                    dragging:
                        _dragAxis == _TableDragAxis.row &&
                        _dragSourceIndex == row,
                    onPointerDown: (event) =>
                        _startTableDrag(_TableDragAxis.row, row, event),
                    onPointerMove: _updateTableDrag,
                    onPointerUp: _finishTableDrag,
                    onPointerCancel: _cancelTableDrag,
                  ),
                ),
              ),
            for (var column = 0; column < columnCount; column++)
              CompositedTransformFollower(
                link: _columnHandleLink(column),
                showWhenUnlinked: false,
                targetAnchor: Alignment.topCenter,
                followerAnchor: Alignment.bottomCenter,
                child: Transform.translate(
                  offset:
                      _dragAxis == _TableDragAxis.column &&
                          _dragSourceIndex == column
                      ? Offset(_dragOffset.dx, 0)
                      : Offset.zero,
                  child: _TableDragHandle(
                    key: ValueKey('ianvs-markdown-table-column-drag-$column'),
                    axis: _TableDragAxis.column,
                    index: column,
                    length: _columnHandleLengths[column] ?? 24,
                    colors: widget.colors,
                    active:
                        _dragAxis == _TableDragAxis.column &&
                            _dragSourceIndex == column ||
                        _mobileTableControls &&
                            (focusedCell?.$2 == column ||
                                _selectedColumn == column),
                    dragging:
                        _dragAxis == _TableDragAxis.column &&
                        _dragSourceIndex == column,
                    onPointerDown: (event) =>
                        _startTableDrag(_TableDragAxis.column, column, event),
                    onPointerMove: _updateTableDrag,
                    onPointerUp: _finishTableDrag,
                    onPointerCancel: _cancelTableDrag,
                  ),
                ),
              ),
            Positioned(
              right: 0,
              top: _handleExtent,
              bottom: _handleExtent,
              width: _handleExtent,
              child: _TableStructureButton(
                key: const ValueKey('ianvs-markdown-table-add-column'),
                colors: widget.colors,
                visible: showControls,
                tooltip: IanvsMarkdownMessage.addColumn.resolve(context),
                icon: Icons.add_rounded,
                onPressed: _addColumn,
              ),
            ),
            Positioned(
              left: _handleExtent,
              right: _handleExtent,
              bottom: 0,
              height: _handleExtent,
              child: _TableStructureButton(
                key: const ValueKey('ianvs-markdown-table-add-row'),
                colors: widget.colors,
                visible: showControls,
                tooltip: IanvsMarkdownMessage.addRow.resolve(context),
                icon: Icons.add_rounded,
                onPressed: _addRow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableCellEditingController extends TextEditingController {
  _TableCellEditingController({required String text}) : super(text: text);

  late IanvsMarkdownSyntaxTheme syntaxTheme;
  Set<String> linkReferenceLabels = const <String>{};
  var revealSource = false;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final displayValue = revealSource
        ? value
        : value.copyWith(
            selection: const TextSelection.collapsed(offset: -1),
            composing: TextRange.empty,
          );
    return buildMarkdownSourceTextSpan(
      displayValue,
      style: style,
      syntaxTheme: syntaxTheme,
      withComposing: withComposing && revealSource,
      hideInactiveInlineMarkers: !revealSource,
      hideInactiveEscapeMarkers: !revealSource,
      linkReferenceLabels: linkReferenceLabels,
    );
  }
}

IanvsMarkdownSyntaxTheme _tableCellSyntaxTheme(
  IanvsMarkdownThemeData colors,
  Brightness brightness,
) {
  return IanvsMarkdownSyntaxTheme(
    heading: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
    marker: TextStyle(color: colors.textTertiary),
    link: TextStyle(
      color: colors.accentDark,
      decoration: TextDecoration.underline,
      decorationColor: colors.accentDark,
    ),
    code: ianvsMarkdownInlineCodeStyle(colors),
    inlineCodeMarker: ianvsMarkdownInlineCodeStyle(colors),
    math: TextStyle(
      color: colors.accentDark,
      fontFamily: colors.monoFontFamily,
      fontFamilyFallback: colors.monoFontFamilyFallback,
    ),
    comment: TextStyle(color: colors.textTertiary, fontStyle: FontStyle.italic),
    strong: TextStyle(
      color: colors.strongForeground,
      fontWeight: FontWeight.w600,
    ),
    emphasis: TextStyle(
      color: colors.emphasisForeground,
      fontStyle: FontStyle.italic,
    ),
    wikiLink: TextStyle(
      color: colors.accentDark,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: colors.accentDark,
    ),
    tag: TextStyle(
      color: colors.accentDark,
      backgroundColor: colors.accentMist,
      fontWeight: FontWeight.w600,
    ),
    highlight: TextStyle(
      color: colors.textPrimary,
      backgroundColor: brightness == Brightness.dark
          ? const Color(0xff6b5b22)
          : const Color(0xffffe184),
    ),
  );
}

enum _TableFocusPlacement { selectAll, start, end, preserve }

enum _TableInlineCommand { bold, italic, link }

_TableInlineCommand? _tableInlineCommandForKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.keyB) return _TableInlineCommand.bold;
  if (key == LogicalKeyboardKey.keyI) return _TableInlineCommand.italic;
  if (key == LogicalKeyboardKey.keyK) return _TableInlineCommand.link;
  return null;
}

enum _TableDragAxis { row, column }

class _TableDragHandle extends StatefulWidget {
  const _TableDragHandle({
    super.key,
    required this.axis,
    required this.index,
    required this.length,
    required this.colors,
    required this.active,
    required this.dragging,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  final _TableDragAxis axis;
  final int index;
  final double length;
  final IanvsMarkdownThemeData colors;
  final bool active;
  final bool dragging;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final ValueChanged<PointerMoveEvent> onPointerMove;
  final ValueChanged<PointerUpEvent> onPointerUp;
  final ValueChanged<PointerCancelEvent> onPointerCancel;

  @override
  State<_TableDragHandle> createState() => _TableDragHandleState();
}

class _TableDragHandleState extends State<_TableDragHandle> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final mobile = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final visible = widget.active || _hovering;
    final label = widget.axis == _TableDragAxis.row
        ? IanvsMarkdownMessage.dragRow.resolve(
            context,
            arguments: {'index': widget.index + 1},
          )
        : IanvsMarkdownMessage.dragColumn.resolve(
            context,
            arguments: {'index': widget.index + 1},
          );
    final icon = Icon(Icons.drag_indicator_rounded, size: 14);
    final orientedIcon = widget.axis == _TableDragAxis.row
        ? icon
        : RotatedBox(quarterTurns: 1, child: icon);
    return IgnorePointer(
      ignoring: mobile && !widget.active,
      child: MouseRegion(
        cursor: widget.dragging
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Semantics(
          container: true,
          button: true,
          label: label,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: widget.onPointerDown,
            onPointerMove: widget.onPointerMove,
            onPointerUp: widget.onPointerUp,
            onPointerCancel: widget.onPointerCancel,
            child: AnimatedOpacity(
              key: ValueKey(
                'ianvs-markdown-table-${widget.axis.name}-drag-${widget.index}-opacity',
              ),
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 100),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: widget.axis == _TableDragAxis.row ? 16 : widget.length,
                height: widget.axis == _TableDragAxis.row ? widget.length : 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.dragging
                      ? widget.colors.accent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: widget.dragging
                      ? <BoxShadow>[
                          BoxShadow(
                            color: widget.colors.accent.withValues(alpha: .35),
                            blurRadius: 0,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: IconTheme(
                  data: IconThemeData(
                    color: widget.dragging
                        ? widget.colors.surface
                        : widget.colors.textTertiary,
                  ),
                  child: orientedIcon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TableStructureButton extends StatefulWidget {
  const _TableStructureButton({
    super.key,
    required this.colors,
    required this.visible,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final IanvsMarkdownThemeData colors;
  final bool visible;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_TableStructureButton> createState() => _TableStructureButtonState();
}

class _TableStructureButtonState extends State<_TableStructureButton> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedOpacity(
        opacity: widget.visible || _hovering ? 1 : 0,
        duration: const Duration(milliseconds: 100),
        alwaysIncludeSemantics: true,
        child: Tooltip(
          message: widget.tooltip,
          child: Semantics(
            container: true,
            button: true,
            label: widget.tooltip,
            onTap: widget.onPressed,
            child: ExcludeSemantics(
              child: SizedBox.expand(
                child: IconButton(
                  onPressed: widget.onPressed,
                  icon: Icon(widget.icon, size: 12),
                  color: widget.colors.textTertiary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: widget.colors.borderSoft),
                    shape: const RoundedRectangleBorder(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _EditableTableModel {
  const _EditableTableModel(this.rows, this.alignments);

  final List<List<_EditableTableCell>> rows;
  final List<_EditableTableAlignment> alignments;
}

enum _EditableTableAlignment { none, left, center, right }

Map<int, TableColumnWidth> _obsidianTableColumnWidths(
  _EditableTableModel model,
) {
  if (model.rows.isEmpty || model.rows.first.isEmpty) {
    return const <int, TableColumnWidth>{};
  }
  final columnCount = model.rows.first.length;
  final contentScores = List<int>.filled(columnCount, 1);
  for (final row in model.rows) {
    for (var column = 0; column < row.length; column += 1) {
      final score = _tableCellDisplayScore(row[column].text);
      if (score > contentScores[column]) contentScores[column] = score;
    }
  }
  final largestScore = contentScores.reduce((left, right) {
    return left > right ? left : right;
  });
  final flexibleThreshold = largestScore * .8;
  return <int, TableColumnWidth>{
    for (var column = 0; column < columnCount; column += 1)
      column: _WrappingIntrinsicColumnWidth(
        columnCount: columnCount,
        flex: contentScores[column] >= flexibleThreshold ? 1 : null,
      ),
  };
}

final class _WrappingIntrinsicColumnWidth extends IntrinsicColumnWidth {
  const _WrappingIntrinsicColumnWidth({required this.columnCount, super.flex});

  final int columnCount;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    // Long tokens can exceed the document width. Let them wrap so columns stay
    // inside the table's painted and interactive bounds, while retaining their
    // content-based preferred widths and flex allocation.
    return math.min(
      super.minIntrinsicWidth(cells, containerWidth),
      containerWidth / columnCount,
    );
  }
}

int _tableCellDisplayScore(String source) {
  return _tableCellDisplayText(source).runes.length;
}

String _tableCellDisplayText(String source) {
  var visible = _protectTableCellEscapes(source).replaceAllMapped(
    RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]'),
    (match) => match.group(2) ?? match.group(1) ?? '',
  );
  visible = visible.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  visible = visible.replaceAllMapped(
    RegExp(r'==((?:(?!\n[ \t]*\n)[^=])+?)=='),
    (match) => match.group(1) ?? '',
  );
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  final plain = document
      .parseInline(visible)
      .map((node) => node.textContent)
      .join();
  return _restoreTableCellEscapes(plain);
}

const _tableEscapePlaceholderBase = 0xf0000;

String _protectTableCellEscapes(String source) {
  final output = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (character != 0x5c) {
      output.writeCharCode(character);
      index += 1;
      continue;
    }

    final runStart = index;
    while (index < source.length && source.codeUnitAt(index) == 0x5c) {
      index += 1;
    }
    final runLength = index - runStart;
    for (var pair = 0; pair < runLength ~/ 2; pair += 1) {
      output.writeCharCode(_tableEscapePlaceholderBase + 0x5c);
    }
    if (runLength.isEven) continue;
    if (index < source.length &&
        _isTableAsciiPunctuation(source.codeUnitAt(index))) {
      output.writeCharCode(
        _tableEscapePlaceholderBase + source.codeUnitAt(index),
      );
      index += 1;
    } else {
      output.writeCharCode(_tableEscapePlaceholderBase + 0x5c);
    }
  }
  return output.toString();
}

String _restoreTableCellEscapes(String source) => String.fromCharCodes(
  source.runes.map((rune) {
    final restored = rune - _tableEscapePlaceholderBase;
    return restored >= 0x21 && restored <= 0x7e ? restored : rune;
  }),
);

bool _isTableAsciiPunctuation(int codeUnit) =>
    (codeUnit >= 0x21 && codeUnit <= 0x2f) ||
    (codeUnit >= 0x3a && codeUnit <= 0x40) ||
    (codeUnit >= 0x5b && codeUnit <= 0x60) ||
    (codeUnit >= 0x7b && codeUnit <= 0x7e);

final class _EditableTableCell {
  const _EditableTableCell({
    required this.tableStart,
    required this.row,
    required this.column,
    required this.start,
    required this.end,
    required this.text,
    required this.alignment,
    required this.isHeader,
    required this.lineStart,
    required this.lineEnd,
    required this.lineSource,
    required this.isSynthetic,
  });

  final int tableStart;
  final int row;
  final int column;
  final int start;
  final int end;
  final String text;
  final TextAlign alignment;
  final bool isHeader;
  final int lineStart;
  final int lineEnd;
  final String lineSource;
  final bool isSynthetic;

  String get key => '$row-$column';
}

final class _EditableTableLine {
  const _EditableTableLine(this.text, this.offset);

  final String text;
  final int offset;
}

_EditableTableModel _parseEditableTable(IanvsMarkdownBlock block) {
  final lines = <_EditableTableLine>[];
  var lineStart = 0;
  while (lineStart <= block.source.length) {
    final newline = block.source.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? block.source.length : newline;
    lines.add(
      _EditableTableLine(block.source.substring(lineStart, lineEnd), lineStart),
    );
    if (newline < 0) break;
    lineStart = newline + 1;
  }
  if (lines.length < 2) return const _EditableTableModel([], []);

  final separatorCells = _tableLineCellRanges(lines[1]);
  if (separatorCells.isEmpty) return const _EditableTableModel([], []);
  final parsedAlignments = separatorCells.map((range) {
    final marker = lines[1].text.substring(range.$1, range.$2).trim();
    if (marker.startsWith(':') && marker.endsWith(':')) {
      return _EditableTableAlignment.center;
    }
    if (marker.endsWith(':')) return _EditableTableAlignment.right;
    if (marker.startsWith(':')) return _EditableTableAlignment.left;
    return _EditableTableAlignment.none;
  }).toList();

  final visibleLines = <_EditableTableLine>[lines.first, ...lines.skip(2)];
  final rangesByLine = [
    for (final line in visibleLines) _tableLineCellRanges(line),
  ];
  final columnCount = rangesByLine.fold<int>(
    parsedAlignments.length,
    (largest, ranges) => ranges.length > largest ? ranges.length : largest,
  );
  final alignments = <_EditableTableAlignment>[
    ...parsedAlignments,
    ...List<_EditableTableAlignment>.filled(
      columnCount - parsedAlignments.length,
      _EditableTableAlignment.none,
    ),
  ];
  final rows = <List<_EditableTableCell>>[];
  for (var rowIndex = 0; rowIndex < visibleLines.length; rowIndex += 1) {
    final line = visibleLines[rowIndex];
    final ranges = rangesByLine[rowIndex];
    final insertionOffset = block.start + line.offset + line.text.length;
    rows.add([
      for (var column = 0; column < columnCount; column += 1)
        _EditableTableCell(
          tableStart: block.start,
          row: rowIndex,
          column: column,
          start: column < ranges.length
              ? block.start + line.offset + ranges[column].$1
              : insertionOffset,
          end: column < ranges.length
              ? block.start + line.offset + ranges[column].$2
              : insertionOffset,
          text: column < ranges.length
              ? line.text.substring(ranges[column].$1, ranges[column].$2)
              : '',
          alignment: switch (alignments[column]) {
            _EditableTableAlignment.center => TextAlign.center,
            _EditableTableAlignment.right => TextAlign.right,
            _ => TextAlign.left,
          },
          isHeader: rowIndex == 0,
          lineStart: block.start + line.offset,
          lineEnd: block.start + line.offset + line.text.length,
          lineSource: line.text,
          isSynthetic: column >= ranges.length,
        ),
    ]);
  }
  return _EditableTableModel(rows, alignments);
}

List<List<String>> _editableTableTextRows(_EditableTableModel model) => [
  for (final row in model.rows) [for (final cell in row) cell.text],
];

String _serializeEditableTable(
  List<List<String>> rows,
  List<_EditableTableAlignment> alignments,
) {
  if (rows.isEmpty || alignments.isEmpty) return '';
  String repeat(String value, int count) => List.filled(count, value).join();
  final columnCount = alignments.length;
  final widths = List<int>.filled(columnCount, 5);
  for (final row in rows) {
    for (
      var column = 0;
      column < columnCount && column < row.length;
      column++
    ) {
      final requiredWidth = row[column].length + 2;
      if (requiredWidth > widths[column]) widths[column] = requiredWidth;
    }
  }

  String serializeRow(List<String> row) {
    final output = StringBuffer();
    for (var column = 0; column < columnCount; column++) {
      final text = column < row.length ? row[column] : '';
      final remaining = widths[column] - text.length;
      final (leading, trailing) = switch (alignments[column]) {
        _EditableTableAlignment.right => (remaining - 1, 1),
        _EditableTableAlignment.center => (
          remaining ~/ 2,
          (remaining / 2).ceil(),
        ),
        _ => (1, remaining - 1),
      };
      output
        ..write('|')
        ..write(repeat(' ', leading))
        ..write(text)
        ..write(repeat(' ', trailing));
    }
    return '${output.toString()}|';
  }

  String serializeAlignmentRow() {
    final output = StringBuffer();
    for (var column = 0; column < columnCount; column++) {
      final width = widths[column];
      output.write(switch (alignments[column]) {
        _EditableTableAlignment.left => '| :${repeat('-', width - 3)} ',
        _EditableTableAlignment.center => '| :${repeat('-', width - 4)}: ',
        _EditableTableAlignment.right => '| ${repeat('-', width - 3)}: ',
        _EditableTableAlignment.none => '| ${repeat('-', width - 2)} ',
      });
    }
    return '${output.toString()}|';
  }

  return <String>[
    serializeRow(rows.first),
    serializeAlignmentRow(),
    for (final row in rows.skip(1)) serializeRow(row),
  ].join('\n');
}

String _materializeTableLineCell(
  String source, {
  required int column,
  required String replacement,
}) {
  var updated = source;
  var ranges = _tableLineCellRanges(_EditableTableLine(updated, 0));
  while (ranges.length <= column) {
    updated = _appendTableLineCell(updated, separator: false);
    ranges = _tableLineCellRanges(_EditableTableLine(updated, 0));
  }
  final range = ranges[column];
  if (range.$1 == range.$2) {
    var rawStart = range.$1;
    var rawEnd = range.$2;
    while (rawStart > 0 &&
        _isTableWhitespace(updated.codeUnitAt(rawStart - 1))) {
      rawStart -= 1;
    }
    while (rawEnd < updated.length &&
        _isTableWhitespace(updated.codeUnitAt(rawEnd))) {
      rawEnd += 1;
    }
    return updated.replaceRange(rawStart, rawEnd, ' $replacement ');
  }
  return updated.replaceRange(range.$1, range.$2, replacement);
}

List<(int, int)> _tableLineCellRanges(_EditableTableLine line) {
  final pipes = <int>[];
  for (var index = 0; index < line.text.length; index += 1) {
    if (line.text.codeUnitAt(index) != 0x7c) continue;
    var slashes = 0;
    for (
      var cursor = index - 1;
      cursor >= 0 && line.text.codeUnitAt(cursor) == 0x5c;
      cursor -= 1
    ) {
      slashes += 1;
    }
    if (slashes.isEven) pipes.add(index);
  }
  if (pipes.isEmpty) {
    var start = 0;
    var end = line.text.length;
    while (start < end && _isTableWhitespace(line.text.codeUnitAt(start))) {
      start += 1;
    }
    while (end > start && _isTableWhitespace(line.text.codeUnitAt(end - 1))) {
      end -= 1;
    }
    return <(int, int)>[(start, end)];
  }

  final trimmedLeft = line.text.length - line.text.trimLeft().length;
  final trimmedRight = line.text.trimRight().length;
  final leadingPipe =
      trimmedLeft < line.text.length && line.text[trimmedLeft] == '|';
  final trailingPipe = trimmedRight > 0 && line.text[trimmedRight - 1] == '|';
  var segmentStart = leadingPipe ? pipes.first + 1 : 0;
  final segments = <(int, int)>[];
  for (final pipe in pipes) {
    if (pipe < segmentStart) continue;
    segments.add((segmentStart, pipe));
    segmentStart = pipe + 1;
  }
  if (!trailingPipe && segmentStart <= line.text.length) {
    segments.add((segmentStart, line.text.length));
  }

  return [
    for (final segment in segments)
      () {
        var start = segment.$1;
        var end = segment.$2;
        while (start < end && _isTableWhitespace(line.text.codeUnitAt(start))) {
          start += 1;
        }
        while (end > start &&
            _isTableWhitespace(line.text.codeUnitAt(end - 1))) {
          end -= 1;
        }
        return (start, end);
      }(),
  ];
}

bool _isTableWhitespace(int codeUnit) => codeUnit == 0x20 || codeUnit == 0x09;

String _appendTableLineCell(String line, {required bool separator}) {
  final trimmedLength = line.trimRight().length;
  final cell = separator ? '---' : '';
  if (trimmedLength > 0 && line[trimmedLength - 1] == '|') {
    return '${line.substring(0, trimmedLength)} $cell |'
        '${line.substring(trimmedLength)}';
  }
  if (cell.isEmpty) return '$line |  |';
  return '$line | $cell';
}
