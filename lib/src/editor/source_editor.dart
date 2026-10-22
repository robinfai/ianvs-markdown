import '../localization.dart';
import '../keyboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../code_surface.dart';
import '../inline_code.dart';
import '../theme.dart';
import 'editor_controller.dart';
import 'editor_diagnostics.dart';
import 'editor_models.dart';
import 'editor_shortcuts.dart';
import 'editor_toolbar.dart';

/// A source highlight and navigation request for [IanvsMarkdownEditor].
///
/// [source] is the exact text snapshot in which [range] was found. Offsets use
/// UTF-16 code units, like [TextSelection]. Empty, invalid or stale ranges are
/// ignored. Create a fresh instance to navigate again, even to the same range.
@immutable
class IanvsMarkdownSourceHighlight {
  const IanvsMarkdownSourceHighlight({
    required this.source,
    required this.range,
  });

  final String source;
  final TextRange range;
}

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
    this.readOnly = false,
    this.highlightedRange,
    this.showToolbar = true,
    this.highlightSyntax = true,
    this.enableModeShortcuts = true,
    this.placeholder,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 40),
    this.onChanged,
    this.onSaveRequested,
    this.onPaste,
    this.theme,
  });

  final IanvsMarkdownController controller;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final bool autofocus;

  /// Keeps source selectable and copyable, but disables user edits and the
  /// editing toolbar, regardless of mode. Save and mode commands remain usable;
  /// [enableModeShortcuts] still controls keyboard mode changes.
  /// Programmatic updates through [controller] remain allowed.
  final bool readOnly;

  /// Paints the exact source match without changing selection, focus or history.
  /// Each new request instance reveals its range after layout. Null clears it.
  /// Text or controller changes invalidate the accepted request; the host must
  /// provide a fresh request for the current source snapshot to highlight again.
  final IanvsMarkdownSourceHighlight? highlightedRange;
  final bool showToolbar;

  /// False keeps full source editing while disabling Markdown syntax styling
  /// and background parsing. The controller's own parse budget also applies.
  final bool highlightSyntax;

  /// Whether the editor binds its mode-switching shortcuts.
  final bool enableModeShortcuts;

  /// Optional hint for an empty document; never becomes Markdown content.
  final String? placeholder;
  final EdgeInsetsGeometry padding;
  final ValueChanged<String>? onChanged;
  final IanvsMarkdownSaveCallback? onSaveRequested;

  /// Handles a user Paste before the built-in text/URL paste, including an
  /// empty selection. Return true to consume it or false to use normal paste.
  /// Errors consume the request to avoid duplicate insertion. Not invoked in
  /// Reading mode, on read-only inputs, or during IME composition.
  ///
  /// The host owns clipboard access and insertion, and must revalidate its
  /// document, controller, selection and focus after awaiting asynchronous work.
  /// The editor guards only its own text fallback against stale requests.
  /// Installing this hook uses an adaptive menu with Paste available even when
  /// the clipboard has no text. Direct platform editing updates bypass it.
  final Future<bool> Function()? onPaste;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownEditor> createState() => _IanvsMarkdownEditorState();
}

class _IanvsMarkdownEditorState extends State<IanvsMarkdownEditor> {
  final GlobalKey _editorSurfaceKey = GlobalKey();
  final GlobalKey _backgroundSurfaceKey = GlobalKey();
  final _backgroundRanges = _SourceBackgroundRanges();
  late final _backgroundLayout = _SourceBackgroundLayout(
    _editorSurfaceKey,
    _backgroundSurfaceKey,
  );
  late FocusNode _focusNode;
  late ScrollController _scrollController;
  late String _lastText;
  final _highlight = ValueNotifier<IanvsMarkdownSourceHighlight?>(null);
  int _highlightNavigationVersion = 0;

  bool get _ownsFocusNode => widget.focusNode == null;
  bool get _ownsScrollController => widget.scrollController == null;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _scrollController = widget.scrollController ?? ScrollController();
    _lastText = widget.controller.text;
    widget.controller.addListener(_handleControllerChanged);
    _acceptHighlight();
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.commitHistoryGroup();
      oldWidget.controller.removeListener(_handleControllerChanged);
      _lastText = widget.controller.text;
      _backgroundRanges.clear();
      _clearHighlight();
      widget.controller.addListener(_handleControllerChanged);
    }
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      if (oldWidget.focusNode == null) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode();
    }
    if (!identical(oldWidget.scrollController, widget.scrollController)) {
      if (oldWidget.scrollController == null) _scrollController.dispose();
      _scrollController = widget.scrollController ?? ScrollController();
      _scheduleHighlightNavigation();
    }
    if (!identical(oldWidget.highlightedRange, widget.highlightedRange)) {
      _acceptHighlight();
    }
  }

  void _clearHighlight() {
    _highlightNavigationVersion++;
    _highlight.value = null;
  }

  void _acceptHighlight() {
    _clearHighlight();
    final request = widget.highlightedRange;
    if (request == null ||
        request.source != widget.controller.text ||
        !request.range.isValid ||
        !request.range.isNormalized ||
        request.range.isCollapsed ||
        request.range.end > request.source.length) {
      return;
    }
    _highlight.value = request;
    _scheduleHighlightNavigation();
  }

  void _scheduleHighlightNavigation() {
    final request = _highlight.value;
    if (request == null) return;
    final version = ++_highlightNavigationVersion;
    final controller = widget.controller;
    final scroll = _scrollController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          version != _highlightNavigationVersion ||
          !identical(controller, widget.controller) ||
          !identical(scroll, _scrollController) ||
          !identical(request, _highlight.value) ||
          request.source != controller.text ||
          !scroll.hasClients) {
        return;
      }
      final geometry = _backgroundLayout.resolve();
      if (geometry == null) return;
      final editable = geometry.editable;
      final boxes = editable.getBoxesForSelection(
        TextSelection(
          baseOffset: request.range.start,
          extentOffset: request.range.end,
        ),
      );
      // Newline-only matches can have no selection box. The first caret still
      // identifies the source location without changing the actual selection.
      final bounds = boxes.isEmpty
          ? editable.getLocalRectForCaret(
              TextPosition(offset: request.range.start),
            )
          : boxes
                .map((box) => box.toRect())
                .reduce((a, b) => a.expandToInclude(b));
      const margin = 8.0;
      final viewportHeight = editable.size.height;
      final delta =
          bounds.height > viewportHeight - 2 * margin || bounds.top < margin
          ? bounds.top - margin
          : bounds.bottom > viewportHeight - margin
          ? bounds.bottom - viewportHeight + margin
          : 0.0;
      final position = scroll.position;
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target != position.pixels) scroll.jumpTo(target);
    });
  }

  void _handleControllerChanged() {
    final next = widget.controller.text;
    if (next == _lastText) return;
    _lastText = next;
    _backgroundRanges.clear();
    _clearHighlight();
    widget.onChanged?.call(next);
  }

  // Raw events keep macOS accessibility-generated editor commands on the
  // source field itself. The inner EditableText otherwise swallows the
  // platform event before the outer Shortcuts widget can invoke them.
  // ignore: deprecated_member_use
  KeyEventResult _handleRawKey(RawKeyEvent event) {
    if (widget.readOnly) return KeyEventResult.ignored;
    if (markdownShortcutHandledRaw(event)) return KeyEventResult.handled;
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
    if (widget.readOnly) return KeyEventResult.ignored;
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
    _highlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final direction = Directionality.of(context);
    widget.controller.syntaxTheme = widget.highlightSyntax
        ? ianvsMarkdownSyntaxTheme(colors, dark: dark)
        : null;
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
        child: MarkdownCommandTarget(
          kind: MarkdownCommandKind.source,
          controller: widget.controller,
          modeShortcutsEnabled: widget.enableModeShortcuts,
          onCommand: (command, focused) {
            if (widget.readOnly) {
              if (command == IanvsMarkdownCommand.save ||
                  markdownCommandIsMode(command)) {
                return false;
              }
              if (command == IanvsMarkdownCommand.copy ||
                  command == IanvsMarkdownCommand.selectAll) {
                return invokeMarkdownTextCommand(command, focused);
              }
              return true;
            }
            if (command != IanvsMarkdownCommand.deleteLine) return false;
            widget.controller.deleteSelectedLines(
              preferredCaretOffset: _preferredDeleteLineCaret(),
            );
            return true;
          },
          child: TextField(
            contextMenuBuilder: (_, state) => buildMarkdownTextContextMenu(
              context,
              state,
              onPaste: widget.onPaste == null || widget.readOnly
                  ? null
                  : () => IanvsMarkdownShortcuts.invoke(
                      IanvsMarkdownCommand.paste,
                      controller: widget.controller,
                    ),
            ),
            key: const ValueKey('ianvs-markdown-source-field'),
            controller: widget.controller,
            focusNode: _focusNode,
            scrollController: _scrollController,
            autofocus: widget.autofocus,
            readOnly: widget.readOnly,
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
              if (widget.readOnly)
                const _ReadOnlySourceFormatter()
              else
                IanvsMarkdownEditingFormatter(
                  budget: widget.controller.parseBudget,
                ),
            ],
            style: textStyle,
            cursorColor: colors.accent,
            decoration: InputDecoration(
              hintText: widget.placeholder,
              hintStyle: textStyle.copyWith(color: colors.textTertiary),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: widget.padding,
            ),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showToolbar && !widget.readOnly)
            IanvsMarkdownEditorToolbar(
              focusNode: _focusNode,
              controller: widget.controller,
              onSaveRequested: widget.onSaveRequested,
              theme: colors,
            ),
          Expanded(
            child: _wrapShortcuts(
              Stack(
                key: _backgroundSurfaceKey,
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey(
                        'ianvs-markdown-source-quote-backgrounds',
                      ),
                      painter: _SourceQuoteBackgroundPainter(
                        enabled: widget.highlightSyntax,
                        controller: widget.controller,
                        layout: _backgroundLayout,
                        ranges: _backgroundRanges,
                        textDirection: direction,
                        colors: colors,
                        dark: dark,
                        repaint: Listenable.merge(<Listenable>[
                          widget.controller,
                          _scrollController,
                        ]),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey(
                        'ianvs-markdown-source-code-backgrounds',
                      ),
                      painter: _SourceFencedCodeBackgroundPainter(
                        enabled: widget.highlightSyntax,
                        controller: widget.controller,
                        layout: _backgroundLayout,
                        ranges: _backgroundRanges,
                        colors: colors,
                        dark: dark,
                        repaint: Listenable.merge(<Listenable>[
                          widget.controller,
                          _scrollController,
                        ]),
                      ),
                    ),
                  ),
                  field,
                  IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey('ianvs-markdown-source-highlight'),
                      painter: _SourceHighlightPainter(
                        highlight: _highlight,
                        controller: widget.controller,
                        layout: _backgroundLayout,
                        color: colors.accent.withValues(alpha: .28),
                        repaint: Listenable.merge(<Listenable>[
                          _highlight,
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

  Widget _wrapShortcuts(Widget child) => IanvsMarkdownEditorShortcuts(
    enableModeShortcuts: widget.enableModeShortcuts,
    controller: widget.controller,
    onSaveRequested: widget.onSaveRequested,
    onPaste: widget.onPaste,
    child: widget.readOnly
        ? Shortcuts(
            // Tab is deliberately excluded from Markdown command dispatch.
            // Shadow the editor's private indentation intents at this surface
            // instead, retaining ordinary forward/backward focus traversal.
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.tab):
                  _ReadOnlySourceTraversalIntent(),
              SingleActivator(LogicalKeyboardKey.tab, shift: true):
                  _ReadOnlySourceTraversalIntent(backwards: true),
            },
            child: Actions(
              // Shadow the enclosing editor Actions. These Flutter intents
              // otherwise bypass the read-only Markdown command boundary.
              actions: <Type, Action<Intent>>{
                _ReadOnlySourceTraversalIntent:
                    _ReadOnlySourceTraversalAction(),
                PasteTextIntent: CallbackAction<PasteTextIntent>(
                  onInvoke: (_) => null,
                ),
                DeleteToNextWordBoundaryIntent:
                    CallbackAction<DeleteToNextWordBoundaryIntent>(
                      onInvoke: (_) => null,
                    ),
                UndoTextIntent: CallbackAction<UndoTextIntent>(
                  onInvoke: (_) => null,
                ),
                RedoTextIntent: CallbackAction<RedoTextIntent>(
                  onInvoke: (_) => null,
                ),
              },
              child: child,
            ),
          )
        : child,
  );
}

class _ReadOnlySourceTraversalIntent extends Intent {
  const _ReadOnlySourceTraversalIntent({this.backwards = false});

  final bool backwards;
}

class _ReadOnlySourceTraversalAction
    extends ContextAction<_ReadOnlySourceTraversalIntent> {
  @override
  Object? invoke(
    _ReadOnlySourceTraversalIntent intent, [
    BuildContext? context,
  ]) {
    // This action always consumes Tab, even when the host has disabled or
    // omitted traversal. Otherwise Shortcuts may fall back to indentation.
    if (context == null) return null;
    return intent.backwards
        ? Actions.maybeInvoke(context, const PreviousFocusIntent())
        : Actions.maybeInvoke(context, const NextFocusIntent());
  }
}

// Flutter's native UndoHistory can invoke userUpdateTextEditingValue directly,
// bypassing EditableText.updateEditingValue's read-only guard. Input formatters
// cover that path without restricting programmatic controller updates.
class _ReadOnlySourceFormatter extends TextInputFormatter {
  const _ReadOnlySourceFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => oldValue;
}

class _SourceHighlightPainter extends CustomPainter {
  _SourceHighlightPainter({
    required this.highlight,
    required this.controller,
    required this.layout,
    required this.color,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ValueListenable<IanvsMarkdownSourceHighlight?> highlight;
  final IanvsMarkdownController controller;
  final _SourceBackgroundLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final request = highlight.value;
    if (request == null || request.source != controller.text) return;
    final geometry = layout.resolve();
    if (geometry == null) return;
    final editable = geometry.editable;
    final boxes = editable.getBoxesForSelection(
      TextSelection(
        baseOffset: request.range.start,
        extentOffset: request.range.end,
      ),
    );
    final paint = Paint()..color = color;
    canvas.save();
    canvas.clipRect(
      (geometry.origin & editable.size).intersect(Offset.zero & size),
    );
    for (final box in boxes) {
      canvas.drawRect(box.toRect().shift(geometry.origin), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SourceHighlightPainter oldDelegate) => true;
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

// Cache only source ranges for the current text, never text layout. Selection,
// scrolling and composition-only updates reuse ranges. Text/controller changes
// clear them, including when a budget rejection disables decoration painting.
class _SourceBackgroundRanges {
  String? _source;
  List<TextRange>? _quotes;
  List<TextRange>? _code;

  void clear() {
    _source = null;
    _quotes = null;
    _code = null;
  }

  void _use(String source) {
    if (_source == source) return;
    clear();
    _source = source;
  }

  List<TextRange> quotes(String source) {
    _use(source);
    return _quotes ??= IanvsMarkdownEditorDiagnostics.measure<List<TextRange>>(
      'source.quoteRanges',
      () {
        IanvsMarkdownEditorDiagnostics.recordSourceBackgroundParse();
        return parseMarkdownBlocks(source)
            .where((block) => block.type == IanvsMarkdownBlockType.blockquote)
            .map((block) => TextRange(start: block.start, end: block.end))
            .toList(growable: false);
      },
    );
  }

  List<TextRange> code(String source) {
    _use(source);
    return _code ??= IanvsMarkdownEditorDiagnostics.measure<List<TextRange>>(
      'source.codeRanges',
      () {
        IanvsMarkdownEditorDiagnostics.recordSourceBackgroundParse();
        return _markdownFencedCodeRanges(source);
      },
    );
  }
}

class _SourceBackgroundLayout {
  const _SourceBackgroundLayout(this.editorKey, this.surfaceKey);

  final GlobalKey editorKey;
  final GlobalKey surfaceKey;

  _SourceTextGeometry? resolve() {
    final editable = _findRenderEditable(
      editorKey.currentContext?.findRenderObject(),
    );
    final surface = surfaceKey.currentContext?.findRenderObject();
    if (editable == null ||
        !editable.attached ||
        !editable.hasSize ||
        editable.size.isEmpty ||
        surface is! RenderBox ||
        !surface.attached ||
        !surface.hasSize) {
      return null;
    }
    return _SourceTextGeometry(
      editable,
      editable.localToGlobal(Offset.zero, ancestor: surface),
    );
  }
}

class _SourceTextGeometry {
  const _SourceTextGeometry(this.editable, this.origin);

  final RenderEditable editable;
  final Offset origin;

  Rect? boundsFor(TextRange range) {
    // RenderEditable owns the styled paragraph and already includes its scroll
    // paint offset in selection boxes. Applying it again would shift surfaces.
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    if (boxes.isEmpty) return null;
    var top = boxes.first.top;
    var bottom = boxes.first.bottom;
    for (final box in boxes.skip(1)) {
      if (box.top < top) top = box.top;
      if (box.bottom > bottom) bottom = box.bottom;
    }
    return Rect.fromLTRB(
      origin.dx,
      origin.dy + top,
      origin.dx + editable.size.width,
      origin.dy + bottom,
    );
  }
}

class _SourceQuoteBackgroundPainter extends CustomPainter {
  _SourceQuoteBackgroundPainter({
    required this.controller,
    required this.enabled,
    required this.layout,
    required this.ranges,
    required this.textDirection,
    required this.colors,
    required this.dark,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final IanvsMarkdownController controller;
  final bool enabled;
  final _SourceBackgroundLayout layout;
  final _SourceBackgroundRanges ranges;
  final TextDirection textDirection;
  final IanvsMarkdownThemeData colors;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || !controller.parseDecision.useMarkdown) return;
    final quoteRanges = ranges.quotes(controller.text);
    if (quoteRanges.isEmpty || size.isEmpty) return;
    final geometry = layout.resolve();
    if (geometry == null) return;
    final patternColor = (dark ? Colors.white : Colors.black).withValues(
      alpha: .12,
    );

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final range in quoteRanges) {
      final bounds = geometry.boundsFor(range);
      if (bounds == null) continue;
      final rect = Rect.fromLTRB(
        (bounds.left - 6).clamp(0, size.width),
        bounds.top - 8,
        (bounds.right + 6).clamp(0, size.width),
        bounds.bottom + 8,
      );
      if (rect.bottom < 0 || rect.top > size.height) continue;
      paintIanvsMarkdownQuoteSurface(
        canvas,
        rect,
        backgroundColor: colors.surface,
        patternColor: patternColor,
        railColor: colors.accent,
        textDirection: textDirection,
        radius: colors.smallRadius / 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SourceQuoteBackgroundPainter oldDelegate) {
    // Host typography and layout can change without changing controller text.
    // Range parsing is cached; geometry always comes from the current field.
    return true;
  }
}

class _SourceFencedCodeBackgroundPainter extends CustomPainter {
  _SourceFencedCodeBackgroundPainter({
    required this.controller,
    required this.enabled,
    required this.layout,
    required this.ranges,
    required this.colors,
    required this.dark,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final IanvsMarkdownController controller;
  final bool enabled;
  final _SourceBackgroundLayout layout;
  final _SourceBackgroundRanges ranges;
  final IanvsMarkdownThemeData colors;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || !controller.parseDecision.useMarkdown) return;
    final codeRanges = ranges.code(controller.text);
    if (codeRanges.isEmpty || size.isEmpty) return;
    final geometry = layout.resolve();
    if (geometry == null) return;
    final outline = Paint()
      ..color = colors.borderSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final activeRail = Paint()
      ..color = colors.accent
      ..style = PaintingStyle.fill;
    final caret = controller.selection.isValid
        ? controller.selection.extentOffset
        : -1;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final range in codeRanges) {
      final bounds = geometry.boundsFor(range);
      if (bounds == null) continue;
      final rect = Rect.fromLTRB(
        (bounds.left - 6).clamp(0, size.width),
        bounds.top - 3,
        (bounds.right + 6).clamp(0, size.width),
        bounds.bottom + 3,
      );
      if (rect.bottom < 0 || rect.top > size.height) continue;
      final radius = Radius.circular(colors.smallRadius / 2);
      final rounded = RRect.fromRectAndRadius(rect, radius);
      canvas.save();
      canvas.clipRRect(rounded);
      paintIanvsMarkdownCodePattern(
        canvas,
        rect,
        color: (dark ? Colors.white : Colors.black).withValues(alpha: .12),
      );
      canvas.restore();
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
    // Host typography and layout can change without changing controller text.
    // Range parsing is cached; geometry always comes from the current field.
    return true;
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
    inlineCodeMarker: ianvsMarkdownInlineCodeStyle(
      colors,
      fontSize: null,
      height: null,
    ),
    math: TextStyle(
      color: colors.accentDark,
      fontFamily: colors.monoFontFamily,
      fontFamilyFallback: colors.monoFontFamilyFallback,
    ),
    codeBlock: TextStyle(
      color: colors.codeForeground,
      fontSize: 14,
      height: 1.5,
    ),
    strong: TextStyle(
      color: colors.strongForeground,
      fontWeight: FontWeight.w600,
    ),
    emphasis: TextStyle(
      color: colors.emphasisForeground,
      fontStyle: FontStyle.italic,
    ),
    comment: TextStyle(color: colors.textTertiary, fontStyle: FontStyle.italic),
    darkCodeHighlighting: dark,
  );
}
