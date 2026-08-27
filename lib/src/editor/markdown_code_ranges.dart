import 'package:flutter/services.dart';

import 'editor_models.dart';

final RegExp _blockquotePrefixPattern = RegExp(r'^ {0,3}>[ \t]?');

/// Finds fenced and indented code blocks in document source coordinates.
///
/// Block quotes are container blocks in CommonMark, so their contents are
/// recursively parsed after removing one quote marker from each quoted line.
/// Every projected UTF-16 code unit is mapped back to the original document;
/// ranges split at removed quote prefixes so those markers remain structural.
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
    if (block.type != IanvsMarkdownBlockType.blockquote) continue;

    final child = _dequoteBlock(projection, block.start, block.end);
    if (child.source.isNotEmpty) {
      _collectBlockCodeRanges(child, ranges);
    }
  }
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

  _MarkdownProjection build() {
    final source = _source.toString();
    assert(_originalCodeUnits.length == source.length);
    return _MarkdownProjection._(
      source,
      List<int>.unmodifiable(_originalCodeUnits),
    );
  }
}
