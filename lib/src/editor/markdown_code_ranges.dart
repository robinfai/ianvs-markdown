import 'package:flutter/services.dart';

import 'editor_models.dart';

final RegExp _blockquotePrefixPattern = RegExp(r'^ {0,3}>[ \t]?');
final RegExp _listMarkerPrefixPattern = RegExp(
  r'^( {0,3})(?:(\d{1,9})([.)])|([*+-]))',
);

/// Finds fenced and indented code blocks in document source coordinates.
///
/// Block quotes and list items are container blocks in CommonMark, so their
/// contents are recursively parsed after removing one container prefix from
/// each line. Every projected UTF-16 code unit is mapped back to the original
/// document; ranges split at removed prefixes so those markers stay structural.
List<TextRange> ianvsMarkdownBlockCodeRanges(String source) {
  if (source.isEmpty) return const <TextRange>[];
  final ranges = <TextRange>[];
  _collectBlockCodeRanges(_MarkdownProjection.root(source), ranges);
  ranges.sort((a, b) => a.start.compareTo(b.start));
  return List<TextRange>.unmodifiable(ranges);
}

void _collectBlockCodeRanges(
  _MarkdownProjection projection,
  List<TextRange> ranges,
) {
  for (final block in parseMarkdownBlocks(
    projection.source,
    groupStandaloneComments: false,
  )) {
    if (block.type == IanvsMarkdownBlockType.fencedCode ||
        block.type == IanvsMarkdownBlockType.indentedCode) {
      ranges.addAll(projection.originalRanges(block.start, block.end));
      continue;
    }
    if (block.type == IanvsMarkdownBlockType.blockquote) {
      final child = _dequoteBlock(projection, block.start, block.end);
      if (child.source.isNotEmpty) {
        _collectBlockCodeRanges(child, ranges);
      }
      continue;
    }
    final paragraphMarker = block.type == IanvsMarkdownBlockType.paragraph
        ? _paragraphListMarker(projection, block.start, block.end)
        : null;
    final isList =
        block.type == IanvsMarkdownBlockType.unorderedList ||
        block.type == IanvsMarkdownBlockType.orderedList ||
        block.type == IanvsMarkdownBlockType.taskList ||
        paragraphMarker != null;
    if (isList) {
      final ordered =
          paragraphMarker?.ordered ??
          block.type == IanvsMarkdownBlockType.orderedList;
      for (final child in _listItemProjections(
        projection,
        block.start,
        block.end,
        ordered: ordered,
      )) {
        if (child.source.isNotEmpty) {
          _collectBlockCodeRanges(child, ranges);
        }
      }
    }
  }
}

_ListMarker? _paragraphListMarker(
  _MarkdownProjection projection,
  int start,
  int end,
) {
  final lines = _projectionLines(projection, start, end);
  if (lines.isEmpty) return null;
  final marker = _listMarker(lines.first.text);
  return marker != null && marker.blank ? marker : null;
}

List<_MarkdownProjection> _listItemProjections(
  _MarkdownProjection parent,
  int start,
  int end, {
  required bool ordered,
}) {
  final items = <_MarkdownProjection>[];
  _MarkdownProjectionBuilder? builder;
  _ListMarker? currentMarker;

  void finishItem() {
    final current = builder;
    if (current != null) items.add(current.build());
  }

  for (final line in _projectionLines(parent, start, end)) {
    final marker = _listMarker(line.text);
    final startsItem =
        marker != null &&
        marker.ordered == ordered &&
        (currentMarker == null ||
            _leadingIndentColumns(line.text) < currentMarker.indent);
    if (startsItem) {
      finishItem();
      builder = _MarkdownProjectionBuilder(parent);
      currentMarker = marker;
      _appendListItemFirstLine(builder, line, marker);
      continue;
    }

    final currentBuilder = builder;
    final itemMarker = currentMarker;
    if (currentBuilder == null || itemMarker == null) continue;
    _appendListItemContinuation(currentBuilder, line, itemMarker.indent);
  }
  finishItem();
  return items;
}

void _appendListItemFirstLine(
  _MarkdownProjectionBuilder builder,
  _ProjectionLine line,
  _ListMarker marker,
) {
  if (!marker.blank) {
    builder.appendRange(line.start + marker.contentStart, line.contentEnd);
  }
  builder.appendRange(line.contentEnd, line.end);
}

void _appendListItemContinuation(
  _MarkdownProjectionBuilder builder,
  _ProjectionLine line,
  int indent,
) {
  if (line.text.trim().isEmpty) {
    builder.appendRange(line.start, line.contentEnd);
  } else if (_leadingIndentColumns(line.text) >= indent) {
    final dedent = _dedent(line.text, indent);
    if (dedent.remainingSpaces > 0 && dedent.partialTabIndex != null) {
      builder.appendSyntheticSpaces(
        dedent.remainingSpaces,
        line.start + dedent.partialTabIndex!,
      );
    }
    builder.appendRange(line.start + dedent.contentStart, line.contentEnd);
  } else {
    // A non-blank under-indented line is a lazy paragraph continuation.
    builder.appendRange(line.start, line.contentEnd);
  }
  builder.appendRange(line.contentEnd, line.end);
}

_ListMarker? _listMarker(String text) {
  final match = _listMarkerPrefixPattern.firstMatch(text);
  if (match == null) return null;
  final markerEnd = match.end;
  if (markerEnd < text.length) {
    final character = text.codeUnitAt(markerEnd);
    if (character != 0x20 && character != 0x09) return null;
  }

  final leading = match.group(1)!.length;
  final digits = match.group(2);
  final markerWidth = digits == null ? 1 : digits.length + 1;
  final ordered = digits != null;
  if (markerEnd == text.length) {
    return _ListMarker(
      ordered: ordered,
      markerEnd: markerEnd,
      contentStart: markerEnd,
      indent: leading + markerWidth + 1,
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
  final blank = content == text.length;
  final extraWhitespace = content - contentStart;
  final precedingWhitespace = leading + markerWidth + 1;
  return _ListMarker(
    ordered: ordered,
    markerEnd: markerEnd,
    contentStart: contentStart,
    indent: blank || extraWhitespace >= 4
        ? precedingWhitespace
        : precedingWhitespace + extraWhitespace,
    blank: blank,
  );
}

int _leadingIndentColumns(String text) {
  var columns = 0;
  for (var index = 0; index < text.length; index += 1) {
    final character = text.codeUnitAt(index);
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

_Dedent _dedent(String text, int length) {
  var contentStart = 0;
  var indentLength = 0;
  var remainingSpaces = 0;
  int? partialTabIndex;
  while (contentStart < text.length && contentStart < length) {
    final character = text.codeUnitAt(contentStart);
    if (character != 0x20 && character != 0x09) break;
    final isTab = character == 0x09;
    indentLength += isTab ? 4 : 1;
    if (indentLength >= length) {
      if (isTab && indentLength > length) {
        remainingSpaces = indentLength - length;
        partialTabIndex = contentStart;
      }
      contentStart += 1;
      break;
    }
    contentStart += 1;
  }
  return _Dedent(
    contentStart: contentStart,
    remainingSpaces: remainingSpaces,
    partialTabIndex: partialTabIndex,
  );
}

List<_ProjectionLine> _projectionLines(
  _MarkdownProjection projection,
  int start,
  int end,
) {
  final lines = <_ProjectionLine>[];
  var lineStart = start;
  while (lineStart < end) {
    final newline = projection.source.indexOf('\n', lineStart);
    final lineEnd = newline < 0 || newline >= end ? end : newline;
    final contentEnd =
        lineEnd > lineStart && projection.source.codeUnitAt(lineEnd - 1) == 0x0d
        ? lineEnd - 1
        : lineEnd;
    final lineSourceEnd = lineEnd < end ? lineEnd + 1 : end;
    lines.add(
      _ProjectionLine(
        start: lineStart,
        contentEnd: contentEnd,
        end: lineSourceEnd,
        text: projection.source.substring(lineStart, contentEnd),
      ),
    );
    lineStart = lineSourceEnd;
  }
  return lines;
}

_MarkdownProjection _dequoteBlock(
  _MarkdownProjection parent,
  int start,
  int end,
) {
  final builder = _MarkdownProjectionBuilder(parent);
  var lineStart = start;
  while (lineStart < end) {
    final newline = parent.source.indexOf('\n', lineStart);
    final lineEnd = newline < 0 || newline >= end ? end : newline;
    final contentEnd =
        lineEnd > lineStart && parent.source.codeUnitAt(lineEnd - 1) == 0x0d
        ? lineEnd - 1
        : lineEnd;
    final line = parent.source.substring(lineStart, contentEnd);
    final prefix = _blockquotePrefixPattern.firstMatch(line);
    builder.appendRange(lineStart + (prefix?.end ?? 0), contentEnd);
    if (lineEnd < end) {
      builder.appendRange(contentEnd, lineEnd + 1);
      lineStart = lineEnd + 1;
    } else {
      lineStart = end;
    }
  }
  return builder.build();
}

final class _MarkdownProjection {
  const _MarkdownProjection._(this.source, this._originalCodeUnits);

  factory _MarkdownProjection.root(String source) {
    return _MarkdownProjection._(source, null);
  }

  final String source;
  final List<int>? _originalCodeUnits;

  int originalCodeUnitOffset(int offset) {
    return _originalCodeUnits?[offset] ?? offset;
  }

  List<TextRange> originalRanges(int start, int end) {
    if (start >= end) return const <TextRange>[];
    final ranges = <TextRange>[];
    var segmentStart = originalCodeUnitOffset(start);
    var previous = segmentStart;
    for (var index = start + 1; index < end; index += 1) {
      final current = originalCodeUnitOffset(index);
      if (current == previous) continue;
      if (current != previous + 1) {
        ranges.add(TextRange(start: segmentStart, end: previous + 1));
        segmentStart = current;
      }
      previous = current;
    }
    ranges.add(TextRange(start: segmentStart, end: previous + 1));
    return ranges;
  }
}

final class _MarkdownProjectionBuilder {
  _MarkdownProjectionBuilder(this.parent);

  final _MarkdownProjection parent;
  final StringBuffer _source = StringBuffer();
  final List<int> _originalCodeUnits = <int>[];

  void appendRange(int start, int end) {
    for (var index = start; index < end; index += 1) {
      _source.writeCharCode(parent.source.codeUnitAt(index));
      _originalCodeUnits.add(parent.originalCodeUnitOffset(index));
    }
  }

  void appendSyntheticSpaces(int count, int parentCodeUnitIndex) {
    final originalOffset = parent.originalCodeUnitOffset(parentCodeUnitIndex);
    for (var index = 0; index < count; index += 1) {
      _source.writeCharCode(0x20);
      _originalCodeUnits.add(originalOffset);
    }
  }

  _MarkdownProjection build() {
    final source = _source.toString();
    assert(_originalCodeUnits.length == source.length);
    return _MarkdownProjection._(
      source,
      List<int>.unmodifiable(_originalCodeUnits),
    );
  }
}

final class _ProjectionLine {
  const _ProjectionLine({
    required this.start,
    required this.contentEnd,
    required this.end,
    required this.text,
  });

  final int start;
  final int contentEnd;
  final int end;
  final String text;
}

final class _ListMarker {
  const _ListMarker({
    required this.ordered,
    required this.markerEnd,
    required this.contentStart,
    required this.indent,
    required this.blank,
  });

  final bool ordered;
  final int markerEnd;
  final int contentStart;
  final int indent;
  final bool blank;
}

final class _Dedent {
  const _Dedent({
    required this.contentStart,
    required this.remainingSpaces,
    required this.partialTabIndex,
  });

  final int contentStart;
  final int remainingSpaces;
  final int? partialTabIndex;
}
