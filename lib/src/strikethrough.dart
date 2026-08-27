import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// One Obsidian-style strikethrough discovered in Markdown source.
@immutable
final class IanvsMarkdownStrikethroughMatch {
  const IanvsMarkdownStrikethroughMatch({
    required this.openingRun,
    required this.content,
    required this.pairedLength,
    required this.openingVisiblePrefixLength,
    required this.deferredOpeningSurplusLength,
    this.closingRun,
    this.closingDelimiter,
  });

  /// The complete opening run consumed by the syntax.
  final TextRange openingRun;

  final TextRange content;

  /// The even number of `~` consumed at each paired edge.
  final int pairedLength;

  /// The single leading surplus `~` retained by an odd opening run.
  final int openingVisiblePrefixLength;

  /// Extra opening pairs that Obsidian renders after the struck content.
  final int deferredOpeningSurplusLength;

  /// The complete source run containing the closing delimiter.
  final TextRange? closingRun;

  /// The prefix of [closingRun] paired with this opening.
  final TextRange? closingDelimiter;

  bool get isClosed => closingDelimiter != null;

  /// Source associated with the inline syntax for marker reveal/selection.
  TextRange get sourceRange =>
      TextRange(start: openingRun.start, end: closingRun?.end ?? content.end);

  /// Source consumed atomically by the inline parser.
  TextRange get consumedRange => TextRange(
    start: openingRun.start,
    end: closingDelimiter?.end ?? content.end,
  );
}

/// Shared lexical result for Reading and Live Preview.
@immutable
final class IanvsMarkdownStrikethroughScan {
  const IanvsMarkdownStrikethroughScan({
    required this.matches,
    required this.readingHiddenRanges,
    required this.editingOnlyHiddenRanges,
  });

  final List<IanvsMarkdownStrikethroughMatch> matches;

  /// Invalid/orphan delimiter runs that Reading consumes without striking.
  final List<TextRange> readingHiddenRanges;

  /// Additional invalid runs hidden by inactive Live Preview.
  final List<TextRange> editingOnlyHiddenRanges;
}

/// Finds Obsidian 1.13-style `~~strikethrough~~` ranges.
///
/// Single tildes remain literal. Even pairs participate in the delimiter;
/// odd surplus tildes remain visible in Reading, while inactive Live Preview
/// hides the complete participating run. A closed pair may cross a soft line
/// break, and a valid unclosed opening strikes only to the physical line end.
IanvsMarkdownStrikethroughScan ianvsMarkdownStrikethroughScan(
  String source, {
  List<TextRange> excludedRanges = const <TextRange>[],
}) {
  final matches = <IanvsMarkdownStrikethroughMatch>[];
  final readingHidden = <TextRange>[];
  final editingOnlyHidden = <TextRange>[];
  final runs = _tildeRuns(source, excludedRanges);

  var paragraphStart = 0;
  while (paragraphStart < runs.length) {
    final paragraphEnd = _strikethroughParagraphEnd(
      source,
      runs[paragraphStart].start,
    );
    var paragraphLimit = paragraphStart + 1;
    while (paragraphLimit < runs.length &&
        runs[paragraphLimit].start < paragraphEnd) {
      paragraphLimit += 1;
    }
    _scanStrikethroughParagraph(
      source,
      runs.sublist(paragraphStart, paragraphLimit),
      paragraphEnd,
      matches,
      readingHidden,
      editingOnlyHidden,
    );
    paragraphStart = paragraphLimit;
  }

  return IanvsMarkdownStrikethroughScan(
    matches: List<IanvsMarkdownStrikethroughMatch>.unmodifiable(matches),
    readingHiddenRanges: _normalizedStrikethroughRanges(readingHidden),
    editingOnlyHiddenRanges: _normalizedStrikethroughRanges(editingOnlyHidden),
  );
}

final class _TildeRun {
  _TildeRun({
    required this.start,
    required this.end,
    required this.escaped,
    required this.excluded,
  }) : availableStart = start;

  final int start;
  final int end;
  final bool escaped;
  final bool excluded;
  int availableStart;
  bool fromClosing = false;
  bool suppressUnclosed = false;

  int get availableLength => end - availableStart;

  TextRange get availableRange => TextRange(start: availableStart, end: end);
}

List<_TildeRun> _tildeRuns(String source, List<TextRange> excludedRanges) {
  final runs = <_TildeRun>[];
  var search = 0;
  while (search < source.length) {
    final start = source.indexOf('~', search);
    if (start < 0) break;
    var end = start + 1;
    while (end < source.length && source.codeUnitAt(end) == 0x7e) {
      end += 1;
    }
    runs.add(
      _TildeRun(
        start: start,
        end: end,
        escaped: _isEscapedStrikethroughDelimiter(source, start),
        excluded: _overlapsStrikethroughRange(start, end, excludedRanges),
      ),
    );
    search = end;
  }
  return runs;
}

void _scanStrikethroughParagraph(
  String source,
  List<_TildeRun> runs,
  int paragraphEnd,
  List<IanvsMarkdownStrikethroughMatch> matches,
  List<TextRange> readingHidden,
  List<TextRange> editingOnlyHidden,
) {
  var index = 0;
  var sawEarlierAttempt = false;
  var sawEarlierEscapedAttempt = false;

  while (index < runs.length) {
    final opening = runs[index];
    if (opening.availableLength <= 0) {
      index += 1;
      continue;
    }
    if (opening.excluded) {
      index += 1;
      continue;
    }
    if (opening.escaped) {
      if (opening.availableLength >= 2) {
        sawEarlierAttempt = true;
        sawEarlierEscapedAttempt = true;
      }
      index += 1;
      continue;
    }
    if (opening.availableLength < 2) {
      index += 1;
      continue;
    }
    if (opening.suppressUnclosed) {
      editingOnlyHidden.add(opening.availableRange);
      sawEarlierAttempt = true;
      index += 1;
      continue;
    }

    final canOpen =
        opening.end < paragraphEnd &&
        !_isStrikethroughBoundaryWhitespace(source.codeUnitAt(opening.end));
    if (!canOpen) {
      sawEarlierAttempt = true;
      index += 1;
      continue;
    }

    var closingIndex = -1;
    for (
      var candidateIndex = index + 1;
      candidateIndex < runs.length;
      candidateIndex += 1
    ) {
      final candidate = runs[candidateIndex];
      if (candidate.availableLength < 2 ||
          candidate.excluded ||
          candidate.escaped) {
        continue;
      }
      final canClose =
          candidate.start > 0 &&
          !_isStrikethroughBoundaryWhitespace(
            source.codeUnitAt(candidate.start - 1),
          );
      if (canClose) {
        closingIndex = candidateIndex;
        break;
      }
    }

    if (closingIndex >= 0) {
      final closing = runs[closingIndex];
      final openingLength = opening.availableLength;
      final openingPrefix = openingLength.isOdd ? 1 : 0;
      final openingEvenLength = openingLength - openingPrefix;
      final closingEvenLength =
          closing.availableLength - (closing.availableLength.isOdd ? 1 : 0);
      final pairedLength = openingEvenLength < closingEvenLength
          ? openingEvenLength
          : closingEvenLength;
      if (pairedLength >= 2) {
        final closingDelimiter = TextRange(
          start: closing.availableStart,
          end: closing.availableStart + pairedLength,
        );
        final match = IanvsMarkdownStrikethroughMatch(
          openingRun: opening.availableRange,
          content: TextRange(start: opening.end, end: closing.start),
          pairedLength: pairedLength,
          openingVisiblePrefixLength: openingPrefix,
          deferredOpeningSurplusLength: openingEvenLength - pairedLength,
          closingRun: TextRange(
            start: closing.availableStart,
            end: closing.end,
          ),
          closingDelimiter: closingDelimiter,
        );
        matches.add(match);
        closing
          ..availableStart = closingDelimiter.end
          ..fromClosing = closing.availableStart < closing.end;
        if (closing.availableLength > 0) {
          index = closingIndex;
          sawEarlierAttempt = true;
        } else {
          index = closingIndex + 1;
          sawEarlierAttempt = false;
          sawEarlierEscapedAttempt = false;
        }
        continue;
      }
    }

    _TildeRun? laterAttempt;
    for (
      var candidateIndex = index + 1;
      candidateIndex < runs.length;
      candidateIndex += 1
    ) {
      final candidate = runs[candidateIndex];
      if (!candidate.excluded && candidate.availableLength >= 2) {
        laterAttempt = candidate;
        break;
      }
    }
    if (laterAttempt != null) {
      if (laterAttempt.escaped) {
        readingHidden.add(opening.availableRange);
        editingOnlyHidden.add(opening.availableRange);
      } else {
        editingOnlyHidden
          ..add(opening.availableRange)
          ..add(laterAttempt.availableRange);
        laterAttempt.suppressUnclosed = true;
      }
      sawEarlierAttempt = true;
      index += 1;
      continue;
    }

    if (opening.availableLength == 4 && !opening.fromClosing) {
      matches.add(
        IanvsMarkdownStrikethroughMatch(
          openingRun: TextRange(
            start: opening.availableStart,
            end: opening.availableStart + 2,
          ),
          content: TextRange(
            start: opening.availableStart + 2,
            end: opening.availableStart + 2,
          ),
          pairedLength: 2,
          openingVisiblePrefixLength: 0,
          deferredOpeningSurplusLength: 0,
          closingRun: TextRange(
            start: opening.availableStart + 2,
            end: opening.end,
          ),
          closingDelimiter: TextRange(
            start: opening.availableStart + 2,
            end: opening.end,
          ),
        ),
      );
      index += 1;
      sawEarlierAttempt = false;
      sawEarlierEscapedAttempt = false;
      continue;
    }

    if (opening.fromClosing || sawEarlierAttempt) {
      editingOnlyHidden.add(opening.availableRange);
      if (sawEarlierEscapedAttempt) {
        readingHidden.add(opening.availableRange);
      }
      index += 1;
      sawEarlierAttempt = false;
      sawEarlierEscapedAttempt = false;
      continue;
    }

    var contentEnd = paragraphEnd;
    final lineFeed = source.indexOf('\n', opening.end);
    final carriageReturn = source.indexOf('\r', opening.end);
    if (lineFeed >= 0 && lineFeed < contentEnd) contentEnd = lineFeed;
    if (carriageReturn >= 0 && carriageReturn < contentEnd) {
      contentEnd = carriageReturn;
    }
    if (contentEnd > opening.end) {
      final openingPrefix = opening.availableLength.isOdd ? 1 : 0;
      matches.add(
        IanvsMarkdownStrikethroughMatch(
          openingRun: opening.availableRange,
          content: TextRange(start: opening.end, end: contentEnd),
          pairedLength: opening.availableLength - openingPrefix,
          openingVisiblePrefixLength: openingPrefix,
          deferredOpeningSurplusLength: 0,
        ),
      );
    }
    index += 1;
  }
}

bool _isEscapedStrikethroughDelimiter(String source, int offset) {
  var backslashes = 0;
  for (var index = offset - 1; index >= 0; index -= 1) {
    if (source.codeUnitAt(index) != 0x5c) break;
    backslashes += 1;
  }
  return backslashes.isOdd;
}

bool _isStrikethroughBoundaryWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0a ||
    codeUnit == 0x0d;

int _strikethroughParagraphEnd(String source, int start) {
  var lineBreak = source.indexOf('\n', start);
  while (lineBreak >= 0) {
    var next = lineBreak + 1;
    while (next < source.length) {
      final codeUnit = source.codeUnitAt(next);
      if (codeUnit != 0x20 && codeUnit != 0x09 && codeUnit != 0x0d) break;
      next += 1;
    }
    if (next < source.length && source.codeUnitAt(next) == 0x0a) {
      return lineBreak;
    }
    lineBreak = source.indexOf('\n', next);
  }
  return source.length;
}

bool _overlapsStrikethroughRange(int start, int end, List<TextRange> ranges) =>
    ranges.any((range) => start < range.end && end > range.start);

List<TextRange> _normalizedStrikethroughRanges(List<TextRange> ranges) {
  if (ranges.isEmpty) return const <TextRange>[];
  final sorted = <TextRange>[...ranges]
    ..sort((a, b) => a.start.compareTo(b.start));
  final result = <TextRange>[];
  for (final range in sorted) {
    if (result.isEmpty || range.start > result.last.end) {
      result.add(range);
      continue;
    }
    final previous = result.removeLast();
    result.add(
      TextRange(
        start: previous.start,
        end: range.end > previous.end ? range.end : previous.end,
      ),
    );
  }
  return List<TextRange>.unmodifiable(result);
}

enum IanvsMarkdownStrikethroughPresentation { reading, editing }

/// Parses Obsidian-style strikethrough while blocking the GFM single-tilde
/// extension from handling literal `~text~` source.
class IanvsMarkdownStrikethroughSyntax extends md.InlineSyntax {
  IanvsMarkdownStrikethroughSyntax({
    this.presentation = IanvsMarkdownStrikethroughPresentation.reading,
  }) : super(r'~+', startCharacter: 0x7e);

  final IanvsMarkdownStrikethroughPresentation presentation;

  String? _cachedSource;
  IanvsMarkdownStrikethroughScan? _cachedScan;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    if (start != parser.pos) return false;
    if (start >= parser.source.length ||
        parser.source.codeUnitAt(start) != 0x7e) {
      return false;
    }
    if (_cachedSource != parser.source) {
      _cachedSource = parser.source;
      _cachedScan = ianvsMarkdownStrikethroughScan(parser.source);
    }
    final scan = _cachedScan!;
    IanvsMarkdownStrikethroughMatch? strike;
    for (final candidate in scan.matches) {
      if (candidate.openingRun.start == start) {
        strike = candidate;
        break;
      }
      if (candidate.openingRun.start > start) break;
    }
    if (strike != null) {
      parser.writeText();
      if (presentation == IanvsMarkdownStrikethroughPresentation.reading &&
          strike.openingVisiblePrefixLength > 0) {
        parser.addNode(md.Text('~' * strike.openingVisiblePrefixLength));
      }
      final content = strike.content.textInside(parser.source);
      final childDocument = md.Document(
        inlineSyntaxes: parser.document.inlineSyntaxes.where(
          (syntax) => syntax is! IanvsMarkdownStrikethroughSyntax,
        ),
        linkResolver: parser.document.linkResolver,
        imageLinkResolver: parser.document.imageLinkResolver,
        encodeHtml: parser.document.encodeHtml,
        withDefaultBlockSyntaxes: false,
        withDefaultInlineSyntaxes: parser.document.withDefaultInlineSyntaxes,
      )..linkReferences.addAll(parser.document.linkReferences);
      final children = childDocument.parseInline(content);
      _markStrikethroughLinkDescendants(children);
      parser.addNode(md.Element('del', children));
      if (presentation == IanvsMarkdownStrikethroughPresentation.reading &&
          strike.deferredOpeningSurplusLength > 0) {
        parser.addNode(md.Text('~' * strike.deferredOpeningSurplusLength));
      }
      parser.consume(strike.consumedRange.end - start);
      return true;
    }

    final hiddenRanges =
        presentation == IanvsMarkdownStrikethroughPresentation.reading
        ? scan.readingHiddenRanges
        : scan.editingOnlyHiddenRanges;
    TextRange? hidden;
    for (final range in hiddenRanges) {
      if (start >= range.start && start < range.end) {
        hidden = range;
        break;
      }
      if (range.start > start) break;
    }
    if (presentation == IanvsMarkdownStrikethroughPresentation.editing) {
      for (final match in scan.matches) {
        final closing = match.closingRun;
        final consumed = match.closingDelimiter;
        if (closing != null &&
            consumed != null &&
            start >= consumed.end &&
            start < closing.end) {
          final candidate = TextRange(start: start, end: closing.end);
          if (hidden == null || candidate.end > hidden.end) hidden = candidate;
        }
      }
    }
    if (hidden != null) {
      parser.writeText();
      parser.consume(hidden.end - start);
      return true;
    }

    final literalEnd = _tildeRunEnd(parser.source, start);
    parser.writeText();
    parser
      ..addNode(md.Text(parser.source.substring(start, literalEnd)))
      ..consume(literalEnd - start);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;
}

int _tildeRunEnd(String source, int start) {
  var end = start;
  while (end < source.length && source.codeUnitAt(end) == 0x7e) {
    end += 1;
  }
  return end;
}

void _markStrikethroughLinkDescendants(List<md.Node> nodes) {
  for (final node in nodes) {
    if (node is! md.Element) continue;
    if (node.tag == 'a') {
      node.attributes['data-ianvs-outer-strikethrough'] = 'true';
    }
    _markStrikethroughLinkDescendants(node.children ?? const <md.Node>[]);
  }
}
