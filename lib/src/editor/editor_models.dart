import 'package:flutter/foundation.dart';

import '../markdown_table_syntax.dart';

/// Display modes supported by [IanvsMarkdownLiveEditor].
enum IanvsMarkdownEditorMode {
  /// The active block is source text and all other blocks are rendered.
  livePreview,

  /// The complete Markdown source is editable.
  source,

  /// The complete document is rendered and read-only.
  preview,
}

enum IanvsMarkdownBlockType {
  frontMatter,
  heading,
  paragraph,
  blockquote,
  unorderedList,
  orderedList,
  taskList,
  fencedCode,
  indentedCode,
  displayMath,
  table,
  thematicBreak,
  html,
}

@immutable
final class IanvsMarkdownBlock {
  const IanvsMarkdownBlock({
    required this.type,
    required this.start,
    required this.end,
    required this.firstLine,
    required this.lastLine,
    required this.source,
  });

  final IanvsMarkdownBlockType type;

  /// Inclusive UTF-16 offset in the original document.
  final int start;

  /// Exclusive UTF-16 offset in the original document.
  ///
  /// Line separators between blocks are intentionally excluded, so editing a
  /// block cannot accidentally destroy the surrounding document structure.
  final int end;
  final int firstLine;
  final int lastLine;
  final String source;

  int get length => end - start;

  bool containsOffset(int offset) {
    if (start == end) return offset == start;
    return offset >= start && offset <= end;
  }
}

/// Splits Markdown into source-preserving blocks for live-preview editing.
///
/// This parser deliberately does not normalize or reserialize Markdown. Each
/// block retains exact offsets into [source], while newlines between blocks
/// remain outside replacement ranges. Set [groupStandaloneComments] to false
/// for structural syntax scans that must still see code blocks nested between
/// paired line-only Obsidian comment delimiters.
List<IanvsMarkdownBlock> parseMarkdownBlocks(
  String source, {
  bool splitListItems = false,
  bool groupStandaloneComments = true,
}) {
  if (source.isEmpty) {
    return const <IanvsMarkdownBlock>[
      IanvsMarkdownBlock(
        type: IanvsMarkdownBlockType.paragraph,
        start: 0,
        end: 0,
        firstLine: 0,
        lastLine: 0,
        source: '',
      ),
    ];
  }

  final lines = _sourceLines(source);
  final blocks = <IanvsMarkdownBlock>[];
  var index = 0;
  while (index < lines.length) {
    if (lines[index].text.trim().isEmpty) {
      index += 1;
      continue;
    }

    final first = index;
    if (blocks.isNotEmpty &&
        _standaloneBlockIdExtends(lines[first].text, blocks.last.type)) {
      final previous = blocks.removeLast();
      blocks.add(
        _block(source, lines, previous.firstLine, first, previous.type),
      );
      index = first + 1;
      continue;
    }
    final nestedListType = splitListItems
        ? _nestedListItemType(lines, first, blocks)
        : null;
    final type = nestedListType ?? _classifyBlock(lines, first);
    final standaloneCommentEnd = groupStandaloneComments
        ? _standaloneCommentEnd(lines, first)
        : null;
    final last =
        standaloneCommentEnd ??
        switch (type) {
          IanvsMarkdownBlockType.frontMatter => _frontMatterEnd(lines, first),
          IanvsMarkdownBlockType.fencedCode => _fencedCodeEnd(lines, first),
          IanvsMarkdownBlockType.indentedCode => _indentedCodeEnd(lines, first),
          IanvsMarkdownBlockType.displayMath => _displayMathEnd(lines, first),
          IanvsMarkdownBlockType.blockquote => _blockquoteEnd(lines, first),
          IanvsMarkdownBlockType.unorderedList ||
          IanvsMarkdownBlockType.orderedList ||
          IanvsMarkdownBlockType.taskList =>
            splitListItems
                ? _listItemEnd(lines, first)
                : _listEnd(lines, first),
          IanvsMarkdownBlockType.table => _tableEnd(lines, first),
          IanvsMarkdownBlockType.heading
              when first + 1 < lines.length &&
                  _isSetextUnderline(lines[first + 1].text) =>
            first + 1,
          IanvsMarkdownBlockType.heading ||
          IanvsMarkdownBlockType.thematicBreak => first,
          IanvsMarkdownBlockType.html => _htmlEnd(lines, first),
          IanvsMarkdownBlockType.paragraph => _paragraphEnd(lines, first),
        };
    blocks.add(_block(source, lines, first, last, type));
    index = last + 1;
  }

  if (blocks.isEmpty) {
    return <IanvsMarkdownBlock>[
      IanvsMarkdownBlock(
        type: IanvsMarkdownBlockType.paragraph,
        start: 0,
        end: 0,
        firstLine: 0,
        lastLine: 0,
        source: '',
      ),
    ];
  }
  return List<IanvsMarkdownBlock>.unmodifiable(blocks);
}

bool _standaloneBlockIdExtends(
  String line,
  IanvsMarkdownBlockType previousType,
) {
  if (previousType == IanvsMarkdownBlockType.frontMatter ||
      previousType == IanvsMarkdownBlockType.fencedCode ||
      previousType == IanvsMarkdownBlockType.indentedCode ||
      previousType == IanvsMarkdownBlockType.html) {
    return false;
  }
  final quotePrefix = RegExp(r'^(?: {0,3}>[ \t]?)+').firstMatch(line);
  if ((quotePrefix != null &&
          previousType != IanvsMarkdownBlockType.blockquote) ||
      (quotePrefix == null &&
          previousType == IanvsMarkdownBlockType.blockquote)) {
    return false;
  }
  final candidate = quotePrefix == null
      ? line
      : line.substring(quotePrefix.end);
  return RegExp(r'^[ \t]*\^[A-Za-z0-9_-]+ *$').hasMatch(candidate);
}

int? _standaloneCommentEnd(List<_SourceLine> lines, int first) {
  if (!RegExp(r'^ {0,3}%%[ \t]*$').hasMatch(lines[first].text)) return null;
  for (var index = first + 1; index < lines.length; index += 1) {
    if (RegExp(r'^ {0,3}%%[ \t]*$').hasMatch(lines[index].text)) {
      return index;
    }
  }
  return null;
}

IanvsMarkdownBlock? markdownBlockAtOffset(
  List<IanvsMarkdownBlock> blocks,
  int offset,
) {
  if (blocks.isEmpty) return null;
  for (final block in blocks) {
    if (block.containsOffset(offset)) return block;
    if (offset < block.start) return block;
  }
  return blocks.last;
}

int markdownGapLineCount(
  String source,
  IanvsMarkdownBlock current,
  IanvsMarkdownBlock? next,
) {
  final gapEnd = next?.start ?? source.length;
  if (gapEnd <= current.end) return 0;
  final gap = source.substring(current.end, gapEnd);
  var newlines = 0;
  for (var index = 0; index < gap.length; index += 1) {
    if (gap.codeUnitAt(index) == 0x0a) newlines += 1;
  }
  return newlines;
}

/// Whether a non-header line remains inside a GFM table body.
///
/// Body rows may omit every pipe (GFM example 202). They continue until a
/// blank line or syntax that can interrupt a leaf block; an empty list marker
/// and an ordered marker not starting at `1` do not interrupt the table.
bool ianvsMarkdownTableBodyContinues(String text, {String? nextLine}) {
  if (text.trim().isEmpty ||
      _fence(text) != null ||
      _isDisplayMathFence(text) ||
      _isAtxHeading(text) ||
      _isThematicBreak(text) ||
      _isBlockquote(text) ||
      RegExp(r'^(?: {4}| {0,3}\t)').hasMatch(text) ||
      _isInterruptingHtmlBlockStart(text) ||
      RegExp(r'^ {0,3}\[[^\]\r\n]+\]:').hasMatch(text)) {
    return false;
  }

  final list = RegExp(
    r'^ {0,3}(?:(\d{1,9})[.)]|[*+-])(?:[ \t]+(.*))?$',
  ).firstMatch(text);
  if (list != null &&
      (list.group(2)?.trim().isNotEmpty ?? false) &&
      (list.group(1) == null || list.group(1) == '1')) {
    return false;
  }

  if (nextLine != null) {
    if (_isSetextUnderline(nextLine)) return false;
    final candidate = _sourceLines('$text\n$nextLine');
    if (_isTableStart(candidate, 0)) return false;
  }
  return true;
}

IanvsMarkdownBlock _block(
  String source,
  List<_SourceLine> lines,
  int first,
  int last,
  IanvsMarkdownBlockType type,
) {
  final start = lines[first].start;
  final end = lines[last].contentEnd;
  return IanvsMarkdownBlock(
    type: type,
    start: start,
    end: end,
    firstLine: first,
    lastLine: last,
    source: source.substring(start, end),
  );
}

IanvsMarkdownBlockType _classifyBlock(List<_SourceLine> lines, int index) {
  final text = lines[index].text;
  if (index == 0 && _isFrontMatterOpening(text)) {
    final end = _frontMatterEnd(lines, index);
    if (end > index) return IanvsMarkdownBlockType.frontMatter;
  }
  if (_fence(text) case final _Fence fence) {
    if (fence.length >= 3) return IanvsMarkdownBlockType.fencedCode;
  }
  if (_isIndentedCode(text)) return IanvsMarkdownBlockType.indentedCode;
  if (_isDisplayMathFence(text)) return IanvsMarkdownBlockType.displayMath;
  if (_isAtxHeading(text)) return IanvsMarkdownBlockType.heading;
  if (_isThematicBreak(text)) return IanvsMarkdownBlockType.thematicBreak;
  if (_isBlockquote(text)) return IanvsMarkdownBlockType.blockquote;
  if (_isTaskList(text)) return IanvsMarkdownBlockType.taskList;
  final listMarker = _blockListMarker(text);
  if (listMarker != null) {
    return listMarker.ordered
        ? IanvsMarkdownBlockType.orderedList
        : IanvsMarkdownBlockType.unorderedList;
  }
  if (_isTableStart(lines, index)) return IanvsMarkdownBlockType.table;
  if (_isHtmlStart(text)) return IanvsMarkdownBlockType.html;
  if (index + 1 < lines.length && _isSetextUnderline(lines[index + 1].text)) {
    return IanvsMarkdownBlockType.heading;
  }
  return IanvsMarkdownBlockType.paragraph;
}

int _frontMatterEnd(List<_SourceLine> lines, int first) {
  if (first != 0 || !_isFrontMatterOpening(lines[first].text)) return first;
  for (
    var index = first + 1;
    index < lines.length && index <= first + 256;
    index += 1
  ) {
    final text = lines[index].text;
    if (text == '---') return index;
  }
  return first;
}

int _fencedCodeEnd(List<_SourceLine> lines, int first) {
  final opening = _fence(lines[first].text);
  if (opening == null) return first;
  for (var index = first + 1; index < lines.length; index += 1) {
    final closing = _fence(lines[index].text);
    if (closing != null &&
        closing.character == opening.character &&
        closing.length >= opening.length &&
        closing.trailing.trim().isEmpty) {
      return index;
    }
  }
  return lines.length - 1;
}

int _indentedCodeEnd(List<_SourceLine> lines, int first) {
  var last = first;
  for (var index = first + 1; index < lines.length; index += 1) {
    final text = lines[index].text;
    if (text.trim().isEmpty || _isIndentedCode(text)) {
      last = index;
      continue;
    }
    break;
  }
  while (last > first && lines[last].text.trim().isEmpty) {
    last -= 1;
  }
  return last;
}

int _displayMathEnd(List<_SourceLine> lines, int first) {
  for (var index = first + 1; index < lines.length; index += 1) {
    if (_isDisplayMathFence(lines[index].text)) return index;
  }
  return lines.length - 1;
}

int _blockquoteEnd(List<_SourceLine> lines, int first) {
  var last = first;
  for (var index = first + 1; index < lines.length; index += 1) {
    final text = lines[index].text;
    if (_isBlockquote(text)) {
      last = index;
      continue;
    }
    // Obsidian follows CommonMark's lazy block-quote continuation: a
    // non-blank paragraph line may omit `>` and still belongs to the current
    // quote. A blank line or another block opener ends that continuation.
    if (text.trim().isEmpty || _startsNewBlock(lines, index)) break;
    last = index;
  }
  return last;
}

int _listEnd(List<_SourceLine> lines, int first) {
  final openingMarker = _blockListMarker(lines[first].text);
  if (openingMarker == null) return first;
  var marker = openingMarker;
  var last = first;
  var pendingBlank = false;
  for (var index = first + 1; index < lines.length; index += 1) {
    final text = lines[index].text;
    if (text.trim().isEmpty) {
      pendingBlank = true;
      continue;
    }

    final candidate = _blockListMarker(text);
    if (candidate != null && candidate.leadingColumns < marker.contentIndent) {
      if (candidate.ordered != marker.ordered ||
          candidate.delimiter != marker.delimiter) {
        break;
      }
      marker = candidate;
      last = index;
      pendingBlank = false;
      continue;
    }
    if (pendingBlank && marker.blank) break;
    if (_isIndentedContinuation(text, minimumColumns: marker.contentIndent)) {
      last = index;
      pendingBlank = false;
      continue;
    }
    if (!pendingBlank && !_startsNewBlock(lines, index)) {
      last = index;
      continue;
    }
    break;
  }
  return last;
}

int _listItemEnd(List<_SourceLine> lines, int first) {
  final marker = _blockListMarker(lines[first].text);
  if (marker == null) return first;
  var last = first;
  var pendingBlank = false;
  for (var index = first + 1; index < lines.length; index += 1) {
    final text = lines[index].text;
    if (text.trim().isEmpty) {
      pendingBlank = true;
      continue;
    }
    if (_listItemTypeAtAnyIndent(text) != null) {
      break;
    }
    if (pendingBlank && marker.blank) break;
    if (_isIndentedContinuation(text, minimumColumns: marker.contentIndent)) {
      last = index;
      pendingBlank = false;
      continue;
    }
    if (!pendingBlank && !_startsNewBlock(lines, index)) {
      last = index;
      continue;
    }
    break;
  }
  return last;
}

IanvsMarkdownBlockType? _nestedListItemType(
  List<_SourceLine> lines,
  int index,
  List<IanvsMarkdownBlock> blocks,
) {
  if (index <= 0 || blocks.isEmpty) {
    return null;
  }
  final previous = blocks.last;
  final separatedByBlank = previous.lastLine + 1 < index;
  for (var cursor = previous.lastLine + 1; cursor < index; cursor += 1) {
    if (lines[cursor].text.trim().isNotEmpty) return null;
  }
  final previousType = previous.type;
  if (previousType != IanvsMarkdownBlockType.unorderedList &&
      previousType != IanvsMarkdownBlockType.orderedList &&
      previousType != IanvsMarkdownBlockType.taskList) {
    return null;
  }
  if (separatedByBlank) {
    final previousFirstLine = previous.source.split('\n').first;
    if (_blockListMarker(previousFirstLine)?.blank ?? false) return null;
  }
  return _listItemTypeAtAnyIndent(lines[index].text);
}

IanvsMarkdownBlockType? _listItemTypeAtAnyIndent(String text) {
  final marker = RegExp(
    r'^[ \t]*(?:([-+*])|(\d{1,9})[.)])(?:(?:[ \t]+)(\[[^\r\n]\](?:[ \t]+|$))?|[ \t]*$)',
  ).firstMatch(text);
  if (marker == null) return null;
  if (marker.group(3) != null) return IanvsMarkdownBlockType.taskList;
  return marker.group(1) != null
      ? IanvsMarkdownBlockType.unorderedList
      : IanvsMarkdownBlockType.orderedList;
}

int _tableEnd(List<_SourceLine> lines, int first) {
  var last = first + 1;
  for (var index = first + 2; index < lines.length; index += 1) {
    final text = lines[index].text;
    if (!ianvsMarkdownTableBodyContinues(
      text,
      nextLine: index + 1 < lines.length ? lines[index + 1].text : null,
    )) {
      break;
    }
    last = index;
  }
  return last;
}

int _htmlEnd(List<_SourceLine> lines, int first) {
  var last = first;
  for (var index = first + 1; index < lines.length; index += 1) {
    final text = lines[index].text;
    if (text.trim().isEmpty || _startsNewBlock(lines, index)) break;
    last = index;
  }
  return last;
}

int _paragraphEnd(List<_SourceLine> lines, int first) {
  var last = first;
  for (var index = first + 1; index < lines.length; index += 1) {
    final text = lines[index].text;
    // An indented code block cannot interrupt a paragraph. Four spaces or a
    // tab only opens code after a real block boundary; without one it remains
    // an exact, whitespace-preserving paragraph continuation.
    if (text.trim().isEmpty ||
        _startsNewBlock(lines, index) && !_isIndentedCode(text)) {
      break;
    }
    if (_isTableStart(lines, index - 1)) {
      return _tableEnd(lines, index - 1);
    }
    last = index;
  }
  return last;
}

bool _startsNewBlock(List<_SourceLine> lines, int index) {
  final text = lines[index].text;
  return _fence(text) != null ||
      _isDisplayMathFence(text) ||
      _isAtxHeading(text) ||
      _isThematicBreak(text) ||
      _isBlockquote(text) ||
      _isUnorderedList(text) ||
      _isOrderedList(text) ||
      _isIndentedCode(text) ||
      _isHtmlStart(text) ||
      _isTableStart(lines, index);
}

bool _isFrontMatterOpening(String text) => text == '---';

bool _isDisplayMathFence(String text) =>
    RegExp(r'^ {0,3}\$\$[ \t]*$').hasMatch(text);

bool _isAtxHeading(String text) {
  final opening = RegExp(r'^ {0,3}#{1,6}(?:[ \t]+|$)').firstMatch(text);
  if (opening == null) return false;
  var content = text.substring(opening.end).trimRight();
  content = content.replaceFirst(RegExp(r'(?:^|[ \t]+)#+$'), '').trimRight();
  return content.isNotEmpty;
}

bool _isSetextUnderline(String text) =>
    RegExp(r'^ {0,3}(?:=+|-+)\s*$').hasMatch(text);

bool _isThematicBreak(String text) => RegExp(
  r'^ {0,3}(?:(?:\*\s*){3,}|(?:-\s*){3,}|(?:_\s*){3,})$',
).hasMatch(text);

bool _isBlockquote(String text) => RegExp(r'^ {0,3}>').hasMatch(text);

bool _isTaskList(String text) => RegExp(
  r'^\s{0,3}(?:[-+*]|\d{1,9}[.)])\s+\[[^\r\n]\](?:[ \t]+|$)',
).hasMatch(text);

bool _isUnorderedList(String text) =>
    RegExp(r'^\s{0,3}[-+*]\s+').hasMatch(text);

bool _isOrderedList(String text) =>
    RegExp(r'^\s{0,3}\d{1,9}[.)]\s+').hasMatch(text);

bool _isIndentedContinuation(String text, {required int minimumColumns}) =>
    text.trim().isNotEmpty && _leadingIndentColumns(text) >= minimumColumns;

int _leadingIndentColumns(String text) {
  var columns = 0;
  for (final character in text.codeUnits) {
    if (character == 0x20) {
      columns += 1;
    } else if (character == 0x09) {
      columns += 4 - (columns % 4);
    } else {
      break;
    }
  }
  return columns;
}

_BlockListMarker? _blockListMarker(String text) {
  final match = RegExp(r'^( {0,3})(?:(\d{1,9})[.)]|([*+-]))').firstMatch(text);
  if (match == null) return null;
  final markerEnd = match.end;
  if (markerEnd < text.length) {
    final character = text.codeUnitAt(markerEnd);
    if (character != 0x20 && character != 0x09) return null;
  }

  final leadingColumns = match.group(1)!.length;
  final digits = match.group(2);
  final markerWidth = digits == null ? 1 : digits.length + 1;
  final delimiter = text.codeUnitAt(markerEnd - 1);
  final precedingWhitespace = leadingColumns + markerWidth + 1;
  if (markerEnd == text.length) {
    return _BlockListMarker(
      ordered: digits != null,
      delimiter: delimiter,
      leadingColumns: leadingColumns,
      contentIndent: precedingWhitespace,
      blank: true,
    );
  }

  final contentStart = markerEnd + 1;
  var content = contentStart;
  while (content < text.length) {
    final character = text.codeUnitAt(content);
    if (character != 0x20 && character != 0x09) break;
    content += 1;
  }
  final extraWhitespace = content - contentStart;
  return _BlockListMarker(
    ordered: digits != null,
    delimiter: delimiter,
    leadingColumns: leadingColumns,
    contentIndent: content == text.length || extraWhitespace >= 4
        ? precedingWhitespace
        : precedingWhitespace + extraWhitespace,
    blank: content == text.length,
  );
}

bool _isIndentedCode(String text) =>
    RegExp(r'^(?: {4}| {0,3}\t)').hasMatch(text);

bool _isTableStart(List<_SourceLine> lines, int index) {
  if (index + 1 >= lines.length) {
    return false;
  }
  final headerCellCount = countMarkdownTableCells(lines[index].text);
  final delimiter = lines[index + 1].text;
  return isMarkdownTableDelimiterRow(delimiter) &&
      countMarkdownTableCells(delimiter) == headerCellCount;
}

bool _isHtmlStart(String text) =>
    RegExp(r'^ {0,3}</?[A-Za-z][^>]*>').hasMatch(text);

final RegExp _interruptingHtmlBlockStartPattern = RegExp(
  r'^ {0,3}(?:'
  r'<(?:pre|script|style|textarea)(?:[ \t]|>|$)'
  r'|<!--'
  r'|<\?'
  r'|<![A-Za-z]'
  r'|<!\[CDATA\['
  r'|</?(?:address|article|aside|base|basefont|blockquote|body|caption|center|'
  r'col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|'
  r'footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|'
  r'legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|'
  r'section|source|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)'
  r'(?:[ \t]|>|/>|$))',
  caseSensitive: false,
);

/// HTML block starts that can interrupt an already-open leaf block.
///
/// CommonMark's generic complete-tag condition cannot interrupt a paragraph
/// or table, so inline HTML such as `<em>cell</em>` remains valid cell text.
bool _isInterruptingHtmlBlockStart(String text) =>
    _interruptingHtmlBlockStartPattern.hasMatch(text);

_Fence? _fence(String text) {
  final match = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(text);
  if (match == null) return null;
  final marker = match.group(1)!;
  return _Fence(
    character: marker.codeUnitAt(0),
    length: marker.length,
    trailing: match.group(2) ?? '',
  );
}

List<_SourceLine> _sourceLines(String source) {
  final lines = <_SourceLine>[];
  var start = 0;
  var number = 0;
  while (start < source.length) {
    final newline = source.indexOf('\n', start);
    final lineEnd = newline < 0 ? source.length : newline;
    final contentEnd = lineEnd > start && source.codeUnitAt(lineEnd - 1) == 0x0d
        ? lineEnd - 1
        : lineEnd;
    lines.add(
      _SourceLine(
        start: start,
        contentEnd: contentEnd,
        end: newline < 0 ? source.length : newline + 1,
        text: source.substring(start, contentEnd),
        number: number,
      ),
    );
    number += 1;
    if (newline < 0) break;
    start = newline + 1;
  }
  return lines;
}

final class _SourceLine {
  const _SourceLine({
    required this.start,
    required this.contentEnd,
    required this.end,
    required this.text,
    required this.number,
  });

  final int start;
  final int contentEnd;
  final int end;
  final String text;
  final int number;
}

final class _BlockListMarker {
  const _BlockListMarker({
    required this.ordered,
    required this.delimiter,
    required this.leadingColumns,
    required this.contentIndent,
    required this.blank,
  });

  final bool ordered;
  final int delimiter;
  final int leadingColumns;
  final int contentIndent;
  final bool blank;
}

final class _Fence {
  const _Fence({
    required this.character,
    required this.length,
    required this.trailing,
  });

  final int character;
  final int length;
  final String trailing;
}
