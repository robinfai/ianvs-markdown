import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../code_surface.dart';
import '../inline_code.dart';
import '../theme.dart';
import 'editor_controller.dart';
import 'editor_shortcuts.dart';
import 'editor_toolbar.dart';

/// Full-source Markdown editor with syntax styling and Markdown-aware input.
///
/// This widget is height-filling. Place it in a bounded parent.
class IanvsMarkdownEditor extends StatefulWidget {
  const IanvsMarkdownEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.scrollController,
    this.autofocus = false,
    this.showToolbar = true,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 40),
    this.onChanged,
    this.onSaveRequested,
    this.theme,
  });

  final IanvsMarkdownController controller;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final bool autofocus;
  final bool showToolbar;
  final EdgeInsetsGeometry padding;
  final ValueChanged<String>? onChanged;
  final IanvsMarkdownSaveCallback? onSaveRequested;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownEditor> createState() => _IanvsMarkdownEditorState();
}

class _IanvsMarkdownEditorState extends State<IanvsMarkdownEditor> {
  final GlobalKey _editorSurfaceKey = GlobalKey();
  late FocusNode _focusNode;
  late ScrollController _scrollController;
  late String _lastText;

  bool get _ownsFocusNode => widget.focusNode == null;
  bool get _ownsScrollController => widget.scrollController == null;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _scrollController = widget.scrollController ?? ScrollController();
    _lastText = widget.controller.text;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.commitHistoryGroup();
      oldWidget.controller.removeListener(_handleControllerChanged);
      _lastText = widget.controller.text;
      widget.controller.addListener(_handleControllerChanged);
    }
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      if (oldWidget.focusNode == null) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode();
    }
    if (!identical(oldWidget.scrollController, widget.scrollController)) {
      if (oldWidget.scrollController == null) _scrollController.dispose();
      _scrollController = widget.scrollController ?? ScrollController();
    }
  }

  void _handleControllerChanged() {
    final next = widget.controller.text;
    if (next == _lastText) return;
    _lastText = next;
    widget.onChanged?.call(next);
  }

  // Raw events keep macOS accessibility-generated editor commands on the
  // source field itself. The inner EditableText otherwise swallows the
  // platform event before the outer Shortcuts widget can invoke them.
  // ignore: deprecated_member_use
  KeyEventResult _handleRawKey(RawKeyEvent event) {
    // ignore: deprecated_member_use
    final metaPressed = event.isMetaPressed;
    // ignore: deprecated_member_use
    final controlPressed = event.isControlPressed;
    // ignore: deprecated_member_use
    final altPressed = event.isAltPressed;
    // ignore: deprecated_member_use
    final shiftPressed = event.isShiftPressed;
    // ignore: deprecated_member_use
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ &&
        metaPressed &&
        !controlPressed &&
        !altPressed) {
      if (shiftPressed) {
        widget.controller.redo();
      } else {
        widget.controller.undo();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyK &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        controlPressed &&
        !metaPressed &&
        !altPressed &&
        !shiftPressed) {
      return _deleteToPhysicalLineEnd();
    }
    if (event.logicalKey == LogicalKeyboardKey.keyH &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        controlPressed &&
        !metaPressed &&
        !altPressed &&
        !shiftPressed) {
      return _deleteBackwardGrapheme();
    }
    if (event.logicalKey == LogicalKeyboardKey.keyD &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        controlPressed &&
        !metaPressed &&
        !altPressed &&
        !shiftPressed) {
      return _deleteForwardGrapheme();
    }
    if ((event.logicalKey == LogicalKeyboardKey.keyN ||
            event.logicalKey == LogicalKeyboardKey.keyP) &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        controlPressed &&
        !metaPressed &&
        !altPressed &&
        !shiftPressed) {
      return _collapseAppleVerticalSelection(
        forward: event.logicalKey == LogicalKeyboardKey.keyN,
      );
    }
    if (event.logicalKey == LogicalKeyboardKey.keyU &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        controlPressed &&
        !metaPressed &&
        !altPressed &&
        !shiftPressed) {
      return _consumeUnboundAppleTextCommand();
    }
    if (event.logicalKey != LogicalKeyboardKey.keyD ||
        !metaPressed ||
        controlPressed ||
        altPressed ||
        shiftPressed) {
      return KeyEventResult.ignored;
    }
    final composing = widget.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    return widget.controller.deleteSelectedLines(
          preferredCaretOffset: _preferredDeleteLineCaret(),
        )
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyZ &&
        keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed) {
      if (keyboard.isShiftPressed) {
        widget.controller.redo();
      } else {
        widget.controller.undo();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyK &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      return _deleteToPhysicalLineEnd();
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyH &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      return _deleteBackwardGrapheme();
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyD &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      return _deleteForwardGrapheme();
    }
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.keyN ||
            event.logicalKey == LogicalKeyboardKey.keyP) &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      return _collapseAppleVerticalSelection(
        forward: event.logicalKey == LogicalKeyboardKey.keyN,
      );
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyU &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      return _consumeUnboundAppleTextCommand();
    }
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyD ||
        !keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final composing = widget.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    return widget.controller.deleteSelectedLines(
          preferredCaretOffset: _preferredDeleteLineCaret(),
        )
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  KeyEventResult _deleteToPhysicalLineEnd() {
    final current = widget.controller.value;
    final selection = current.selection;
    if (!selection.isValid ||
        (current.composing.isValid && !current.composing.isCollapsed)) {
      return KeyEventResult.ignored;
    }

    final source = current.text;
    final start = selection.start.clamp(0, source.length);
    var end = selection.end.clamp(start, source.length);
    if (selection.isCollapsed) {
      final lineEnd = _sourceLineEnd(source, start);
      end = start < lineEnd
          ? lineEnd
          : lineEnd < source.length
          ? lineEnd + 1
          : lineEnd;
    }
    if (end == start) return KeyEventResult.handled;

    widget.controller.commitHistoryGroup();
    widget.controller.value = TextEditingValue(
      text: source.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    widget.controller.commitHistoryGroup();
    return KeyEventResult.handled;
  }

  KeyEventResult _deleteBackwardGrapheme() {
    final current = widget.controller.value;
    final selection = current.selection;
    if (!selection.isValid ||
        (current.composing.isValid && !current.composing.isCollapsed)) {
      return KeyEventResult.ignored;
    }

    final source = current.text;
    var start = selection.start.clamp(0, source.length);
    final end = selection.end.clamp(start, source.length);
    if (selection.isCollapsed) {
      if (start == 0) return KeyEventResult.handled;
      start =
          CharacterBoundary(source).getLeadingTextBoundaryAt(start - 1) ?? 0;
    }
    if (end == start) return KeyEventResult.handled;

    widget.controller.commitHistoryGroup();
    widget.controller.value = TextEditingValue(
      text: source.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    widget.controller.commitHistoryGroup();
    return KeyEventResult.handled;
  }

  KeyEventResult _deleteForwardGrapheme() {
    final current = widget.controller.value;
    final selection = current.selection;
    if (!selection.isValid ||
        (current.composing.isValid && !current.composing.isCollapsed)) {
      return KeyEventResult.ignored;
    }

    final source = current.text;
    final start = selection.start.clamp(0, source.length);
    var end = selection.end.clamp(start, source.length);
    if (selection.isCollapsed) {
      if (end == source.length) return KeyEventResult.handled;
      end =
          CharacterBoundary(source).getTrailingTextBoundaryAt(end) ??
          source.length;
    }
    if (end == start) return KeyEventResult.handled;

    widget.controller.commitHistoryGroup();
    widget.controller.value = TextEditingValue(
      text: source.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    widget.controller.commitHistoryGroup();
    return KeyEventResult.handled;
  }

  KeyEventResult _collapseAppleVerticalSelection({required bool forward}) {
    final current = widget.controller.value;
    final selection = current.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    widget.controller.value = current.copyWith(
      selection: TextSelection.collapsed(
        offset: forward ? selection.end : selection.start,
      ),
      composing: TextRange.empty,
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _consumeUnboundAppleTextCommand() {
    final current = widget.controller.value;
    if (!current.selection.isValid ||
        (current.composing.isValid && !current.composing.isCollapsed)) {
      return KeyEventResult.ignored;
    }
    // Obsidian leaves Control+U unbound, including when text is selected.
    return KeyEventResult.handled;
  }

  int? _preferredDeleteLineCaret() {
    final selection = widget.controller.selection;
    if (!selection.isValid) return null;
    final source = widget.controller.text;
    final head = selection.extentOffset.clamp(0, source.length);
    final lineEnd = _sourceLineEnd(source, head);
    if (lineEnd == source.length) return head;

    final editable = _findRenderEditable(
      _editorSurfaceKey.currentContext?.findRenderObject(),
    );
    if (editable == null) return null;
    final nextStart = lineEnd + 1;
    final nextEnd = _sourceLineEnd(source, nextStart);
    final headRect = editable.getLocalRectForCaret(
      TextPosition(offset: head, affinity: selection.affinity),
    );
    final nextLineRect = editable.getLocalRectForCaret(
      TextPosition(offset: nextStart),
    );
    final resolved = editable.getPositionForPoint(
      editable.localToGlobal(Offset(headRect.left, nextLineRect.center.dy)),
    );
    return resolved.offset.clamp(nextStart, nextEnd);
  }

  @override
  void dispose() {
    widget.controller.commitHistoryGroup();
    widget.controller.removeListener(_handleControllerChanged);
    if (_ownsFocusNode) _focusNode.dispose();
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final direction = Directionality.of(context);
    final resolvedPadding = widget.padding.resolve(direction);
    final textScaler = MediaQuery.textScalerOf(context);
    widget.controller.syntaxTheme = ianvsMarkdownSyntaxTheme(
      colors,
      dark: dark,
    );
    final textStyle = TextStyle(
      color: colors.textPrimary,
      fontFamily: colors.monoFontFamily,
      fontFamilyFallback: colors.monoFontFamilyFallback,
      fontSize: 13.5,
      height: 1.62,
    );
    final field = Focus(
      key: _editorSurfaceKey,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => _handleKeyEvent(event),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        // ignore: deprecated_member_use
        onKey: (_, event) => _handleRawKey(event),
        child: TextField(
          key: const ValueKey('ianvs-markdown-source-field'),
          controller: widget.controller,
          focusNode: _focusNode,
          scrollController: _scrollController,
          autofocus: widget.autofocus,
          expands: true,
          minLines: null,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: <TextInputFormatter>[
            IanvsMarkdownEditingFormatter(),
          ],
          style: textStyle,
          cursorColor: colors.accent,
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: widget.padding,
          ),
        ),
      ),
    );
    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showToolbar)
            IanvsMarkdownEditorToolbar(
              controller: widget.controller,
              onSaveRequested: widget.onSaveRequested,
              theme: colors,
            ),
          Expanded(
            child: IanvsMarkdownEditorShortcuts(
              controller: widget.controller,
              onSaveRequested: widget.onSaveRequested,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  field,
                  IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey(
                        'ianvs-markdown-source-code-backgrounds',
                      ),
                      painter: _SourceFencedCodeBackgroundPainter(
                        controller: widget.controller,
                        scrollController: _scrollController,
                        style: textStyle,
                        padding: resolvedPadding,
                        textDirection: direction,
                        textScaler: textScaler,
                        colors: colors,
                        dark: dark,
                        repaint: Listenable.merge(<Listenable>[
                          widget.controller,
                          _scrollController,
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

RenderEditable? _findRenderEditable(RenderObject? root) {
  if (root == null) return null;
  if (root is RenderEditable) return root;
  RenderEditable? result;
  void visit(RenderObject child) {
    if (result != null) return;
    if (child is RenderEditable) {
      result = child;
      return;
    }
    child.visitChildren(visit);
  }

  root.visitChildren(visit);
  return result;
}

int _sourceLineEnd(String text, int offset) {
  final safeOffset = offset.clamp(0, text.length);
  final newline = text.indexOf('\n', safeOffset);
  return newline < 0 ? text.length : newline;
}

class _SourceFencedCodeBackgroundPainter extends CustomPainter {
  _SourceFencedCodeBackgroundPainter({
    required this.controller,
    required this.scrollController,
    required this.style,
    required this.padding,
    required this.textDirection,
    required this.textScaler,
    required this.colors,
    required this.dark,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final IanvsMarkdownController controller;
  final ScrollController scrollController;
  final TextStyle style;
  final EdgeInsets padding;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final IanvsMarkdownThemeData colors;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final ranges = _markdownFencedCodeRanges(controller.text);
    if (ranges.isEmpty || size.isEmpty) return;

    final contentWidth = size.width - padding.horizontal;
    if (contentWidth <= 0) return;
    final textPainter = TextPainter(
      text: TextSpan(text: controller.text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(maxWidth: contentWidth);
    final positions = scrollController.positions;
    final scrollOffset = positions.isEmpty ? 0.0 : positions.last.pixels;
    final fill = Paint()
      ..color = colors.accent.withValues(alpha: dark ? .045 : .025)
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = colors.borderSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    final activeRail = Paint()
      ..color = colors.accent
      ..style = PaintingStyle.fill;
    final caret = controller.selection.isValid
        ? controller.selection.extentOffset
        : -1;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final range in ranges) {
      final boxes = textPainter.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
        boxHeightStyle: BoxHeightStyle.max,
      );
      if (boxes.isEmpty) continue;
      final top = boxes
          .map((box) => box.top)
          .reduce((value, next) => value < next ? value : next);
      final bottom = boxes
          .map((box) => box.bottom)
          .reduce((value, next) => value > next ? value : next);
      final rect = Rect.fromLTRB(
        (padding.left - 6).clamp(0, size.width),
        padding.top + top - scrollOffset - 3,
        (size.width - padding.right + 6).clamp(0, size.width),
        padding.top + bottom - scrollOffset + 3,
      );
      if (rect.bottom < 0 || rect.top > size.height) continue;
      final radius = Radius.circular(colors.smallRadius);
      final rounded = RRect.fromRectAndRadius(rect, radius);
      canvas.drawRRect(rounded, fill);
      paintIanvsMarkdownDashedRRect(canvas, rounded, outline);
      if (caret >= range.start && caret <= range.end) {
        final rail = RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top + 3, 2, rect.height - 6),
          const Radius.circular(1),
        );
        canvas.drawRRect(rail, activeRail);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SourceFencedCodeBackgroundPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.scrollController != scrollController ||
        oldDelegate.style != style ||
        oldDelegate.padding != padding ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.colors != colors ||
        oldDelegate.dark != dark;
  }
}

List<TextRange> _markdownFencedCodeRanges(String source) {
  final ranges = <TextRange>[];
  final lines = RegExp(r'.*(?:\r\n|\n|$)').allMatches(source);
  int? start;
  String? marker;
  var minimumLength = 0;
  for (final lineMatch in lines) {
    if (lineMatch.start == source.length) break;
    final line = lineMatch.group(0)!.replaceFirst(RegExp(r'\r?\n$'), '');
    final match = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
    if (match == null) continue;
    final fence = match.group(1)!;
    if (start == null) {
      start = lineMatch.start;
      marker = fence[0];
      minimumLength = fence.length;
      continue;
    }
    if (fence[0] != marker ||
        fence.length < minimumLength ||
        line.substring(match.end).trim().isNotEmpty) {
      continue;
    }
    ranges.add(TextRange(start: start, end: lineMatch.end));
    start = null;
    marker = null;
    minimumLength = 0;
  }
  if (start != null) ranges.add(TextRange(start: start, end: source.length));
  return ranges;
}

IanvsMarkdownSyntaxTheme ianvsMarkdownSyntaxTheme(
  IanvsMarkdownThemeData colors, {
  bool dark = false,
}) {
  return IanvsMarkdownSyntaxTheme(
    heading: TextStyle(color: colors.accentDark, fontWeight: FontWeight.w700),
    marker: TextStyle(color: colors.textTertiary),
    link: TextStyle(
      color: colors.accentDark,
      decoration: TextDecoration.underline,
      decorationColor: colors.textTertiary,
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
      backgroundColor: colors.surface.computeLuminance() < .4
          ? const Color(0xff6b5b22)
          : const Color(0xffffe184),
    ),
    code: ianvsMarkdownInlineCodeStyle(colors, fontSize: null, height: null),
    math: TextStyle(
      color: colors.accentDark,
      fontFamily: colors.monoFontFamily,
      fontFamilyFallback: colors.monoFontFamilyFallback,
    ),
    codeBlock: TextStyle(color: colors.textPrimary),
    comment: TextStyle(color: colors.textTertiary, fontStyle: FontStyle.italic),
    darkCodeHighlighting: dark,
  );
}
