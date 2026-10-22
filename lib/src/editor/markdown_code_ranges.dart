import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import '../callout.dart';
import '../markdown_table_syntax.dart';
import '../math.dart' show IanvsMarkdownDisplayMathSyntax;
import '../obsidian_metadata.dart'
    show ianvsMarkdownLivePreviewFootnoteReferences;
import '../wiki_embed.dart' show IanvsMarkdownWikiEmbedSyntax;
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
  const _MarkdownProjection._(
    this.source,
    this._originalCodeUnits,
    this._originalCodeUnitEnds,
  );

  factory _MarkdownProjection.root(String source) {
    return _MarkdownProjection._(source, null, null);
  }

  final String source;
  final List<int>? _originalCodeUnits;
  final List<int>? _originalCodeUnitEnds;

  int originalCodeUnitOffset(int offset) {
    return _originalCodeUnits?[offset] ?? offset;
  }

  int originalCodeUnitEnd(int offset) {
    return _originalCodeUnitEnds?[offset] ?? originalCodeUnitOffset(offset) + 1;
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
  final List<int> _originalCodeUnitEnds = <int>[];

  void appendRange(int start, int end) {
    for (var index = start; index < end; index += 1) {
      _source.writeCharCode(parent.source.codeUnitAt(index));
      _originalCodeUnits.add(parent.originalCodeUnitOffset(index));
      _originalCodeUnitEnds.add(parent.originalCodeUnitEnd(index));
    }
  }

  // TableSyntax removes this escape before inline parsing. Keep the whole
  // source token attached to the resulting pipe, including at range edges.
  void appendTablePipe(int slashIndex) {
    _source.write('|');
    _originalCodeUnits.add(parent.originalCodeUnitOffset(slashIndex));
    _originalCodeUnitEnds.add(parent.originalCodeUnitEnd(slashIndex + 1));
  }

  void appendSyntheticSpaces(int count, int parentCodeUnitIndex) {
    final originalOffset = parent.originalCodeUnitOffset(parentCodeUnitIndex);
    for (var index = 0; index < count; index += 1) {
      _source.writeCharCode(0x20);
      _originalCodeUnits.add(originalOffset);
      _originalCodeUnitEnds.add(
        parent.originalCodeUnitEnd(parentCodeUnitIndex),
      );
    }
  }

  _MarkdownProjection build() {
    final source = _source.toString();
    assert(_originalCodeUnits.length == source.length);
    return _MarkdownProjection._(
      source,
      List<int>.unmodifiable(_originalCodeUnits),
      List<int>.unmodifiable(_originalCodeUnitEnds),
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

/// Internal source-mapped leaf block used by semantic analysis.
///
/// Container prefixes are removed using the same projection as code exclusion.
/// All offsets still map to the unchanged original UTF-16 source.
final class IanvsMarkdownSemanticSourceRegion {
  IanvsMarkdownSemanticSourceRegion._(
    this._projection,
    this.type, {
    this.unsupportedContext,
  });

  final _MarkdownProjection _projection;
  final IanvsMarkdownBlockType type;
  final String? unsupportedContext;
  String get source => _projection.source;

  // Internal only: this class is not exported by the package. Every source
  // token must be adjacent and unchanged, except a proven table \| token.
  bool matchesOriginalSource(int start, int end, String originalSource) {
    if (start == end) return true;
    var cursor = _projection.originalCodeUnitOffset(start);
    for (var index = start; index < end; index++) {
      final tokenStart = _projection.originalCodeUnitOffset(index);
      final tokenEnd = _projection.originalCodeUnitEnd(index);
      if (tokenStart != cursor) return false;
      final token = originalSource.substring(tokenStart, tokenEnd);
      if (token != source[index] &&
          !(type == IanvsMarkdownBlockType.table &&
              token == r'\|' &&
              source[index] == '|')) {
        return false;
      }
      cursor = tokenEnd;
    }
    return true;
  }

  TextRange originalRange(int start, int end) {
    final length = source.length;
    final first = start < length
        ? _projection.originalCodeUnitOffset(start)
        : length == 0
        ? 0
        : _projection.originalCodeUnitEnd(length - 1);
    return TextRange(
      start: first,
      end: start == end ? first : _projection.originalCodeUnitEnd(end - 1),
    );
  }
}

/// Internal leaf-block projections for a bounded semantic parse.
List<IanvsMarkdownSemanticSourceRegion> ianvsMarkdownSemanticSourceRegions(
  String source, {
  List<TextRange> removedRanges = const [],
}) {
  final root = _MarkdownProjection.root(source);
  final builder = _MarkdownProjectionBuilder(root);
  var cursor = 0;
  for (final range in removedRanges) {
    builder.appendRange(cursor, range.start);
    // Reading comments preserve line breaks, not horizontal placeholder spaces.
    for (var index = range.start; index < range.end; index++) {
      if (source.codeUnitAt(index) == 0x0a ||
          source.codeUnitAt(index) == 0x0d) {
        builder.appendRange(index, index + 1);
      }
    }
    cursor = range.end;
  }
  builder.appendRange(cursor, source.length);
  final regions = <IanvsMarkdownSemanticSourceRegion>[];
  final projected = builder.build();
  // The renderer expands inline footnotes before table splitting, potentially
  // moving content out of a column that the table parser would otherwise drop.
  // Detect the actual shared grammar before any such loss of source coverage.
  for (final footnote in ianvsMarkdownLivePreviewFootnoteReferences(
    projected.source,
  )) {
    if (!projected.source.startsWith('^[', footnote.sourceRange.start)) {
      continue;
    }
    final context = _MarkdownProjectionBuilder(projected)
      ..appendRange(footnote.sourceRange.start, footnote.sourceRange.end);
    regions.add(
      IanvsMarkdownSemanticSourceRegion._(
        context.build(),
        IanvsMarkdownBlockType.paragraph,
        unsupportedContext: 'inlineFootnoteContext',
      ),
    );
    break; // One explicit limitation is sufficient to invalidate completeness.
  }
  _collectSemanticSourceRegions(
    projected,
    regions,
    _rendererTablePadding(projected),
  );
  return regions;
}

void _collectSemanticSourceRegions(
  _MarkdownProjection projection,
  List<IanvsMarkdownSemanticSourceRegion> regions,
  Map<int, ({int columns, bool separator})> tablePadding, [
  int depth = 0,
  bool scanTables = true,
]) {
  if (depth > 64) {
    throw const FormatException('Semantic container depth exceeds 64.');
  }
  if (scanTables) {
    final tables = _nativeTableSourceRegions(projection, tablePadding);
    if (tables.isNotEmpty) {
      var cursor = 0;
      void collectGap(int end) {
        if (cursor >= end) return;
        final gap = _MarkdownProjectionBuilder(projection)
          ..appendRange(cursor, end);
        _collectSemanticSourceRegions(
          gap.build(),
          regions,
          tablePadding,
          depth,
          false,
        );
      }

      for (final table in tables) {
        collectGap(table.start);
        regions.addAll(table.regions);
        cursor = table.end;
      }
      collectGap(projection.source.length);
      return;
    }
  }
  for (final block in parseMarkdownBlocks(
    projection.source,
    groupStandaloneComments: false,
  )) {
    if (block.type == IanvsMarkdownBlockType.blockquote) {
      if (parseIanvsMarkdownCalloutHeader(block.source) != null) {
        // Callout titles and bodies instantiate their own renderer, including
        // another preprocessing/padding pass and an independent definition map.
        // Ordinary dequoting is not a source proof for those recursive contexts.
        final context = _MarkdownProjectionBuilder(projection)
          ..appendRange(block.start, block.end);
        regions.add(
          IanvsMarkdownSemanticSourceRegion._(
            context.build(),
            block.type,
            unsupportedContext: 'calloutContext',
          ),
        );
        continue;
      }
      final child = _dequoteBlock(projection, block.start, block.end);
      if (child.source.isNotEmpty) {
        _collectSemanticSourceRegions(child, regions, tablePadding, depth + 1);
      }
      continue;
    }
    final paragraphMarker = block.type == IanvsMarkdownBlockType.paragraph
        ? _paragraphListMarker(projection, block.start, block.end)
        : null;
    if (block.type == IanvsMarkdownBlockType.unorderedList ||
        block.type == IanvsMarkdownBlockType.orderedList ||
        block.type == IanvsMarkdownBlockType.taskList ||
        paragraphMarker != null) {
      for (final child in _listItemProjections(
        projection,
        block.start,
        block.end,
        ordered:
            paragraphMarker?.ordered ??
            block.type == IanvsMarkdownBlockType.orderedList,
      )) {
        if (child.source.isNotEmpty) {
          _collectSemanticSourceRegions(
            child,
            regions,
            tablePadding,
            depth + 1,
          );
        }
      }
      continue;
    }
    final builder = _MarkdownProjectionBuilder(projection)
      ..appendRange(block.start, block.end);
    regions.add(
      IanvsMarkdownSemanticSourceRegion._(
        builder.build(),
        block.type == IanvsMarkdownBlockType.table
            ? IanvsMarkdownBlockType.paragraph
            : block.type,
      ),
    );
  }
}

// Run the actual block parser, not the editor's approximate table classifier.
// In particular, escaped trailing pipes and heading-like headers can differ.
// Nested parsers are collected after the existing container source projection.
List<({int start, int end, List<IanvsMarkdownSemanticSourceRegion> regions})>
_nativeTableSourceRegions(
  _MarkdownProjection parent,
  Map<int, ({int columns, bool separator})> tablePadding,
) {
  if (!parent.source.contains('|')) return const [];
  final lines = _projectionLines(parent, 0, parent.source.length);
  if (lines.length < 2) return const [];
  final nativeLines = <md.Line>[];
  for (final line in lines) {
    var text = line.text;
    final padding = text.isEmpty
        ? null
        : tablePadding[parent.originalCodeUnitEnd(line.contentEnd - 1)];
    if (padding != null) {
      while (countMarkdownTableCells(text) < padding.columns) {
        final length = text.trimRight().length;
        final cell = padding.separator ? '---' : '';
        text = length > 0 && text[length - 1] == '|'
            ? '${text.substring(0, length)} $cell |${text.substring(length)}'
            : cell.isEmpty
            ? '$text |  |'
            : '$text | $cell';
      }
    }
    nativeLines.add(md.Line(text));
  }
  final syntax = _SourceTableSyntax(parent, lines, nativeLines);
  md.BlockParser(
    nativeLines,
    md.Document(
      extensionSet: md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes
            .where((syntax) => syntax is! md.TableSyntax)
            .toList(),
        md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
      ),
      blockSyntaxes: [
        const md.CodeBlockSyntax(),
        const IanvsMarkdownDisplayMathSyntax(),
        const IanvsMarkdownWikiEmbedSyntax(),
        const IanvsMarkdownCalloutSyntax(),
        syntax,
      ],
    ),
  ).parseLines();
  return syntax.tables;
}

final class _SourceTableSyntax extends md.TableSyntax {
  _SourceTableSyntax(this.parent, this.lines, this.nativeLines);
  final _MarkdownProjection parent;
  final List<_ProjectionLine> lines;
  final List<md.Line> nativeLines;
  final tables =
      <
        ({int start, int end, List<IanvsMarkdownSemanticSourceRegion> regions})
      >[];

  @override
  md.Node? parse(md.BlockParser parser) {
    final root = identical(parser.lines, nativeLines);
    final first = root ? nativeLines.indexOf(parser.current) : -1;
    final node = super.parse(parser);
    if (!root || node is! md.Element || node.tag != 'table') return node;
    final next = parser.isDone
        ? lines.length
        : nativeLines.indexOf(parser.current);
    final rows = <md.Element>[
      for (final section in node.children!.cast<md.Element>())
        ...section.children!.cast<md.Element>(),
    ];
    if (first < 0 || next < 0 || rows.length != next - first - 1) {
      throw const FormatException('Table rows could not be source-mapped.');
    }
    final regions = <IanvsMarkdownSemanticSourceRegion>[];
    for (var row = 0; row < rows.length; row++) {
      final line = lines[first + (row == 0 ? 0 : row + 1)];
      final cells = _tableRowProjections(parent, line);
      final nativeCells = rows[row].children!.cast<md.Element>().toList();
      for (var column = 0; column < nativeCells.length; column++) {
        final children = nativeCells[column].children!;
        if (children.isEmpty ||
            (children.length == 1 &&
                column >= cells.length &&
                children.single.textContent.isEmpty)) {
          continue; // Synthetic empty cells have no source occurrence.
        }
        if (children.length != 1 ||
            children.single is! md.UnparsedContent ||
            column >= cells.length ||
            cells[column].source != children.single.textContent) {
          throw const FormatException(
            'Table cell source projection disagrees.',
          );
        }
        regions.add(
          IanvsMarkdownSemanticSourceRegion._(
            cells[column],
            IanvsMarkdownBlockType.table,
          ),
        );
      }
    }
    tables.add((
      start: lines[first].start,
      end: lines[next - 1].end,
      regions: regions,
    ));
    return node;
  }
}

List<_MarkdownProjection> _tableRowProjections(
  _MarkdownProjection parent,
  _ProjectionLine line,
) {
  final text = line.text;
  var index = 0;
  int skipWhitespace(int at) {
    while (at < text.length &&
        (text.codeUnitAt(at) == 0x20 || text.codeUnitAt(at) == 0x09)) {
      at++;
    }
    return at;
  }

  index = skipWhitespace(index);
  if (index < text.length && text.codeUnitAt(index) == 0x7c) {
    index = skipWhitespace(index + 1);
  }
  final cells = <_MarkdownProjection>[];
  var builder = _MarkdownProjectionBuilder(parent);
  void finishCell() {
    final cell = builder.build();
    final trimmed = _MarkdownProjectionBuilder(cell)
      ..appendRange(0, cell.source.trimRight().length);
    cells.add(trimmed.build());
    builder = _MarkdownProjectionBuilder(parent);
  }

  while (true) {
    if (index >= text.length) {
      finishCell();
      break;
    }
    final unit = text.codeUnitAt(index);
    if (unit == 0x5c && index + 1 < text.length) {
      if (text.codeUnitAt(index + 1) == 0x7c) {
        builder.appendTablePipe(line.start + index);
      } else {
        builder.appendRange(line.start + index, line.start + index + 2);
      }
      index += 2;
    } else if (unit == 0x7c) {
      finishCell();
      index = skipWhitespace(index + 1);
      if (index >= text.length) break;
    } else {
      builder.appendRange(line.start + index, line.start + index + 1);
      index++;
    }
  }
  return cells;
}

// Mirror _projectIrregularObsidianTables before removing container prefixes.
// The view pads only eligible raw source rows, not arbitrary nested tables.
// Keys use the original end of each affected line so dedenting retains identity.
Map<int, ({int columns, bool separator})> _rendererTablePadding(
  _MarkdownProjection projection,
) {
  final source = projection.source;
  if (!source.contains('|')) return const {};
  final lines = _projectionLines(projection, 0, source.length);
  final raw = [
    for (final line in lines)
      source.substring(
        line.start,
        line.end > line.start && source.codeUnitAt(line.end - 1) == 0x0a
            ? line.end - 1
            : line.end,
      ),
  ];
  final code = ianvsMarkdownBlockCodeRanges(source);
  bool codeLine(int index) => code.any(
    (range) => range.start < lines[index].end && range.end > lines[index].start,
  );
  final result = <int, ({int columns, bool separator})>{};
  for (var row = 0; row + 1 < lines.length; row++) {
    final headerCount = countMarkdownTableCells(raw[row]);
    if (codeLine(row) ||
        codeLine(row + 1) ||
        !isMarkdownTableDelimiterRow(raw[row + 1]) ||
        countMarkdownTableCells(raw[row + 1]) != headerCount) {
      continue;
    }
    var end = row + 1;
    while (end + 1 < lines.length &&
        !codeLine(end + 1) &&
        ianvsMarkdownTableBodyContinues(
          raw[end + 1],
          nextLine: end + 2 < lines.length ? raw[end + 2] : null,
        )) {
      end++;
    }
    var columns = headerCount;
    for (var body = row + 2; body <= end; body++) {
      final count = countMarkdownTableCells(raw[body]);
      if (count > columns) columns = count;
    }
    for (var padded = row; padded <= end; padded++) {
      result[projection.originalCodeUnitEnd(lines[padded].contentEnd - 1)] = (
        columns: columns,
        separator: padded == row + 1,
      );
    }
    row = end;
  }
  return result;
}
