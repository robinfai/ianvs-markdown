import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle, PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show HitTestResult, kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../callout.dart';
import '../code_block.dart';
import '../code_surface.dart';
import '../front_matter.dart';
import '../front_matter_card.dart';
import '../heading_folding.dart';
import '../highlight.dart';
import '../ianvs_markdown.dart';
import '../inline_code.dart';
import '../inline_link.dart';
import '../list_guide.dart';
import '../math.dart';
import '../markdown_document.dart';
import '../obsidian_image.dart';
import '../obsidian_metadata.dart';
import '../render_budget.dart';
import '../rich_clipboard.dart';
import '../task_checkbox.dart';
import '../task_syntax.dart';
import '../theme.dart';
import '../wiki_embed.dart';
import '../wiki_link_reference.dart';
import 'editor_controller.dart';
import 'editor_models.dart';
import 'editor_shortcuts.dart';
import 'editor_toolbar.dart';
import 'markdown_paste.dart';
import 'reference_links.dart';
import 'source_editor.dart';

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

/// Obsidian-style Markdown editor with live, source, and reading modes.
///
/// In live preview, the focused block exposes its exact Markdown source while
/// all other blocks use [IanvsMarkdown]. The complete source in [controller]
/// remains the only document model; rendered widgets are never serialized back
/// into Markdown.
class IanvsMarkdownLiveEditor extends StatefulWidget {
  const IanvsMarkdownLiveEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.scrollController,
    this.autofocus = false,
    this.showToolbar = true,
    this.showOutlineInPreview = true,
    this.showNavigationPane = false,
    this.navigationBreakpoint = 900,
    this.navigationWidth = 292,
    this.contentMaxWidth = 840,
    this.showFrontMatter = false,
    this.compactFrontMatter = true,
    this.showDocumentTitle = false,
    this.enableHeadingFolding = false,
    this.padding = const EdgeInsets.fromLTRB(28, 20, 32, 44),
    this.onChanged,
    this.onSelectionChanged,
    this.onModeChanged,
    this.onSaveRequested,
    this.onTapLink,
    this.imageBuilder,
    this.diagramBuilder,
    this.mathBuilder,
    this.onCopyCode,
    this.wikiEmbedBuilder,
    this.wikiLinkExists,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.styleSheet,
    this.renderBudget = const IanvsMarkdownRenderBudget(),
    this.softLineBreak = true,
    this.enableFileLinkChips = false,
    this.normalizeTablesOnEdit = true,
    this.clipboardWriter = writeIanvsMarkdownClipboard,
    this.theme,
  });

  final IanvsMarkdownController controller;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final bool autofocus;
  final bool showToolbar;
  final bool showOutlineInPreview;
  final bool showNavigationPane;
  final double navigationBreakpoint;
  final double navigationWidth;
  final double contentMaxWidth;

  /// Whether to show YAML properties above the document body.
  ///
  /// Obsidian can keep Properties out of the document surface, which is the
  /// default. Set this to true to render the package's editable properties
  /// card in Live Preview and Reading view.
  final bool showFrontMatter;
  final bool compactFrontMatter;
  final bool showDocumentTitle;

  /// Whether heading fold controls are shown in Live Preview and Reading.
  ///
  /// Obsidian can hide these controls; that configuration is the default.
  final bool enableHeadingFolding;
  final EdgeInsetsGeometry padding;
  final ValueChanged<String>? onChanged;
  final MarkdownOnSelectionChangedCallback? onSelectionChanged;
  final ValueChanged<IanvsMarkdownEditorMode>? onModeChanged;
  final IanvsMarkdownSaveCallback? onSaveRequested;
  final MarkdownTapLinkCallback? onTapLink;
  final MarkdownImageBuilder? imageBuilder;
  final IanvsMarkdownDiagramBuilder? diagramBuilder;
  final IanvsMarkdownMathBuilder? mathBuilder;
  final IanvsMarkdownCodeCopyHandler? onCopyCode;
  final IanvsMarkdownWikiEmbedContentBuilder? wikiEmbedBuilder;
  final IanvsMarkdownWikiLinkExists? wikiLinkExists;
  final Map<String, MarkdownElementBuilder> builders;
  final MarkdownStyleSheet? styleSheet;
  final IanvsMarkdownRenderBudget? renderBudget;
  final bool softLineBreak;
  final bool enableFileLinkChips;

  /// Whether a changed table cell reformats its complete GFM table.
  ///
  /// Obsidian's Advanced Tables behavior writes aligned rows and separator
  /// widths after a cell edit. Set this to false when a host must preserve
  /// each table's original whitespace while typing.
  final bool normalizeTablesOnEdit;

  /// Writes the plain Markdown and rich HTML copied in Reading mode.
  final IanvsMarkdownClipboardWriter clipboardWriter;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownLiveEditor> createState() =>
      _IanvsMarkdownLiveEditorState();
}

class _IanvsMarkdownLiveEditorState extends State<IanvsMarkdownLiveEditor> {
  static final RegExp _orderedListMarkerLine = RegExp(
    r'^(?:>[ \t]?)*[ \t]*\d{1,9}[.)][ \t]+$',
  );
  static final RegExp _orderedListMarkerPrefix = RegExp(
    r'^((?:>[ \t]?)*)([ \t]*)(\d{1,9})([.)])[ \t]+',
  );

  final GlobalKey _activeEditorKey = GlobalKey();
  final _BlockEditingController _blockController = _BlockEditingController();
  final IanvsMarkdownEditingFormatter _editingFormatter =
      IanvsMarkdownEditingFormatter();
  final Map<int, GlobalKey> _blockKeys = <int, GlobalKey>{};
  final Map<int, GlobalKey> _renderedBlockTapKeys = <int, GlobalKey>{};
  final IanvsMarkdownHeadingFoldController _headingFoldController =
      IanvsMarkdownHeadingFoldController();

  late FocusNode _focusNode;
  late ScrollController _scrollController;
  late List<IanvsMarkdownBlock> _blocks;
  late List<TextRange> _crossParagraphHighlightLiteralRuns;
  late List<IanvsMarkdownLivePreviewFootnoteReference>
  _livePreviewFootnoteReferences;
  late IanvsMarkdownHeadingFoldModel _headingFoldModel;
  late MarkdownLinkReferenceContext _linkReferences;
  late String _lastText;
  late IanvsMarkdownEditorMode _lastMode;
  int? _activeBlockStart;
  int? _activeHeadingStart;
  var _editingStartValue = 0;
  int get _editingStart => _editingStartValue;
  set _editingStart(int value) {
    _editingStartValue = value;
    _blockController.sourceOffset = value;
  }

  var _editingEnd = 0;
  var _activeGapLine = false;
  var _activeGapPrefixLength = 0;
  var _pendingGapLocalY = 0.0;
  Offset? _pendingRenderedTapGlobal;
  Duration? _lastPointerDownTimeStamp;
  Offset? _lastPointerDownGlobal;
  var _pointerTapCount = 0;
  int? _projectedRenderedTapBlockStart;
  int? _projectedRenderedTapLocalOffset;
  var _syncingFromBlock = false;
  var _syncingToBlock = false;
  double? _verticalNavigationX;
  var _verticalNavigationColumn = 0;
  int? _documentDragPointer;
  Offset? _documentDragOrigin;
  Offset? _documentDragLatest;
  int? _documentDragAnchor;
  Offset? _documentDragProjectedExtentPoint;
  int? _documentDragProjectedExtent;
  var _documentDragActive = false;
  var _documentDragEnding = false;
  var _documentDragUpdateScheduled = false;
  var _documentDragExpansionAttempts = 0;
  var _documentDragEpoch = 0;
  _FoldedSelectionBridge? _foldedSelectionBridge;

  bool get _ownsFocusNode => widget.focusNode == null;
  bool get _ownsScrollController => widget.scrollController == null;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _scrollController = widget.scrollController ?? ScrollController();
    _lastText = widget.controller.text;
    _lastMode = widget.controller.mode;
    _refreshBlocks(_lastText);
    _headingFoldController.addListener(_handleHeadingFoldsChanged);
    widget.controller.addListener(_handleDocumentChanged);
    widget.controller.modeListenable.addListener(_handleModeChanged);
    _blockController.addListener(_handleBlockChanged);
    if (widget.autofocus &&
        widget.controller.mode == IanvsMarkdownEditorMode.livePreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _blocks.isNotEmpty) _activateBlock(_blocks.first);
      });
    }
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownLiveEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.commitHistoryGroup();
      oldWidget.controller.removeListener(_handleDocumentChanged);
      oldWidget.controller.modeListenable.removeListener(_handleModeChanged);
      _lastText = widget.controller.text;
      _lastMode = widget.controller.mode;
      _refreshBlocks(_lastText);
      _activeBlockStart = null;
      _activeGapLine = false;
      _foldedSelectionBridge = null;
      _blockController.revealLeadingMarker = false;
      widget.controller.addListener(_handleDocumentChanged);
      widget.controller.modeListenable.addListener(_handleModeChanged);
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

  void _handleModeChanged() {
    final next = widget.controller.mode;
    if (next == _lastMode) return;
    _lastMode = next;
    if (next != IanvsMarkdownEditorMode.livePreview) {
      _resetDocumentDragSelection();
      _activeBlockStart = null;
      _activeGapLine = false;
      _foldedSelectionBridge = null;
      _blockController.revealLeadingMarker = false;
    }
    widget.onModeChanged?.call(next);
    if (mounted) setState(() {});
  }

  void _handleDocumentChanged() {
    final source = widget.controller.text;
    if (source != _lastText) {
      _lastText = source;
      widget.onChanged?.call(source);
    }
    _refreshBlocks(source);
    if (_activeBlockStart != null && _blocks.isNotEmpty) {
      final documentSelection = widget.controller.selection;
      final activeIndex = _blocks.indexWhere(
        (block) => block.start == _activeBlockStart,
      );
      if (activeIndex < 0 && documentSelection.isCollapsed) {
        final selectionOffset = _documentSelectionOffset();
        final previousIndex = _blocks.lastIndexWhere(
          (block) => block.end < selectionOffset,
        );
        if (previousIndex >= 0) {
          final previous = _blocks[previousIndex];
          final next = previousIndex + 1 < _blocks.length
              ? _blocks[previousIndex + 1]
              : null;
          final lineStart = _lineStartAt(source, selectionOffset);
          if (lineStart > previous.end &&
              (next == null || selectionOffset < next.start)) {
            // Removing an empty list item can delete its block while leaving
            // the caret on the now-plain gap line. Keep that line active so
            // the next character becomes a paragraph instead of replacing
            // the preceding list item.
            _activateTrailingGapLine(
              previous,
              lineStart: lineStart,
              lineEnd: _lineEndAt(source, lineStart),
              caretOffset: selectionOffset,
            );
            return;
          }
        }
      }
      final controllerEnd = _editingStart + _blockController.text.length;
      final matchesReparsedLeadingSurface =
          activeIndex < 0 &&
          _editingStart < _blocks.first.start &&
          controllerEnd >= _blocks.first.end &&
          controllerEnd <= source.length &&
          _blockController.text ==
              source.substring(_editingStart, controllerEnd);
      final resolvedActiveIndex = activeIndex >= 0
          ? activeIndex
          : matchesReparsedLeadingSurface
          ? 0
          : -1;
      final canonicalActive = resolvedActiveIndex < 0
          ? null
          : _blocks[resolvedActiveIndex];
      final nextStart =
          resolvedActiveIndex >= 0 && resolvedActiveIndex + 1 < _blocks.length
          ? _blocks[resolvedActiveIndex + 1].start
          : source.length;
      final selectionSurface =
          documentSelection.isValid && !documentSelection.isCollapsed
          ? _selectionSurfaceFor(documentSelection)
          : null;
      final keepsSelectionSurface =
          canonicalActive != null &&
          documentSelection.isValid &&
          !documentSelection.isCollapsed &&
          controllerEnd >= canonicalActive.end &&
          controllerEnd <= source.length &&
          documentSelection.start >= _editingStart &&
          documentSelection.end <= controllerEnd &&
          _blockController.text ==
              source.substring(_editingStart, controllerEnd);
      if (keepsSelectionSurface) {
        _activeGapLine = false;
        _activeBlockStart = canonicalActive.start;
        _editingEnd = controllerEnd;
      } else if (selectionSurface != null) {
        _activeGapLine = false;
        _syncSelectionSurfaceFromDocument(documentSelection, selectionSurface);
      } else {
        final selectionOffset = _documentSelectionOffset();
        final keepsTransientLeadingGap =
            canonicalActive != null &&
            _editingStart < canonicalActive.start &&
            controllerEnd >= canonicalActive.end &&
            controllerEnd <= nextStart &&
            selectionOffset >= _editingStart &&
            selectionOffset <= controllerEnd &&
            controllerEnd <= source.length &&
            _blockController.text ==
                source.substring(_editingStart, controllerEnd);
        final keepsTransientTrailingGap =
            canonicalActive != null &&
            controllerEnd > canonicalActive.end &&
            controllerEnd <= nextStart &&
            selectionOffset >= canonicalActive.end &&
            selectionOffset <= controllerEnd &&
            controllerEnd <= source.length &&
            _blockController.text ==
                source.substring(_editingStart, controllerEnd);
        final selected = keepsTransientLeadingGap || keepsTransientTrailingGap
            ? canonicalActive
            : markdownBlockAtOffset(_blocks, selectionOffset)!;
        _activeGapLine = keepsTransientTrailingGap;
        final requiresStructuralResync =
            selected.start != _editingStart ||
            selected.source != _blockController.text;
        _activeBlockStart = selected.start;
        if (!keepsTransientLeadingGap) _editingStart = selected.start;
        _editingEnd = keepsTransientLeadingGap || keepsTransientTrailingGap
            ? controllerEnd
            : selected.end;
        if (!keepsTransientLeadingGap &&
            !keepsTransientTrailingGap &&
            (!_syncingFromBlock || requiresStructuralResync)) {
          if (_syncingFromBlock && requiresStructuralResync) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncBlockFromDocument(selected);
            });
          } else {
            _syncBlockFromDocument(selected);
          }
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _handleHeadingFoldsChanged() {
    _foldedSelectionBridge = null;
    if (mounted) setState(() {});
  }

  void _refreshBlocks(String source) {
    _linkReferences = MarkdownLinkReferenceContext.parse(source);
    _blockController.linkReferenceLabels = _linkReferences.labels;
    _crossParagraphHighlightLiteralRuns =
        ianvsMarkdownCrossParagraphHighlightLiteralRuns(source);
    _blockController.documentHighlightLiteralRuns =
        _crossParagraphHighlightLiteralRuns;
    _livePreviewFootnoteReferences = ianvsMarkdownLivePreviewFootnoteReferences(
      source,
    );
    _blocks = parseMarkdownBlocks(source, splitListItems: true);
    _headingFoldModel = IanvsMarkdownHeadingFoldModel.fromBlocks(
      source,
      _blocks,
    );
    _headingFoldController.retainIdentities(_headingFoldModel.identities);
    final starts = _blocks.map((block) => block.start).toSet();
    _blockKeys.removeWhere((start, _) => !starts.contains(start));
    _renderedBlockTapKeys.removeWhere((start, _) => !starts.contains(start));
    for (final block in _blocks) {
      _blockKeys.putIfAbsent(block.start, GlobalKey.new);
      _renderedBlockTapKeys.putIfAbsent(block.start, GlobalKey.new);
    }
    final headings = _navigationHeadings;
    if (headings.isEmpty) {
      _activeHeadingStart = null;
    } else if (!headings.any(
      (heading) => heading.blockStart == _activeHeadingStart,
    )) {
      _activeHeadingStart = headings.first.blockStart;
    }
  }

  List<_EditorNavigationHeading> get _navigationHeadings {
    final result = <_EditorNavigationHeading>[];
    for (final block in _blocks) {
      if (block.type != IanvsMarkdownBlockType.heading) continue;
      final headings = parseMarkdownHeadings(block.source);
      if (headings.isEmpty) continue;
      result.add(
        _EditorNavigationHeading(
          blockStart: block.start,
          level: headings.first.level,
          text: headings.first.text,
        ),
      );
    }
    return result;
  }

  void _handleBlockChanged() {
    if (_syncingToBlock || _activeBlockStart == null) return;
    final bridge = _foldedSelectionBridge;
    if (bridge != null && !_foldedSelectionBridgeIsActive(bridge)) {
      _foldedSelectionBridge = null;
    }
    final document = widget.controller.value;
    final start = _editingStart.clamp(0, document.text.length);
    final end = _editingEnd.clamp(start, document.text.length);
    final local = _blockController.value;
    final previousBlock = document.text.substring(start, end);
    if (local.text != previousBlock) {
      _projectedRenderedTapBlockStart = null;
      _projectedRenderedTapLocalOffset = null;
    }
    final removedRootOrderedLine = _rootOrderedExitLine(
      previousBlock,
      local.text,
    );
    final hasFollowingDocumentLine =
        end < document.text.length && document.text.codeUnitAt(end) == 0x0a;
    var mergedLocal = local;
    if (removedRootOrderedLine != null &&
        hasFollowingDocumentLine &&
        local.text.endsWith('\n')) {
      final removedOffset = local.text.length - 1;
      int mapTrimmedOffset(int offset) =>
          offset > removedOffset ? offset - 1 : offset;
      mergedLocal = local.copyWith(
        text: local.text.substring(0, removedOffset),
        selection: TextSelection(
          baseOffset: mapTrimmedOffset(local.selection.baseOffset),
          extentOffset: mapTrimmedOffset(local.selection.extentOffset),
          affinity: local.selection.affinity,
          isDirectional: local.selection.isDirectional,
        ),
        composing: local.composing.isValid
            ? TextRange(
                start: mapTrimmedOffset(local.composing.start),
                end: mapTrimmedOffset(local.composing.end),
              )
            : TextRange.empty,
      );
    }
    final updatedText = document.text.replaceRange(
      start,
      end,
      mergedLocal.text,
    );
    final selection = _localSelectionToDocument(mergedLocal.selection, start);
    final composing = _localComposingToDocument(mergedLocal.composing, start);
    var updatedValue = TextEditingValue(
      text: updatedText,
      selection: selection,
      composing: composing,
    );
    final continuationOffset = _orderedContinuationInsertionOffset(
      previousBlock,
      local.text,
    );
    final outdentedOffset = continuationOffset == null
        ? _orderedOutdentLineOffset(previousBlock, local.text)
        : null;
    if (removedRootOrderedLine != null && hasFollowingDocumentLine) {
      updatedValue = _editingFormatter.renumberAfterRemovedOrderedListItem(
        updatedValue,
        removedLine: removedRootOrderedLine,
        followingLineStart: start + mergedLocal.text.length + 1,
      );
    } else if (continuationOffset != null) {
      updatedValue = _editingFormatter.renumberOrderedLists(
        updatedValue,
        touchedLineStarts: {start + continuationOffset},
      );
    } else if (outdentedOffset != null) {
      updatedValue = _editingFormatter.renumberOutdentedOrderedList(
        updatedValue,
        lineStart: start + outdentedOffset,
      );
    }
    _syncingFromBlock = true;
    try {
      widget.controller.value = updatedValue;
    } finally {
      _syncingFromBlock = false;
    }
  }

  int? _orderedContinuationInsertionOffset(String previous, String current) {
    if (current.length <= previous.length) return null;
    var prefix = 0;
    while (prefix < previous.length &&
        prefix < current.length &&
        previous.codeUnitAt(prefix) == current.codeUnitAt(prefix)) {
      prefix += 1;
    }
    var previousEnd = previous.length;
    var currentEnd = current.length;
    while (previousEnd > prefix &&
        currentEnd > prefix &&
        previous.codeUnitAt(previousEnd - 1) ==
            current.codeUnitAt(currentEnd - 1)) {
      previousEnd -= 1;
      currentEnd -= 1;
    }
    if (previousEnd != prefix) return null;
    final inserted = current.substring(prefix, currentEnd);
    if (!inserted.startsWith('\n')) return null;
    final continuation = inserted.substring(1);
    if (!_orderedListMarkerLine.hasMatch(continuation)) {
      return null;
    }
    return prefix + 1;
  }

  String? _rootOrderedExitLine(String previous, String current) {
    final lineStart = previous.lastIndexOf('\n') + 1;
    final removedLine = previous.substring(lineStart);
    final marker = _orderedListMarkerPrefix.firstMatch(removedLine);
    if (marker == null ||
        marker.end != removedLine.length ||
        marker.group(1)!.isNotEmpty ||
        _markdownIndentColumns(marker.group(2)!) != 0 ||
        current != previous.substring(0, lineStart) &&
            current != '${previous.substring(0, lineStart)}\n') {
      return null;
    }
    return removedLine;
  }

  int? _orderedOutdentLineOffset(String previous, String current) {
    if (current.length >= previous.length) return null;
    final previousLines = previous.split('\n');
    final currentLines = current.split('\n');
    if (previousLines.length != currentLines.length) return null;

    var currentLineStart = 0;
    for (var index = 0; index < currentLines.length; index += 1) {
      final before = _orderedListMarkerPrefix.firstMatch(previousLines[index]);
      final after = _orderedListMarkerPrefix.firstMatch(currentLines[index]);
      if (before != null &&
          after != null &&
          before.group(1) == after.group(1) &&
          before.group(4) == after.group(4) &&
          _markdownIndentColumns(after.group(2)!) <
              _markdownIndentColumns(before.group(2)!)) {
        return currentLineStart;
      }
      currentLineStart += currentLines[index].length + 1;
    }
    return null;
  }

  int _markdownIndentColumns(String indent) {
    var columns = 0;
    for (final unit in indent.codeUnits) {
      columns += unit == 0x09 ? 4 - columns % 4 : 1;
    }
    return columns;
  }

  // Raw key events are intentionally used at this boundary because macOS
  // accessibility-generated combinations can carry modifier flags only in the
  // platform event. The normalized HardwareKeyboard event then contains just
  // Arrow Left/Right, which would turn Shift-selection into plain navigation.
  // ignore: deprecated_member_use
  KeyEventResult _handleActiveBlockRawKey(RawKeyEvent event) {
    // ignore: deprecated_member_use
    final rawShiftPressed = event.isShiftPressed;
    // ignore: deprecated_member_use
    final rawAltPressed = event.isAltPressed;
    // ignore: deprecated_member_use
    final rawControlPressed = event.isControlPressed;
    // ignore: deprecated_member_use
    final rawMetaPressed = event.isMetaPressed;
    // ignore: deprecated_member_use
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }
    return _handleActiveBlockKeyDown(
      event.logicalKey,
      hasShiftModifier: rawShiftPressed,
      hasAltModifier: rawAltPressed,
      hasControlModifier: rawControlPressed,
      hasMetaModifier: rawMetaPressed,
    );
  }

  KeyEventResult _handleActiveBlockKeyDown(
    LogicalKeyboardKey key, {
    required bool hasShiftModifier,
    required bool hasAltModifier,
    required bool hasControlModifier,
    required bool hasMetaModifier,
  }) {
    final local = _blockController.value;
    final selection = local.selection;
    final hasCommandModifier =
        hasAltModifier || hasControlModifier || hasMetaModifier;
    if (key == LogicalKeyboardKey.tab &&
        !hasAltModifier &&
        !hasControlModifier &&
        !hasMetaModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed) &&
        _activeBlockIsCode) {
      return _handleActiveCodeIndentation(outdent: hasShiftModifier);
    }
    if (key == LogicalKeyboardKey.keyZ &&
        !hasAltModifier &&
        (hasMetaModifier || hasControlModifier)) {
      if (hasShiftModifier) {
        widget.controller.redo();
      } else {
        widget.controller.undo();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyY &&
        hasControlModifier &&
        !hasAltModifier &&
        !hasMetaModifier &&
        !hasShiftModifier) {
      widget.controller.redo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC &&
        !hasAltModifier &&
        (hasMetaModifier || hasControlModifier) &&
        !hasShiftModifier) {
      final result = _handleFoldedSelectionCopy();
      if (result == KeyEventResult.handled) return result;
    }
    if (key == LogicalKeyboardKey.keyK &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        hasControlModifier &&
        !hasAltModifier &&
        !hasMetaModifier &&
        !hasShiftModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleDeleteToPhysicalLineEnd();
    }
    if (key == LogicalKeyboardKey.keyH &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        hasControlModifier &&
        !hasAltModifier &&
        !hasMetaModifier &&
        !hasShiftModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleDeleteBackwardGrapheme();
    }
    if (key == LogicalKeyboardKey.keyD &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        hasControlModifier &&
        !hasAltModifier &&
        !hasMetaModifier &&
        !hasShiftModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleDeleteForwardGrapheme();
    }
    if ((key == LogicalKeyboardKey.keyB || key == LogicalKeyboardKey.keyF) &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        hasControlModifier &&
        !hasAltModifier &&
        !hasMetaModifier &&
        !hasShiftModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleAppleCharacterNavigation(
        forward: key == LogicalKeyboardKey.keyF,
      );
    }
    if ((key == LogicalKeyboardKey.keyN || key == LogicalKeyboardKey.keyP) &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        hasControlModifier &&
        !hasAltModifier &&
        !hasMetaModifier &&
        !hasShiftModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      if (!selection.isCollapsed) {
        final documentSelection = _localSelectionToDocument(
          selection,
          _editingStart,
        );
        _verticalNavigationX = null;
        _activateDocumentCaret(
          key == LogicalKeyboardKey.keyN
              ? documentSelection.end
              : documentSelection.start,
        );
        return KeyEventResult.handled;
      }
      return _handleVerticalNavigation(down: key == LogicalKeyboardKey.keyN);
    }
    if (key == LogicalKeyboardKey.keyU &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        hasControlModifier &&
        !hasAltModifier &&
        !hasMetaModifier &&
        !hasShiftModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      // Obsidian leaves Control+U unbound, including when text is selected.
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.keyE) &&
        Theme.of(context).platform == TargetPlatform.macOS &&
        hasControlModifier &&
        !hasAltModifier &&
        !hasMetaModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handlePhysicalLineHorizontalBoundaryNavigation(
        forward: key == LogicalKeyboardKey.keyE,
        extendSelection: hasShiftModifier,
      );
    }
    if (key == LogicalKeyboardKey.keyD &&
        (hasMetaModifier ||
            (hasControlModifier &&
                Theme.of(context).platform != TargetPlatform.macOS &&
                Theme.of(context).platform != TargetPlatform.iOS)) &&
        !(hasMetaModifier && hasControlModifier) &&
        !hasAltModifier &&
        !hasShiftModifier &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return widget.controller.deleteSelectedLines(
            preferredCaretOffset: _preferredDeleteLineCaret(),
          )
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _verticalNavigationX = null;
    }
    if (key == LogicalKeyboardKey.keyA &&
        hasMetaModifier &&
        !hasAltModifier &&
        !hasControlModifier &&
        !hasShiftModifier &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleSelectAllDocument();
    }
    if ((key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown) &&
        hasAltModifier &&
        !hasControlModifier &&
        !hasMetaModifier &&
        !hasShiftModifier &&
        selection.isValid &&
        selection.isCollapsed &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handlePhysicalLineBoundaryNavigation(
        down: key == LogicalKeyboardKey.arrowDown,
      );
    }
    if ((key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown) &&
        hasMetaModifier &&
        !hasAltModifier &&
        !hasControlModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleDocumentBoundaryNavigation(
        toEnd: key == LogicalKeyboardKey.arrowDown,
        extendSelection: hasShiftModifier,
      );
    }
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        hasMetaModifier &&
        !hasAltModifier &&
        !hasControlModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleVisualLineBoundaryNavigation(
        forward: key == LogicalKeyboardKey.arrowRight,
        extendSelection: hasShiftModifier,
      );
    }
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        hasAltModifier &&
        !hasControlModifier &&
        !hasMetaModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      final result = _handleDocumentWordNavigation(
        forward: key == LogicalKeyboardKey.arrowRight,
        extendSelection: hasShiftModifier,
      );
      if (result == KeyEventResult.handled) return result;
    }
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        !hasCommandModifier &&
        hasShiftModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleHorizontalSelection(
        right: key == LogicalKeyboardKey.arrowRight,
      );
    }
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        !hasCommandModifier &&
        !hasShiftModifier &&
        selection.isValid &&
        selection.isCollapsed &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleHorizontalNavigation(
        right: key == LogicalKeyboardKey.arrowRight,
      );
    }
    if ((key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown) &&
        !hasCommandModifier &&
        hasShiftModifier &&
        selection.isValid &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleVerticalSelection(
        down: key == LogicalKeyboardKey.arrowDown,
      );
    }
    if ((key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown) &&
        !hasCommandModifier &&
        !hasShiftModifier &&
        selection.isValid &&
        selection.isCollapsed &&
        (!local.composing.isValid || local.composing.isCollapsed)) {
      return _handleVerticalNavigation(
        down: key == LogicalKeyboardKey.arrowDown,
      );
    }

    final isBackspace = key == LogicalKeyboardKey.backspace;
    final isDelete = key == LogicalKeyboardKey.delete;
    if ((!isBackspace && !isDelete) || hasCommandModifier) {
      return KeyEventResult.ignored;
    }

    if (!selection.isValid ||
        !selection.isCollapsed ||
        (isBackspace
            ? selection.extentOffset != 0
            : selection.extentOffset != local.text.length) ||
        (local.composing.isValid && !local.composing.isCollapsed)) {
      return KeyEventResult.ignored;
    }

    final document = widget.controller.value;
    if (isBackspace) {
      final boundary = _editingStart.clamp(0, document.text.length);
      if (boundary == 0 || document.text.codeUnitAt(boundary - 1) != 0x0a) {
        return KeyEventResult.ignored;
      }
      widget.controller.value = TextEditingValue(
        text: document.text.replaceRange(boundary - 1, boundary, ''),
        selection: TextSelection.collapsed(offset: boundary - 1),
      );
      widget.controller.commitHistoryGroup();
      return KeyEventResult.handled;
    }

    final boundary = _editingEnd.clamp(0, document.text.length);
    if (boundary == document.text.length ||
        document.text.codeUnitAt(boundary) != 0x0a) {
      return KeyEventResult.ignored;
    }
    widget.controller.value = TextEditingValue(
      text: document.text.replaceRange(boundary, boundary + 1, ''),
      selection: TextSelection.collapsed(offset: boundary),
    );
    widget.controller.commitHistoryGroup();
    return KeyEventResult.handled;
  }

  bool get _activeBlockIsCode {
    final activeIndex = _blocks.indexWhere(
      (block) => block.start == _activeBlockStart,
    );
    if (activeIndex < 0) return false;
    final type = _blocks[activeIndex].type;
    return type == IanvsMarkdownBlockType.fencedCode ||
        type == IanvsMarkdownBlockType.indentedCode;
  }

  KeyEventResult _handleActiveCodeIndentation({required bool outdent}) {
    final value = _blockController.value;
    final selection = value.selection;
    if (!selection.isValid) return KeyEventResult.handled;

    final source = value.text;
    final selectionStart = selection.start.clamp(0, source.length);
    final selectionEnd = selection.end.clamp(selectionStart, source.length);
    final firstLineStart = _lineStartAt(source, selectionStart);
    var lastSelectedOffset = selectionEnd;
    if (!selection.isCollapsed &&
        lastSelectedOffset > selectionStart &&
        source.codeUnitAt(lastSelectedOffset - 1) == 0x0a) {
      lastSelectedOffset -= 1;
    }
    final lastLineStart = _lineStartAt(source, lastSelectedOffset);
    final lineStarts = <int>[];
    var lineStart = firstLineStart;
    while (lineStart <= lastLineStart) {
      lineStarts.add(lineStart);
      final nextBreak = source.indexOf('\n', lineStart);
      if (nextBreak < 0 || nextBreak + 1 <= lineStart) break;
      lineStart = nextBreak + 1;
    }

    var updated = source;
    var baseOffset = selection.baseOffset;
    var extentOffset = selection.extentOffset;
    var cumulativeDelta = 0;
    var changed = false;
    for (final originalLineStart in lineStarts) {
      final editOffset = originalLineStart + cumulativeDelta;
      if (!outdent) {
        updated = updated.replaceRange(editOffset, editOffset, '    ');
        if (baseOffset >= editOffset) baseOffset += 4;
        if (extentOffset >= editOffset) extentOffset += 4;
        cumulativeDelta += 4;
        changed = true;
        continue;
      }

      var removable = 0;
      if (editOffset < updated.length &&
          updated.codeUnitAt(editOffset) == 0x09) {
        removable = 1;
      } else {
        while (removable < 4 &&
            editOffset + removable < updated.length &&
            updated.codeUnitAt(editOffset + removable) == 0x20) {
          removable += 1;
        }
      }
      if (removable == 0) continue;
      updated = updated.replaceRange(editOffset, editOffset + removable, '');
      baseOffset = _offsetAfterCodeOutdent(baseOffset, editOffset, removable);
      extentOffset = _offsetAfterCodeOutdent(
        extentOffset,
        editOffset,
        removable,
      );
      cumulativeDelta -= removable;
      changed = true;
    }

    if (!changed) return KeyEventResult.handled;
    _blockController.value = value.copyWith(
      text: updated,
      selection: TextSelection(
        baseOffset: baseOffset,
        extentOffset: extentOffset,
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _handleDeleteToPhysicalLineEnd() {
    final localSelection = _blockController.selection;
    if (!localSelection.isValid) return KeyEventResult.handled;

    final current = widget.controller.value;
    final source = current.text;
    final documentSelection = _localSelectionToDocument(
      localSelection,
      _editingStart,
    );
    final start = documentSelection.start.clamp(0, source.length);
    var end = documentSelection.end.clamp(start, source.length);
    if (documentSelection.isCollapsed) {
      final lineEnd = _lineEndAt(source, start);
      end = start < lineEnd
          ? lineEnd
          : lineEnd < source.length
          ? lineEnd + 1
          : lineEnd;
    }

    // Consuming the command at EOF prevents the outer Markdown shortcut layer
    // from turning Control+K into link insertion on Apple platforms.
    if (end == start) return KeyEventResult.handled;

    _verticalNavigationX = null;
    widget.controller.commitHistoryGroup();
    widget.controller.value = TextEditingValue(
      text: source.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    widget.controller.commitHistoryGroup();
    return KeyEventResult.handled;
  }

  KeyEventResult _handleDeleteBackwardGrapheme() {
    final localSelection = _blockController.selection;
    if (!localSelection.isValid) return KeyEventResult.handled;

    final current = widget.controller.value;
    final source = current.text;
    final documentSelection = _localSelectionToDocument(
      localSelection,
      _editingStart,
    );
    var start = documentSelection.start.clamp(0, source.length);
    final end = documentSelection.end.clamp(start, source.length);
    if (documentSelection.isCollapsed) {
      if (start == 0) return KeyEventResult.handled;
      start =
          CharacterBoundary(source).getLeadingTextBoundaryAt(start - 1) ?? 0;
    }
    if (end == start) return KeyEventResult.handled;

    _verticalNavigationX = null;
    widget.controller.commitHistoryGroup();
    widget.controller.value = TextEditingValue(
      text: source.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    widget.controller.commitHistoryGroup();
    return KeyEventResult.handled;
  }

  KeyEventResult _handleDeleteForwardGrapheme() {
    final localSelection = _blockController.selection;
    if (!localSelection.isValid) return KeyEventResult.handled;

    final current = widget.controller.value;
    final source = current.text;
    final documentSelection = _localSelectionToDocument(
      localSelection,
      _editingStart,
    );
    final start = documentSelection.start.clamp(0, source.length);
    var end = documentSelection.end.clamp(start, source.length);
    if (documentSelection.isCollapsed) {
      if (end == source.length) return KeyEventResult.handled;
      end =
          CharacterBoundary(source).getTrailingTextBoundaryAt(end) ??
          source.length;
    }
    if (end == start) return KeyEventResult.handled;

    _verticalNavigationX = null;
    widget.controller.commitHistoryGroup();
    widget.controller.value = TextEditingValue(
      text: source.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    widget.controller.commitHistoryGroup();
    return KeyEventResult.handled;
  }

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

  int _offsetAfterCodeOutdent(int offset, int start, int removed) {
    if (offset <= start) return offset;
    if (offset <= start + removed) return start;
    return offset - removed;
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
      if (!hiddenBlockIndices.contains(index)) return index;
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

  RenderEditable? _activeRenderEditable() {
    final root = _activeEditorKey.currentContext?.findRenderObject();
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

  int? _preferredDeleteLineCaret() {
    final selection = widget.controller.selection;
    if (!selection.isValid) return null;
    final source = widget.controller.text;
    final head = selection.extentOffset.clamp(0, source.length);
    final lineEnd = _lineEndAt(source, head);
    if (lineEnd == source.length) return head;

    final nextStart = lineEnd + 1;
    final nextEnd = _lineEndAt(source, nextStart);
    if (head < _editingStart ||
        head > _editingEnd ||
        nextStart < _editingStart ||
        nextEnd > _editingEnd) {
      return null;
    }

    final editable = _activeRenderEditable();
    if (editable == null) return null;
    final localHead = head - _editingStart;
    final localNextStart = nextStart - _editingStart;
    final localNextEnd = nextEnd - _editingStart;
    final headRect = editable.getLocalRectForCaret(
      TextPosition(offset: localHead, affinity: selection.affinity),
    );
    final nextLineRect = editable.getLocalRectForCaret(
      TextPosition(offset: localNextStart),
    );
    final resolved = editable.getPositionForPoint(
      editable.localToGlobal(Offset(headRect.left, nextLineRect.center.dy)),
    );
    return _editingStart + resolved.offset.clamp(localNextStart, localNextEnd);
  }

  void _activateTrailingGapLine(
    IanvsMarkdownBlock active, {
    required int lineStart,
    required int lineEnd,
    int? caretOffset,
  }) {
    _blockController.revealLeadingMarker = false;
    _activeGapLine = true;
    _activeGapPrefixLength = lineStart - active.start;
    final source = widget.controller.text;
    final lineLength = lineEnd - lineStart;
    final resolvedCaretOffset =
        caretOffset ??
        lineStart + _verticalNavigationColumn.clamp(0, lineLength);
    final gapEditorSource = source.substring(active.start, lineEnd);
    _activeBlockStart = active.start;
    _editingStart = active.start;
    _editingEnd = lineEnd;
    _syncingToBlock = true;
    try {
      _blockController.value = TextEditingValue(
        text: gapEditorSource,
        selection: TextSelection.collapsed(
          offset: resolvedCaretOffset - active.start,
        ),
      );
    } finally {
      _syncingToBlock = false;
    }
    widget.controller.value = widget.controller.value.copyWith(
      selection: TextSelection.collapsed(offset: resolvedCaretOffset),
      composing: TextRange.empty,
    );
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _activeBlockStart != active.start ||
            _blockController.text != gapEditorSource) {
          return;
        }
        final localCaret = resolvedCaretOffset - active.start;
        _syncingToBlock = true;
        try {
          _blockController.selection = TextSelection.collapsed(
            offset: localCaret,
          );
        } finally {
          _syncingToBlock = false;
        }
        _activeGapLine = true;
        widget.controller.value = widget.controller.value.copyWith(
          selection: TextSelection.collapsed(offset: resolvedCaretOffset),
          composing: TextRange.empty,
        );
        if (mounted) setState(() {});
      });
    });
  }

  void _activateBlockHorizontally(
    IanvsMarkdownBlock block, {
    required int localOffset,
  }) {
    _foldedSelectionBridge = null;
    _blockController.revealLeadingMarker = false;
    _activeGapLine = false;
    final resolvedLocalOffset = localOffset.clamp(0, block.source.length);
    _activeBlockStart = block.start;
    _editingStart = block.start;
    _editingEnd = block.end;
    widget.controller.value = widget.controller.value.copyWith(
      selection: TextSelection.collapsed(
        offset: block.start + resolvedLocalOffset,
      ),
      composing: TextRange.empty,
    );
    _syncBlockFromDocument(block);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _activateDocumentCaret(int offset) {
    _foldedSelectionBridge = null;
    _blockController.revealLeadingMarker = false;
    if (_blocks.isEmpty) return;
    final source = widget.controller.text;
    final target = offset.clamp(0, source.length);
    final blockIndex = _verticalBlockIndexAt(target);
    if (blockIndex >= 0) {
      final block = _blocks[blockIndex];
      _activateBlockHorizontally(block, localOffset: target - block.start);
      return;
    }

    final first = _blocks.first;
    if (target < first.start) {
      _activeGapLine = false;
      _activeBlockStart = first.start;
      _editingStart = 0;
      _editingEnd = first.end;
      _syncingToBlock = true;
      try {
        _blockController.value = TextEditingValue(
          text: source.substring(0, first.end),
          selection: TextSelection.collapsed(offset: target),
        );
      } finally {
        _syncingToBlock = false;
      }
      widget.controller.value = widget.controller.value.copyWith(
        selection: TextSelection.collapsed(offset: target),
        composing: TextRange.empty,
      );
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
      return;
    }

    var previous = first;
    for (final block in _blocks.skip(1)) {
      if (block.start > target) break;
      previous = block;
    }
    _activateTrailingGapLine(
      previous,
      lineStart: _lineStartAt(source, target),
      lineEnd: _lineEndAt(source, target),
      caretOffset: target,
    );
  }

  ({IanvsMarkdownBlock first, int start, int end})? _selectionSurfaceFor(
    TextSelection selection,
  ) {
    if (!selection.isValid || selection.isCollapsed || _blocks.isEmpty) {
      return null;
    }
    var firstIndex = -1;
    for (var index = 0; index < _blocks.length; index += 1) {
      if (_blocks[index].start > selection.start) break;
      firstIndex = index;
    }
    if (firstIndex < 0) firstIndex = 0;

    var lastIndex = firstIndex;
    for (var index = firstIndex + 1; index < _blocks.length; index += 1) {
      if (_blocks[index].start >= selection.end) break;
      lastIndex = index;
    }
    final first = _blocks[firstIndex];
    final last = _blocks[lastIndex];
    final surfaceEnd = selection.end > last.end ? selection.end : last.end;
    final surfaceStart = selection.start < first.start
        ? selection.start
        : first.start;
    if (surfaceEnd > widget.controller.text.length) {
      return null;
    }
    return (first: first, start: surfaceStart, end: surfaceEnd);
  }

  void _activateSelectionSurface(
    TextSelection selection,
    ({IanvsMarkdownBlock first, int start, int end}) surface,
  ) {
    _syncSelectionSurfaceFromDocument(selection, surface);
    widget.controller.value = widget.controller.value.copyWith(
      selection: selection,
      composing: TextRange.empty,
    );
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _activateVerticalSelection(
    TextSelection selection,
    ({IanvsMarkdownBlock first, int start, int end}) surface,
    ({int offset, int lineStart, int lineEnd}) target,
  ) {
    _activateSelectionSurface(selection, surface);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editable = _activeRenderEditable();
      final x = _verticalNavigationX;
      if (editable == null || x == null) return;
      final localLineStart = (target.lineStart - _editingStart).clamp(
        0,
        _blockController.text.length,
      );
      final localLineEnd = (target.lineEnd - _editingStart).clamp(
        localLineStart,
        _blockController.text.length,
      );
      final targetLocalOffset = (target.offset - _editingStart).clamp(
        localLineStart,
        localLineEnd,
      );
      final targetRect = editable.getLocalRectForCaret(
        TextPosition(offset: targetLocalOffset),
      );
      final resolved = editable.getPositionForPoint(
        editable.localToGlobal(Offset(x, targetRect.center.dy)),
      );
      final resolvedExtent = resolved.offset.clamp(
        localLineStart,
        localLineEnd,
      );
      final current = _blockController.selection;
      if (!current.isValid || current.extentOffset == resolvedExtent) return;
      _blockController.selection = TextSelection(
        baseOffset: current.baseOffset,
        extentOffset: resolvedExtent,
        affinity: current.affinity,
        isDirectional: true,
      );
    });
  }

  void _syncSelectionSurfaceFromDocument(
    TextSelection selection,
    ({IanvsMarkdownBlock first, int start, int end}) surface,
  ) {
    _blockController.revealLeadingMarker = false;
    _activeGapLine = false;
    final source = widget.controller.text;
    _activeBlockStart = surface.first.start;
    _editingStart = surface.start;
    _editingEnd = surface.end;
    _syncingToBlock = true;
    try {
      _blockController.value = TextEditingValue(
        text: source.substring(surface.start, surface.end),
        selection: TextSelection(
          baseOffset: selection.baseOffset - surface.start,
          extentOffset: selection.extentOffset - surface.start,
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
      );
    } finally {
      _syncingToBlock = false;
    }
  }

  void _activateBlockVertically(
    IanvsMarkdownBlock block, {
    required bool atStart,
  }) {
    _blockController.revealLeadingMarker = false;
    _activeGapLine = false;
    final sourceLineStart = atStart
        ? 0
        : _lineStartAt(block.source, block.source.length);
    final sourceLineEnd = atStart
        ? _lineEndAt(block.source, 0)
        : block.source.length;
    final localOffset =
        sourceLineStart +
        _verticalNavigationColumn.clamp(0, sourceLineEnd - sourceLineStart);
    _activeBlockStart = block.start;
    _editingStart = block.start;
    _editingEnd = block.end;
    widget.controller.value = widget.controller.value.copyWith(
      selection: TextSelection.collapsed(offset: block.start + localOffset),
      composing: TextRange.empty,
    );
    _syncBlockFromDocument(block);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      final editable = _activeRenderEditable();
      final x = _verticalNavigationX;
      if (editable == null || x == null) return;
      final edgeOffset = atStart ? 0 : _blockController.text.length;
      final edgeRect = editable.getLocalRectForCaret(
        TextPosition(offset: edgeOffset),
      );
      final resolved = editable.getPositionForPoint(
        editable.localToGlobal(Offset(x, edgeRect.center.dy)),
      );
      final offset = resolved.offset.clamp(0, _blockController.text.length);
      if (_blockController.selection.extentOffset == offset) return;
      _blockController.selection = TextSelection.collapsed(offset: offset);
    });
  }

  int _lineStartAt(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    if (safeOffset == 0) return 0;
    return text.lastIndexOf('\n', safeOffset - 1) + 1;
  }

  int _lineEndAt(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    final newline = text.indexOf('\n', safeOffset);
    return newline < 0 ? text.length : newline;
  }

  void _activateBlock(
    IanvsMarkdownBlock block, {
    bool selectWholeSource = false,
    int? documentOffset,
  }) {
    _foldedSelectionBridge = null;
    _projectedRenderedTapBlockStart = null;
    _projectedRenderedTapLocalOffset = null;
    _blockController.revealLeadingMarker = false;
    _activeGapLine = false;
    final currentSelection = widget.controller.selection;
    final currentOffset =
        documentOffset ??
        (currentSelection.isValid ? currentSelection.extentOffset : block.end);
    final offset = currentOffset >= block.start && currentOffset <= block.end
        ? currentOffset
        : block.end;
    final selection = selectWholeSource
        ? TextSelection(baseOffset: block.start, extentOffset: block.end)
        : TextSelection.collapsed(offset: offset);
    _activeBlockStart = block.start;
    _editingStart = block.start;
    _editingEnd = block.end;
    widget.controller.value = widget.controller.value.copyWith(
      selection: selection,
      composing: TextRange.empty,
    );
    _syncBlockFromDocument(block);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _handleDocumentDragPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kPrimaryMouseButton == 0 ||
        !_pointerHitsEditableText(event)) {
      return;
    }
    _resetDocumentDragSelection();
    _documentDragPointer = event.pointer;
    _documentDragOrigin = event.position;
    _documentDragLatest = event.position;
  }

  bool _pointerHitsEditableText(PointerDownEvent event) {
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(
      result,
      event.position,
      event.viewId,
    );
    final activeEditable = _activeRenderEditable();
    return result.path.any((entry) {
      final target = entry.target;
      return target is RenderEditable &&
          (target.readOnly || identical(target, activeEditable));
    });
  }

  void _handleDocumentDragPointerMove(PointerMoveEvent event) {
    if (event.pointer != _documentDragPointer ||
        event.buttons & kPrimaryMouseButton == 0) {
      return;
    }
    _documentDragLatest = event.position;
    if (!_documentDragActive) {
      final origin = _documentDragOrigin;
      if (origin == null || (event.position - origin).distance < 4) return;
      _documentDragActive = true;
      _beginDocumentDragSelection();
      return;
    }
    _scheduleDocumentDragUpdate();
  }

  void _handleDocumentDragPointerUp(PointerUpEvent event) {
    if (event.pointer != _documentDragPointer) return;
    _documentDragLatest = event.position;
    if (!_documentDragActive) {
      _resetDocumentDragSelection();
      return;
    }
    _documentDragEnding = true;
    _scheduleDocumentDragUpdate();
  }

  void _handleDocumentDragPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _documentDragPointer) {
      _resetDocumentDragSelection();
    }
  }

  void _beginDocumentDragSelection() {
    final origin = _documentDragOrigin;
    if (origin == null) {
      _resetDocumentDragSelection();
      return;
    }
    final activeOffset = _documentOffsetAtActivePoint(origin);
    if (activeOffset != null) {
      _documentDragAnchor = activeOffset;
      _scheduleDocumentDragUpdate();
      return;
    }

    final block = _renderedBlockAtGlobalPoint(origin);
    if (block == null) {
      _resetDocumentDragSelection();
      return;
    }
    final renderedOffset = _projectedDocumentOffsetAtRenderedPoint(
      block,
      origin,
    );
    final latest = _documentDragLatest;
    final renderedExtent = renderedOffset != null && latest != null
        ? _projectedDocumentOffsetAtRenderedPoint(block, latest)
        : null;
    final epoch = _documentDragEpoch;
    _activateBlock(block, documentOffset: renderedOffset ?? block.end);
    if (renderedOffset != null) {
      _documentDragAnchor = renderedOffset;
      _documentDragProjectedExtentPoint = renderedExtent == null
          ? null
          : latest;
      _documentDragProjectedExtent = renderedExtent;
      _scheduleDocumentDragUpdate();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _documentDragEpoch || !_documentDragActive) {
        return;
      }
      final anchor = _documentOffsetAtActivePoint(origin);
      if (anchor == null) {
        _resetDocumentDragSelection();
        return;
      }
      _documentDragAnchor = anchor;
      _scheduleDocumentDragUpdate();
    });
  }

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

  void _scheduleDocumentDragUpdate() {
    if (_documentDragUpdateScheduled || !_documentDragActive) return;
    _documentDragUpdateScheduled = true;
    final epoch = _documentDragEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _documentDragEpoch) return;
      _documentDragUpdateScheduled = false;
      _resolveDocumentDragSelection();
    });
  }

  void _resolveDocumentDragSelection() {
    final anchor = _documentDragAnchor;
    final latest = _documentDragLatest;
    if (!_documentDragActive || anchor == null || latest == null) return;

    final projectedExtent = _documentDragProjectedExtent;
    if (projectedExtent != null &&
        _documentDragProjectedExtentPoint == latest) {
      _documentDragProjectedExtentPoint = null;
      _documentDragProjectedExtent = null;
      _documentDragExpansionAttempts = 0;
      _applyDocumentDragSelection(anchor, projectedExtent);
      if (_documentDragEnding) _resetDocumentDragSelection();
      return;
    }
    _documentDragProjectedExtentPoint = null;
    _documentDragProjectedExtent = null;

    final exactExtent = _documentOffsetAtActivePoint(latest);
    if (exactExtent != null) {
      _documentDragExpansionAttempts = 0;
      _applyDocumentDragSelection(anchor, exactExtent);
      if (_documentDragEnding) _resetDocumentDragSelection();
      return;
    }

    final target =
        _renderedBlockAtGlobalPoint(latest) ?? _nearestRenderedBlock(latest);
    final extent = target == null
        ? latest.dy < (_documentDragOrigin?.dy ?? latest.dy)
              ? 0
              : widget.controller.text.length
        : target.end <= anchor
        ? target.start
        : target.end;
    final previousStart = _editingStart;
    final previousEnd = _editingEnd;
    _applyDocumentDragSelection(anchor, extent);
    final expanded =
        previousStart != _editingStart || previousEnd != _editingEnd;
    if (expanded && _documentDragExpansionAttempts < 2) {
      _documentDragExpansionAttempts += 1;
      _scheduleDocumentDragUpdate();
      return;
    }
    if (_documentDragEnding) _resetDocumentDragSelection();
  }

  void _applyDocumentDragSelection(int anchor, int extent) {
    if (anchor == extent) return;
    final selection = TextSelection(
      baseOffset: anchor,
      extentOffset: extent,
      isDirectional: true,
    );
    final surface = _selectionSurfaceFor(selection);
    if (surface == null) return;
    final current = widget.controller.selection;
    if (current.baseOffset == selection.baseOffset &&
        current.extentOffset == selection.extentOffset &&
        current.isDirectional == selection.isDirectional &&
        _editingStart == surface.start &&
        _editingEnd == surface.end) {
      return;
    }
    _activateSelectionSurface(selection, surface);
  }

  void _resetDocumentDragSelection() {
    _documentDragEpoch += 1;
    _documentDragPointer = null;
    _documentDragOrigin = null;
    _documentDragLatest = null;
    _documentDragAnchor = null;
    _documentDragProjectedExtentPoint = null;
    _documentDragProjectedExtent = null;
    _documentDragActive = false;
    _documentDragEnding = false;
    _documentDragUpdateScheduled = false;
    _documentDragExpansionAttempts = 0;
  }

  void _recordPointerDown(PointerDownEvent event) {
    final previousTime = _lastPointerDownTimeStamp;
    final previousPosition = _lastPointerDownGlobal;
    final elapsed = previousTime == null
        ? null
        : event.timeStamp - previousTime;
    final continuesSequence =
        elapsed != null &&
        elapsed >= Duration.zero &&
        elapsed <= const Duration(milliseconds: 500) &&
        previousPosition != null &&
        (event.position - previousPosition).distance <= 24;
    if (!continuesSequence) {
      _projectedRenderedTapBlockStart = null;
      _projectedRenderedTapLocalOffset = null;
    }
    _pointerTapCount = continuesSequence ? _pointerTapCount + 1 : 1;
    _lastPointerDownTimeStamp = event.timeStamp;
    _lastPointerDownGlobal = event.position;
  }

  void _activateRenderedBlock(IanvsMarkdownBlock block, {int tapCount = 1}) {
    final pendingGlobal = _pendingRenderedTapGlobal;
    _pendingRenderedTapGlobal = null;
    final renderObject = _renderedBlockTapKeys[block.start]?.currentContext
        ?.findRenderObject();
    final selectThematicSource =
        block.type == IanvsMarkdownBlockType.thematicBreak;
    final quoteMarkerTapOffset =
        block.type == IanvsMarkdownBlockType.blockquote &&
            parseIanvsMarkdownCalloutHeader(block.source) == null &&
            pendingGlobal != null &&
            renderObject is RenderBox
        ? _quoteMarkerCaretOffsetForTap(
            block,
            renderObject.globalToLocal(pendingGlobal),
            renderObject.size,
          )
        : null;
    final tapOffset =
        block.type == IanvsMarkdownBlockType.blockquote &&
            pendingGlobal != null &&
            renderObject is RenderBox
        ? _quoteCaretOffsetForTap(
            block,
            renderObject.globalToLocal(pendingGlobal),
            renderObject.size,
          )
        : null;
    final projectedTapOffset = tapCount == 1 && pendingGlobal != null
        ? _projectedDocumentOffsetAtRenderedPoint(block, pendingGlobal)
        : null;
    _activateBlock(
      block,
      selectWholeSource: selectThematicSource,
      documentOffset: quoteMarkerTapOffset ?? projectedTapOffset ?? tapOffset,
    );
    if (projectedTapOffset != null && quoteMarkerTapOffset == null) {
      _projectedRenderedTapBlockStart = block.start;
      _projectedRenderedTapLocalOffset = projectedTapOffset - block.start;
    }
    if (pendingGlobal != null &&
        block.type != IanvsMarkdownBlockType.thematicBreak &&
        projectedTapOffset == null) {
      _placeSelectionAtRenderedTap(
        block,
        pendingGlobal,
        tapCount >= 3
            ? _RenderedTapSelection.line
            : tapCount == 2
            ? _RenderedTapSelection.word
            : _RenderedTapSelection.caret,
      );
    }
  }

  void _placeSelectionAtRenderedTap(
    IanvsMarkdownBlock block,
    Offset globalPosition,
    _RenderedTapSelection selectionKind,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeBlockStart != block.start) return;
      final editable = _activeRenderEditable();
      if (editable == null) return;
      final localSelection = _selectionAtEditablePoint(
        editable,
        globalPosition,
        selectionKind,
      );
      final resolvedSelection = selectionKind == _RenderedTapSelection.caret
          ? _escapedEmphasisCaretSelection(
              _hardBreakCaretSelection(localSelection, block.source),
              block.source,
            )
          : localSelection;
      if (selectionKind == _RenderedTapSelection.caret &&
          resolvedSelection.isCollapsed) {
        _projectedRenderedTapBlockStart = block.start;
        _projectedRenderedTapLocalOffset = resolvedSelection.extentOffset;
      }
      _setActiveSelection(resolvedSelection);
    });
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

  void _setActiveSelection(TextSelection localSelection) {
    _syncingToBlock = true;
    try {
      _blockController.selection = localSelection;
    } finally {
      _syncingToBlock = false;
    }
    final documentLength = widget.controller.text.length;
    widget.controller.value = widget.controller.value.copyWith(
      selection: TextSelection(
        baseOffset: (_editingStart + localSelection.baseOffset).clamp(
          0,
          documentLength,
        ),
        extentOffset: (_editingStart + localSelection.extentOffset).clamp(
          0,
          documentLength,
        ),
        affinity: localSelection.affinity,
        isDirectional: localSelection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }

  void _handleActivePointerUp(PointerUpEvent event) {
    if (_documentDragActive) return;
    final tapCount = _pointerTapCount;
    if (tapCount < 2) return;
    final globalPosition = event.position;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || tapCount != _pointerTapCount) return;
      final editable = _activeRenderEditable();
      if (editable == null) return;
      final projectedOffset =
          _projectedRenderedTapBlockStart == _activeBlockStart
          ? _projectedRenderedTapLocalOffset
          : null;
      final selectionKind = tapCount >= 3
          ? _RenderedTapSelection.line
          : _RenderedTapSelection.word;
      _setActiveSelection(
        projectedOffset == null
            ? _selectionAtEditablePoint(editable, globalPosition, selectionKind)
            : _selectionAtEditablePosition(
                editable,
                TextPosition(offset: projectedOffset),
                selectionKind,
              ),
      );
    });
  }

  Widget _activeMultiTapRegion(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _recordPointerDown,
      onPointerUp: _handleActivePointerUp,
      child: child,
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

  void _activateGapLine(
    IanvsMarkdownBlock block, {
    required int gapLines,
    required double localY,
    required double height,
  }) {
    final source = widget.controller.text;
    final blankLineCount = gapLines > 1 ? gapLines - 1 : 1;
    final row = ((localY / height) * blankLineCount).floor().clamp(
      0,
      blankLineCount - 1,
    );
    var lineStart = (block.end + 1).clamp(0, source.length);
    for (var index = 0; index < row && lineStart < source.length; index += 1) {
      final lineEnd = _lineEndAt(source, lineStart);
      lineStart = lineEnd < source.length ? lineEnd + 1 : lineEnd;
    }
    final lineEnd = _lineEndAt(source, lineStart);
    _activateTrailingGapLine(
      block,
      lineStart: lineStart,
      lineEnd: lineEnd,
      caretOffset: lineStart,
    );
  }

  Widget _buildBlockGap(IanvsMarkdownBlock block, {required int gapLines}) {
    final height = gapLines <= 1 ? 4.0 : 14.0;
    if (gapLines <= 1) return SizedBox(height: height);
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: Semantics(
        button: true,
        label: 'Edit blank Markdown line',
        child: GestureDetector(
          key: ValueKey('ianvs-markdown-gap-${block.end}'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _pendingGapLocalY = details.localPosition.dy;
          },
          onTap: () => _activateGapLine(
            block,
            gapLines: gapLines,
            localY: _pendingGapLocalY,
            height: height,
          ),
          child: SizedBox(height: height),
        ),
      ),
    );
  }

  void _toggleHeadingFold(IanvsMarkdownHeadingSection section) {
    final collapsing = !_headingFoldController.isCollapsed(section.identity);
    if (collapsing && _activeBlockStart != null) {
      final activeIndex = _blocks.indexWhere(
        (block) => block.start == _activeBlockStart,
      );
      if (activeIndex >= 0 && section.containsDescendantBlock(activeIndex)) {
        _activeBlockStart = null;
        _activeGapLine = false;
        _blockController.revealLeadingMarker = false;
        _focusNode.unfocus();
      }
    }
    _headingFoldController.toggleIdentity(section.identity);
  }

  void _syncBlockFromDocument(IanvsMarkdownBlock block) {
    _activeGapLine = false;
    final document = widget.controller.value;
    if (block.end > document.text.length) return;
    final selection = _documentSelectionToLocal(
      document.selection,
      block.start,
      block.end,
    );
    final composing = _documentComposingToLocal(
      document.composing,
      block.start,
      block.end,
    );
    _editingStart = block.start;
    _editingEnd = block.end;
    _syncingToBlock = true;
    try {
      _blockController.value = TextEditingValue(
        text: document.text.substring(block.start, block.end),
        selection: selection,
        composing: composing,
      );
    } finally {
      _syncingToBlock = false;
    }
  }

  int _documentSelectionOffset() {
    final selection = widget.controller.selection;
    if (!selection.isValid) {
      return (_activeBlockStart ?? 0).clamp(0, _lastText.length);
    }
    return selection.extentOffset.clamp(0, _lastText.length);
  }

  @override
  void dispose() {
    widget.controller.commitHistoryGroup();
    widget.controller.removeListener(_handleDocumentChanged);
    widget.controller.modeListenable.removeListener(_handleModeChanged);
    _blockController
      ..removeListener(_handleBlockChanged)
      ..dispose();
    _headingFoldController
      ..removeListener(_handleHeadingFoldsChanged)
      ..dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    _blockController.syntaxTheme = _livePreviewSyntaxTheme(colors);
    return ColoredBox(
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showNavigation =
              widget.showNavigationPane &&
              constraints.maxWidth >= widget.navigationBreakpoint;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showNavigation) ...[
                SizedBox(
                  width: widget.navigationWidth,
                  child: ValueListenableBuilder<IanvsMarkdownEditorMode>(
                    valueListenable: widget.controller.modeListenable,
                    builder: (context, mode, _) => _EditorNavigationPane(
                      mode: mode,
                      headings: _navigationHeadings,
                      activeHeadingStart: _activeHeadingStart,
                      colors: colors,
                      onModeSelected: (next) => widget.controller.mode = next,
                      onHeadingSelected: _scrollToNavigationHeading,
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: colors.border),
              ],
              Expanded(
                child: _buildEditorSurface(
                  colors,
                  showNavigation: showNavigation,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEditorSurface(
    IanvsMarkdownThemeData colors, {
    required bool showNavigation,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showToolbar)
          IanvsMarkdownEditorToolbar(
            controller: widget.controller,
            onSaveRequested: widget.onSaveRequested,
            showModeSwitcher: !showNavigation,
            theme: colors,
          ),
        Expanded(
          child: IanvsMarkdownEditorShortcuts(
            controller: widget.controller,
            onSaveRequested: widget.onSaveRequested,
            child: ValueListenableBuilder<IanvsMarkdownEditorMode>(
              valueListenable: widget.controller.modeListenable,
              builder: (context, mode, _) => switch (mode) {
                IanvsMarkdownEditorMode.livePreview => _buildLiveMode(colors),
                IanvsMarkdownEditorMode.source => IanvsMarkdownEditor(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  autofocus: widget.autofocus,
                  showToolbar: false,
                  padding: widget.padding,
                  onSaveRequested: widget.onSaveRequested,
                  theme: colors,
                ),
                IanvsMarkdownEditorMode.preview => IanvsMarkdownView(
                  data: widget.controller.text,
                  controller: _scrollController,
                  padding: widget.padding,
                  showFrontMatter: widget.showFrontMatter,
                  showOutline: widget.showOutlineInPreview && !showNavigation,
                  contentMaxWidth: widget.contentMaxWidth,
                  contentAlignment: Alignment.topLeft,
                  compactFrontMatter: widget.compactFrontMatter,
                  showDocumentTitle: widget.showDocumentTitle,
                  enableHeadingFolding: widget.enableHeadingFolding,
                  headingFoldController: _headingFoldController,
                  styleSheet: widget.styleSheet,
                  onSelectionChanged: widget.onSelectionChanged,
                  onTapLink: widget.onTapLink,
                  imageBuilder: widget.imageBuilder,
                  builders: widget.builders,
                  softLineBreak: widget.softLineBreak,
                  renderBudget: widget.renderBudget,
                  diagramBuilder: widget.diagramBuilder,
                  mathBuilder: widget.mathBuilder,
                  onCopyCode: widget.onCopyCode,
                  wikiEmbedBuilder: widget.wikiEmbedBuilder,
                  wikiLinkExists: widget.wikiLinkExists,
                  enableFileLinkChips: widget.enableFileLinkChips,
                  clipboardWriter: widget.clipboardWriter,
                  theme: colors,
                ),
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _scrollToNavigationHeading(
    _EditorNavigationHeading heading,
  ) async {
    setState(() => _activeHeadingStart = heading.blockStart);
    if (widget.controller.mode != IanvsMarkdownEditorMode.livePreview) {
      widget.controller.mode = IanvsMarkdownEditorMode.livePreview;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    final targetIndex = _blocks.indexWhere(
      (block) => block.start == heading.blockStart,
    );
    if (widget.enableHeadingFolding && targetIndex >= 0) {
      final ancestors = _headingFoldModel
          .collapsedAncestorIdentities(targetIndex, _headingFoldController)
          .toList(growable: false);
      if (ancestors.isNotEmpty) {
        _headingFoldController.expandIdentities(ancestors);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    var blockContext = _blockKeys[heading.blockStart]?.currentContext;
    if (blockContext == null && _scrollController.hasClients) {
      if (targetIndex >= 0) {
        final position = _scrollController.position;
        final fraction = _blocks.length <= 1
            ? 0.0
            : targetIndex / (_blocks.length - 1);
        await _scrollController.animateTo(
          position.maxScrollExtent * fraction,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
        await WidgetsBinding.instance.endOfFrame;

        // Block heights vary substantially (tables, diagrams, and code can be
        // much taller than prose), so refine the proportional jump a viewport
        // at a time until the lazily-built target obtains a context.
        for (var attempt = 0; attempt < 12; attempt += 1) {
          if (!mounted) return;
          blockContext = _blockKeys[heading.blockStart]?.currentContext;
          if (blockContext != null || !_scrollController.hasClients) break;
          final visibleStarts = _blockKeys.entries
              .where((entry) => entry.value.currentContext != null)
              .map((entry) => entry.key)
              .toList(growable: false);
          if (visibleStarts.isEmpty) break;
          final beforeVisible = heading.blockStart < visibleStarts.first;
          final direction = beforeVisible ? -1.0 : 1.0;
          final current = _scrollController.position;
          final next =
              (current.pixels + direction * current.viewportDimension * .8)
                  .clamp(current.minScrollExtent, current.maxScrollExtent)
                  .toDouble();
          if ((next - current.pixels).abs() < 1) break;
          await _scrollController.animateTo(
            next,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOutCubic,
          );
          await WidgetsBinding.instance.endOfFrame;
        }
      }
    }
    blockContext = _blockKeys[heading.blockStart]?.currentContext;
    if (blockContext == null || !blockContext.mounted) return;
    await Scrollable.ensureVisible(
      blockContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: .08,
    );
  }

  Widget _buildLiveMode(IanvsMarkdownThemeData colors) {
    final hiddenBlockIndices = widget.enableHeadingFolding
        ? _headingFoldModel.hiddenBlockIndices(_headingFoldController)
        : const <int>{};
    final styleSheet =
        widget.styleSheet ?? ianvsMarkdownStyleSheet(context, colors);
    final listIndentStep =
        (styleSheet.listIndent ?? 24) +
        (styleSheet.listBulletPadding?.horizontal ?? 4);
    final listNestingLevels = _liveListNestingLevels();
    return Listener(
      key: const ValueKey('ianvs-markdown-document-drag-selection'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDocumentDragPointerDown,
      onPointerMove: _handleDocumentDragPointerMove,
      onPointerUp: _handleDocumentDragPointerUp,
      onPointerCancel: _handleDocumentDragPointerCancel,
      child: IanvsMarkdownListGuideSurface(
        key: const ValueKey('ianvs-markdown-live-list-guides'),
        color: colors.listGuideColor,
        indent: listIndentStep,
        textDirection: Directionality.of(context),
        child: ListView.builder(
          key: const ValueKey('ianvs-markdown-live-blocks'),
          controller: _scrollController,
          padding: widget.padding,
          itemCount: _blocks.length,
          itemBuilder: (context, index) {
            final block = _blocks[index];
            final listNestingLevel = listNestingLevels[index];
            if (hiddenBlockIndices.contains(index)) {
              return KeyedSubtree(
                key: _blockKeys[block.start],
                child: const SizedBox.shrink(),
              );
            }
            final headingSection = _headingFoldModel.sectionAtBlockIndex(index);
            final coveredByActiveSelection =
                _activeBlockStart != null &&
                block.start != _activeBlockStart &&
                block.start > _editingStart &&
                block.start < _editingEnd;
            if (coveredByActiveSelection) {
              return KeyedSubtree(
                key: _blockKeys[block.start],
                child: const SizedBox.shrink(),
              );
            }
            final next = index + 1 < _blocks.length ? _blocks[index + 1] : null;
            final gapLines = markdownGapLineCount(
              widget.controller.text,
              block,
              next,
            );
            final activeGapLine =
                _activeBlockStart == block.start && _activeGapLine;
            return KeyedSubtree(
              key: _blockKeys[block.start],
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: widget.contentMaxWidth),
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: listNestingLevel * listIndentStep,
                    ),
                    child: Column(
                      key: ValueKey(
                        'ianvs-markdown-block-${block.start}-${block.type.name}',
                      ),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_activeBlockStart == block.start && !activeGapLine)
                          _buildActiveBlock(
                            block,
                            colors,
                            listNestingLevel: listNestingLevel,
                            headingSection: headingSection,
                          )
                        else
                          _buildRenderedBlock(
                            block,
                            colors,
                            listNestingLevel: listNestingLevel,
                            headingSection: headingSection,
                          ),
                        if (activeGapLine)
                          _buildActiveGapLine(colors)
                        else if (_activeBlockStart == block.start &&
                            _editingEnd > block.end)
                          const SizedBox.shrink()
                        else
                          _buildBlockGap(block, gapLines: gapLines),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<int> _liveListNestingLevels() {
    final levels = List<int>.filled(_blocks.length, 0);
    final indentationStack = <int>[];
    IanvsMarkdownBlock? previousListBlock;
    for (var index = 0; index < _blocks.length; index += 1) {
      final block = _blocks[index];
      final listBlock = switch (block.type) {
        IanvsMarkdownBlockType.taskList ||
        IanvsMarkdownBlockType.unorderedList ||
        IanvsMarkdownBlockType.orderedList => true,
        _ => false,
      };
      if (!listBlock) {
        indentationStack.clear();
        previousListBlock = null;
        continue;
      }
      if (previousListBlock != null &&
          markdownGapLineCount(
                widget.controller.text,
                previousListBlock,
                block,
              ) >
              1 &&
          _isMarkerOnlyListSource(previousListBlock.source)) {
        indentationStack.clear();
      }
      final indentation = _liveListIndentationColumns(block.source);
      while (indentationStack.isNotEmpty &&
          indentation < indentationStack.last) {
        indentationStack.removeLast();
      }
      if (indentationStack.isEmpty || indentation > indentationStack.last) {
        indentationStack.add(indentation);
      }
      levels[index] = indentationStack.length - 1;
      previousListBlock = block;
    }
    return levels;
  }

  Widget _buildActiveGapLine(IanvsMarkdownThemeData colors) {
    final styleSheet =
        widget.styleSheet ?? ianvsMarkdownStyleSheet(context, colors);
    _blockController
      ..leadingMarkerCharacters = 0
      ..revealLeadingMarker = false
      ..hiddenLeadingCharacters = 0
      ..collapsedLeadingCharacters = _activeGapPrefixLength
      ..sourceProjections = const <_SourceProjection>[]
      ..highlightFencedCode = false;
    final style =
        (styleSheet.p ?? const TextStyle(fontSize: 14.5, height: 1.58))
            .copyWith(color: colors.textPrimary);
    final editor = TextField(
      key: _activeEditorKey,
      controller: _blockController,
      focusNode: _focusNode,
      autofocus: true,
      minLines: 1,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: <TextInputFormatter>[_editingFormatter],
      style: style,
      cursorColor: colors.accent,
      cursorWidth: 1.5,
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isCollapsed: true,
        contentPadding: EdgeInsets.symmetric(vertical: 3),
      ),
    );
    final activeChild = _ActiveTextLineRail(
      controller: _blockController,
      textStyle: style,
      colors: colors,
      child: editor,
    );
    return _activeMultiTapRegion(
      Focus(
        canRequestFocus: false,
        skipTraversal: true,
        // ignore: deprecated_member_use
        onKey: (_, event) => _handleActiveBlockRawKey(event),
        child: Container(
          key: const ValueKey('ianvs-markdown-active-block'),
          constraints: const BoxConstraints(minHeight: 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: activeChild,
        ),
      ),
    );
  }

  Widget _buildActiveBlock(
    IanvsMarkdownBlock block,
    IanvsMarkdownThemeData colors, {
    required int listNestingLevel,
    IanvsMarkdownHeadingSection? headingSection,
  }) {
    final referenceDefinitions = parseMarkdownLinkReferenceDefinitions(
      block.source,
    );
    if (referenceDefinitions.isNotEmpty) {
      return Container(
        key: const ValueKey('ianvs-markdown-active-block'),
        constraints: const BoxConstraints(minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: _buildReferenceDefinitionProjection(
          referenceDefinitions,
          colors,
        ),
      );
    }
    final styleSheet =
        widget.styleSheet ?? ianvsMarkdownStyleSheet(context, colors);
    final standardImages = <IanvsMarkdownStandardImageSource>[];
    if (widget.imageBuilder != null) {
      for (var imageIndex = 0; ; imageIndex += 1) {
        final image = findIanvsMarkdownStandardImageSource(
          block.source,
          imageIndex: imageIndex,
          linkReferenceLabels: _linkReferences.labels,
        );
        if (image == null) break;
        standardImages.add(image);
      }
    }
    final fencedCode = block.type == IanvsMarkdownBlockType.fencedCode;
    final indentedCode = block.type == IanvsMarkdownBlockType.indentedCode;
    final displayMath = block.type == IanvsMarkdownBlockType.displayMath;
    final wikiEmbed = RegExp(
      r'^ {0,3}!\[\[[^\]\n]+\]\][ \t]*$',
    ).hasMatch(block.source);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final activeCodeCanvasColor = colors.surface;
    final activeCodePatternColor = (dark ? Colors.white : Colors.black)
        .withValues(alpha: .12);
    final activeCodeRadius = colors.smallRadius / 2;
    final taskMarker = block.type == IanvsMarkdownBlockType.taskList
        ? RegExp(
            r'^([ \t]*)(?:[-+*]|\d{1,9}[.)])\s+\[([^\r\n])\][ \t]*',
          ).firstMatch(block.source)
        : null;
    final unorderedMarker = block.type == IanvsMarkdownBlockType.unorderedList
        ? RegExp(r'^([ \t]*)[-+*][ \t]+').firstMatch(block.source)
        : null;
    final orderedMarker = block.type == IanvsMarkdownBlockType.orderedList
        ? RegExp(r'^([ \t]*)(\d{1,9})([.)])[ \t]+').firstMatch(block.source)
        : null;
    final quoteMarker = block.type == IanvsMarkdownBlockType.blockquote
        ? RegExp(r'^( {0,3})>[ \t]?').firstMatch(block.source)
        : null;
    final quoteLines = quoteMarker == null
        ? const <_QuoteLineLayout>[]
        : _quoteLineLayouts(block.source);
    final callout =
        quoteMarker != null &&
        parseIanvsMarkdownCalloutHeader(block.source) != null;
    final headingLevel = block.type == IanvsMarkdownBlockType.heading
        ? _activeHeadingLevelForSource(block.source)
        : null;
    final setextUnderline = _setextHeadingUnderline(block.source);
    final hiddenMarker = taskMarker ?? unorderedMarker ?? orderedMarker;
    final hiddenMarkerEnd = hiddenMarker?.end ?? 0;
    final listIndentStep =
        (styleSheet.listIndent ?? 24) +
        (styleSheet.listBulletPadding?.horizontal ?? 4);
    final activeSelection = _blockController.selection;
    final inactiveInlineMathSources =
        ianvsMarkdownInlineMathSources(
              block.source,
              linkReferenceLabels: _linkReferences.labels,
            )
            .where(
              (source) => !_selectionRevealsSourceRange(
                activeSelection,
                source.sourceRange,
              ),
            )
            .toList(growable: false);
    _blockController.leadingMarkerCharacters = hiddenMarkerEnd;
    _blockController.collapsedLeadingCharacters = 0;
    if (hiddenMarkerEnd == 0 ||
        (activeSelection.isValid && activeSelection.start >= hiddenMarkerEnd)) {
      _blockController.revealLeadingMarker = false;
    }
    final revealHiddenMarker =
        hiddenMarkerEnd > 0 &&
        _blockController.revealLeadingMarker &&
        activeSelection.isValid &&
        activeSelection.start < hiddenMarkerEnd;
    _blockController.highlightFencedCode =
        block.type == IanvsMarkdownBlockType.fencedCode;
    _blockController.hiddenLeadingCharacters = revealHiddenMarker
        ? 0
        : hiddenMarkerEnd;
    final sourceProjections = <_SourceProjection>[
      if (hiddenMarkerEnd > 0 && !revealHiddenMarker)
        _HiddenMarkerSpan(
          TextRange(start: 0, end: hiddenMarkerEnd),
          _hiddenTaskMarkerStyle,
        ),
      if (quoteMarker != null && !callout)
        ..._hiddenQuoteMarkerRanges(quoteLines, activeSelection.extentOffset)
      else if (setextUnderline != null)
        _HiddenMarkerSpan(
          TextRange(
            start: block.source.lastIndexOf('\n'),
            end: block.source.length,
          ),
          _collapsedGapPrefixStyle,
        ),
      ..._hiddenBlockIdCaretRanges(block.source),
    ];
    var activeTextStyle = _isEmptyAtxHeadingSource(block.source)
        ? (styleSheet.p ?? const TextStyle(fontSize: 14.5, height: 1.58))
              .copyWith(color: colors.textPrimary)
        : _activeBlockTextStyle(block, styleSheet, colors);
    if (fencedCode) {
      activeTextStyle = activeTextStyle.copyWith(
        color: colors.codeForeground,
        fontSize: 14,
        height: 1.5,
      );
    }
    if (indentedCode) {
      activeTextStyle = activeTextStyle.copyWith(color: colors.accentDark);
    }
    if (taskMarker != null &&
        ianvsMarkdownTaskMarkerUsesDoneText(taskMarker.group(2)!)) {
      activeTextStyle = activeTextStyle.copyWith(
        color: colors.taskDoneColor,
        decoration: TextDecoration.lineThrough,
        decorationColor: colors.taskDoneColor,
      );
    }
    for (final source in inactiveInlineMathSources) {
      sourceProjections.add(
        _InlineMathProjection(
          range: source.sourceRange,
          contentRange: source.contentRange,
          expression: source.expressionFrom(block.source),
          displayMode: source.delimiterLength == 2,
          mathBuilder: widget.mathBuilder,
          textStyle: activeTextStyle,
          colors: colors,
          onTapOffset: (offset) {
            _blockController.selection = TextSelection.collapsed(
              offset: offset,
            );
            _focusNode.requestFocus();
          },
        ),
      );
    }
    sourceProjections.sort((a, b) => a.range.start.compareTo(b.range.start));
    _blockController.sourceProjections = List<_SourceProjection>.unmodifiable(
      sourceProjections,
    );
    final textEditor = TextField(
      key: _activeEditorKey,
      controller: _blockController,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: <TextInputFormatter>[_editingFormatter],
      style: activeTextStyle,
      cursorColor: colors.accent,
      cursorWidth: 1.5,
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isCollapsed: true,
        contentPadding: EdgeInsets.symmetric(vertical: 3),
      ),
    );
    final Widget editor = textEditor;
    Widget activeListEditor(double markerExtent) {
      return Expanded(
        child: _ActiveTextLineRail(
          controller: _blockController,
          textStyle: activeTextStyle,
          colors: colors,
          logicalStartOffset:
              10 + markerExtent + listNestingLevel * listIndentStep,
          child: editor,
        ),
      );
    }

    final Widget activeChild;
    if (taskMarker != null && !revealHiddenMarker) {
      activeChild = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IanvsMarkdownListGuideAnchor(
            nestLevel: listNestingLevel,
            child: SizedBox(
              width: 28,
              height: 30,
              child: Center(
                child: IanvsMarkdownTaskCheckbox(
                  value: ianvsMarkdownTaskMarkerIsChecked(taskMarker.group(2)!),
                  marker: taskMarker.group(2)!,
                  onChanged: (value) => _setTaskChecked(
                    block,
                    block.source.indexOf('[', taskMarker.start) + 1,
                    value,
                  ),
                  theme: colors,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          activeListEditor(30),
        ],
      );
    } else if (unorderedMarker != null && !revealHiddenMarker) {
      activeChild = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IanvsMarkdownListGuideAnchor(
            nestLevel: listNestingLevel,
            child: SizedBox(
              key: const ValueKey('ianvs-markdown-active-list-marker'),
              width: 28,
              child: Center(
                child: IanvsMarkdownUnorderedListMarker(
                  nestLevel: listNestingLevel,
                  color: colors.textSecondary,
                  fontSize: activeTextStyle.fontSize ?? 14.5,
                  height: activeTextStyle.height ?? 1.58,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          activeListEditor(30),
        ],
      );
    } else if (orderedMarker != null && !revealHiddenMarker) {
      activeChild = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IanvsMarkdownListGuideAnchor(
            nestLevel: listNestingLevel,
            child: SizedBox(
              key: const ValueKey('ianvs-markdown-active-list-marker'),
              width: 32,
              child: Text(
                '${orderedMarker.group(2)}${orderedMarker.group(3)}',
                textAlign: TextAlign.right,
                style: activeTextStyle.copyWith(
                  color: colors.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          activeListEditor(38),
        ],
      );
    } else if (quoteMarker != null) {
      activeChild = _ActiveQuoteBlock(
        textSpan: _blockController.buildTextSpan(
          context: context,
          style: activeTextStyle,
          withComposing: false,
        ),
        lines: quoteLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        colors: colors,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(27, 8, 8, 8),
          child: editor,
        ),
      );
    } else if (headingLevel != null) {
      activeChild = _IanvsHeadingRail(
        key: const ValueKey('ianvs-markdown-active-heading-rail'),
        level: headingLevel,
        colors: colors,
        foldIdentity: headingSection?.identity,
        foldable:
            widget.enableHeadingFolding && (headingSection?.canFold ?? false),
        collapsed:
            headingSection != null &&
            _headingFoldController.isCollapsed(headingSection.identity),
        onToggle: headingSection == null
            ? null
            : () => _toggleHeadingFold(headingSection),
        setextUnderline: setextUnderline,
        child: editor,
      );
    } else if (standardImages.isNotEmpty) {
      activeChild = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          editor,
          for (final image in standardImages)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: IanvsMarkdown(
                  data: _linkReferences.appendDefinitionsTo(
                    block.source.substring(
                      image.sourceRange.start,
                      image.sourceRange.end,
                    ),
                  ),
                  selectable: false,
                  styleSheet: widget.styleSheet,
                  imageBuilder: widget.imageBuilder,
                  showListIndentationGuides: false,
                  softLineBreak: widget.softLineBreak,
                  renderBudget: widget.renderBudget,
                  obsidianMetadataMode:
                      IanvsMarkdownObsidianMetadataMode.editing,
                  theme: colors,
                ),
              ),
            ),
        ],
      );
    } else if (displayMath) {
      activeChild = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          editor,
          IanvsMarkdown(
            data: block.source,
            selectable: true,
            documentSelection: false,
            styleSheet: widget.styleSheet,
            imageBuilder: widget.imageBuilder,
            builders: widget.builders,
            softLineBreak: widget.softLineBreak,
            renderBudget: widget.renderBudget,
            diagramBuilder: widget.diagramBuilder,
            mathBuilder: widget.mathBuilder,
            onCopyCode: widget.onCopyCode,
            wikiEmbedBuilder: widget.wikiEmbedBuilder,
            wikiLinkExists: widget.wikiLinkExists,
            enableFileLinkChips: widget.enableFileLinkChips,
            obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
            theme: colors,
          ),
        ],
      );
    } else if (wikiEmbed) {
      activeChild = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          editor,
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IanvsMarkdown(
              data: block.source,
              selectable: true,
              documentSelection: false,
              styleSheet: widget.styleSheet,
              onTapLink: widget.onTapLink,
              imageBuilder: widget.imageBuilder,
              builders: widget.builders,
              softLineBreak: widget.softLineBreak,
              renderBudget: widget.renderBudget,
              diagramBuilder: widget.diagramBuilder,
              mathBuilder: widget.mathBuilder,
              onCopyCode: widget.onCopyCode,
              wikiEmbedBuilder: widget.wikiEmbedBuilder,
              wikiLinkExists: widget.wikiLinkExists,
              enableFileLinkChips: widget.enableFileLinkChips,
              obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
              theme: colors,
            ),
          ),
        ],
      );
    } else {
      activeChild = editor;
    }
    final decoratedActiveChild = indentedCode
        ? _ActiveIndentedCodeLineRail(
            controller: _blockController,
            textStyle: activeTextStyle,
            colors: colors,
            child: activeChild,
          )
        : quoteMarker != null ||
              headingLevel != null ||
              (hiddenMarker != null && !revealHiddenMarker)
        ? activeChild
        : _ActiveTextLineRail(
            controller: _blockController,
            textStyle: activeTextStyle,
            colors: colors,
            logicalStartOffset: hiddenMarker == null
                ? 10
                : 10 + listNestingLevel * listIndentStep,
            child: activeChild,
          );
    final surfacedActiveChild = fencedCode
        ? CustomPaint(
            key: const ValueKey('ianvs-markdown-active-code-pattern'),
            painter: IanvsMarkdownCodePatternPainter(
              color: activeCodePatternColor,
            ),
            child: decoratedActiveChild,
          )
        : quoteMarker != null
        ? CustomPaint(
            key: const ValueKey('ianvs-markdown-active-quote-pattern'),
            painter: IanvsMarkdownCodePatternPainter(
              color: activeCodePatternColor,
            ),
            child: decoratedActiveChild,
          )
        : decoratedActiveChild;
    final quoteBlock = quoteMarker != null;
    final activeBlockContainer = Container(
      key: const ValueKey('ianvs-markdown-active-block'),
      constraints: BoxConstraints(
        minHeight: fencedCode || quoteBlock ? 36 : 24,
      ),
      clipBehavior: fencedCode || quoteBlock ? Clip.antiAlias : Clip.none,
      margin: fencedCode || quoteBlock
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 3)
          : null,
      decoration: fencedCode
          ? BoxDecoration(
              color: activeCodeCanvasColor,
              borderRadius: BorderRadius.circular(activeCodeRadius),
            )
          : quoteBlock
          ? BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(activeCodeRadius),
            )
          : null,
      foregroundDecoration: fencedCode
          ? IanvsMarkdownDashedBorderDecoration(
              color: colors.borderSoft,
              radius: activeCodeRadius,
            )
          : null,
      padding: fencedCode
          ? const EdgeInsets.symmetric(horizontal: 16)
          : quoteBlock
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 10),
      child: surfacedActiveChild,
    );
    final framedActiveBlock = fencedCode
        ? _ActiveCodeLineRail(
            controller: _blockController,
            textStyle: activeTextStyle,
            colors: colors,
            child: activeBlockContainer,
          )
        : activeBlockContainer;
    return _activeMultiTapRegion(
      Focus(
        canRequestFocus: false,
        skipTraversal: true,
        // ignore: deprecated_member_use
        onKey: (_, event) => _handleActiveBlockRawKey(event),
        child: Semantics(
          key: fencedCode
              ? const ValueKey('ianvs-markdown-active-code-semantics')
              : null,
          container: fencedCode,
          value: fencedCode ? _blockController.text : null,
          child: framedActiveBlock,
        ),
      ),
    );
  }

  Widget _buildRenderedBlock(
    IanvsMarkdownBlock block,
    IanvsMarkdownThemeData colors, {
    required int listNestingLevel,
    IanvsMarkdownHeadingSection? headingSection,
  }) {
    if (block.type == IanvsMarkdownBlockType.table) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: _EditableMarkdownTable(
          block: block,
          colors: colors,
          linkReferenceLabels: _linkReferences.labels,
          onCommitHistoryGroup: widget.controller.commitHistoryGroup,
          onCellChanged: _replaceTableCell,
          onCellFormatted: _replaceFormattedTableCell,
          onCellSelectionChanged: _syncTableCellSelection,
          onSelectAll: _handleSelectAllDocument,
          onDeleteLine: _deleteTableLine,
          onAddRow: () => _appendTableRow(block),
          onAddRowAbove: () => _prependTableRow(block),
          onAddColumn: () => _appendTableColumn(block),
          onMoveRow: (from, to) => _moveTableRow(block, from, to),
          onMoveColumn: (from, to) => _moveTableColumn(block, from, to),
        ),
      );
    }
    final sourceTasks = projectObsidianTaskMarkers(block.source).tasks;
    final referenceDefinitions = parseMarkdownLinkReferenceDefinitions(
      block.source,
    );
    var renderedTaskIndex = 0;
    Widget rendered;
    if (block.source.trim().isEmpty) {
      rendered = const SizedBox.shrink();
    } else if (referenceDefinitions.isNotEmpty) {
      rendered = _buildReferenceDefinitionProjection(
        referenceDefinitions,
        colors,
        onTapText: () =>
            _activateRenderedBlock(block, tapCount: _pointerTapCount),
      );
    } else if (block.type == IanvsMarkdownBlockType.frontMatter &&
        widget.showFrontMatter) {
      final document = parseMarkdownFrontMatter(block.source);
      if (!document.hasFrontMatter) {
        rendered = IanvsMarkdown(
          data: block.source,
          documentSelection: false,
          softLineBreak: widget.softLineBreak,
          renderBudget: widget.renderBudget,
          theme: colors,
        );
      } else if (document.entries.isEmpty) {
        rendered = const SizedBox.shrink();
      } else {
        rendered = IanvsMarkdownFrontMatterCard(
          entries: document.entries,
          theme: colors,
          compact: widget.compactFrontMatter,
          initiallyExpanded: true,
          showDocumentTitle: widget.showDocumentTitle,
          onTapLink: widget.onTapLink,
          onTextChanged: (entry, value) =>
              _setFrontMatterText(block, entry, value),
          onBooleanChanged: (entry, value) =>
              _setFrontMatterBoolean(block, entry, value),
          onNumberChanged: (entry, value) =>
              _setFrontMatterNumber(block, entry, value),
          onDateChanged: (entry, value) =>
              _setFrontMatterDate(block, entry, value),
          onListChanged: (entry, values) =>
              _setFrontMatterList(block, entry, values),
          onKeyChanged: (entry, key) => _setFrontMatterKey(block, entry, key),
        );
      }
    } else if (block.type == IanvsMarkdownBlockType.indentedCode) {
      rendered = _LivePreviewIndentedCode(
        source: block.source,
        colors: colors,
        onTap: () => _activateRenderedBlock(block, tapCount: _pointerTapCount),
      );
    } else {
      final completedTask = sourceTasks.any(
        (task) => ianvsMarkdownTaskMarkerUsesDoneText(task.marker),
      );
      final baseStyleSheet =
          widget.styleSheet ?? ianvsMarkdownStyleSheet(context, colors);
      final renderedStyleSheet = completedTask
          ? baseStyleSheet.copyWith(
              del: (baseStyleSheet.del ?? const TextStyle()).copyWith(
                color: colors.taskDoneColor,
                decoration: TextDecoration.lineThrough,
                decorationColor: colors.taskDoneColor,
              ),
            )
          : widget.styleSheet;
      rendered = IanvsMarkdown(
        data: _renderedBlockSource(block),
        selectable: true,
        documentSelection: false,
        styleSheet: renderedStyleSheet,
        onTapText: () =>
            _activateRenderedBlock(block, tapCount: _pointerTapCount),
        onCalloutToggle: () =>
            _activateRenderedBlock(block, tapCount: _pointerTapCount),
        onTapLink: (text, href, title) =>
            _handleRenderedLinkTap(block, text: text, href: href, title: title),
        imageBuilder: widget.imageBuilder,
        onImageResize: (request) => _resizeImage(block, request),
        onEditImage: (imageIndex) => _editStandardImage(block, imageIndex),
        checkboxBuilder: sourceTasks.isNotEmpty
            ? (checked) {
                final taskIndex = renderedTaskIndex;
                final task = taskIndex < sourceTasks.length
                    ? sourceTasks[taskIndex]
                    : IanvsMarkdownTaskSourceMarker(
                        marker: checked ? 'x' : ' ',
                        offset: -1,
                        nestLevel: 0,
                      );
                renderedTaskIndex += 1;
                return IanvsMarkdownTaskCheckbox(
                  value: ianvsMarkdownTaskMarkerIsChecked(task.marker),
                  marker: task.marker,
                  onChanged: task.offset < 0
                      ? null
                      : (value) => _setTaskChecked(block, task.offset, value),
                  theme: colors,
                );
              }
            : null,
        builders: widget.builders,
        showListIndentationGuides: false,
        listNestingOffset: listNestingLevel,
        softLineBreak: widget.softLineBreak,
        renderBudget: widget.renderBudget,
        diagramBuilder: widget.diagramBuilder,
        mathBuilder: widget.mathBuilder,
        onCopyCode: widget.onCopyCode,
        wikiEmbedBuilder: widget.wikiEmbedBuilder,
        wikiLinkExists: widget.wikiLinkExists,
        enableFileLinkChips: widget.enableFileLinkChips,
        obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      );
    }
    final headingLevel = block.type == IanvsMarkdownBlockType.heading
        ? _headingLevelForSource(block.source)
        : null;
    if (headingLevel != null) {
      rendered = _IanvsHeadingRail(
        key: ValueKey('ianvs-markdown-live-heading-rail-$headingLevel'),
        level: headingLevel,
        colors: colors,
        foldIdentity: headingSection?.identity,
        foldable:
            widget.enableHeadingFolding && (headingSection?.canFold ?? false),
        collapsed:
            headingSection != null &&
            _headingFoldController.isCollapsed(headingSection.identity),
        onToggle: headingSection == null
            ? null
            : () => _toggleHeadingFold(headingSection),
        setextUnderline: _setextHeadingUnderline(block.source),
        child: rendered,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: Semantics(
        button: true,
        label: 'Edit Markdown block',
        child: Listener(
          key: _renderedBlockTapKeys[block.start],
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _recordPointerDown(event);
            _pendingRenderedTapGlobal = event.position;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () =>
                _activateRenderedBlock(block, tapCount: _pointerTapCount),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: rendered,
              ),
            ),
          ),
        ),
      ),
    );
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

  void _handleRenderedLinkTap(
    IanvsMarkdownBlock block, {
    required String text,
    required String? href,
    required String title,
  }) {
    final navigatesInLivePreview =
        RegExp(r'^ {0,3}!\[\[[^\]\n]+\]\][ \t]*$').hasMatch(block.source) ||
        _sourceContainsMatchingWikiLink(block.source, text: text, href: href);
    if (navigatesInLivePreview && widget.onTapLink != null) {
      _pendingRenderedTapGlobal = null;
      widget.onTapLink!(text, href, title);
      return;
    }
    // Obsidian keeps ordinary Markdown links as rendered controls on a normal
    // click. The inline-link builder consumes that interaction in Live
    // Preview; navigation remains available in Reading mode, while Wiki links
    // use the host callback directly in Live Preview.
    _activateRenderedBlock(block, tapCount: _pointerTapCount);
  }

  bool _sourceContainsMatchingWikiLink(
    String source, {
    required String text,
    required String? href,
  }) {
    final targetHref = href?.trim();
    if (targetHref == null || targetHref.isEmpty) return false;
    final tappedLabel = text.trim();
    final pattern = RegExp(r'\[\[([^\]\n]+)\]\]');
    for (final match in pattern.allMatches(source)) {
      final reference = parseIanvsMarkdownWikiLinkBody(match.group(1)!);
      if (reference != null &&
          reference.target == targetHref &&
          reference.label == tappedLabel) {
        return true;
      }
    }
    return false;
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

  void _resizeImage(
    IanvsMarkdownBlock block,
    IanvsMarkdownImageResizeRequest request,
  ) {
    final replacement = switch (request.syntax) {
      IanvsMarkdownImageSourceSyntax.standard => rewriteIanvsMarkdownImageWidth(
        block.source,
        imageIndex: request.imageIndex,
        width: request.width,
        linkReferenceLabels: _linkReferences.labels,
      ),
      IanvsMarkdownImageSourceSyntax.wiki => rewriteIanvsMarkdownWikiImageWidth(
        block.source,
        width: request.width,
      ),
    };
    if (replacement == block.source) return;
    _replaceBlockSource(block, replacement);
  }

  void _editStandardImage(IanvsMarkdownBlock block, int imageIndex) {
    final image = findIanvsMarkdownStandardImageSource(
      block.source,
      imageIndex: imageIndex,
      linkReferenceLabels: _linkReferences.labels,
    );
    if (image == null) return;
    if (image.syntax != IanvsMarkdownStandardImageSourceSyntax.inline) {
      return;
    }
    final selection = TextSelection(
      baseOffset: block.start + image.editableRange.start,
      extentOffset: block.start + image.editableRange.end,
    );
    _activateSelectionSurface(selection, (
      first: block,
      start: block.start,
      end: block.end,
    ));
  }

  void _setTaskChecked(
    IanvsMarkdownBlock block,
    int markerOffsetInBlock,
    bool checked,
  ) {
    final markerOffset = block.start + markerOffsetInBlock;
    final current = widget.controller.value;
    if (markerOffsetInBlock < 0 ||
        markerOffsetInBlock >= block.source.length ||
        markerOffset < 0 ||
        markerOffset >= current.text.length) {
      return;
    }
    widget.controller.value = current.copyWith(
      text: current.text.replaceRange(
        markerOffset,
        markerOffset + 1,
        checked ? 'x' : ' ',
      ),
      composing: TextRange.empty,
    );
  }

  void _setFrontMatterText(
    IanvsMarkdownBlock block,
    MarkdownMetadataEntry entry,
    String value,
  ) {
    final target = _currentFrontMatterTarget(block, entry);
    if (target == null || !_canReplayFrontMatterEntry(entry, target.entry)) {
      return;
    }
    final replacement = replaceMarkdownFrontMatterTextValue(
      target.block.source,
      target.entry,
      value,
    );
    if (replacement == target.block.source) return;
    _replaceBlockSource(target.block, replacement);
  }

  void _setFrontMatterBoolean(
    IanvsMarkdownBlock block,
    MarkdownMetadataEntry entry,
    bool value,
  ) {
    final target = _currentFrontMatterTarget(block, entry);
    if (target == null || !_canReplayFrontMatterEntry(entry, target.entry)) {
      return;
    }
    final replacement = replaceMarkdownFrontMatterBooleanValue(
      target.block.source,
      target.entry,
      value,
    );
    if (replacement == target.block.source) return;
    _replaceBlockSource(target.block, replacement);
  }

  void _setFrontMatterNumber(
    IanvsMarkdownBlock block,
    MarkdownMetadataEntry entry,
    num value,
  ) {
    final target = _currentFrontMatterTarget(block, entry);
    if (target == null || !_canReplayFrontMatterEntry(entry, target.entry)) {
      return;
    }
    final replacement = replaceMarkdownFrontMatterNumberValue(
      target.block.source,
      target.entry,
      value,
    );
    if (replacement == target.block.source) return;
    _replaceBlockSource(target.block, replacement);
  }

  void _setFrontMatterDate(
    IanvsMarkdownBlock block,
    MarkdownMetadataEntry entry,
    String value,
  ) {
    final target = _currentFrontMatterTarget(block, entry);
    if (target == null || !_canReplayFrontMatterEntry(entry, target.entry)) {
      return;
    }
    final replacement = replaceMarkdownFrontMatterDateValue(
      target.block.source,
      target.entry,
      value,
    );
    if (replacement == target.block.source) return;
    _replaceBlockSource(target.block, replacement);
  }

  void _setFrontMatterList(
    IanvsMarkdownBlock block,
    MarkdownMetadataEntry entry,
    List<String> values,
  ) {
    final target = _currentFrontMatterTarget(block, entry);
    if (target == null || !target.entry.listValuesEditable) return;
    var resolvedValues = values;
    if (!identical(target.entry, entry)) {
      final rebased = _rebaseFrontMatterListEdit(
        base: entry.items,
        local: values,
        remote: target.entry.items,
        suppressDuplicates: _isAliasProperty(entry.key),
      );
      if (rebased == null) return;
      resolvedValues = rebased;
    }
    final replacement = replaceMarkdownFrontMatterListValue(
      target.block.source,
      target.entry,
      resolvedValues,
    );
    if (replacement == target.block.source) return;
    _replaceBlockSource(target.block, replacement);
  }

  bool _isAliasProperty(String key) {
    final normalized = key.toLowerCase().replaceAll('-', '_');
    return normalized == 'alias' || normalized == 'aliases';
  }

  List<int>? _subsequencePositions(
    List<String> subsequence,
    List<String> values,
  ) {
    final positions = <int>[];
    var valueIndex = 0;
    for (final item in subsequence) {
      while (valueIndex < values.length && values[valueIndex] != item) {
        valueIndex += 1;
      }
      if (valueIndex >= values.length) return null;
      positions.add(valueIndex);
      valueIndex += 1;
    }
    return positions;
  }

  List<String>? _rebaseFrontMatterListEdit({
    required List<String> base,
    required List<String> local,
    required List<String> remote,
    required bool suppressDuplicates,
  }) {
    final basePositions = _subsequencePositions(base, remote);
    if (basePositions == null) return null;
    if (listEquals(local, base)) return List<String>.of(remote);
    if (local.length == base.length + 1 &&
        listEquals(local.sublist(0, base.length), base)) {
      final result = List<String>.of(remote);
      final added = local.last;
      if (!suppressDuplicates || !result.contains(added)) result.add(added);
      return result;
    }
    if (local.length + 1 == base.length) {
      for (var removedIndex = 0; removedIndex < base.length; removedIndex++) {
        final candidate = List<String>.of(base)..removeAt(removedIndex);
        if (!listEquals(candidate, local)) continue;
        final result = List<String>.of(remote)
          ..removeAt(basePositions[removedIndex]);
        return result;
      }
    }
    return null;
  }

  void _setFrontMatterKey(
    IanvsMarkdownBlock block,
    MarkdownMetadataEntry entry,
    String key,
  ) {
    final target = _currentFrontMatterTarget(block, entry);
    if (target == null || !_canReplayFrontMatterEntry(entry, target.entry)) {
      return;
    }
    final replacement = replaceMarkdownFrontMatterKey(
      target.block.source,
      target.entry,
      key,
    );
    if (replacement == target.block.source) return;
    _replaceBlockSource(target.block, replacement);
  }

  bool _canReplayFrontMatterEntry(
    MarkdownMetadataEntry base,
    MarkdownMetadataEntry current,
  ) {
    return identical(base, current) ||
        (base.type == current.type &&
            base.value == current.value &&
            listEquals(base.items, current.items));
  }

  ({IanvsMarkdownBlock block, MarkdownMetadataEntry entry})?
  _currentFrontMatterTarget(
    IanvsMarkdownBlock block,
    MarkdownMetadataEntry entry,
  ) {
    final current = widget.controller.text;
    if (block.start >= 0 &&
        block.end >= block.start &&
        block.end <= current.length &&
        current.substring(block.start, block.end) == block.source) {
      return (block: block, entry: entry);
    }
    IanvsMarkdownBlock? currentBlock;
    for (final candidate in parseMarkdownBlocks(
      current,
      splitListItems: true,
    )) {
      if (candidate.type == IanvsMarkdownBlockType.frontMatter) {
        currentBlock = candidate;
        break;
      }
    }
    if (currentBlock == null) return null;
    final document = parseMarkdownFrontMatter(currentBlock.source);
    if (!document.hasFrontMatter) return null;
    for (final candidate in document.entries) {
      if (candidate.key == entry.key) {
        return (block: currentBlock, entry: candidate);
      }
    }
    return null;
  }

  void _replaceTableCell(
    _EditableTableCell cell,
    TextEditingValue replacement,
  ) {
    final currentCell = _currentTableCell(cell);
    if (currentCell == null) return;
    final current = widget.controller.value;
    if (widget.normalizeTablesOnEdit) {
      final currentBlock = _currentTableBlock(currentCell.tableStart);
      if (currentBlock == null) return;
      final model = _parseEditableTable(currentBlock);
      if (currentCell.row >= model.rows.length ||
          currentCell.column >= model.rows[currentCell.row].length) {
        return;
      }
      final rows = _editableTableTextRows(model);
      rows[currentCell.row][currentCell.column] = replacement.text;
      final serialized = _serializeEditableTable(rows, model.alignments);
      if (serialized.isEmpty) return;
      final nextText = current.text.replaceRange(
        currentBlock.start,
        currentBlock.end,
        serialized,
      );
      IanvsMarkdownBlock? nextBlock;
      for (final candidate in parseMarkdownBlocks(
        nextText,
        splitListItems: true,
      )) {
        if (candidate.type == IanvsMarkdownBlockType.table &&
            candidate.start == currentBlock.start) {
          nextBlock = candidate;
          break;
        }
      }
      _EditableTableCell? nextCell;
      if (nextBlock != null) {
        final nextModel = _parseEditableTable(nextBlock);
        if (currentCell.row < nextModel.rows.length &&
            currentCell.column < nextModel.rows[currentCell.row].length) {
          nextCell = nextModel.rows[currentCell.row][currentCell.column];
        }
      }
      final selection = nextCell == null
          ? current.selection
          : _tableCellDocumentSelection(
                  nextCell,
                  nextText,
                  replacement.selection,
                ) ??
                current.selection;
      widget.controller.value = current.copyWith(
        text: nextText,
        selection: selection,
        composing: TextRange.empty,
      );
      return;
    }
    final editStart = currentCell.isSynthetic
        ? currentCell.lineStart
        : currentCell.start;
    final editEnd = currentCell.isSynthetic
        ? currentCell.lineEnd
        : currentCell.end;
    final sourceReplacement = currentCell.isSynthetic
        ? _materializeTableLineCell(
            currentCell.lineSource,
            column: currentCell.column,
            replacement: replacement.text,
          )
        : replacement.text;
    if (editStart < 0 || editEnd < editStart || editEnd > current.text.length) {
      return;
    }
    final delta = sourceReplacement.length - (editEnd - editStart);
    TextSelection selection = current.selection;
    if (selection.isValid) {
      int shift(int offset) {
        if (offset <= editStart) return offset;
        if (offset >= editEnd) return offset + delta;
        return editStart + sourceReplacement.length;
      }

      selection = TextSelection(
        baseOffset: shift(selection.baseOffset),
        extentOffset: shift(selection.extentOffset),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      );
    }
    final nextText = current.text.replaceRange(
      editStart,
      editEnd,
      sourceReplacement,
    );
    selection =
        _tableCellDocumentSelection(
          currentCell,
          nextText,
          replacement.selection,
        ) ??
        selection;
    widget.controller.value = current.copyWith(
      text: nextText,
      selection: selection,
      composing: TextRange.empty,
    );
  }

  void _replaceFormattedTableCell(
    _EditableTableCell cell,
    TextEditingValue replacement,
  ) {
    _replaceTableCell(cell, replacement);
  }

  void _syncTableCellSelection(
    _EditableTableCell cell,
    TextEditingValue value,
  ) {
    final currentCell = _currentTableCell(cell);
    if (currentCell == null) return;
    final selection = _tableCellDocumentSelection(
      currentCell,
      widget.controller.text,
      value.selection,
    );
    if (selection == null || selection == widget.controller.selection) return;
    widget.controller.selection = selection;
  }

  _EditableTableCell? _currentTableCell(_EditableTableCell snapshot) {
    final block = _currentTableBlock(snapshot.tableStart);
    if (block == null) return null;
    final model = _parseEditableTable(block);
    if (snapshot.row < 0 ||
        snapshot.row >= model.rows.length ||
        snapshot.column < 0 ||
        snapshot.column >= model.rows[snapshot.row].length) {
      return null;
    }
    return model.rows[snapshot.row][snapshot.column];
  }

  IanvsMarkdownBlock? _currentTableBlock(int tableStart) {
    for (final block in _blocks) {
      if (block.type == IanvsMarkdownBlockType.table &&
          block.start == tableStart) {
        return block;
      }
    }
    return null;
  }

  TextSelection? _tableCellDocumentSelection(
    _EditableTableCell cell,
    String source,
    TextSelection localSelection,
  ) {
    if (!localSelection.isValid ||
        cell.lineStart < 0 ||
        cell.lineStart > source.length) {
      return null;
    }
    final newline = source.indexOf('\n', cell.lineStart);
    final lineEnd = newline < 0 ? source.length : newline;
    final line = source.substring(cell.lineStart, lineEnd);
    final ranges = _tableLineCellRanges(_EditableTableLine(line, 0));
    if (cell.column >= ranges.length) return null;
    final range = ranges[cell.column];
    final cellStart = cell.lineStart + range.$1;
    final cellLength = range.$2 - range.$1;
    return TextSelection(
      baseOffset: cellStart + localSelection.baseOffset.clamp(0, cellLength),
      extentOffset:
          cellStart + localSelection.extentOffset.clamp(0, cellLength),
      affinity: localSelection.affinity,
      isDirectional: localSelection.isDirectional,
    );
  }

  void _deleteTableLine(_EditableTableCell cell) {
    final currentCell = _currentTableCell(cell);
    if (currentCell == null) return;
    final current = widget.controller.value;
    final caret =
        (currentCell.isSynthetic ? currentCell.lineStart : currentCell.start)
            .clamp(0, current.text.length);
    widget.controller.selection = TextSelection.collapsed(offset: caret);
    widget.controller.deleteSelectedLines();
  }

  void _appendTableRow(IanvsMarkdownBlock block) {
    final model = _parseEditableTable(block);
    if (model.rows.isEmpty || model.alignments.isEmpty) return;
    final rows = _editableTableTextRows(model)
      ..add(List<String>.filled(model.alignments.length, ''));
    _replaceBlockSource(block, _serializeEditableTable(rows, model.alignments));
  }

  void _prependTableRow(IanvsMarkdownBlock block) {
    final model = _parseEditableTable(block);
    if (model.rows.isEmpty || model.alignments.isEmpty) return;
    final rows = _editableTableTextRows(model)
      ..insert(0, List<String>.filled(model.alignments.length, ''));
    _replaceBlockSource(block, _serializeEditableTable(rows, model.alignments));
  }

  void _appendTableColumn(IanvsMarkdownBlock block) {
    final model = _parseEditableTable(block);
    if (model.rows.isEmpty || model.alignments.isEmpty) return;
    final rows = _editableTableTextRows(model);
    for (final row in rows) {
      row.add('');
    }
    final alignments = [...model.alignments, _EditableTableAlignment.none];
    _replaceBlockSource(block, _serializeEditableTable(rows, alignments));
  }

  void _moveTableRow(IanvsMarkdownBlock block, int from, int to) {
    final model = _parseEditableTable(block);
    if (from < 0 ||
        to < 0 ||
        from >= model.rows.length ||
        to >= model.rows.length ||
        from == to) {
      return;
    }
    final rows = _editableTableTextRows(model);
    final moved = rows.removeAt(from);
    rows.insert(to, moved);
    _replaceBlockSource(block, _serializeEditableTable(rows, model.alignments));
  }

  void _moveTableColumn(IanvsMarkdownBlock block, int from, int to) {
    final model = _parseEditableTable(block);
    if (model.rows.isEmpty ||
        from < 0 ||
        to < 0 ||
        from >= model.alignments.length ||
        to >= model.alignments.length ||
        from == to) {
      return;
    }
    final rows = _editableTableTextRows(model);
    for (final row in rows) {
      final moved = row.removeAt(from);
      row.insert(to, moved);
    }
    final alignments = [...model.alignments];
    final movedAlignment = alignments.removeAt(from);
    alignments.insert(to, movedAlignment);
    _replaceBlockSource(block, _serializeEditableTable(rows, alignments));
  }

  void _replaceBlockSource(IanvsMarkdownBlock block, String replacement) {
    final current = widget.controller.value;
    if (block.start < 0 ||
        block.end < block.start ||
        block.end > current.text.length ||
        current.text.substring(block.start, block.end) != block.source) {
      return;
    }
    final delta = replacement.length - (block.end - block.start);
    final selection = current.selection.isValid
        ? TextSelection(
            baseOffset: _shiftOffsetAfterReplacement(
              current.selection.baseOffset,
              block.start,
              block.end,
              replacement.length,
              delta,
            ),
            extentOffset: _shiftOffsetAfterReplacement(
              current.selection.extentOffset,
              block.start,
              block.end,
              replacement.length,
              delta,
            ),
            affinity: current.selection.affinity,
            isDirectional: current.selection.isDirectional,
          )
        : current.selection;
    widget.controller.commitHistoryGroup();
    widget.controller.value = current.copyWith(
      text: current.text.replaceRange(block.start, block.end, replacement),
      selection: selection,
      composing: TextRange.empty,
    );
    widget.controller.commitHistoryGroup();
  }

  TextStyle _activeBlockTextStyle(
    IanvsMarkdownBlock block,
    MarkdownStyleSheet styleSheet,
    IanvsMarkdownThemeData colors,
  ) {
    final TextStyle? renderedStyle = switch (block.type) {
      IanvsMarkdownBlockType.heading => _headingStyleForSource(
        block.source,
        styleSheet,
      ),
      IanvsMarkdownBlockType.fencedCode ||
      IanvsMarkdownBlockType.indentedCode ||
      IanvsMarkdownBlockType.displayMath ||
      IanvsMarkdownBlockType.table ||
      IanvsMarkdownBlockType.frontMatter ||
      IanvsMarkdownBlockType.html => TextStyle(
        color: colors.textPrimary,
        fontFamily: colors.monoFontFamily,
        fontFamilyFallback: colors.monoFontFamilyFallback,
        fontSize: 13,
        height: 1.55,
      ),
      _ => styleSheet.p,
    };
    return (renderedStyle ?? const TextStyle(fontSize: 14.5, height: 1.58))
        .copyWith(color: colors.textPrimary);
  }

  TextStyle? _headingStyleForSource(
    String source,
    MarkdownStyleSheet styleSheet,
  ) {
    return switch (_headingLevelForSource(source) ?? 1) {
      1 => styleSheet.h1,
      2 => styleSheet.h2,
      3 => styleSheet.h3,
      4 => styleSheet.h4,
      5 => styleSheet.h5,
      _ => styleSheet.h6,
    };
  }

  IanvsMarkdownSyntaxTheme _livePreviewSyntaxTheme(
    IanvsMarkdownThemeData colors,
  ) {
    return IanvsMarkdownSyntaxTheme(
      heading: TextStyle(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
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
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff6b5b22)
            : const Color(0xffffe184),
      ),
      code: ianvsMarkdownInlineCodeStyle(colors),
      inlineCodeMarker: ianvsMarkdownInlineCodeStyle(colors),
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
      comment: TextStyle(
        color: colors.textTertiary,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

int? _headingLevelForSource(String source) {
  final firstLineEnd = source.indexOf('\n');
  final firstLine = firstLineEnd < 0
      ? source
      : source.substring(0, firstLineEnd);
  final atx = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+|$)').firstMatch(firstLine);
  if (atx != null) {
    final headings = parseMarkdownHeadings(firstLine);
    return headings.isEmpty ? null : headings.first.level;
  }
  final headings = parseMarkdownHeadings(source);
  return headings.isEmpty ? null : headings.first.level;
}

int? _activeHeadingLevelForSource(String source) =>
    _headingLevelForSource(source);

bool _isEmptyAtxHeadingSource(String source) {
  final firstLineEnd = source.indexOf('\n');
  final firstLine = firstLineEnd < 0
      ? source
      : source.substring(0, firstLineEnd);
  final opening = RegExp(r'^ {0,3}#{1,6}(?:[ \t]+|$)').firstMatch(firstLine);
  if (opening == null) return false;
  var content = firstLine.substring(opening.end).trimRight();
  content = content.replaceFirst(RegExp(r'(?:^|[ \t]+)#+$'), '').trimRight();
  return content.isEmpty;
}

String? _setextHeadingUnderline(String source) {
  final lines = source.split('\n');
  if (lines.length < 2 || lines.first.trim().isEmpty) return null;
  final underline = lines.last.trimRight();
  return RegExp(r'^ {0,3}(?:=+|-+)$').hasMatch(underline) ? underline : null;
}

String _indentedCodeContentLine(String sourceLine) {
  if (sourceLine.startsWith('\t')) return sourceLine.substring(1);
  if (sourceLine.startsWith('    ')) return sourceLine.substring(4);
  return sourceLine;
}

class _LivePreviewIndentedCode extends StatelessWidget {
  const _LivePreviewIndentedCode({
    required this.source,
    required this.colors,
    required this.onTap,
  });

  final String source;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = colors.smallRadius / 2;
    final patternColor = (dark ? Colors.white : Colors.black).withValues(
      alpha: .12,
    );
    final style = TextStyle(
      color: colors.codeForeground,
      fontFamily: colors.monoFontFamily,
      fontFamilyFallback: colors.monoFontFamilyFallback,
      fontSize: 14,
      height: 1.5,
    );
    final lines = source.split('\n');
    return Container(
      key: const ValueKey('ianvs-markdown-live-indented-code'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      foregroundDecoration: IanvsMarkdownDashedBorderDecoration(
        color: colors.borderSoft,
        radius: radius,
      ),
      child: CustomPaint(
        key: const ValueKey('ianvs-markdown-live-indented-code-pattern'),
        painter: IanvsMarkdownCodePatternPainter(color: patternColor),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < lines.length; index += 1)
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onTap,
                  child: Container(
                    key: ValueKey('ianvs-markdown-indented-code-line-$index'),
                    constraints: const BoxConstraints(minHeight: 21),
                    child: lines[index].isEmpty
                        ? const SizedBox(height: 21)
                        : SelectableText(
                            _indentedCodeContentLine(lines[index]),
                            style: style,
                            onTap: onTap,
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveTextLineRail extends StatelessWidget {
  const _ActiveTextLineRail({
    required this.controller,
    required this.textStyle,
    required this.colors,
    this.logicalStartOffset = 10,
    required this.child,
  });

  final TextEditingController controller;
  final TextStyle textStyle;
  final IanvsMarkdownThemeData colors;
  final double logicalStartOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fallbackLineHeight =
        ((textStyle.fontSize ?? 14.5) * (textStyle.height ?? 1.2))
            .clamp(16.0, 26.0)
            .toDouble();
    return _ActiveTextLineRailLayout(
      controller: controller,
      textDirection: Directionality.of(context),
      logicalStartOffset: logicalStartOffset,
      fallbackLineHeight: fallbackLineHeight,
      children: [
        child,
        IgnorePointer(
          key: const ValueKey('ianvs-markdown-active-line-rail'),
          child: Container(
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveTextLineRailLayout extends MultiChildRenderObjectWidget {
  const _ActiveTextLineRailLayout({
    required this.controller,
    required this.textDirection,
    required this.logicalStartOffset,
    required this.fallbackLineHeight,
    required super.children,
  });

  final TextEditingController controller;
  final TextDirection textDirection;
  final double logicalStartOffset;
  final double fallbackLineHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderActiveTextLineRail(
        controller,
        textDirection,
        logicalStartOffset,
        fallbackLineHeight,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderActiveTextLineRail renderObject,
  ) {
    renderObject
      ..controller = controller
      ..textDirection = textDirection
      ..logicalStartOffset = logicalStartOffset
      ..fallbackLineHeight = fallbackLineHeight;
  }
}

class _ActiveTextLineRailParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderActiveTextLineRail extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ActiveTextLineRailParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _ActiveTextLineRailParentData
        > {
  _RenderActiveTextLineRail(
    this._controller,
    this._textDirection,
    this._logicalStartOffset,
    this._fallbackLineHeight,
  );

  TextEditingController _controller;
  TextDirection _textDirection;
  double _logicalStartOffset;
  double _fallbackLineHeight;
  double? _railTop;
  double? _railHeight;
  var _railGeometryUpdateScheduled = false;

  TextEditingController get controller => _controller;
  set controller(TextEditingController value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(markNeedsLayout);
    _controller = value;
    if (attached) _controller.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  double get logicalStartOffset => _logicalStartOffset;
  set logicalStartOffset(double value) {
    if (value == _logicalStartOffset) return;
    _logicalStartOffset = value;
    markNeedsLayout();
  }

  double get fallbackLineHeight => _fallbackLineHeight;
  set fallbackLineHeight(double value) {
    if (value == _fallbackLineHeight) return;
    _fallbackLineHeight = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _ActiveTextLineRailParentData) {
      child.parentData = _ActiveTextLineRailParentData();
    }
  }

  @override
  void performLayout() {
    final editor = firstChild;
    final rail = editor == null ? null : childAfter(editor);
    if (editor == null || rail == null) {
      size = constraints.smallest;
      return;
    }

    editor.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(editor.size);
    final editorParentData =
        editor.parentData! as _ActiveTextLineRailParentData;
    editorParentData.offset = Offset.zero;

    final selection = _controller.selection;
    final caretOffset = selection.isValid
        ? selection.extentOffset.clamp(0, _controller.text.length)
        : 0;
    final railTop = _railTop ?? 3.0;
    final railHeight = _railHeight ?? _fallbackLineHeight;

    rail.layout(
      BoxConstraints.tightFor(width: 2, height: railHeight),
      parentUsesSize: true,
    );
    final railParentData = rail.parentData! as _ActiveTextLineRailParentData;
    final railLeft = switch (_textDirection) {
      TextDirection.ltr => -_logicalStartOffset,
      TextDirection.rtl => size.width + _logicalStartOffset - rail.size.width,
    };
    railParentData.offset = Offset(railLeft, railTop);
    _scheduleRailGeometryUpdate(caretOffset);
  }

  void _scheduleRailGeometryUpdate(int caretOffset) {
    if (_railGeometryUpdateScheduled) return;
    _railGeometryUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _railGeometryUpdateScheduled = false;
      if (!attached) return;
      final editor = firstChild;
      final editable = editor == null ? null : _findRenderEditable(editor);
      if (editable == null || !editable.hasSize || !hasSize) return;
      final caret = editable.getLocalRectForCaret(
        TextPosition(offset: caretOffset),
      );
      final nextTop = editable.localToGlobal(caret.topLeft, ancestor: this).dy;
      final nextHeight = caret.height.clamp(16.0, 26.0).toDouble();
      if (_railTop == nextTop && _railHeight == nextHeight) return;
      _railTop = nextTop;
      _railHeight = nextHeight;
      markNeedsLayout();
    });
  }

  RenderEditable? _findRenderEditable(RenderObject root) {
    if (root is RenderEditable) return root;
    RenderEditable? result;
    root.visitChildren((child) {
      result ??= _findRenderEditable(child);
    });
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _ActiveIndentedCodeLineRail extends StatelessWidget {
  const _ActiveIndentedCodeLineRail({
    required this.controller,
    required this.textStyle,
    required this.colors,
    required this.child,
  });

  final TextEditingController controller;
  final TextStyle textStyle;
  final IanvsMarkdownThemeData colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final selection = controller.selection;
        final caretOffset = selection.isValid
            ? selection.extentOffset.clamp(0, controller.text.length)
            : 0;
        final lineStart = caretOffset == 0
            ? 0
            : controller.text.lastIndexOf('\n', caretOffset - 1) + 1;
        final nextBreak = controller.text.indexOf('\n', caretOffset);
        final lineEnd = nextBreak < 0 ? controller.text.length : nextBreak;
        final painter =
            TextPainter(
              text: controller.buildTextSpan(
                context: context,
                style: textStyle,
                withComposing: false,
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              textWidthBasis: TextWidthBasis.parent,
            )..layout(
              maxWidth: constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width,
            );
        const markerSize = Size(7, 6);
        final lineHeight = painter.preferredLineHeight;
        final logicalStart = painter.getOffsetForCaret(
          TextPosition(offset: lineStart),
          Rect.zero,
        );
        final logicalEnd = painter.getOffsetForCaret(
          TextPosition(offset: lineEnd),
          Rect.zero,
        );
        final caret = painter.getOffsetForCaret(
          TextPosition(offset: caretOffset),
          Rect.zero,
        );
        final railHeight = (logicalEnd.dy - logicalStart.dy + lineHeight)
            .clamp(lineHeight, double.infinity)
            .toDouble();
        final markerTop =
            3 + caret.dy + ((lineHeight - markerSize.height) / 2) + 1;
        final markerColor = Color.lerp(
          colors.textTertiary,
          colors.accent,
          .28,
        )!.withValues(alpha: .78);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              key: const ValueKey(
                'ianvs-markdown-active-indented-code-line-rail',
              ),
              left: -10,
              top: 3 + logicalStart.dy,
              child: Container(
                width: 2,
                height: railHeight,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
            Positioned(
              key: const ValueKey(
                'ianvs-markdown-active-indented-code-line-marker',
              ),
              left: -5,
              top: markerTop,
              child: CustomPaint(
                size: markerSize,
                painter: _CodeCaretMarkerPainter(markerColor),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ActiveCodeLineRail extends StatelessWidget {
  const _ActiveCodeLineRail({
    required this.controller,
    required this.textStyle,
    required this.colors,
    required this.child,
  });

  final TextEditingController controller;
  final TextStyle textStyle;
  final IanvsMarkdownThemeData colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final selection = controller.selection;
        final caretOffset = selection.isValid
            ? selection.extentOffset.clamp(0, controller.text.length)
            : 0;
        final lineStart = caretOffset == 0
            ? 0
            : controller.text.lastIndexOf('\n', caretOffset - 1) + 1;
        final nextBreak = controller.text.indexOf('\n', caretOffset);
        final lineEnd = nextBreak < 0 ? controller.text.length : nextBreak;
        // The active surface contributes 10px margins and 16px padding on
        // both sides. RenderEditable then reserves its 1px caret gap and the
        // 1.5px cursor width. Match all of those insets so a logical source
        // line and its wrapped visual rows share identical geometry.
        final editableWidth = constraints.maxWidth - 20 - 32 - 2.5;
        final painter =
            TextPainter(
              text: controller.buildTextSpan(
                context: context,
                style: textStyle,
                withComposing: false,
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              textWidthBasis: TextWidthBasis.parent,
            )..layout(
              maxWidth: constraints.hasBoundedWidth
                  ? editableWidth.clamp(0, double.infinity)
                  : MediaQuery.sizeOf(context).width,
            );
        final lineHeight = painter.preferredLineHeight;
        final logicalStart = painter.getOffsetForCaret(
          TextPosition(offset: lineStart),
          Rect.zero,
        );
        final logicalEnd = painter.getOffsetForCaret(
          TextPosition(offset: lineEnd),
          Rect.zero,
        );
        final logicalLineHeight = (logicalEnd.dy - logicalStart.dy + lineHeight)
            .clamp(lineHeight, double.infinity)
            .toDouble();
        const railInset = 3.0;
        final railHeight = (logicalLineHeight - railInset * 2)
            .clamp(1, double.infinity)
            .toDouble();
        // Surface top margin (3) + TextField top padding (3) + CSS rail inset.
        final railTop = 6 + logicalStart.dy + railInset;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            PositionedDirectional(
              key: const ValueKey('ianvs-markdown-active-code-line-rail'),
              // Equivalent to the old inner-content offset of -31px, now
              // outside the clipped code surface so the gutter stays visible.
              start: -5,
              top: railTop,
              child: Container(
                width: 3,
                height: railHeight,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CodeCaretMarkerPainter extends CustomPainter {
  const _CodeCaretMarkerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CodeCaretMarkerPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _IanvsHeadingRail extends StatelessWidget {
  const _IanvsHeadingRail({
    super.key,
    required this.level,
    required this.colors,
    required this.child,
    this.foldIdentity,
    this.foldable = false,
    this.collapsed = false,
    this.onToggle,
    this.setextUnderline,
  });

  final int level;
  final IanvsMarkdownThemeData colors;
  final Widget child;
  final String? foldIdentity;
  final bool foldable;
  final bool collapsed;
  final VoidCallback? onToggle;
  final String? setextUnderline;

  @override
  Widget build(BuildContext context) {
    return _LiveHeadingFoldFrame(
      identity: foldIdentity,
      colors: colors,
      foldable: foldable,
      collapsed: collapsed,
      onToggle: onToggle,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colors.headingAccent(level), width: 2),
          ),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 17, height: 19),
                const SizedBox(width: 4),
                Expanded(child: child),
              ],
            ),
            if (setextUnderline case final underline?)
              Padding(
                padding: const EdgeInsets.only(left: 21),
                child: Align(
                  key: const ValueKey('ianvs-markdown-setext-underline-source'),
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: (underline.trim().length * 6.0)
                        .clamp(28.0, 220.0)
                        .toDouble(),
                    height: 1,
                    margin: const EdgeInsets.only(top: 1, bottom: 2),
                    decoration: BoxDecoration(
                      color: colors.textTertiary.withValues(alpha: .58),
                      borderRadius: BorderRadius.circular(.5),
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

class _LiveHeadingFoldFrame extends StatefulWidget {
  const _LiveHeadingFoldFrame({
    required this.identity,
    required this.colors,
    required this.foldable,
    required this.collapsed,
    required this.onToggle,
    required this.child,
  });

  final String? identity;
  final IanvsMarkdownThemeData colors;
  final bool foldable;
  final bool collapsed;
  final VoidCallback? onToggle;
  final Widget child;

  @override
  State<_LiveHeadingFoldFrame> createState() => _LiveHeadingFoldFrameState();
}

class _LiveHeadingFoldFrameState extends State<_LiveHeadingFoldFrame> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.foldable && (_hovering || widget.collapsed);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.foldable)
            SizedBox(
              width: 22,
              child: AnimatedOpacity(
                opacity: showToggle ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                alwaysIncludeSemantics: true,
                child: IconButton(
                  key: ValueKey(
                    'ianvs-markdown-live-heading-fold-${widget.identity}',
                  ),
                  tooltip: widget.collapsed ? '展开标题内容' : '折叠标题内容',
                  onPressed: widget.onToggle,
                  icon: Icon(
                    widget.collapsed
                        ? Icons.keyboard_arrow_right_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 17,
                  ),
                  color: widget.colors.textTertiary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 22,
                    height: 24,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

int _liveListIndentationColumns(String source) {
  final marker = RegExp(
    r'^([ \t]*)(?:[-+*]|\d{1,9}[.)])(?:[ \t]+|$)',
  ).firstMatch(source);
  if (marker == null) return 0;
  var columns = 0;
  for (final codeUnit in marker.group(1)!.codeUnits) {
    columns = codeUnit == 0x09 ? columns + (4 - columns % 4) : columns + 1;
  }
  return columns;
}

bool _isMarkerOnlyListSource(String source) =>
    RegExp(r'^[ \t]*(?:[-+*]|\d{1,9}[.)])[ \t]*$').hasMatch(source);

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
    if (tableRender is RenderTable && !tableRender.debugNeedsLayout) {
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
        label: 'Editable Markdown table',
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
                                    child: TextField(
                                      key: ValueKey(
                                        'ianvs-markdown-table-${cell.key}',
                                      ),
                                      controller: controller,
                                      focusNode: focusNode,
                                      maxLines: null,
                                      keyboardType: TextInputType.text,
                                      textInputAction: TextInputAction.next,
                                      smartDashesType: SmartDashesType.disabled,
                                      smartQuotesType: SmartQuotesType.disabled,
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
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        isCollapsed: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4.5,
                                        ),
                                      ),
                                      onChanged: (_) => widget.onCellChanged(
                                        cell,
                                        controller.value,
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
                tooltip: '在右侧新增列',
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
                tooltip: '在下方新增行',
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
        ? '拖动表格第 ${widget.index + 1} 行'
        : '拖动表格第 ${widget.index + 1} 列';
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
      column: contentScores[column] >= flexibleThreshold
          ? const IntrinsicColumnWidth(flex: 1)
          : const IntrinsicColumnWidth(),
  };
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

int _shiftOffsetAfterReplacement(
  int offset,
  int start,
  int end,
  int replacementLength,
  int delta,
) {
  if (offset <= start) return offset;
  if (offset >= end) return offset + delta;
  return start + replacementLength;
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
                _NavigationSectionLabel(label: 'MODE', colors: colors),
                const SizedBox(height: 10),
                _EditorModeTile(
                  tooltip: '实时预览',
                  label: 'Preview',
                  shortcut: '⌘1',
                  icon: Icons.visibility_outlined,
                  selected: mode == IanvsMarkdownEditorMode.livePreview,
                  colors: colors,
                  onTap: () =>
                      onModeSelected(IanvsMarkdownEditorMode.livePreview),
                ),
                _EditorModeTile(
                  tooltip: '源码模式',
                  label: 'Source',
                  shortcut: '⌘2',
                  icon: Icons.code_rounded,
                  selected: mode == IanvsMarkdownEditorMode.source,
                  colors: colors,
                  onTap: () => onModeSelected(IanvsMarkdownEditorMode.source),
                ),
                _EditorModeTile(
                  tooltip: '阅读模式',
                  label: 'Read',
                  shortcut: '⌘3',
                  icon: Icons.menu_book_outlined,
                  selected: mode == IanvsMarkdownEditorMode.preview,
                  colors: colors,
                  onTap: () => onModeSelected(IanvsMarkdownEditorMode.preview),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1, color: colors.border),
                ),
                _NavigationSectionLabel(label: 'OUTLINE', colors: colors),
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
  int caretOffset,
) {
  if (lines.isEmpty) return const <_HiddenMarkerSpan>[];
  var activeLine = lines.indexWhere(
    (line) => caretOffset >= line.line.start && caretOffset <= line.line.end,
  );
  if (activeLine < 0) activeLine = lines.length - 1;
  final hidden = <_HiddenMarkerSpan>[];
  for (var index = 0; index < lines.length; index += 1) {
    final markers = lines[index].markerRanges;
    if (markers.isEmpty) continue;
    // Obsidian exposes the complete marker run on the active physical line;
    // surrounding lines remain visually normalized.
    if (index == activeLine) continue;
    hidden.add(_HiddenMarkerSpan(markers.first, _collapsedGapPrefixStyle));
    hidden.addAll(
      markers
          .skip(1)
          .map((range) => _HiddenMarkerSpan(range, _hiddenQuoteMarkerStyle)),
    );
  }
  return List<_HiddenMarkerSpan>.unmodifiable(hidden);
}

class _ActiveQuoteBlock extends StatelessWidget {
  const _ActiveQuoteBlock({
    required this.textSpan,
    required this.lines,
    required this.textDirection,
    required this.textScaler,
    required this.colors,
    required this.child,
  });

  final TextSpan textSpan;
  final List<_QuoteLineLayout> lines;
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
  });

  final TextSpan textSpan;
  final List<_QuoteLineLayout> lines;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty || size.isEmpty) return;
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: (size.width - 35).clamp(0.0, double.infinity));
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
          ? 11 + index * fallbackHeight
          : 11 + boxes.map((box) => box.top).reduce((a, b) => a < b ? a : b);
      final bottom = boxes.isEmpty
          ? top + fallbackHeight
          : 11 + boxes.map((box) => box.bottom).reduce((a, b) => a > b ? a : b);
      for (var depth = 1; depth < line.depth; depth += 1) {
        final logicalX = 9.5 + depth * 19.0;
        final x = textDirection == TextDirection.rtl
            ? size.width - logicalX
            : logicalX;
        canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ActiveQuoteRailsPainter oldDelegate) {
    return oldDelegate.textSpan != textSpan ||
        oldDelegate.lines != lines ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler ||
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
            TextSpan(text: value.text.substring(start, end), style: style),
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

TextSpan _buildHighlightedFencedCodeSpan(
  String source, {
  required TextStyle style,
  required IanvsMarkdownSyntaxTheme syntaxTheme,
  required bool dark,
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
      TextSpan(text: source.substring(0, bodyStart), style: syntaxTheme.marker),
      markdownHighlightedCodeSpan(
        source.substring(bodyStart, closingStart),
        language: language,
        baseStyle: style,
        dark: dark,
      ),
      if (closingStart < source.length)
        TextSpan(
          text: source.substring(closingStart),
          style: syntaxTheme.marker,
        ),
    ],
  );
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
