import 'package:flutter/foundation.dart';

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
/// remain outside replacement ranges.
List<IanvsMarkdownBlock> parseMarkdownBlocks(
  String source, {
  bool splitListItems = false,
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
    final standaloneCommentEnd = _standaloneCommentEnd(lines, first);
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
  if (_isUnorderedList(text)) return IanvsMarkdownBlockType.unorderedList;
  if (_isOrderedList(text)) return IanvsMarkdownBlockType.orderedList;
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
  final ordered = _isOrderedList(lines[first].text);
  var last = first;
  for (var index = first + 1; index < lines.length; index += 1) {
    final text = lines[index].text;
    if (text.trim().isEmpty) break;
    if (_isIndentedContinuation(text) ||
        (ordered ? _isOrderedList(text) : _isUnorderedList(text))) {
      last = index;
      continue;
    }
    break;
  }
  return last;
}

int _listItemEnd(List<_SourceLine> lines, int first) {
  var last = first;
  for (var index = first + 1; index < lines.length; index += 1) {
    final text = lines[index].text;
    if (text.trim().isEmpty || _listItemTypeAtAnyIndent(text) != null) {
      break;
    }
    if (_isIndentedContinuation(text)) {
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
  if (index <= 0 ||
      blocks.isEmpty ||
      blocks.last.lastLine != index - 1 ||
      lines[index - 1].text.trim().isEmpty) {
    return null;
  }
  final previousType = blocks.last.type;
  if (previousType != IanvsMarkdownBlockType.unorderedList &&
      previousType != IanvsMarkdownBlockType.orderedList &&
      previousType != IanvsMarkdownBlockType.taskList) {
    return null;
  }
  return _listItemTypeAtAnyIndent(lines[index].text);
}

IanvsMarkdownBlockType? _listItemTypeAtAnyIndent(String text) {
  final marker = RegExp(
    r'^[ \t]*(?:([-+*])|(\d{1,9})[.)])[ \t]+(\[[^\r\n]\](?:[ \t]+|$))?',
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
    if (text.trim().isEmpty || !text.contains('|')) break;
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

bool _isTaskList(String text) =>
    RegExp(r'^\s{0,3}(?:[-+*]|\d{1,9}[.)])\s+\[[^\r\n]\]\s+').hasMatch(text);

bool _isUnorderedList(String text) =>
    RegExp(r'^\s{0,3}[-+*]\s+').hasMatch(text);

bool _isOrderedList(String text) =>
    RegExp(r'^\s{0,3}\d{1,9}[.)]\s+').hasMatch(text);

bool _isIndentedContinuation(String text) =>
    RegExp(r'^(?: {2,}|\t)\S').hasMatch(text);

bool _isIndentedCode(String text) =>
    text.startsWith('    ') || text.startsWith('\t');

bool _isTableStart(List<_SourceLine> lines, int index) {
  if (index + 1 >= lines.length || !lines[index].text.contains('|')) {
    return false;
  }
  final delimiter = lines[index + 1].text.trim();
  return RegExp(r'^\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)+\|?$').hasMatch(delimiter);
}

bool _isHtmlStart(String text) =>
    RegExp(r'^ {0,3}</?[A-Za-z][^>]*>').hasMatch(text);

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
