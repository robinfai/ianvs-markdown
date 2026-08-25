import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../code_block.dart';
import '../obsidian_autolink.dart';
import '../obsidian_html.dart';
import 'editor_models.dart';
import 'markdown_paste.dart';
import 'reference_links.dart';

@immutable
final class IanvsMarkdownHistoryValue {
  const IanvsMarkdownHistoryValue({
    required this.canUndo,
    required this.canRedo,
  });

  static const empty = IanvsMarkdownHistoryValue(
    canUndo: false,
    canRedo: false,
  );

  final bool canUndo;
  final bool canRedo;
}

@immutable
final class IanvsMarkdownSyntaxTheme {
  const IanvsMarkdownSyntaxTheme({
    required this.heading,
    required this.marker,
    required this.link,
    required this.code,
    required this.comment,
    this.inlineCodeMarker,
    this.codeBlock = const TextStyle(),
    this.strong = const TextStyle(fontWeight: FontWeight.w700),
    this.emphasis = const TextStyle(fontStyle: FontStyle.italic),
    this.strikethrough = const TextStyle(
      decoration: TextDecoration.lineThrough,
    ),
    this.wikiLink = const TextStyle(fontWeight: FontWeight.w600),
    this.tag = const TextStyle(fontWeight: FontWeight.w600),
    this.highlight = const TextStyle(backgroundColor: Color(0x66ffd54f)),
    this.math = const TextStyle(fontStyle: FontStyle.italic),
    this.darkCodeHighlighting = false,
  });

  final TextStyle heading;
  final TextStyle marker;
  final TextStyle link;
  final TextStyle code;
  final TextStyle comment;
  final TextStyle? inlineCodeMarker;
  final TextStyle codeBlock;
  final TextStyle strong;
  final TextStyle emphasis;
  final TextStyle strikethrough;
  final TextStyle wikiLink;
  final TextStyle tag;
  final TextStyle highlight;
  final TextStyle math;
  final bool darkCodeHighlighting;
}

/// Owns Markdown source, selection, editor mode, dirty state, and history.
///
/// The controller is intentionally storage-agnostic. Hosts observe [text] or
/// [dirtyListenable] and decide when and where to persist the document.
class IanvsMarkdownController extends TextEditingController {
  IanvsMarkdownController({
    String text = '',
    IanvsMarkdownEditorMode mode = IanvsMarkdownEditorMode.livePreview,
    this.historyCoalescingDuration = const Duration(milliseconds: 500),
  }) : _mode = ValueNotifier<IanvsMarkdownEditorMode>(mode),
       _savedText = text,
       super.fromValue(
         TextEditingValue(
           text: text,
           selection: const TextSelection.collapsed(offset: 0),
         ),
       ) {
    _linkReferences = MarkdownLinkReferenceContext.parse(text);
    _history.add(value);
    _lastObservedValue = value;
    addListener(_handleValueChanged);
  }

  final Duration historyCoalescingDuration;
  final ValueNotifier<IanvsMarkdownEditorMode> _mode;
  final ValueNotifier<IanvsMarkdownHistoryValue> _historyState =
      ValueNotifier<IanvsMarkdownHistoryValue>(IanvsMarkdownHistoryValue.empty);
  final ValueNotifier<bool> _dirty = ValueNotifier<bool>(false);
  final List<TextEditingValue> _history = <TextEditingValue>[];

  late TextEditingValue _lastObservedValue;
  late MarkdownLinkReferenceContext _linkReferences;
  String _savedText;
  Timer? _coalescingTimer;
  var _historyIndex = 0;
  var _applyingHistory = false;
  _EditKind? _coalescingKind;

  /// Updated by editor widgets before they build their editable text.
  IanvsMarkdownSyntaxTheme? syntaxTheme;

  ValueListenable<IanvsMarkdownEditorMode> get modeListenable => _mode;
  IanvsMarkdownEditorMode get mode => _mode.value;

  set mode(IanvsMarkdownEditorMode value) {
    if (_mode.value == value) return;
    _mode.value = value;
  }

  ValueListenable<IanvsMarkdownHistoryValue> get historyListenable =>
      _historyState;
  ValueListenable<bool> get dirtyListenable => _dirty;
  bool get isDirty => _dirty.value;
  bool get canUndo => _historyIndex > 0;
  bool get canRedo => _historyIndex + 1 < _history.length;

  void markSaved() {
    _savedText = text;
    _setDirty(false);
  }

  void undo() {
    if (!canUndo) return;
    _closeCoalescingGroup();
    _historyIndex -= 1;
    _restoreHistoryValue(_history[_historyIndex]);
  }

  void redo() {
    if (!canRedo) return;
    _closeCoalescingGroup();
    _historyIndex += 1;
    _restoreHistoryValue(_history[_historyIndex]);
  }

  void clearHistory() {
    _closeCoalescingGroup();
    _history
      ..clear()
      ..add(value);
    _historyIndex = 0;
    _updateHistoryState();
  }

  /// Ends the current typing coalescing window without changing the document.
  ///
  /// Editor widgets call this when they are removed so hosts and tests are not
  /// left with a pending coalescing timer.
  void commitHistoryGroup() {
    _closeCoalescingGroup();
  }

  void replaceSelection(
    String replacement, {
    int? selectionStart,
    int? selectionEnd,
  }) {
    final range = _normalizedSelection(value);
    final updatedText = text.replaceRange(range.start, range.end, replacement);
    final base = range.start;
    final start = (selectionStart ?? replacement.length).clamp(
      0,
      replacement.length,
    );
    final end = (selectionEnd ?? start).clamp(0, replacement.length);
    _performCommand(
      TextEditingValue(
        text: updatedText,
        selection: TextSelection(
          baseOffset: base + start,
          extentOffset: base + end,
        ),
      ),
    );
  }

  void toggleInline(String marker) {
    assert(marker.isNotEmpty);
    var range = _normalizedSelection(value);
    final collapsedCaret = range.isCollapsed ? range.start : null;
    if (collapsedCaret != null) {
      final wordRange = _inlineWordRangeAtCaret(text, collapsedCaret);
      if (wordRange != null) {
        range = wordRange;
        final wrapped =
            range.start >= marker.length &&
            range.end + marker.length <= text.length &&
            text.substring(range.start - marker.length, range.start) ==
                marker &&
            text.substring(range.end, range.end + marker.length) == marker;
        if (wrapped) {
          final updated = text.replaceRange(
            range.start - marker.length,
            range.end + marker.length,
            text.substring(range.start, range.end),
          );
          _performCommand(
            TextEditingValue(
              text: updated,
              selection: TextSelection.collapsed(
                offset: collapsedCaret - marker.length,
              ),
            ),
          );
          return;
        }

        final selected = text.substring(range.start, range.end);
        final replacement = '$marker$selected$marker';
        final updated = text.replaceRange(range.start, range.end, replacement);
        _performCommand(
          TextEditingValue(
            text: updated,
            selection: TextSelection.collapsed(
              offset: collapsedCaret + marker.length,
            ),
          ),
        );
        return;
      }
    }
    if (range.start >= marker.length &&
        range.end + marker.length <= text.length &&
        text.substring(range.start - marker.length, range.start) == marker &&
        text.substring(range.end, range.end + marker.length) == marker) {
      final updated = text.replaceRange(
        range.start - marker.length,
        range.end + marker.length,
        text.substring(range.start, range.end),
      );
      _performCommand(
        TextEditingValue(
          text: updated,
          selection: TextSelection(
            baseOffset: range.start - marker.length,
            extentOffset: range.end - marker.length,
          ),
        ),
      );
      return;
    }

    final selected = text.substring(range.start, range.end);
    final replacement = '$marker$selected$marker';
    replaceSelection(
      replacement,
      selectionStart: marker.length,
      selectionEnd: marker.length + selected.length,
    );
  }

  void toggleLinePrefix(String prefix) {
    assert(prefix.isNotEmpty);
    final range = _selectedLineRange(value);
    final selected = text.substring(range.start, range.end);
    final lines = selected.split('\n');
    final nonEmpty = lines.where((line) => line.isNotEmpty).toList();
    final remove =
        nonEmpty.isNotEmpty &&
        nonEmpty.every((line) => line.startsWith(prefix));
    final replacement = lines
        .map((line) {
          if (line.isEmpty) return line;
          if (remove) return line.substring(prefix.length);
          return '$prefix$line';
        })
        .join('\n');
    _replaceRangeAndSelect(range.start, range.end, replacement);
  }

  void indentSelection({bool outdent = false}) {
    final range = _selectedLineRange(value);
    final selected = text.substring(range.start, range.end);
    final edits = <({int offset, int removed, int inserted})>[];
    final lines = selected.split('\n');
    const indentation = '    ';
    var lineOffset = 0;
    var transformedLineOffset = 0;
    final movedLineStarts = <int>{};
    final replacementLines = <String>[];
    for (final line in lines) {
      final indentationOffset = _markdownStructuralIndentOffset(line);
      late final String transformedLine;
      late final int removed;
      late final int inserted;
      if (!outdent) {
        removed = 0;
        inserted = indentation.length;
        transformedLine = line.replaceRange(
          indentationOffset,
          indentationOffset,
          indentation,
        );
      } else {
        removed = _leadingIndentRemoval(
          line.substring(indentationOffset),
          indentation.length,
        );
        inserted = 0;
        transformedLine = line.replaceRange(
          indentationOffset,
          indentationOffset + removed,
          '',
        );
      }
      edits.add((
        offset: lineOffset + indentationOffset,
        removed: removed,
        inserted: inserted,
      ));
      if (removed != 0 || inserted != 0) {
        movedLineStarts.add(range.start + transformedLineOffset);
      }
      replacementLines.add(transformedLine);
      lineOffset += line.length + 1;
      transformedLineOffset += transformedLine.length + 1;
    }
    final replacement = replacementLines.join('\n');

    int mapOffset(int documentOffset) {
      final local = (documentOffset - range.start).clamp(0, selected.length);
      var delta = 0;
      for (final edit in edits) {
        if (local < edit.offset) break;
        if (edit.removed > 0 && local <= edit.offset + edit.removed) {
          return range.start + edit.offset + delta + edit.inserted;
        }
        delta += edit.inserted - edit.removed;
      }
      return range.start + local + delta;
    }

    final currentSelection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: range.end);
    final indentedText = text.replaceRange(range.start, range.end, replacement);
    final indentedSelection = TextSelection(
      baseOffset: mapOffset(currentSelection.baseOffset),
      extentOffset: mapOffset(currentSelection.extentOffset),
      affinity: currentSelection.affinity,
      isDirectional: currentSelection.isDirectional,
    );
    final renumbered = _renumberOrderedLists(
      indentedText,
      touchedLineStarts: movedLineStarts,
      movedLineStarts: movedLineStarts,
    );

    _performCommand(
      TextEditingValue(
        text: renumbered.text,
        selection: TextSelection(
          baseOffset: _mapOffsetThroughMarkdownEdits(
            indentedSelection.baseOffset,
            renumbered.edits,
          ),
          extentOffset: _mapOffsetThroughMarkdownEdits(
            indentedSelection.extentOffset,
            renumbered.edits,
          ),
          affinity: indentedSelection.affinity,
          isDirectional: indentedSelection.isDirectional,
        ),
      ),
    );
  }

  /// Deletes every physical source line touched by the current selection.
  ///
  /// This follows CodeMirror's `deleteLine` range behavior used by Obsidian's
  /// “Delete paragraph” command: interior lines consume the preceding line
  /// break, the first line consumes the following break, and a selection that
  /// ends exactly at the next line start does not include that next line.
  bool deleteSelectedLines({int? preferredCaretOffset}) {
    final current = value;
    if (current.text.isEmpty ||
        current.composing.isValid && !current.composing.isCollapsed) {
      return false;
    }

    final selection = current.selection.isValid
        ? current.selection
        : TextSelection.collapsed(offset: current.text.length);
    final normalized = _normalizedSelection(
      current.copyWith(selection: selection),
    );
    final start = _sourceLineStart(current.text, normalized.start);
    final endProbe =
        !selection.isCollapsed &&
            normalized.end > 0 &&
            normalized.end == _sourceLineStart(current.text, normalized.end)
        ? normalized.end - 1
        : normalized.end;
    final end = _sourceLineEnd(current.text, endProbe);
    final deleteStart = start > 0 ? start - 1 : 0;
    final deleteEnd = start == 0 && end < current.text.length ? end + 1 : end;

    final oldCaret =
        (preferredCaretOffset ??
                _nextSourceLineCaret(current.text, selection.extentOffset))
            .clamp(0, current.text.length);
    final removed = deleteEnd - deleteStart;
    final mappedCaret = oldCaret <= deleteStart
        ? oldCaret
        : oldCaret >= deleteEnd
        ? oldCaret - removed
        : deleteStart;
    final updatedText = current.text.replaceRange(deleteStart, deleteEnd, '');
    final deletedContextSeeds = <String, int>{};
    for (final deletedLine in current.text.substring(start, end).split('\n')) {
      final marker = _parseMarkdownOrderedMarker(deletedLine);
      if (marker != null) {
        deletedContextSeeds.putIfAbsent(marker.contextKey, () => marker.number);
      }
    }
    final affectedOffset = deleteStart.clamp(0, updatedText.length);
    final nextAffectedOffset = (affectedOffset + 1).clamp(
      0,
      updatedText.length,
    );
    final renumbered = _renumberOrderedLists(
      updatedText,
      touchedLineStarts: {
        _sourceLineStart(updatedText, affectedOffset),
        _sourceLineStart(updatedText, nextAffectedOffset),
      },
      contextSeeds: deletedContextSeeds,
      affectedOffset: affectedOffset,
    );
    _performCommand(
      TextEditingValue(
        text: renumbered.text,
        selection: TextSelection.collapsed(
          offset: _mapOffsetThroughMarkdownEdits(
            mappedCaret.clamp(0, updatedText.length),
            renumbered.edits,
          ),
        ),
      ),
    );
    return true;
  }

  /// Whether a Tab shortcut should edit Markdown instead of traversing focus.
  ///
  /// Obsidian lets Tab leave a collapsed plain-text paragraph. List and quote
  /// lines keep Obsidian's four-space structural indentation behavior. Quote
  /// containers stay before the inserted indentation. Fenced and indented code
  /// use the same width, while a real selection remains multi-line indentable.
  bool get canIndentSelection {
    final currentSelection = selection;
    if (!currentSelection.isValid) return false;
    if (_selectionUsesCodeIndentation(value)) return true;
    if (!currentSelection.isCollapsed) return true;

    final caret = currentSelection.extentOffset.clamp(0, text.length);
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final nextLineBreak = text.indexOf('\n', caret);
    final lineEnd = nextLineBreak < 0 ? text.length : nextLineBreak;
    final line = text.substring(lineStart, lineEnd);
    return RegExp(
      r'^\s*(?:(?:[-+*] )(?:\[[ xX]\] )?|\d{1,9}[.)] |> )',
    ).hasMatch(line);
  }

  bool _selectionUsesCodeIndentation(TextEditingValue current) {
    final currentSelection = current.selection;
    if (!currentSelection.isValid) return false;
    final selected = _normalizedSelection(current);
    for (final block in parseMarkdownBlocks(current.text)) {
      final codeBlock =
          block.type == IanvsMarkdownBlockType.fencedCode ||
          block.type == IanvsMarkdownBlockType.indentedCode;
      if (codeBlock &&
          selected.start >= block.start &&
          selected.end <= block.end) {
        return true;
      }
    }
    return false;
  }

  /// Deletes a contiguous Markdown punctuation segment beside the caret.
  ///
  /// Obsidian treats punctuation such as a closing `**` or `)` as a separate
  /// Option+Delete segment. Returning false lets the editor delegate ordinary
  /// word and whitespace boundaries to Flutter's platform text action.
  bool deleteMarkdownPunctuationSegment({required bool forward}) {
    final current = value;
    final currentSelection = current.selection;
    if (!currentSelection.isValid ||
        !currentSelection.isCollapsed ||
        current.composing.isValid && !current.composing.isCollapsed) {
      return false;
    }

    final caret = currentSelection.extentOffset.clamp(0, current.text.length);
    final adjacent = forward ? caret : caret - 1;
    if (adjacent < 0 ||
        adjacent >= current.text.length ||
        !_isMarkdownPunctuation(current.text[adjacent])) {
      return false;
    }

    var start = caret;
    var end = caret;
    if (forward) {
      while (end < current.text.length &&
          _isMarkdownPunctuation(current.text[end])) {
        end += 1;
      }
    } else {
      while (start > 0 && _isMarkdownPunctuation(current.text[start - 1])) {
        start -= 1;
      }
    }

    _performCommand(
      TextEditingValue(
        text: current.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      ),
    );
    return true;
  }

  /// Moves or extends the caret across an adjacent Markdown punctuation run.
  ///
  /// Returning false delegates ordinary word movement to Flutter so language,
  /// whitespace, and underscore boundaries keep their platform behavior.
  bool moveAcrossMarkdownPunctuation({
    required bool forward,
    required bool extendSelection,
  }) {
    final current = value;
    final currentSelection = current.selection;
    if (!currentSelection.isValid ||
        !extendSelection && !currentSelection.isCollapsed ||
        current.composing.isValid && !current.composing.isCollapsed) {
      return false;
    }

    final extent = currentSelection.extentOffset.clamp(0, current.text.length);
    final adjacent = forward ? extent : extent - 1;
    if (adjacent < 0 ||
        adjacent >= current.text.length ||
        !_isMarkdownPunctuation(current.text[adjacent])) {
      return false;
    }

    var target = extent;
    if (forward) {
      while (target < current.text.length &&
          _isMarkdownPunctuation(current.text[target])) {
        target += 1;
      }
    } else {
      while (target > 0 && _isMarkdownPunctuation(current.text[target - 1])) {
        target -= 1;
      }
    }

    value = current.copyWith(
      selection: extendSelection
          ? TextSelection(
              baseOffset: currentSelection.baseOffset,
              extentOffset: target,
              affinity: currentSelection.affinity,
              isDirectional: true,
            )
          : TextSelection.collapsed(offset: target),
      composing: TextRange.empty,
    );
    return true;
  }

  void insertLink({String fallbackLabel = '', String destination = ''}) {
    final range = _normalizedSelection(value);
    final selected = text.substring(range.start, range.end);
    final label = selected.isEmpty ? fallbackLabel : selected;
    final replacement = '[$label]($destination)';
    final destinationStart = label.length + 3;
    replaceSelection(
      replacement,
      selectionStart: selected.isEmpty && label.isEmpty
          ? 1
          : destination.isEmpty
          ? destinationStart
          : 1,
      selectionEnd: selected.isEmpty && label.isEmpty
          ? 1
          : destination.isEmpty
          ? destinationStart
          : 1 + label.length,
    );
  }

  void insertCodeFence({String language = ''}) {
    final range = _normalizedSelection(value);
    final selected = text.substring(range.start, range.end);
    final body = selected.isEmpty ? '' : selected;
    final replacement = '```$language\n$body\n```';
    final bodyStart = language.length + 4;
    replaceSelection(
      replacement,
      selectionStart: bodyStart,
      selectionEnd: bodyStart + body.length,
    );
  }

  void _replaceRangeAndSelect(int start, int end, String replacement) {
    final updated = text.replaceRange(start, end, replacement);
    _performCommand(
      TextEditingValue(
        text: updated,
        selection: TextSelection(
          baseOffset: start,
          extentOffset: start + replacement.length,
        ),
      ),
    );
  }

  void _performCommand(TextEditingValue next) {
    _closeCoalescingGroup();
    value = next;
    _closeCoalescingGroup();
  }

  void _handleValueChanged() {
    final current = value;
    final previous = _lastObservedValue;
    _lastObservedValue = current;
    _setDirty(current.text != _savedText);
    if (current.text != previous.text) {
      _linkReferences = MarkdownLinkReferenceContext.parse(current.text);
    }
    if (_applyingHistory) return;

    if (current.text == previous.text) {
      if (current.selection != previous.selection) {
        _closeCoalescingGroup();
      }
      if (_history.isNotEmpty) _history[_historyIndex] = current;
      return;
    }

    if (_historyIndex + 1 < _history.length) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    final kind = _editKind(previous, current);
    final canCoalesce =
        _coalescingTimer?.isActive == true &&
        kind != _EditKind.replacement &&
        kind == _coalescingKind &&
        _historyIndex > 0;
    if (canCoalesce) {
      _history[_historyIndex] = current;
    } else {
      _history.add(current);
      _historyIndex = _history.length - 1;
    }
    _coalescingKind = kind;
    _coalescingTimer?.cancel();
    _coalescingTimer = Timer(historyCoalescingDuration, _closeCoalescingGroup);
    _updateHistoryState();
  }

  void _restoreHistoryValue(TextEditingValue restored) {
    _applyingHistory = true;
    try {
      value = restored.copyWith(composing: TextRange.empty);
      _lastObservedValue = value;
      _setDirty(text != _savedText);
    } finally {
      _applyingHistory = false;
    }
    _updateHistoryState();
  }

  void _closeCoalescingGroup() {
    _coalescingTimer?.cancel();
    _coalescingTimer = null;
    _coalescingKind = null;
  }

  void _updateHistoryState() {
    final next = IanvsMarkdownHistoryValue(canUndo: canUndo, canRedo: canRedo);
    final old = _historyState.value;
    if (old.canUndo == next.canUndo && old.canRedo == next.canRedo) return;
    _historyState.value = next;
  }

  void _setDirty(bool next) {
    if (_dirty.value != next) _dirty.value = next;
  }

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
    return buildMarkdownSourceTextSpan(
      value,
      style: style,
      syntaxTheme: syntax,
      withComposing: withComposing,
      linkReferenceLabels: _linkReferences.labels,
    );
  }

  @override
  void dispose() {
    removeListener(_handleValueChanged);
    _coalescingTimer?.cancel();
    _mode.dispose();
    _historyState.dispose();
    _dirty.dispose();
    super.dispose();
  }
}

final _markdownInlineWordPattern = RegExp(r'[\p{L}\p{N}_]+', unicode: true);

TextRange? _inlineWordRangeAtCaret(String source, int caret) {
  if (caret <= 0 || caret >= source.length) return null;
  for (final match in _markdownInlineWordPattern.allMatches(source)) {
    if (match.start >= caret) break;
    if (caret < match.end) {
      return TextRange(start: match.start, end: match.end);
    }
  }
  return null;
}

bool _isMarkdownPunctuation(String character) {
  return switch (character) {
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
    '\\' ||
    ']' ||
    '^' ||
    '`' ||
    '{' ||
    '|' ||
    '}' ||
    '~' => true,
    _ => false,
  };
}

/// Completes Markdown delimiter pairs and backtick fences, surrounds selected
/// text with Obsidian's Markdown-only delimiters, continues list and quote
/// prefixes when the user presses Enter, preserves marker-width continuation
/// indentation for Shift+Enter, snaps leading code and list marker indentation
/// Backspace to four-column tab stops, and keeps native word deletion aligned
/// with Obsidian punctuation boundaries.
///
/// An empty nested list item outdents once; an empty root item exits the list.
/// Composing IME input is never rewritten.
class IanvsMarkdownEditingFormatter extends TextInputFormatter {
  IanvsMarkdownEditingFormatter() {
    _markdownNewlineModifiers.ensureListening();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final smartUrlPaste = formatSmartUrlPasteEdit(oldValue, newValue);
    if (smartUrlPaste != null) return smartUrlPaste;

    final indentBackspace = _formatStructuralIndentBackspace(
      oldValue,
      newValue,
    );
    if (indentBackspace != null) return indentBackspace;

    final codeClosingIndent = _formatCodeClosingIndent(oldValue, newValue);
    if (codeClosingIndent != null) return codeClosingIndent;

    final narrowedDeletion = _narrowMarkdownPunctuationDeletion(
      oldValue,
      newValue,
    );
    if (narrowedDeletion != null) return narrowedDeletion;

    final pairedEdit = _formatPairingEdit(oldValue, newValue);
    if (pairedEdit != null) return pairedEdit;

    if (!oldValue.selection.isCollapsed ||
        !newValue.selection.isCollapsed ||
        newValue.text.length != oldValue.text.length + 1) {
      return newValue;
    }
    final caret = newValue.selection.extentOffset;
    final insertedAt = caret - 1;
    if (insertedAt < 0 || oldValue.selection.extentOffset != insertedAt) {
      return newValue;
    }

    if (newValue.text.codeUnitAt(insertedAt) == 0x60) {
      final completedFence = _completeBacktickFence(newValue, caret);
      if (completedFence != null) return completedFence;
    }
    if (newValue.text.codeUnitAt(insertedAt) != 0x0a) return newValue;
    final shiftPressed = _markdownNewlineModifiers.takeShiftForNewline();

    final lineStart = oldValue.text.lastIndexOf('\n', insertedAt - 1) + 1;
    final line = oldValue.text.substring(lineStart, insertedAt);
    // Fenced code owns its line semantics. Code that happens to start with a
    // Markdown marker (for example `- item`) must not continue as a list.
    final fencedCodeIndent = _codeIndentForNewline(
      oldValue.text,
      lineStart,
      insertedAt,
      fencedOnly: true,
    );
    if (fencedCodeIndent != null) {
      if (fencedCodeIndent.isEmpty) return newValue;
      final updated = newValue.text.replaceRange(
        caret,
        caret,
        fencedCodeIndent,
      );
      return TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(
          offset: caret + fencedCodeIndent.length,
        ),
      );
    }
    final continuation = _parseMarkdownContinuationLine(line);
    if (continuation == null) {
      final codeIndent = _codeIndentForNewline(
        oldValue.text,
        lineStart,
        insertedAt,
      );
      if (codeIndent == null || codeIndent.isEmpty) return newValue;
      final updated = newValue.text.replaceRange(caret, caret, codeIndent);
      return TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: caret + codeIndent.length),
      );
    }

    if (shiftPressed) {
      final continuationIndent = continuation.softPrefix;
      if (continuationIndent.isEmpty) return newValue;
      final updated = newValue.text.replaceRange(
        caret,
        caret,
        continuationIndent,
      );
      return TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(
          offset: caret + continuationIndent.length,
        ),
      );
    }

    final prefix = continuation.nextPrefix;

    if (continuation.content.trim().isEmpty) {
      final nextLineBreak = oldValue.text.indexOf('\n', insertedAt);
      final lineEnd = nextLineBreak < 0 ? oldValue.text.length : nextLineBreak;
      final trailingContent = oldValue.text.substring(insertedAt, lineEnd);
      if (trailingContent.trim().isNotEmpty) {
        return newValue;
      }
      final leaf = continuation.components.last;
      if (continuation.components.length > 1 && leaf.isQuote) {
        // Obsidian leaves an empty nested quote line intact and moves the
        // caret to a plain line.
        return newValue;
      }
      if (leaf.leadingIndent.isNotEmpty) {
        // An item indented after a quote container exits one indentation
        // level before its marker is removed. For example, `>     - ` first
        // becomes `> - `, then a second Enter becomes `> `.
        final outdented =
            '${continuation.parentPrefix}'
            '${_outdentOneLevel(leaf.leadingIndent)}${leaf.source}';
        final updated = newValue.text.replaceRange(lineStart, caret, outdented);
        final result = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(
            offset: lineStart + outdented.length,
          ),
        );
        return _renumberOutdentedOrderedEdit(result, lineStart: lineStart);
      }
      if (continuation.components.length > 1) {
        // Empty inner lists without their own structural indentation exit
        // their container marker in one step.
        final outdented = continuation.outerPrefix;
        final updated = newValue.text.replaceRange(lineStart, caret, outdented);
        final result = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(
            offset: lineStart + outdented.length,
          ),
        );
        return _renumberOutdentedOrderedEdit(result, lineStart: lineStart);
      }
      if (continuation.indent.isNotEmpty) {
        final currentMarker = continuation.components.single.source;
        final outdented =
            '${_outdentOneLevel(continuation.indent)}$currentMarker';
        final updated = newValue.text.replaceRange(lineStart, caret, outdented);
        final result = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(
            offset: lineStart + outdented.length,
          ),
        );
        return _renumberOutdentedOrderedEdit(result, lineStart: lineStart);
      }
      final hasFollowingLine = nextLineBreak >= 0;
      final preserveTrailingEmptyLine = leaf.isQuote && !hasFollowingLine;
      final updated = newValue.text.replaceRange(
        lineStart,
        hasFollowingLine || !preserveTrailingEmptyLine ? caret : insertedAt,
        '',
      );
      // At EOF Obsidian removes an empty list/task/ordered item together with
      // the newly inserted newline, leaving only the separator before it. A
      // root quote is different: exiting `> ` keeps one empty paragraph.
      final offset = hasFollowingLine || !preserveTrailingEmptyLine
          ? lineStart
          : caret - line.length;
      final result = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: offset),
      );
      final removedMarker = _parseMarkdownOrderedMarker(line);
      if (removedMarker == null || !hasFollowingLine) return result;

      final followingOffset = (lineStart + 1).clamp(0, updated.length);
      final followingStart = _sourceLineStart(updated, followingOffset);
      return _renumberOrderedEdit(
        result,
        touchedLineStarts: {followingStart},
        contextSeeds: {removedMarker.contextKey: removedMarker.number},
        affectedOffset: followingStart,
      );
    }

    final updated = newValue.text.replaceRange(caret, caret, prefix);
    final result = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: caret + prefix.length),
    );
    if (_parseMarkdownOrderedMarker(prefix) == null) return result;
    return _renumberOrderedEdit(
      result,
      touchedLineStarts: {_sourceLineStart(updated, caret)},
    );
  }

  TextEditingValue _renumberOutdentedOrderedEdit(
    TextEditingValue value, {
    required int lineStart,
  }) {
    final lineEnd = value.text.indexOf('\n', lineStart);
    final currentLine = value.text.substring(
      lineStart,
      lineEnd < 0 ? value.text.length : lineEnd,
    );
    final outdentedMarker = _parseMarkdownOrderedMarker(currentLine);
    if (outdentedMarker == null) return value;

    final touchedLineStarts = <int>{lineStart};
    final movedLineStarts = <int>{};
    if (lineEnd >= 0 && lineEnd + 1 < value.text.length) {
      final followingStart = lineEnd + 1;
      final followingEnd = value.text.indexOf('\n', followingStart);
      final followingLine = value.text.substring(
        followingStart,
        followingEnd < 0 ? value.text.length : followingEnd,
      );
      final followingMarker = _parseMarkdownOrderedMarker(followingLine);
      if (followingMarker != null &&
          followingMarker.quotePrefix == outdentedMarker.quotePrefix &&
          followingMarker.indentColumns > outdentedMarker.indentColumns) {
        touchedLineStarts.add(followingStart);
        movedLineStarts.add(followingStart);
      }
    }
    return _renumberOrderedEdit(
      value,
      touchedLineStarts: touchedLineStarts,
      movedLineStarts: movedLineStarts,
      preservedLineStarts: {lineStart},
    );
  }

  TextEditingValue _renumberOrderedEdit(
    TextEditingValue value, {
    required Set<int> touchedLineStarts,
    Set<int> movedLineStarts = const {},
    Set<int> preservedLineStarts = const {},
    Map<String, int> contextSeeds = const {},
    int? affectedOffset,
  }) {
    final renumbered = _renumberOrderedLists(
      value.text,
      touchedLineStarts: touchedLineStarts,
      movedLineStarts: movedLineStarts,
      preservedLineStarts: preservedLineStarts,
      contextSeeds: contextSeeds,
      affectedOffset: affectedOffset,
    );
    if (renumbered.edits.isEmpty) return value;

    final selection = value.selection;
    return value.copyWith(
      text: renumbered.text,
      selection: TextSelection(
        baseOffset: _mapOffsetThroughMarkdownEdits(
          selection.baseOffset,
          renumbered.edits,
        ),
        extentOffset: _mapOffsetThroughMarkdownEdits(
          selection.extentOffset,
          renumbered.edits,
        ),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
    );
  }

  /// Normalizes ordered-list markers in blocks containing [touchedLineStarts].
  ///
  /// Live preview uses this after a block-local Enter edit is merged back into
  /// the full document, where following list siblings become visible again.
  TextEditingValue renumberOrderedLists(
    TextEditingValue value, {
    required Set<int> touchedLineStarts,
  }) => _renumberOrderedEdit(value, touchedLineStarts: touchedLineStarts);

  /// Normalizes the document after an empty ordered item outdents in a
  /// block-local editor.
  TextEditingValue renumberOutdentedOrderedList(
    TextEditingValue value, {
    required int lineStart,
  }) => _renumberOutdentedOrderedEdit(value, lineStart: lineStart);

  /// Continues the removed marker's sequence at [followingLineStart].
  TextEditingValue renumberAfterRemovedOrderedListItem(
    TextEditingValue value, {
    required String removedLine,
    required int followingLineStart,
  }) {
    final marker = _parseMarkdownOrderedMarker(removedLine);
    if (marker == null) return value;
    return _renumberOrderedEdit(
      value,
      touchedLineStarts: {followingLineStart},
      contextSeeds: {marker.contextKey: marker.number},
      affectedOffset: followingLineStart,
    );
  }

  TextEditingValue? _formatStructuralIndentBackspace(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isValid ||
        !oldValue.selection.isCollapsed ||
        !newValue.selection.isValid ||
        !newValue.selection.isCollapsed ||
        oldValue.text.length != newValue.text.length + 1) {
      return null;
    }

    final oldCaret = oldValue.selection.extentOffset;
    final newCaret = newValue.selection.extentOffset;
    if (oldCaret <= 0 ||
        newCaret != oldCaret - 1 ||
        newValue.text !=
            oldValue.text.replaceRange(oldCaret - 1, oldCaret, '')) {
      return null;
    }

    final lineStart = oldValue.text.lastIndexOf('\n', oldCaret - 1) + 1;
    if (lineStart == oldCaret) return null;
    final leading = oldValue.text.substring(lineStart, oldCaret);
    final lineBreak = oldValue.text.indexOf('\n', oldCaret);
    final lineEnd = lineBreak < 0 ? oldValue.text.length : lineBreak;
    final afterCaret = oldValue.text.substring(oldCaret, lineEnd);
    final startsListMarker = RegExp(
      r'^(?:[-+*] (?:\[[ xX]\] )?|\d{1,9}[.)] )',
    ).hasMatch(afterCaret);
    final isCodeContent = _isCodeContentCaret(
      oldValue.text,
      lineStart,
      oldCaret,
    );
    if (leading.codeUnits.any((codeUnit) => codeUnit != 0x20) ||
        (!isCodeContent && !startsListMarker)) {
      return null;
    }

    final indentation = oldCaret - lineStart;
    final removed = indentation % 4 == 0 ? 4 : indentation % 4;
    if (removed <= 1) return null;
    final target = oldCaret - removed;
    final result = TextEditingValue(
      text: oldValue.text.replaceRange(target, oldCaret, ''),
      selection: TextSelection.collapsed(offset: target),
    );
    if (isCodeContent ||
        _parseMarkdownOrderedMarker(
              oldValue.text.substring(lineStart, lineEnd),
            ) ==
            null) {
      return result;
    }
    return _renumberOrderedEdit(
      result,
      touchedLineStarts: {lineStart},
      movedLineStarts: {lineStart},
    );
  }

  String _outdentOneLevel(String indent) {
    if (indent.endsWith('\t')) {
      return indent.substring(0, indent.length - 1);
    }
    var removableSpaces = 0;
    for (
      var index = indent.length - 1;
      index >= 0 && removableSpaces < 4 && indent.codeUnitAt(index) == 0x20;
      index -= 1
    ) {
      removableSpaces += 1;
    }
    if (removableSpaces > 0) {
      return indent.substring(0, indent.length - removableSpaces);
    }
    return indent.substring(0, indent.length - 1);
  }

  TextEditingValue? _formatCodeClosingIndent(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isValid ||
        !oldValue.selection.isCollapsed ||
        !newValue.selection.isValid ||
        !newValue.selection.isCollapsed ||
        newValue.text.length != oldValue.text.length + 1) {
      return null;
    }

    final oldCaret = oldValue.selection.extentOffset;
    final newCaret = newValue.selection.extentOffset;
    if (oldCaret < 0 ||
        newCaret != oldCaret + 1 ||
        oldCaret > oldValue.text.length) {
      return null;
    }
    final inserted = newValue.text.substring(oldCaret, oldCaret + 1);
    if (!_electricCodeClosers.contains(inserted) ||
        newValue.text !=
            oldValue.text.replaceRange(oldCaret, oldCaret, inserted)) {
      return null;
    }

    final lineStart = oldValue.text.lastIndexOf('\n', oldCaret - 1) + 1;
    final indentation = oldValue.text.substring(lineStart, oldCaret);
    if (indentation.isEmpty ||
        indentation.codeUnits.any(
          (codeUnit) => codeUnit != 0x20 && codeUnit != 0x09,
        )) {
      return null;
    }
    final codeBlock = _codeContentBlockAtCaret(
      oldValue.text,
      lineStart,
      oldCaret,
    );
    if (codeBlock == null || !_usesElectricCodeIndent(codeBlock)) return null;

    final outdented = _outdentOneLevel(indentation);
    final removed = indentation.length - outdented.length;
    if (removed <= 0) return null;

    // When native editing inserts a closer over an auto-completed mate, keep
    // the existing closer while still applying CodeMirror-style outdent.
    if (oldCaret < oldValue.text.length &&
        oldValue.text.substring(oldCaret, oldCaret + 1) == inserted) {
      return TextEditingValue(
        text: oldValue.text.replaceRange(lineStart, oldCaret, outdented),
        selection: TextSelection.collapsed(
          offset: lineStart + outdented.length + 1,
        ),
      );
    }

    return TextEditingValue(
      text: newValue.text.replaceRange(lineStart, oldCaret, outdented),
      selection: TextSelection.collapsed(offset: newCaret - removed),
    );
  }

  TextEditingValue? _formatPairingEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isValid || !newValue.selection.isValid) {
      return null;
    }

    final oldSelection = oldValue.selection;
    final newSelection = newValue.selection;
    if (!oldSelection.isCollapsed) {
      if (!newSelection.isCollapsed) return null;
      final start = oldSelection.start;
      final end = oldSelection.end;
      final selected = oldValue.text.substring(start, end);
      if (newSelection.extentOffset != start + 1 ||
          newValue.text.length != oldValue.text.length - selected.length + 1) {
        return null;
      }
      final opener = newValue.text.substring(start, start + 1);
      final closer =
          _markdownPairClosers[opener] ??
          (_markdownSurroundOnlyCharacters.contains(opener) ? opener : null);
      if (closer == null ||
          newValue.text != oldValue.text.replaceRange(start, end, opener)) {
        return null;
      }
      final updated = oldValue.text.replaceRange(
        start,
        end,
        '$opener$selected$closer',
      );
      final forward = oldSelection.baseOffset <= oldSelection.extentOffset;
      return TextEditingValue(
        text: updated,
        selection: TextSelection(
          baseOffset: forward ? start + 1 : end + 1,
          extentOffset: forward ? end + 1 : start + 1,
          isDirectional: oldSelection.isDirectional,
        ),
      );
    }

    if (!newSelection.isCollapsed) return null;
    final oldCaret = oldSelection.extentOffset;
    final newCaret = newSelection.extentOffset;

    // Native Backspace removes only the opening character. Obsidian removes
    // the untouched closing mate in the same edit when the caret is between
    // an empty auto-completed pair.
    if (oldValue.text.length == newValue.text.length + 1 &&
        newCaret == oldCaret - 1 &&
        oldCaret > 0 &&
        oldCaret < oldValue.text.length &&
        newValue.text ==
            oldValue.text.replaceRange(oldCaret - 1, oldCaret, '')) {
      final opener = oldValue.text.substring(oldCaret - 1, oldCaret);
      final closer = oldValue.text.substring(oldCaret, oldCaret + 1);
      if (_markdownPairClosers[opener] == closer) {
        return TextEditingValue(
          text: oldValue.text.replaceRange(oldCaret - 1, oldCaret + 1, ''),
          selection: TextSelection.collapsed(offset: oldCaret - 1),
        );
      }
      return null;
    }

    if (newValue.text.length != oldValue.text.length + 1 ||
        newCaret != oldCaret + 1 ||
        oldCaret < 0 ||
        oldCaret > oldValue.text.length) {
      return null;
    }
    final inserted = newValue.text.substring(oldCaret, oldCaret + 1);
    if (newValue.text !=
        oldValue.text.replaceRange(oldCaret, oldCaret, inserted)) {
      return null;
    }

    if (inserted == '`') {
      final completedFence = _completeBacktickFence(newValue, newCaret);
      if (completedFence != null) return completedFence;
    }

    // Typing an auto-inserted closer advances over it without duplicating it.
    if (_markdownPairClosers.containsValue(inserted) &&
        oldCaret < oldValue.text.length &&
        oldValue.text.substring(oldCaret, oldCaret + 1) == inserted) {
      return TextEditingValue(
        text: oldValue.text,
        selection: TextSelection.collapsed(offset: oldCaret + 1),
      );
    }

    final closer = _markdownPairClosers[inserted];
    if (closer == null) return null;
    if ((inserted == '`' || inserted == '*' || inserted == '_') &&
        oldCaret > 0 &&
        oldValue.text.substring(oldCaret - 1, oldCaret) == inserted) {
      return null;
    }
    // Obsidian completes opening brackets before blank space or its small
    // close-before set. Other words and punctuation keep the opener literal.
    if ((inserted == '[' || inserted == '(' || inserted == '{') &&
        !_shouldAutoCloseBracket(oldValue.text, oldCaret)) {
      return null;
    }
    // Obsidian leaves symmetric inline delimiters single beside word
    // characters. A run of backticks can still reach three and become a
    // fenced block via the completion check above; only the first inline mate
    // is contextual.
    if ((inserted == '`' ||
            inserted == '*' ||
            inserted == '_' ||
            inserted == '"' ||
            inserted == "'") &&
        !_shouldAutoCloseQuoteLikeDelimiter(oldValue.text, oldCaret)) {
      return null;
    }

    return TextEditingValue(
      text: newValue.text.replaceRange(newCaret, newCaret, closer),
      selection: TextSelection.collapsed(offset: newCaret),
    );
  }

  TextEditingValue? _completeBacktickFence(TextEditingValue value, int caret) {
    if (caret < 3 || value.text.substring(caret - 3, caret) != '```') {
      return null;
    }
    // The third backtick opens the pair. A fourth (or later) backtick only
    // lengthens the opening marker, matching Obsidian's one-shot completion.
    if (caret >= 4 && value.text.codeUnitAt(caret - 4) == 0x60) return null;

    final fenceStart = caret - 3;
    if (_closesExistingFencedBlock(value.text, fenceStart, caret)) {
      return null;
    }
    final lineStart = fenceStart == 0
        ? 0
        : value.text.lastIndexOf('\n', fenceStart - 1) + 1;
    final beforeFence = value.text.substring(lineStart, fenceStart);
    final closingPrefix = _backtickFenceClosingPrefix(beforeFence);
    final updated = value.text.replaceRange(
      caret,
      caret,
      '\n$closingPrefix```',
    );
    return TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  bool _closesExistingFencedBlock(String text, int fenceStart, int caret) {
    // Inspect the source immediately before the third backtick. If that
    // position was already inside fenced code, the new run closes that block
    // and must not grow another automatic pair below it.
    final beforeThird = text.replaceRange(caret - 1, caret, '');
    for (final block in parseMarkdownBlocks(beforeThird)) {
      if (block.type != IanvsMarkdownBlockType.fencedCode ||
          fenceStart <= block.start ||
          fenceStart >= block.end) {
        continue;
      }
      final openingLineEnd = beforeThird.indexOf('\n', block.start);
      if (openingLineEnd >= 0 && fenceStart > openingLineEnd) return true;
    }
    return false;
  }

  TextEditingValue? _narrowMarkdownPunctuationDeletion(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isValid ||
        !oldValue.selection.isCollapsed ||
        !newValue.selection.isValid ||
        !newValue.selection.isCollapsed) {
      return null;
    }

    final removedLength = oldValue.text.length - newValue.text.length;
    if (removedLength <= 1) return null;
    final oldCaret = oldValue.selection.extentOffset;
    final newCaret = newValue.selection.extentOffset;
    final forward = newCaret == oldCaret;
    final backward =
        newCaret < oldCaret && oldCaret - newCaret == removedLength;
    if (!forward && !backward) return null;

    final start = forward ? oldCaret : newCaret;
    final end = forward ? oldCaret + removedLength : oldCaret;
    if (start < 0 || end > oldValue.text.length) return null;
    if (oldValue.text.replaceRange(start, end, '') != newValue.text) {
      return null;
    }

    if (forward) {
      if (start >= oldValue.text.length ||
          !_isMarkdownPunctuation(oldValue.text[start])) {
        return null;
      }
      var punctuationEnd = start;
      while (punctuationEnd < oldValue.text.length &&
          _isMarkdownPunctuation(oldValue.text[punctuationEnd])) {
        punctuationEnd += 1;
      }
      if (punctuationEnd >= end) return null;
      return TextEditingValue(
        text: oldValue.text.replaceRange(start, punctuationEnd, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }

    if (end == 0 || !_isMarkdownPunctuation(oldValue.text[end - 1])) {
      return null;
    }
    var punctuationStart = end;
    while (punctuationStart > 0 &&
        _isMarkdownPunctuation(oldValue.text[punctuationStart - 1])) {
      punctuationStart -= 1;
    }
    if (punctuationStart <= start) return null;
    return TextEditingValue(
      text: oldValue.text.replaceRange(punctuationStart, end, ''),
      selection: TextSelection.collapsed(offset: punctuationStart),
    );
  }
}

const _markdownPairClosers = <String, String>{
  '[': ']',
  '(': ')',
  '{': '}',
  '`': '`',
  '*': '*',
  '_': '_',
  '"': '"',
  "'": "'",
};

const _markdownSurroundOnlyCharacters = <String>{'=', '~', r'$', '%'};

const _markdownBracketCloseBefore = <String>{
  ')',
  ']',
  '}',
  "'",
  '"',
  ':',
  ';',
  '>',
};

bool _shouldAutoCloseBracket(String text, int caret) {
  if (caret >= text.length) return true;
  final next = text[caret];
  return next.trim().isEmpty || _markdownBracketCloseBefore.contains(next);
}

bool _shouldAutoCloseQuoteLikeDelimiter(String text, int caret) {
  if (caret > 0 && _isPairingWordCharacter(text[caret - 1])) return false;
  if (caret < text.length && _isPairingWordCharacter(text[caret])) return false;
  return caret == 0 || text[caret - 1] != '\\';
}

bool _isPairingWordCharacter(String character) {
  final unit = character.codeUnitAt(0);
  return unit >= 0x80 ||
      unit >= 0x30 && unit <= 0x39 ||
      unit >= 0x41 && unit <= 0x5a ||
      unit == 0x5f ||
      unit >= 0x61 && unit <= 0x7a;
}

class _MarkdownContinuationLine {
  const _MarkdownContinuationLine({
    required this.indent,
    required this.components,
    required this.content,
  });

  final String indent;
  final List<_MarkdownPrefixComponent> components;
  final String content;

  String get parentPrefix {
    final buffer = StringBuffer(indent);
    for (final component in components.take(components.length - 1)) {
      buffer.write(component.containerPrefix);
    }
    return buffer.toString();
  }

  String get outerPrefix => '$parentPrefix${components.last.leadingIndent}';

  String get nextPrefix => '$outerPrefix${components.last.continuation}';

  String get softPrefix =>
      '$outerPrefix${_markdownPrefixSpaces(components.last.source.length)}';
}

class _MarkdownPrefixComponent {
  const _MarkdownPrefixComponent({
    this.leadingIndent = '',
    required this.source,
    required this.continuation,
    required this.isQuote,
  });

  final String leadingIndent;
  final String source;
  final String continuation;
  final bool isQuote;

  String get containerPrefix =>
      '$leadingIndent'
      '${isQuote ? source : _markdownPrefixSpaces(source.length)}';
}

_MarkdownContinuationLine? _parseMarkdownContinuationLine(String line) {
  final indent = RegExp(r'^[ \t]*').firstMatch(line)!.group(0)!;
  var offset = indent.length;
  final components = <_MarkdownPrefixComponent>[];

  while (offset < line.length) {
    var componentOffset = offset;
    var leadingIndent = '';
    if (components.isNotEmpty) {
      leadingIndent = RegExp(
        r'^[ \t]*',
      ).firstMatch(line.substring(componentOffset))!.group(0)!;
      componentOffset += leadingIndent.length;
    }
    final remaining = line.substring(componentOffset);
    final quote = RegExp(r'^> ').firstMatch(remaining);
    if (quote != null) {
      const marker = '> ';
      components.add(
        _MarkdownPrefixComponent(
          leadingIndent: leadingIndent,
          source: marker,
          continuation: marker,
          isQuote: true,
        ),
      );
      offset = componentOffset + marker.length;
      continue;
    }

    final unordered = RegExp(r'^([-+*] )(\[[ xX]\] )?').firstMatch(remaining);
    if (unordered != null) {
      final marker = unordered.group(1)!;
      final task = unordered.group(2);
      final source = unordered.group(0)!;
      components.add(
        _MarkdownPrefixComponent(
          leadingIndent: leadingIndent,
          source: source,
          continuation: task == null ? marker : '$marker[ ] ',
          isQuote: false,
        ),
      );
      offset = componentOffset + source.length;
      continue;
    }

    final ordered = RegExp(r'^(\d{1,9})([.)] )').firstMatch(remaining);
    if (ordered != null) {
      final source = ordered.group(0)!;
      final number = int.parse(ordered.group(1)!);
      components.add(
        _MarkdownPrefixComponent(
          leadingIndent: leadingIndent,
          source: source,
          continuation: '${number + 1}${ordered.group(2)}',
          isQuote: false,
        ),
      );
      offset = componentOffset + source.length;
      continue;
    }
    break;
  }

  if (components.isEmpty) return null;
  return _MarkdownContinuationLine(
    indent: indent,
    components: components,
    content: line.substring(offset),
  );
}

String _markdownPrefixSpaces(int length) =>
    List<String>.filled(length, ' ').join();

final _markdownNewlineModifiers = _MarkdownNewlineModifierTracker();

class _MarkdownNewlineModifierTracker {
  bool _listening = false;
  bool _shiftForNewline = false;

  void ensureListening() {
    if (_listening) return;
    _listening = true;
    // Raw events retain the modifier flags attached to the exact Enter event,
    // while global pressed-key snapshots can remain stale after accessibility
    // or IME-generated key sequences.
    // ignore: deprecated_member_use
    RawKeyboard.instance.addListener(_handleRawKey);
  }

  // ignore: deprecated_member_use
  void _handleRawKey(RawKeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return;
    }
    // ignore: deprecated_member_use
    if (event is RawKeyDownEvent) {
      // ignore: deprecated_member_use
      _shiftForNewline = event.isShiftPressed;
      return;
    }
    // ignore: deprecated_member_use
    if (event is RawKeyUpEvent) {
      _shiftForNewline = false;
    }
  }

  bool takeShiftForNewline() {
    final value = _shiftForNewline;
    _shiftForNewline = false;
    return value;
  }
}

int _markdownStructuralIndentOffset(String line) {
  var offset = 0;
  while (line.startsWith('> ', offset) || line.startsWith('>\t', offset)) {
    offset += 2;
  }
  return offset;
}

int _leadingIndentRemoval(String line, int maximumSpaces) {
  if (line.startsWith('\t')) return 1;
  var removed = 0;
  while (removed < line.length &&
      removed < maximumSpaces &&
      line.codeUnitAt(removed) == 0x20) {
    removed += 1;
  }
  return removed;
}

class _MarkdownRenumbering {
  const _MarkdownRenumbering({required this.text, required this.edits});

  final String text;
  final List<({int offset, int removed, int inserted})> edits;
}

class _MarkdownOrderedMarker {
  const _MarkdownOrderedMarker({
    required this.quotePrefix,
    required this.indentColumns,
    required this.numberOffset,
    required this.numberLength,
    required this.number,
  });

  final String quotePrefix;
  final int indentColumns;
  final int numberOffset;
  final int numberLength;
  final int number;

  // Obsidian treats `1.` and `2)` as one sequence when they share the same
  // quote container and indentation level. The delimiter is presentation,
  // rather than part of the ordered-list numbering context.
  String get contextKey => '$quotePrefix\u0000$indentColumns';
}

class _MarkdownOrderedSequence {
  const _MarkdownOrderedSequence({required this.next});

  final int next;
}

_MarkdownRenumbering _renumberOrderedLists(
  String source, {
  required Set<int> touchedLineStarts,
  Set<int> movedLineStarts = const {},
  Set<int> preservedLineStarts = const {},
  Map<String, int> contextSeeds = const {},
  int? affectedOffset,
}) {
  if (touchedLineStarts.isEmpty) {
    return _MarkdownRenumbering(text: source, edits: const []);
  }

  final lines =
      <
        ({
          int start,
          String text,
          bool touched,
          bool moved,
          bool preserved,
          bool fenced,
        })
      >[];
  var lineStart = 0;
  String? activeFenceCharacter;
  var activeFenceLength = 0;
  while (lineStart <= source.length) {
    final lineBreak = source.indexOf('\n', lineStart);
    final lineEnd = lineBreak < 0 ? source.length : lineBreak;
    final lineText = source.substring(lineStart, lineEnd);
    final fence = _parseMarkdownFence(lineText);
    final fenced = activeFenceCharacter != null || fence != null;
    lines.add((
      start: lineStart,
      text: lineText,
      touched: touchedLineStarts.contains(lineStart),
      moved: movedLineStarts.contains(lineStart),
      preserved: preservedLineStarts.contains(lineStart),
      fenced: fenced,
    ));
    if (activeFenceCharacter == null && fence != null) {
      activeFenceCharacter = fence.character;
      activeFenceLength = fence.length;
    } else if (activeFenceCharacter != null &&
        fence?.character == activeFenceCharacter &&
        fence!.length >= activeFenceLength &&
        fence.trailing.trim().isEmpty) {
      activeFenceCharacter = null;
      activeFenceLength = 0;
    }
    if (lineBreak < 0) break;
    lineStart = lineBreak + 1;
  }

  final replacements = <({int offset, int removed, String text})>[];
  var blockStart = 0;
  while (blockStart < lines.length) {
    while (blockStart < lines.length && lines[blockStart].text.trim().isEmpty) {
      blockStart += 1;
    }
    if (blockStart >= lines.length) break;
    var blockEnd = blockStart + 1;
    while (blockEnd < lines.length && lines[blockEnd].text.trim().isNotEmpty) {
      blockEnd += 1;
    }
    final block = lines.sublist(blockStart, blockEnd);
    if (block.any((line) => line.touched && !line.fenced)) {
      final sequences = <String, _MarkdownOrderedSequence>{};
      final remainingSeeds = Map<String, int>.of(contextSeeds);
      for (final line in block) {
        if (line.fenced) {
          sequences.clear();
          continue;
        }
        final marker = _parseMarkdownOrderedMarker(line.text);
        if (marker == null) {
          _resetOrderedSequencesForNonOrderedLine(sequences, line.text);
          continue;
        }
        sequences.removeWhere((key, _) {
          final parts = key.split('\u0000');
          if (parts.length < 2 || parts.first != marker.quotePrefix) {
            return false;
          }
          return int.parse(parts[1]) > marker.indentColumns;
        });
        final existing = sequences[marker.contextKey];
        int? seeded;
        if (affectedOffset != null && line.start >= affectedOffset) {
          if (existing == null) {
            seeded = remainingSeeds.remove(marker.contextKey);
          } else {
            remainingSeeds.remove(marker.contextKey);
          }
        }
        final expected = line.preserved
            ? marker.number
            : existing?.next ?? seeded ?? (line.moved ? 1 : marker.number);
        if (marker.number != expected) {
          replacements.add((
            offset: line.start + marker.numberOffset,
            removed: marker.numberLength,
            text: '$expected',
          ));
        }
        sequences[marker.contextKey] = _MarkdownOrderedSequence(
          next: expected + 1,
        );
      }
    }
    blockStart = blockEnd + 1;
  }

  var updated = source;
  for (final replacement in replacements.reversed) {
    updated = updated.replaceRange(
      replacement.offset,
      replacement.offset + replacement.removed,
      replacement.text,
    );
  }

  return _MarkdownRenumbering(
    text: updated,
    edits: replacements
        .map(
          (replacement) => (
            offset: replacement.offset,
            removed: replacement.removed,
            inserted: replacement.text.length,
          ),
        )
        .toList(growable: false),
  );
}

int _mapOffsetThroughMarkdownEdits(
  int offset,
  List<({int offset, int removed, int inserted})> edits,
) {
  var delta = 0;
  for (final edit in edits) {
    if (offset <= edit.offset) break;
    if (offset <= edit.offset + edit.removed) {
      return edit.offset + delta + edit.inserted;
    }
    delta += edit.inserted - edit.removed;
  }
  return offset + delta;
}

({String character, int length, String trailing})? _parseMarkdownFence(
  String line,
) {
  var offset = 0;
  while (offset + 1 < line.length &&
      line.codeUnitAt(offset) == 0x3e &&
      (line.codeUnitAt(offset + 1) == 0x20 ||
          line.codeUnitAt(offset + 1) == 0x09)) {
    offset += 2;
  }
  while (offset < line.length &&
      (line.codeUnitAt(offset) == 0x20 || line.codeUnitAt(offset) == 0x09)) {
    offset += 1;
  }
  if (offset >= line.length) return null;
  final character = line[offset];
  if (character != '`' && character != '~') return null;
  var end = offset;
  while (end < line.length && line[end] == character) {
    end += 1;
  }
  final length = end - offset;
  if (length < 3) return null;
  return (character: character, length: length, trailing: line.substring(end));
}

_MarkdownOrderedMarker? _parseMarkdownOrderedMarker(String line) {
  var offset = 0;
  var quotePrefix = '';
  while (offset + 1 < line.length &&
      line.codeUnitAt(offset) == 0x3e &&
      (line.codeUnitAt(offset + 1) == 0x20 ||
          line.codeUnitAt(offset + 1) == 0x09)) {
    quotePrefix += line.substring(offset, offset + 2);
    offset += 2;
  }

  var indentColumns = 0;
  while (offset < line.length) {
    final codeUnit = line.codeUnitAt(offset);
    if (codeUnit == 0x20) {
      indentColumns += 1;
    } else if (codeUnit == 0x09) {
      indentColumns += 4 - indentColumns % 4;
    } else {
      break;
    }
    offset += 1;
  }

  final match = RegExp(
    r'^(\d{1,9})([.)])[ \t]+',
  ).firstMatch(line.substring(offset));
  if (match == null) return null;
  final numberSource = match.group(1)!;
  return _MarkdownOrderedMarker(
    quotePrefix: quotePrefix,
    indentColumns: indentColumns,
    numberOffset: offset,
    numberLength: numberSource.length,
    number: int.parse(numberSource),
  );
}

void _resetOrderedSequencesForNonOrderedLine(
  Map<String, _MarkdownOrderedSequence> sequences,
  String line,
) {
  if (sequences.isEmpty) return;
  final container = _markdownContainerIndent(line);
  sequences.removeWhere((key, _) {
    final parts = key.split('\u0000');
    if (parts.length < 2 || parts.first != container.quotePrefix) return false;
    return int.parse(parts[1]) >= container.indentColumns;
  });
}

({String quotePrefix, int indentColumns}) _markdownContainerIndent(
  String line,
) {
  var offset = 0;
  var quotePrefix = '';
  while (offset + 1 < line.length &&
      line.codeUnitAt(offset) == 0x3e &&
      (line.codeUnitAt(offset + 1) == 0x20 ||
          line.codeUnitAt(offset + 1) == 0x09)) {
    quotePrefix += line.substring(offset, offset + 2);
    offset += 2;
  }
  var indentColumns = 0;
  while (offset < line.length) {
    final codeUnit = line.codeUnitAt(offset);
    if (codeUnit == 0x20) {
      indentColumns += 1;
    } else if (codeUnit == 0x09) {
      indentColumns += 4 - indentColumns % 4;
    } else {
      break;
    }
    offset += 1;
  }
  return (quotePrefix: quotePrefix, indentColumns: indentColumns);
}

String _backtickFenceClosingPrefix(String beforeFence) {
  final leadingWhitespace = RegExp(
    r'^[ \t]*',
  ).firstMatch(beforeFence)!.group(0)!;
  var offset = leadingWhitespace.length;
  var prefix = leadingWhitespace;
  var foundMarkdownPrefix = false;

  while (offset < beforeFence.length) {
    final remaining = beforeFence.substring(offset);
    final quote = RegExp(r'^>[ \t]?').firstMatch(remaining);
    if (quote != null) {
      final marker = quote.group(0)!;
      prefix += marker;
      offset += marker.length;
      foundMarkdownPrefix = true;
      continue;
    }

    final list = RegExp(
      r'^(?:[-+*][ \t]+(?:\[[ xX]\][ \t]+)?|\d{1,9}[.)][ \t]+)',
    ).firstMatch(remaining);
    if (list != null) {
      final marker = list.group(0)!;
      prefix += ' ' * marker.length;
      offset += marker.length;
      foundMarkdownPrefix = true;
      continue;
    }
    break;
  }

  return foundMarkdownPrefix && offset == beforeFence.length
      ? prefix
      : leadingWhitespace;
}

String? _codeIndentForNewline(
  String source,
  int lineStart,
  int caret, {
  bool fencedOnly = false,
}) {
  final codeBlock = _codeContentBlockAtCaret(source, lineStart, caret);
  if (codeBlock == null ||
      (fencedOnly && codeBlock.type != IanvsMarkdownBlockType.fencedCode)) {
    return null;
  }

  final lineBreak = source.indexOf('\n', caret);
  final lineEnd = lineBreak < 0 ? source.length : lineBreak;
  final line = source.substring(lineStart, lineEnd);
  if (codeBlock.type == IanvsMarkdownBlockType.fencedCode &&
      lineStart > codeBlock.start &&
      _isClosingFenceLine(codeBlock.source, line)) {
    return null;
  }
  final beforeCaret = source.substring(lineStart, caret);
  final leading = RegExp(r'^[ \t]*').firstMatch(beforeCaret)!.group(0)!;
  final trimmedBeforeCaret = beforeCaret.trimRight();
  if (_usesElectricCodeIndent(codeBlock) &&
      trimmedBeforeCaret.isNotEmpty &&
      _electricCodeOpeners.contains(
        trimmedBeforeCaret[trimmedBeforeCaret.length - 1],
      )) {
    return '$leading    ';
  }
  return leading;
}

bool _isCodeContentCaret(String source, int lineStart, int caret) {
  return _codeContentBlockAtCaret(source, lineStart, caret) != null;
}

IanvsMarkdownBlock? _codeContentBlockAtCaret(
  String source,
  int lineStart,
  int caret,
) {
  for (final block in parseMarkdownBlocks(source)) {
    final isCode =
        block.type == IanvsMarkdownBlockType.fencedCode ||
        block.type == IanvsMarkdownBlockType.indentedCode;
    if (!isCode || caret < block.start || caret > block.end) continue;

    if (block.type != IanvsMarkdownBlockType.fencedCode) return block;
    final openingLineEnd = source.indexOf('\n', block.start);
    if (openingLineEnd < 0 || lineStart <= openingLineEnd) return null;
    final lineBreak = source.indexOf('\n', caret);
    final lineEnd = lineBreak < 0 ? source.length : lineBreak;
    final line = source.substring(lineStart, lineEnd);
    return _isClosingFenceLine(block.source, line) ? null : block;
  }
  return null;
}

bool _usesElectricCodeIndent(IanvsMarkdownBlock block) {
  if (block.type != IanvsMarkdownBlockType.fencedCode) return false;
  final openingLineBreak = block.source.indexOf('\n');
  final openingLine = openingLineBreak < 0
      ? block.source
      : block.source.substring(0, openingLineBreak);
  final match = RegExp(
    r'^ {0,3}(?:`{3,}|~{3,})[ \t]*([^\s`~]+)?',
  ).firstMatch(openingLine);
  final language = match?.group(1)?.toLowerCase();
  return language != null && _electricCodeLanguages.contains(language);
}

const _electricCodeOpeners = <String>{'{', '[', '('};
const _electricCodeClosers = <String>{'}', ']', ')'};
const _electricCodeLanguages = <String>{
  'c',
  'c++',
  'cc',
  'cpp',
  'c#',
  'cs',
  'csharp',
  'css',
  'dart',
  'go',
  'graphql',
  'gql',
  'html',
  'java',
  'javascript',
  'js',
  'jsx',
  'json',
  'kotlin',
  'kt',
  'objc',
  'objectivec',
  'php',
  'rs',
  'rust',
  'swift',
  'ts',
  'tsx',
  'typescript',
  'xml',
};

bool _isClosingFenceLine(String blockSource, String line) {
  final openingLineBreak = blockSource.indexOf('\n');
  final openingLine = openingLineBreak < 0
      ? blockSource
      : blockSource.substring(0, openingLineBreak);
  final opening = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(openingLine);
  final closing = RegExp(r'^ {0,3}(`{3,}|~{3,})[ \t]*$').firstMatch(line);
  if (opening == null || closing == null) return false;
  final openingFence = opening.group(1)!;
  final closingFence = closing.group(1)!;
  return openingFence.codeUnitAt(0) == closingFence.codeUnitAt(0) &&
      closingFence.length >= openingFence.length;
}

TextSpan buildMarkdownSourceTextSpan(
  TextEditingValue value, {
  required TextStyle? style,
  required IanvsMarkdownSyntaxTheme syntaxTheme,
  required bool withComposing,
  bool hideInactiveInlineMarkers = false,
  bool hideInactiveEscapeMarkers = false,
  Set<String>? linkReferenceLabels,
}) {
  final text = value.text;
  final effectiveLinkReferenceLabels =
      linkReferenceLabels ?? MarkdownLinkReferenceContext.parse(text).labels;
  final tokens = _markdownSyntaxTokens(
    text,
    syntaxTheme,
    linkReferenceLabels: effectiveLinkReferenceLabels,
  );
  if (hideInactiveEscapeMarkers) {
    _addEscapeMarkerSyntaxTokens(tokens, text, syntaxTheme.marker);
  }
  final children = <InlineSpan>[];
  final boundaries = <int>{0, text.length};
  final startingAt = <int, List<_SyntaxToken>>{};
  final endingAt = <int, List<_SyntaxToken>>{};
  for (final token in tokens) {
    if (token.start < 0 ||
        token.end > text.length ||
        token.start >= token.end) {
      continue;
    }
    boundaries
      ..add(token.start)
      ..add(token.end);
    (startingAt[token.start] ??= <_SyntaxToken>[]).add(token);
    (endingAt[token.end] ??= <_SyntaxToken>[]).add(token);
  }
  final sortedBoundaries = boundaries.toList()..sort();
  final active = <_SyntaxToken>{};
  for (var index = 0; index + 1 < sortedBoundaries.length; index += 1) {
    final start = sortedBoundaries[index];
    final end = sortedBoundaries[index + 1];
    active.removeAll(endingAt[start] ?? const <_SyntaxToken>[]);
    active.addAll(startingAt[start] ?? const <_SyntaxToken>[]);
    if (start >= end) continue;
    final tokenStyle = _composedMarkdownSyntaxStyle(
      active,
      selection: value.selection,
      hideInactiveInlineMarkers: hideInactiveInlineMarkers,
    );
    _appendComposingSpan(
      children,
      text,
      start,
      end,
      style?.merge(tokenStyle) ?? tokenStyle,
      value.composing,
      withComposing,
    );
  }
  return TextSpan(style: style, children: children);
}

void _addEscapeMarkerSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  TextStyle markerStyle,
) {
  for (var offset = 0; offset + 1 < text.length; offset += 1) {
    if (text.codeUnitAt(offset) != 0x5c) continue;
    final runStart = offset;
    while (offset + 1 < text.length && text.codeUnitAt(offset + 1) == 0x5c) {
      offset += 1;
    }
    final runLength = offset - runStart + 1;
    if (runLength.isEven || offset + 1 >= text.length) continue;
    final escaped = text.codeUnitAt(offset + 1);
    if (!_isAsciiPunctuation(escaped)) continue;
    target.add(
      _SyntaxToken(
        offset,
        offset + 1,
        markerStyle,
        inlineMarkerRange: TextRange(start: offset, end: offset + 2),
      ),
    );
  }
}

bool _isAsciiPunctuation(int codeUnit) =>
    (codeUnit >= 0x21 && codeUnit <= 0x2f) ||
    (codeUnit >= 0x3a && codeUnit <= 0x40) ||
    (codeUnit >= 0x5b && codeUnit <= 0x60) ||
    (codeUnit >= 0x7b && codeUnit <= 0x7e);

TextStyle? _composedMarkdownSyntaxStyle(
  Set<_SyntaxToken> active, {
  required TextSelection selection,
  required bool hideInactiveInlineMarkers,
}) {
  if (active.isEmpty) return null;
  final markerTokens = active
      .where((token) => token.inlineMarkerRange != null)
      .toList();
  if (markerTokens.isNotEmpty) {
    final revealed = markerTokens.where(
      (token) => _selectionReveals(selection, token.inlineMarkerRange!),
    );
    if (hideInactiveInlineMarkers && revealed.isEmpty) {
      return _hiddenMarkdownMarkerStyle;
    }
    final visibleMarkers = revealed.isEmpty ? markerTokens : revealed;
    return _mergeMarkdownSyntaxStyles(
      visibleMarkers.map((token) => token.style),
    );
  }

  final contentTokens = active.toList()
    ..sort((a, b) {
      final lengthOrder = (b.end - b.start).compareTo(a.end - a.start);
      if (lengthOrder != 0) return lengthOrder;
      final startOrder = a.start.compareTo(b.start);
      if (startOrder != 0) return startOrder;
      return b.end.compareTo(a.end);
    });
  return _mergeMarkdownSyntaxStyles(contentTokens.map((token) => token.style));
}

TextStyle? _mergeMarkdownSyntaxStyles(Iterable<TextStyle> styles) {
  TextStyle? result;
  for (final style in styles) {
    if (result == null) {
      result = style;
      continue;
    }
    final inheritedDecoration = result.decoration;
    final overlayDecoration = style.decoration;
    result = result.merge(style);
    if (inheritedDecoration != null &&
        inheritedDecoration != TextDecoration.none &&
        overlayDecoration != null &&
        overlayDecoration != TextDecoration.none &&
        inheritedDecoration != overlayDecoration) {
      result = result.copyWith(
        decoration: TextDecoration.combine(<TextDecoration>[
          inheritedDecoration,
          overlayDecoration,
        ]),
      );
    }
  }
  return result;
}

List<_SyntaxToken> _markdownSyntaxTokens(
  String text,
  IanvsMarkdownSyntaxTheme theme, {
  required Set<String> linkReferenceLabels,
}) {
  final tokens = <_SyntaxToken>[];
  final fencedRanges = <TextRange>[];
  final lines = text.split('\n');
  var offset = 0;
  int? fenceStart;
  int? fenceCharacter;
  var fenceLength = 0;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final match = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
    if (match != null) {
      final marker = match.group(1)!;
      if (fenceStart == null) {
        fenceStart = offset;
        fenceCharacter = marker.codeUnitAt(0);
        fenceLength = marker.length;
      } else if (marker.codeUnitAt(0) == fenceCharacter &&
          marker.length >= fenceLength) {
        fencedRanges.add(
          TextRange(start: fenceStart, end: offset + line.length),
        );
        fenceStart = null;
      }
    }
    offset += line.length + (index + 1 < lines.length ? 1 : 0);
  }
  if (fenceStart != null) {
    fencedRanges.add(TextRange(start: fenceStart, end: text.length));
  }
  for (final range in fencedRanges) {
    _addFencedCodeSyntaxTokens(tokens, text, range, theme);
  }

  final obsidianCommentRanges = <TextRange>[];
  final obsidianCommentPattern = RegExp(r'%%.*?(?:%%|$)', dotAll: true);
  for (final match in obsidianCommentPattern.allMatches(text)) {
    if (_overlapsAnyRange(match.start, match.end, fencedRanges)) continue;
    obsidianCommentRanges.add(TextRange(start: match.start, end: match.end));
    tokens.add(_SyntaxToken(match.start, match.end, theme.comment));
  }
  final displayMathRanges = _addDisplayMathSyntaxTokens(
    tokens,
    text,
    theme,
    <TextRange>[...fencedRanges, ...obsidianCommentRanges],
  );
  final excludedRanges = <TextRange>[
    ...fencedRanges,
    ...obsidianCommentRanges,
    ...displayMathRanges,
  ];
  final inlineStructuralRanges = <TextRange>[];

  final headingPattern = RegExp(r'^( {0,3}#{1,6}[ \t]+)(.*)$', multiLine: true);
  for (final match in headingPattern.allMatches(text)) {
    if (_overlapsAnyRange(match.start, match.end, excludedRanges)) continue;
    final markerEnd = match.start + match.group(1)!.length;
    inlineStructuralRanges.add(TextRange(start: match.start, end: markerEnd));
    tokens
      ..add(_SyntaxToken(match.start, markerEnd, theme.marker))
      ..add(_SyntaxToken(markerEnd, match.end, theme.heading));
  }

  final setextHeadingPattern = RegExp(
    r'^( {0,3})([^\n]+)\n( {0,3})(?:=+|-+)[ \t]*$',
    multiLine: true,
  );
  for (final match in setextHeadingPattern.allMatches(text)) {
    if (_overlapsAnyRange(match.start, match.end, excludedRanges)) continue;
    final titleLine = match.group(1)! + match.group(2)!;
    if (RegExp(r'^ {0,3}#{1,6}(?:[ \t]+|$)').hasMatch(titleLine)) {
      continue;
    }
    final underlineStart = match.start + titleLine.length + 1;
    inlineStructuralRanges.add(
      TextRange(start: underlineStart, end: match.end),
    );
    tokens
      ..add(
        _SyntaxToken(
          match.start,
          match.start + titleLine.length,
          theme.heading,
        ),
      )
      ..add(_SyntaxToken(underlineStart, match.end, theme.marker));
  }

  final pattern = RegExp(
    r'(^ {0,3}(?:>|[-+*]|\d{1,9}[.)])[ \t]+)|'
    r'(<!--[^\n]*-->)',
    multiLine: true,
  );
  for (final match in pattern.allMatches(text)) {
    if (_overlapsAnyRange(match.start, match.end, excludedRanges)) continue;
    final tokenStyle = switch (match.groups(<int>[1, 2])) {
      [final String _, null] => theme.marker,
      [null, final String _] => theme.comment,
      _ => theme.marker,
    };
    inlineStructuralRanges.add(TextRange(start: match.start, end: match.end));
    tokens.add(_SyntaxToken(match.start, match.end, tokenStyle));
  }
  final blockIdPattern = RegExp(
    r'[ \t]+\^[A-Za-z0-9-]+[ \t]*$',
    multiLine: true,
  );
  for (final match in blockIdPattern.allMatches(text)) {
    if (_overlapsAnyRange(match.start, match.end, excludedRanges)) continue;
    inlineStructuralRanges.add(TextRange(start: match.start, end: match.end));
    tokens.add(_SyntaxToken(match.start, match.end, theme.comment));
  }
  final footnotePattern = RegExp(
    r'\[\^[^\]\n]+\](?::)?|\^\[[^\]\n]+\]',
    multiLine: true,
  );
  for (final match in footnotePattern.allMatches(text)) {
    if (_overlapsAnyRange(match.start, match.end, excludedRanges)) continue;
    inlineStructuralRanges.add(TextRange(start: match.start, end: match.end));
    tokens.add(_SyntaxToken(match.start, match.end, theme.comment));
  }
  final codeExcludedRanges = <TextRange>[
    ...excludedRanges,
    ...inlineStructuralRanges,
  ];
  final codeRanges = _addInlineCodeSyntaxTokens(
    tokens,
    text,
    theme.code,
    theme.inlineCodeMarker ?? theme.marker,
    codeExcludedRanges,
  );
  final mathRanges = _addInlineMathSyntaxTokens(
    tokens,
    text,
    theme,
    <TextRange>[...codeExcludedRanges, ...codeRanges],
  );
  final inlineHtmlLiteralRanges = _addInlineHtmlSyntaxTokens(
    tokens,
    text,
    theme,
    <TextRange>[...codeExcludedRanges, ...codeRanges, ...mathRanges],
  );
  final wikiLinkLiteralRanges = _addWikiLinkSyntaxTokens(
    tokens,
    text,
    theme,
    <TextRange>[...codeExcludedRanges, ...mathRanges],
    openingExcludedRanges: <TextRange>[...codeRanges, ...mathRanges],
  );
  final inlineLinkLiteralRanges = _addLinkSyntaxTokens(
    tokens,
    text,
    theme,
    <TextRange>[...codeExcludedRanges, ...mathRanges, ...wikiLinkLiteralRanges],
    openingExcludedRanges: <TextRange>[
      ...codeRanges,
      ...mathRanges,
      ...wikiLinkLiteralRanges,
    ],
  );
  final referenceLinkLiteralRanges = _addReferenceLinkSyntaxTokens(
    tokens,
    text,
    theme,
    linkReferenceLabels,
    <TextRange>[
      ...codeExcludedRanges,
      ...mathRanges,
      ...wikiLinkLiteralRanges,
      ...inlineLinkLiteralRanges,
    ],
    openingExcludedRanges: <TextRange>[
      ...codeRanges,
      ...mathRanges,
      ...wikiLinkLiteralRanges,
      ...inlineLinkLiteralRanges,
    ],
  );
  final explicitLinkLiteralRanges = <TextRange>[
    ...mathRanges,
    ...inlineHtmlLiteralRanges,
    ...wikiLinkLiteralRanges,
    ...inlineLinkLiteralRanges,
    ...referenceLinkLiteralRanges,
  ];
  final autolinkRanges = _addAutolinkSyntaxTokens(
    tokens,
    text,
    theme,
    <TextRange>[
      ...codeExcludedRanges,
      ...codeRanges,
      ...explicitLinkLiteralRanges,
    ],
  );
  final inlineLiteralRanges = <TextRange>[
    ...codeExcludedRanges,
    ...explicitLinkLiteralRanges,
    ...autolinkRanges,
  ];
  final inlineSyntaxExcludedRanges = <TextRange>[
    ...inlineLiteralRanges,
    ...codeRanges,
  ];
  _addTagSyntaxTokens(tokens, text, theme, inlineSyntaxExcludedRanges);
  _addDelimitedSyntaxTokens(
    tokens,
    text,
    RegExp(r'(==)(\S(?:(?:(?!\n[ \t]*\n)[\s\S])*?\S)?)=='),
    theme.highlight,
    theme.marker,
    inlineSyntaxExcludedRanges,
  );
  _addDelimitedSyntaxTokens(
    tokens,
    text,
    RegExp(
      r'(?<!\*)(\*\*\*)(?!\*)(\S(?:(?:(?!\n[ \t]*\n)[\s\S])*?\S)?)(?<!\*)\*\*\*(?!\*)',
    ),
    theme.strong.merge(theme.emphasis),
    theme.strong.merge(theme.emphasis),
    inlineSyntaxExcludedRanges,
  );
  _addDelimitedSyntaxTokens(
    tokens,
    text,
    RegExp(
      r'(?<!_)(___)(?!_)(\S(?:(?:(?!\n[ \t]*\n)[\s\S])*?\S)?)(?<!_)___(?!_)',
    ),
    theme.strong.merge(theme.emphasis),
    theme.strong.merge(theme.emphasis),
    inlineSyntaxExcludedRanges,
  );
  _addDelimitedSyntaxTokens(
    tokens,
    text,
    RegExp(
      r'(?<!\*)(\*\*)(?!\*)(\S(?:(?:(?!\n[ \t]*\n)[\s\S])*?\S)?)(?<!\*)\*\*(?!\*)',
    ),
    theme.strong,
    theme.strong,
    inlineSyntaxExcludedRanges,
  );
  _addDelimitedSyntaxTokens(
    tokens,
    text,
    RegExp(
      r'(?<!_)(__)(?!_)(\S(?:(?:(?!\n[ \t]*\n)[\s\S])*?\S)?)(?<!_)__(?!_)',
    ),
    theme.strong,
    theme.strong,
    inlineSyntaxExcludedRanges,
  );
  _addDelimitedSyntaxTokens(
    tokens,
    text,
    RegExp(r'(~~)(\S(?:(?:(?!\n[ \t]*\n)[\s\S])*?\S)?)~~'),
    theme.strikethrough,
    theme.marker,
    inlineSyntaxExcludedRanges,
  );
  _addDelimitedSyntaxTokens(
    tokens,
    text,
    RegExp(
      r'(?<!\*)(\*)(?!\*)(\S(?:(?:(?!\n[ \t]*\n)[\s\S])*?\S)?)(?<!\*)\*(?!\*)',
    ),
    theme.emphasis,
    theme.emphasis,
    inlineSyntaxExcludedRanges,
  );
  _addDelimitedSyntaxTokens(
    tokens,
    text,
    RegExp(r'(?<!_)(_)(?!_)(\S(?:(?:(?!\n[ \t]*\n)[\s\S])*?\S)?)(?<!_)_(?!_)'),
    theme.emphasis,
    theme.emphasis,
    inlineSyntaxExcludedRanges,
    disallowIntraWord: true,
  );
  tokens.sort((a, b) => a.start.compareTo(b.start));
  return tokens;
}

List<TextRange> _addDisplayMathSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  IanvsMarkdownSyntaxTheme theme,
  List<TextRange> excludedRanges,
) {
  final ranges = <TextRange>[];
  final pattern = RegExp(
    r'^ {0,3}\$\$[ \t]*\r?\n[\s\S]*?\r?\n {0,3}\$\$[ \t]*$',
    multiLine: true,
  );
  for (final match in pattern.allMatches(text)) {
    if (_overlapsAnyRange(match.start, match.end, excludedRanges)) continue;
    final source = match.group(0)!;
    final openingStart = match.start + source.indexOf(r'$$');
    final openingEnd = openingStart + 2;
    final closingStart = match.start + source.lastIndexOf(r'$$');
    final closingEnd = closingStart + 2;
    final firstBreak = text.indexOf('\n', openingEnd);
    final lastBreak = text.lastIndexOf('\n', closingStart);
    if (firstBreak < 0 || lastBreak < firstBreak) continue;
    final range = TextRange(start: match.start, end: match.end);
    ranges.add(range);
    target
      ..add(_SyntaxToken(openingStart, openingEnd, theme.marker))
      ..add(_SyntaxToken(firstBreak + 1, lastBreak, theme.math))
      ..add(_SyntaxToken(closingStart, closingEnd, theme.marker));
  }
  return ranges;
}

List<TextRange> _addInlineMathSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  IanvsMarkdownSyntaxTheme theme,
  List<TextRange> excludedRanges,
) {
  final ranges = <TextRange>[];
  var index = 0;
  while (index < text.length) {
    if (text.codeUnitAt(index) != 0x24 ||
        _isEscapedAt(text, index) ||
        _isOffsetInsideAnyRange(index, excludedRanges)) {
      index += 1;
      continue;
    }
    final delimiterLength =
        index + 1 < text.length && text.codeUnitAt(index + 1) == 0x24 ? 2 : 1;
    if (delimiterLength == 1 &&
        index > 0 &&
        text.codeUnitAt(index - 1) == 0x24) {
      index += 1;
      continue;
    }
    final contentStart = index + delimiterLength;
    if (contentStart >= text.length ||
        _isMarkdownWhitespaceAt(text, contentStart)) {
      index = contentStart;
      continue;
    }

    var search = contentStart;
    var matched = false;
    while (search < text.length) {
      final closingStart = text.indexOf(
        delimiterLength == 2 ? r'$$' : r'$',
        search,
      );
      if (closingStart < 0) break;
      final lineBreak = text.indexOf('\n', search);
      if (lineBreak >= 0 && lineBreak < closingStart) break;
      final codeDelimiter = text.indexOf('`', search);
      if (codeDelimiter >= 0 && codeDelimiter < closingStart) break;
      final closingEnd = closingStart + delimiterLength;
      final invalidSingleClose =
          delimiterLength == 1 &&
          (closingEnd < text.length &&
              (text.codeUnitAt(closingEnd) == 0x24 ||
                  _isAsciiDigitCodeUnit(text.codeUnitAt(closingEnd))));
      if (closingStart == contentStart ||
          _isEscapedAt(text, closingStart) ||
          _isMarkdownWhitespaceAt(text, closingStart - 1) ||
          invalidSingleClose ||
          _overlapsAnyRange(index, closingEnd, excludedRanges)) {
        search = closingEnd;
        continue;
      }

      final revealRange = TextRange(start: index, end: closingEnd);
      ranges.add(revealRange);
      target
        ..add(
          _SyntaxToken(
            index,
            contentStart,
            theme.marker,
            inlineMarkerRange: revealRange,
          ),
        )
        ..add(_SyntaxToken(contentStart, closingStart, theme.math))
        ..add(
          _SyntaxToken(
            closingStart,
            closingEnd,
            theme.marker,
            inlineMarkerRange: revealRange,
          ),
        );
      index = closingEnd;
      matched = true;
      break;
    }
    if (!matched) index = contentStart;
  }
  return ranges;
}

bool _isMarkdownWhitespaceAt(String text, int index) {
  if (index < 0 || index >= text.length) return false;
  final codeUnit = text.codeUnitAt(index);
  return codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0d ||
      codeUnit == 0x0a;
}

bool _isAsciiDigitCodeUnit(int codeUnit) =>
    codeUnit >= 0x30 && codeUnit <= 0x39;

List<TextRange> _addInlineHtmlSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  IanvsMarkdownSyntaxTheme theme,
  List<TextRange> excludedRanges,
) {
  final literalRanges = <TextRange>[];
  final pattern = RegExp(
    r'<([A-Za-z][A-Za-z0-9-]*)\b([^>\n]*)>([\s\S]*?)</\1\s*>|<br\s*>',
    caseSensitive: false,
  );

  void scan(int start, int end) {
    for (final match in pattern.allMatches(text, start)) {
      if (match.start >= end) break;
      if (match.end > end || _isEscapedAt(text, match.start)) continue;
      final tag = match.group(1)?.toLowerCase();
      if (tag == null) {
        if (_overlapsAnyRange(match.start, match.end, excludedRanges)) {
          continue;
        }
        final range = TextRange(start: match.start, end: match.end);
        literalRanges.add(range);
        target.add(
          _SyntaxToken(
            match.start,
            match.end,
            theme.marker,
            inlineMarkerRange: range,
          ),
        );
        continue;
      }
      if (tag == 'script' || tag == 'style') continue;

      final openingEnd = text.indexOf('>', match.start) + 1;
      final closingStart = text.lastIndexOf('</', match.end - 1);
      if (openingEnd <= match.start || closingStart < openingEnd) continue;
      if (_overlapsAnyRange(match.start, openingEnd, excludedRanges) ||
          _overlapsAnyRange(closingStart, match.end, excludedRanges)) {
        continue;
      }
      final revealRange = TextRange(start: match.start, end: match.end);
      final openingRange = TextRange(start: match.start, end: openingEnd);
      final closingRange = TextRange(start: closingStart, end: match.end);
      literalRanges
        ..add(openingRange)
        ..add(closingRange);
      target
        ..add(
          _SyntaxToken(
            openingRange.start,
            openingRange.end,
            theme.marker,
            inlineMarkerRange: revealRange,
          ),
        )
        ..add(
          _SyntaxToken(
            closingRange.start,
            closingRange.end,
            theme.marker,
            inlineMarkerRange: revealRange,
          ),
        );

      final attributes = match.group(2) ?? '';
      final spanColor = tag == 'span'
          ? ianvsMarkdownSafeHtmlColor(attributes)
          : null;
      final contentStyle = switch (tag) {
        'strong' || 'b' => theme.strong,
        'em' || 'i' => theme.emphasis,
        's' || 'del' => theme.strikethrough,
        'mark' => theme.highlight,
        'code' || 'kbd' => theme.code,
        'a' => theme.link,
        'u' => const TextStyle(decoration: TextDecoration.underline),
        'sup' || 'sub' => const TextStyle(fontSize: 10),
        'span' => spanColor == null ? null : TextStyle(color: spanColor),
        _ => null,
      };
      if (contentStyle != null && openingEnd < closingStart) {
        target.add(_SyntaxToken(openingEnd, closingStart, contentStyle));
      }
      scan(openingEnd, closingStart);
    }
  }

  scan(0, text.length);
  return literalRanges;
}

const _hiddenMarkdownMarkerStyle = TextStyle(
  color: Colors.transparent,
  fontSize: .01,
  height: .01,
  letterSpacing: -.01,
);

bool _selectionReveals(TextSelection selection, TextRange range) {
  if (!selection.isValid) return false;
  if (selection.isCollapsed) {
    return selection.extentOffset >= range.start &&
        selection.extentOffset <= range.end;
  }
  return selection.start < range.end && selection.end > range.start;
}

bool _overlapsAnyRange(int start, int end, List<TextRange> ranges) {
  return ranges.any((range) => start < range.end && end > range.start);
}

void _addFencedCodeSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  TextRange range,
  IanvsMarkdownSyntaxTheme theme,
) {
  final source = text.substring(range.start, range.end);
  final openingBreak = source.indexOf('\n');
  if (openingBreak < 0) {
    target.add(_SyntaxToken(range.start, range.end, theme.marker));
    return;
  }
  final openingEnd = range.start + openingBreak;
  target.add(_SyntaxToken(range.start, openingEnd, theme.marker));

  final closingBreak = source.lastIndexOf('\n');
  final closingSource = closingBreak < 0
      ? ''
      : source.substring(closingBreak + 1);
  final hasClosingFence = RegExp(
    r'^ {0,3}(`{3,}|~{3,})\s*$',
  ).hasMatch(closingSource);
  final bodyStart = openingEnd + 1;
  final bodyEnd = hasClosingFence ? range.start + closingBreak : range.end;
  if (bodyStart < bodyEnd) {
    final openingSource = source.substring(0, openingBreak);
    final openingMarker = RegExp(
      r'^ {0,3}(?:`{3,}|~{3,})',
    ).firstMatch(openingSource);
    final info = openingMarker == null
        ? ''
        : openingSource.substring(openingMarker.end).trim();
    final language = info.isEmpty ? null : info.split(RegExp(r'\s+')).first;
    final highlighted = markdownHighlightedCodeSpan(
      text.substring(bodyStart, bodyEnd),
      language: language,
      baseStyle: theme.codeBlock,
      dark: theme.darkCodeHighlighting,
    );
    _appendHighlightedCodeSyntaxTokens(
      target,
      highlighted,
      bodyStart,
      theme.codeBlock,
    );
  }
  if (hasClosingFence) {
    target.add(_SyntaxToken(bodyEnd + 1, range.end, theme.marker));
  }
}

void _appendHighlightedCodeSyntaxTokens(
  List<_SyntaxToken> target,
  TextSpan span,
  int sourceStart,
  TextStyle baseStyle,
) {
  var offset = sourceStart;

  void visit(TextSpan current, TextStyle inheritedStyle) {
    final effectiveStyle = inheritedStyle.merge(current.style);
    final segment = current.text;
    if (segment != null && segment.isNotEmpty) {
      target.add(_SyntaxToken(offset, offset + segment.length, effectiveStyle));
      offset += segment.length;
    }
    for (final child in current.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) visit(child, effectiveStyle);
    }
  }

  visit(span, baseStyle);
}

List<TextRange> _addDelimitedSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  RegExp pattern,
  TextStyle contentStyle,
  TextStyle markerStyle,
  List<TextRange> excludedRanges, {
  bool disallowIntraWord = false,
}) {
  final ranges = <TextRange>[];
  for (final match in pattern.allMatches(text)) {
    final marker = match.group(1)!;
    final contentStart = match.start + marker.length;
    final contentEnd = match.end - marker.length;
    if (contentStart >= contentEnd) continue;
    if (_containsMarkdownParagraphBreak(text, contentStart, contentEnd)) {
      continue;
    }
    if (disallowIntraWord &&
        ((_isMarkdownWordLikeAt(text, match.start - 1) &&
                _isMarkdownWordLikeAt(text, contentStart)) ||
            (_isMarkdownWordLikeAt(text, contentEnd - 1) &&
                _isMarkdownWordLikeAt(text, match.end)))) {
      continue;
    }
    if (_overlapsAnyRange(match.start, contentStart, excludedRanges) ||
        _overlapsAnyRange(contentEnd, match.end, excludedRanges) ||
        _isEscapedAt(text, match.start) ||
        _isEscapedAt(text, contentEnd)) {
      continue;
    }
    final revealRange = TextRange(start: match.start, end: match.end);
    final openingLineEnd = text.indexOf('\n', contentStart);
    final multiline = openingLineEnd >= 0 && openingLineEnd < contentEnd;
    final closingLineStart = multiline
        ? text.lastIndexOf('\n', contentEnd - 1) + 1
        : match.start;
    final openingRevealRange = multiline
        ? TextRange(start: match.start, end: openingLineEnd)
        : revealRange;
    final closingRevealRange = multiline
        ? TextRange(start: closingLineStart, end: match.end)
        : revealRange;
    ranges.add(revealRange);
    target
      ..add(
        _SyntaxToken(
          match.start,
          contentStart,
          markerStyle,
          inlineMarkerRange: openingRevealRange,
        ),
      )
      ..add(_SyntaxToken(contentStart, contentEnd, contentStyle))
      ..add(
        _SyntaxToken(
          contentEnd,
          match.end,
          markerStyle,
          inlineMarkerRange: closingRevealRange,
        ),
      );
  }
  return ranges;
}

bool _isMarkdownWordLikeAt(String text, int index) {
  if (index < 0 || index >= text.length) return false;
  final codeUnit = text.codeUnitAt(index);
  if (_isMarkdownWhitespaceAt(text, index) || _isAsciiPunctuation(codeUnit)) {
    return false;
  }
  // Common prose characters, including non-ASCII letters and digits, are
  // word-like for delimiter flanking. Treating symbols the same way is the
  // conservative choice: it prevents a stray underscore from becoming
  // emphasis in the middle of an uninterrupted token.
  return true;
}

List<TextRange> _addInlineCodeSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  TextStyle contentStyle,
  TextStyle markerStyle,
  List<TextRange> excludedRanges,
) {
  final ranges = <TextRange>[];
  var index = 0;
  while (index < text.length) {
    if (text.codeUnitAt(index) != 0x60 || _isEscapedAt(text, index)) {
      index += 1;
      continue;
    }
    final openingStart = index;
    final openingEnd = _backtickRunEnd(text, openingStart);
    if (_overlapsAnyRange(openingStart, openingEnd, excludedRanges)) {
      index = openingEnd;
      continue;
    }
    final markerLength = openingEnd - openingStart;
    var search = openingEnd;
    var matched = false;
    while (search < text.length) {
      final closingStart = text.indexOf('`', search);
      if (closingStart < 0) break;
      if (_containsMarkdownParagraphBreak(text, openingEnd, closingStart)) {
        break;
      }
      final closingEnd = _backtickRunEnd(text, closingStart);
      if (closingEnd - closingStart != markerLength) {
        search = closingEnd;
        continue;
      }
      if (_overlapsAnyRange(openingStart, closingEnd, excludedRanges)) break;

      final revealRange = TextRange(start: openingStart, end: closingEnd);
      final openingLineEnd = text.indexOf('\n', openingEnd);
      final multiline = openingLineEnd >= 0 && openingLineEnd < closingStart;
      final closingLineStart = multiline
          ? text.lastIndexOf('\n', closingStart - 1) + 1
          : openingStart;
      final openingRevealRange = multiline
          ? TextRange(start: openingStart, end: openingLineEnd)
          : revealRange;
      final closingRevealRange = multiline
          ? TextRange(start: closingLineStart, end: closingEnd)
          : revealRange;
      ranges.add(revealRange);
      target.add(
        _SyntaxToken(
          openingStart,
          openingEnd,
          markerStyle,
          inlineMarkerRange: openingRevealRange,
        ),
      );

      final contentStart = openingEnd;
      final contentEnd = closingStart;
      final trimsPadding =
          contentStart < contentEnd &&
          text.codeUnitAt(contentStart) == 0x20 &&
          text.codeUnitAt(contentEnd - 1) == 0x20 &&
          text.substring(contentStart, contentEnd).trim().isNotEmpty;
      if (trimsPadding) {
        target.add(
          _SyntaxToken(
            contentStart,
            contentStart + 1,
            contentStyle,
            inlineMarkerRange: openingRevealRange,
          ),
        );
        if (contentStart + 1 < contentEnd - 1) {
          target.add(
            _SyntaxToken(contentStart + 1, contentEnd - 1, contentStyle),
          );
        }
        target.add(
          _SyntaxToken(
            contentEnd - 1,
            contentEnd,
            contentStyle,
            inlineMarkerRange: closingRevealRange,
          ),
        );
      } else if (contentStart < contentEnd) {
        target.add(_SyntaxToken(contentStart, contentEnd, contentStyle));
      }
      target.add(
        _SyntaxToken(
          closingStart,
          closingEnd,
          markerStyle,
          inlineMarkerRange: closingRevealRange,
        ),
      );
      index = closingEnd;
      matched = true;
      break;
    }
    if (!matched) index = openingEnd;
  }
  return ranges;
}

bool _containsMarkdownParagraphBreak(String text, int start, int end) {
  var lineBreak = text.indexOf('\n', start);
  while (lineBreak >= 0 && lineBreak < end) {
    var next = lineBreak + 1;
    while (next < end) {
      final codeUnit = text.codeUnitAt(next);
      if (codeUnit != 0x20 && codeUnit != 0x09 && codeUnit != 0x0d) break;
      next += 1;
    }
    if (next < end && text.codeUnitAt(next) == 0x0a) return true;
    lineBreak = text.indexOf('\n', next);
  }
  return false;
}

int _backtickRunEnd(String text, int start) {
  var end = start;
  while (end < text.length && text.codeUnitAt(end) == 0x60) {
    end += 1;
  }
  return end;
}

List<TextRange> _addLinkSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  IanvsMarkdownSyntaxTheme theme,
  List<TextRange> excludedRanges, {
  List<TextRange> openingExcludedRanges = const <TextRange>[],
}) {
  final literalRanges = <TextRange>[];
  var index = 0;
  while (index < text.length) {
    final isImage =
        text.codeUnitAt(index) == 0x21 &&
        index + 1 < text.length &&
        text.codeUnitAt(index + 1) == 0x5b;
    final bracketStart = isImage
        ? index + 1
        : text.codeUnitAt(index) == 0x5b
        ? index
        : -1;
    if (bracketStart < 0) {
      index += 1;
      continue;
    }
    final matchStart = index;
    if (_isEscapedAt(text, matchStart) ||
        _isOffsetInsideAnyRange(matchStart, openingExcludedRanges)) {
      index = bracketStart + 1;
      continue;
    }
    final labelEnd = _balancedMarkdownDelimiterEnd(
      text,
      bracketStart,
      opening: 0x5b,
      closing: 0x5d,
    );
    if (labelEnd == null ||
        labelEnd + 1 >= text.length ||
        text.codeUnitAt(labelEnd + 1) != 0x28) {
      index = bracketStart + 1;
      continue;
    }
    final destinationEnd = _balancedMarkdownDelimiterEnd(
      text,
      labelEnd + 1,
      opening: 0x28,
      closing: 0x29,
    );
    if (destinationEnd == null) {
      index = bracketStart + 1;
      continue;
    }
    final matchEnd = destinationEnd + 1;
    if (_overlapsAnyRange(matchStart, matchEnd, excludedRanges)) {
      index = matchEnd;
      continue;
    }
    final labelStart = bracketStart + 1;
    if (labelStart >= labelEnd) {
      index = matchEnd;
      continue;
    }
    final revealRange = TextRange(start: matchStart, end: matchEnd);
    literalRanges
      ..add(TextRange(start: matchStart, end: labelStart))
      ..add(TextRange(start: labelEnd, end: matchEnd));
    target
      ..add(
        _SyntaxToken(
          matchStart,
          labelStart,
          theme.marker,
          inlineMarkerRange: revealRange,
        ),
      )
      ..add(_SyntaxToken(labelStart, labelEnd, theme.link))
      ..add(
        _SyntaxToken(
          labelEnd,
          matchEnd,
          theme.marker,
          inlineMarkerRange: revealRange,
        ),
      );
    index = matchEnd;
  }
  return literalRanges;
}

List<TextRange> _addReferenceLinkSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  IanvsMarkdownSyntaxTheme theme,
  Set<String> definedLabels,
  List<TextRange> excludedRanges, {
  List<TextRange> openingExcludedRanges = const <TextRange>[],
}) {
  if (definedLabels.isEmpty) return const <TextRange>[];
  final literalRanges = <TextRange>[];
  var index = 0;
  while (index < text.length) {
    final isImage =
        text.codeUnitAt(index) == 0x21 &&
        index + 1 < text.length &&
        text.codeUnitAt(index + 1) == 0x5b;
    final bracketStart = isImage
        ? index + 1
        : text.codeUnitAt(index) == 0x5b
        ? index
        : -1;
    if (bracketStart < 0) {
      index += 1;
      continue;
    }
    final matchStart = index;
    if (_isEscapedAt(text, matchStart) ||
        _isOffsetInsideAnyRange(matchStart, openingExcludedRanges)) {
      index = bracketStart + 1;
      continue;
    }
    final labelEnd = _balancedMarkdownDelimiterEnd(
      text,
      bracketStart,
      opening: 0x5b,
      closing: 0x5d,
    );
    if (labelEnd == null) {
      index = bracketStart + 1;
      continue;
    }

    final labelStart = bracketStart + 1;
    final primaryLabel = text.substring(labelStart, labelEnd);
    var referenceLabel = primaryLabel;
    var matchEnd = labelEnd + 1;
    if (matchEnd < text.length && text.codeUnitAt(matchEnd) == 0x28) {
      final inlineDestinationEnd = _balancedMarkdownDelimiterEnd(
        text,
        matchEnd,
        opening: 0x28,
        closing: 0x29,
      );
      if (inlineDestinationEnd != null) {
        index = matchEnd;
        continue;
      }
    }
    if (matchEnd < text.length && text.codeUnitAt(matchEnd) == 0x5b) {
      final referenceEnd = _balancedMarkdownDelimiterEnd(
        text,
        matchEnd,
        opening: 0x5b,
        closing: 0x5d,
      );
      if (referenceEnd == null) {
        index = matchEnd + 1;
        continue;
      }
      final secondaryLabel = text.substring(matchEnd + 1, referenceEnd);
      if (secondaryLabel.isNotEmpty) referenceLabel = secondaryLabel;
      matchEnd = referenceEnd + 1;
    } else {
      if (matchEnd < text.length && text.codeUnitAt(matchEnd) == 0x3a) {
        index = matchEnd;
        continue;
      }
      if (_isTaskCheckboxCandidate(text, bracketStart, labelEnd)) {
        index = matchEnd;
        continue;
      }
    }

    final normalized = normalizeMarkdownLinkReferenceLabel(referenceLabel);
    if (!definedLabels.contains(normalized) ||
        _overlapsAnyRange(matchStart, matchEnd, excludedRanges)) {
      index = matchEnd;
      continue;
    }
    final revealRange = TextRange(start: matchStart, end: matchEnd);
    literalRanges
      ..add(TextRange(start: matchStart, end: labelStart))
      ..add(TextRange(start: labelEnd, end: matchEnd));
    target.add(
      _SyntaxToken(
        matchStart,
        labelStart,
        theme.marker,
        inlineMarkerRange: revealRange,
      ),
    );
    if (labelStart < labelEnd) {
      target.add(_SyntaxToken(labelStart, labelEnd, theme.link));
    }
    target.add(
      _SyntaxToken(
        labelEnd,
        matchEnd,
        theme.marker,
        inlineMarkerRange: revealRange,
      ),
    );
    index = matchEnd;
  }
  return literalRanges;
}

bool _isTaskCheckboxCandidate(String text, int start, int end) {
  final label = text.substring(start + 1, end);
  if (label != ' ' && label != 'x' && label != 'X') return false;
  final lineStart = text.lastIndexOf('\n', start - 1) + 1;
  final prefix = text.substring(lineStart, start);
  return RegExp(r'^ {0,3}(?:[-+*]|\d{1,9}[.)])[ \t]+$').hasMatch(prefix);
}

int? _balancedMarkdownDelimiterEnd(
  String text,
  int start, {
  required int opening,
  required int closing,
}) {
  if (start < 0 || start >= text.length || text.codeUnitAt(start) != opening) {
    return null;
  }
  var depth = 1;
  var index = start + 1;
  while (index < text.length) {
    final character = text.codeUnitAt(index);
    if (character == 0x0a || character == 0x0d) return null;
    if (character == 0x5c && index + 1 < text.length) {
      index += 2;
      continue;
    }
    if (character == opening) {
      depth += 1;
    } else if (character == closing) {
      depth -= 1;
      if (depth == 0) return index;
    }
    index += 1;
  }
  return null;
}

List<TextRange> _addAutolinkSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  IanvsMarkdownSyntaxTheme theme,
  List<TextRange> excludedRanges,
) {
  final ranges = <TextRange>[];
  var index = 0;
  while (index < text.length) {
    final match = matchIanvsMarkdownAutolinkAt(text, index);
    if (match == null) {
      index += 1;
      continue;
    }
    if (_overlapsAnyRange(match.start, match.end, excludedRanges)) {
      index = match.end;
      continue;
    }

    final range = TextRange(start: match.start, end: match.end);
    ranges.add(range);
    target.add(_SyntaxToken(match.labelStart, match.labelEnd, theme.link));
    if (match.angleWrapped) {
      final opening = match.escapedAngle ? match.start + 1 : match.start;
      target
        ..add(
          _SyntaxToken(
            opening,
            opening + 1,
            theme.marker,
            inlineMarkerRange: TextRange.empty,
          ),
        )
        ..add(
          _SyntaxToken(
            match.end - 1,
            match.end,
            theme.marker,
            inlineMarkerRange: TextRange.empty,
          ),
        );
    }
    index = match.end;
  }
  return ranges;
}

List<TextRange> _addWikiLinkSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  IanvsMarkdownSyntaxTheme theme,
  List<TextRange> excludedRanges, {
  List<TextRange> openingExcludedRanges = const <TextRange>[],
}) {
  final literalRanges = <TextRange>[];
  final pattern = RegExp(r'\[\[([^\]\n]+)\]\]');
  for (final match in pattern.allMatches(text)) {
    if (_overlapsAnyRange(match.start, match.end, excludedRanges) ||
        _isOffsetInsideAnyRange(match.start, openingExcludedRanges) ||
        _isEscapedAt(text, match.start)) {
      continue;
    }
    final source = match.group(0)!;
    final separator = source.indexOf('|', 2);
    final labelStart = separator < 0
        ? match.start + 2
        : match.start + separator + 1;
    final labelEnd = match.end - 2;
    if (labelStart >= labelEnd) continue;
    final revealRange = TextRange(start: match.start, end: match.end);
    literalRanges
      ..add(TextRange(start: match.start, end: labelStart))
      ..add(TextRange(start: labelEnd, end: match.end));
    target
      ..add(
        _SyntaxToken(
          match.start,
          labelStart,
          theme.marker,
          inlineMarkerRange: revealRange,
        ),
      )
      ..add(_SyntaxToken(labelStart, labelEnd, theme.wikiLink))
      ..add(
        _SyntaxToken(
          labelEnd,
          match.end,
          theme.marker,
          inlineMarkerRange: revealRange,
        ),
      );
  }
  return literalRanges;
}

void _addTagSyntaxTokens(
  List<_SyntaxToken> target,
  String text,
  IanvsMarkdownSyntaxTheme theme,
  List<TextRange> excludedRanges,
) {
  final pattern = RegExp(r'(?<![A-Za-z0-9_/])#[A-Za-z0-9_\-/\u3400-\u9fff]+');
  for (final match in pattern.allMatches(text)) {
    if (_overlapsAnyRange(match.start, match.end, excludedRanges) ||
        _isEscapedAt(text, match.start)) {
      continue;
    }
    target.add(_SyntaxToken(match.start, match.end, theme.tag));
  }
}

bool _isEscapedAt(String text, int offset) {
  var backslashes = 0;
  for (var index = offset - 1; index >= 0; index -= 1) {
    if (text.codeUnitAt(index) != 0x5c) break;
    backslashes += 1;
  }
  return backslashes.isOdd;
}

bool _isOffsetInsideAnyRange(int offset, List<TextRange> ranges) {
  return ranges.any((range) => offset >= range.start && offset < range.end);
}

void _appendComposingSpan(
  List<InlineSpan> target,
  String text,
  int start,
  int end,
  TextStyle? style,
  TextRange composing,
  bool withComposing,
) {
  if (start >= end) return;
  final hasComposing =
      withComposing &&
      composing.isValid &&
      !composing.isCollapsed &&
      composing.start < end &&
      composing.end > start;
  if (!hasComposing) {
    target.add(TextSpan(text: text.substring(start, end), style: style));
    return;
  }
  final composingStart = composing.start.clamp(start, end);
  final composingEnd = composing.end.clamp(start, end);
  if (start < composingStart) {
    target.add(
      TextSpan(text: text.substring(start, composingStart), style: style),
    );
  }
  target.add(
    TextSpan(
      text: text.substring(composingStart, composingEnd),
      style:
          style?.merge(const TextStyle(decoration: TextDecoration.underline)) ??
          const TextStyle(decoration: TextDecoration.underline),
    ),
  );
  if (composingEnd < end) {
    target.add(TextSpan(text: text.substring(composingEnd, end), style: style));
  }
}

TextRange _normalizedSelection(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid) {
    return TextRange(start: value.text.length, end: value.text.length);
  }
  return TextRange(
    start: selection.start.clamp(0, value.text.length),
    end: selection.end.clamp(0, value.text.length),
  );
}

TextRange _selectedLineRange(TextEditingValue value) {
  final selection = _normalizedSelection(value);
  final start = selection.start == 0
      ? 0
      : value.text.lastIndexOf('\n', selection.start - 1) + 1;
  final newline = value.text.indexOf('\n', selection.end);
  final end = newline < 0 ? value.text.length : newline;
  return TextRange(start: start, end: end);
}

int _sourceLineStart(String text, int offset) {
  final safeOffset = offset.clamp(0, text.length);
  if (safeOffset == 0) return 0;
  return text.lastIndexOf('\n', safeOffset - 1) + 1;
}

int _sourceLineEnd(String text, int offset) {
  final safeOffset = offset.clamp(0, text.length);
  final newline = text.indexOf('\n', safeOffset);
  return newline < 0 ? text.length : newline;
}

int _nextSourceLineCaret(String text, int offset) {
  final caret = offset.clamp(0, text.length);
  final lineStart = _sourceLineStart(text, caret);
  final lineEnd = _sourceLineEnd(text, caret);
  if (lineEnd == text.length) return caret;
  final nextStart = lineEnd + 1;
  final nextEnd = _sourceLineEnd(text, nextStart);
  final column = caret.clamp(lineStart, lineEnd) - lineStart;
  return nextStart + column.clamp(0, nextEnd - nextStart);
}

_EditKind _editKind(TextEditingValue previous, TextEditingValue current) {
  if (current.text.length > previous.text.length) return _EditKind.insertion;
  if (current.text.length < previous.text.length) return _EditKind.deletion;
  return _EditKind.replacement;
}

enum _EditKind { insertion, deletion, replacement }

final class _SyntaxToken {
  const _SyntaxToken(
    this.start,
    this.end,
    this.style, {
    this.inlineMarkerRange,
  });

  final int start;
  final int end;
  final TextStyle style;
  final TextRange? inlineMarkerRange;
}
