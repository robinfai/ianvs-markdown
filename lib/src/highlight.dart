import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'inline_code.dart';
import 'markdown_link_source.dart';
import 'obsidian_metadata.dart';
import 'theme.dart';

/// One Obsidian-style highlight discovered in Markdown source.
@immutable
final class IanvsMarkdownHighlightMatch {
  const IanvsMarkdownHighlightMatch({
    required this.openingRun,
    required this.openingDelimiter,
    required this.content,
    this.closingRun,
    this.closingDelimiter,
  });

  /// The complete opening run. Live Preview hides surplus `=` with the pair.
  final TextRange openingRun;

  /// The final two `=` in [openingRun], consumed in Reading view.
  final TextRange openingDelimiter;

  final TextRange content;

  /// The complete closing run, when this is a closed highlight.
  final TextRange? closingRun;

  /// The first two `=` in [closingRun], consumed in Reading view.
  final TextRange? closingDelimiter;

  bool get isClosed => closingDelimiter != null;

  /// Exact source revealed by Live Preview and selected on double click.
  TextRange get sourceRange =>
      TextRange(start: openingRun.start, end: closingRun?.end ?? content.end);

  /// Source consumed by the Reading parser, preserving surplus `=`.
  TextRange get readingRange => TextRange(
    start: openingDelimiter.start,
    end: closingDelimiter?.end ?? content.end,
  );
}

/// Finds the lexical ranges that Obsidian treats as highlights.
///
/// A valid closed pair has non-whitespace content boundaries, may cross a
/// soft line break, and stops before a Markdown paragraph break. A lone valid
/// opening highlights only to the current physical line end. Reading consumes
/// two `=` at each edge and preserves surplus characters; inactive Live
/// Preview uses [openingRun] and [closingRun] to hide each complete run.
List<IanvsMarkdownHighlightMatch> ianvsMarkdownHighlightMatches(
  String source, {
  List<TextRange> excludedRanges = const <TextRange>[],
}) => _scanIanvsMarkdownHighlightDocument(source, excludedRanges).matches;

/// Delimiter runs that form one attempted highlight across a blank line.
///
/// Obsidian keeps both runs literal instead of independently treating each
/// side as an unclosed highlight. Code, math, HTML, link destinations, Wiki
/// targets, and comments retain their higher parsing priority and are not
/// returned.
List<TextRange> ianvsMarkdownCrossParagraphHighlightLiteralRuns(String source) {
  if (!source.contains('\n') || !source.contains('==')) {
    return const <TextRange>[];
  }
  final excludedRanges = <TextRange>[
    ...ianvsMarkdownCommentRanges(source),
    ..._ianvsMarkdownHighlightCodeRanges(source),
  ];
  excludedRanges.addAll(
    _ianvsMarkdownHighlightHigherPriorityRanges(source, excludedRanges),
  );
  excludedRanges.sort((a, b) => a.start.compareTo(b.start));
  return _scanIanvsMarkdownHighlightDocument(
    source,
    excludedRanges,
  ).crossParagraphLiteralRuns;
}

/// Escapes only the rendering copy of cross-paragraph highlight delimiters.
///
/// Inserting one backslash preserves an existing even backslash run while
/// making the first `=` literal to Markdown. Live/source editors continue to
/// own and expose the exact unprojected document text.
String projectObsidianCrossParagraphHighlightsForRendering(
  String source, {
  Iterable<TextRange>? literalRuns,
  int sourceOffset = 0,
}) {
  final runs =
      (literalRuns ?? ianvsMarkdownCrossParagraphHighlightLiteralRuns(source))
          .where(
            (range) =>
                range.start >= sourceOffset &&
                range.end <= sourceOffset + source.length,
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  if (runs.isEmpty) return source;

  final output = StringBuffer();
  var cursor = 0;
  for (final range in runs) {
    final localStart = range.start - sourceOffset;
    if (localStart < cursor || localStart >= source.length) continue;
    output
      ..write(source.substring(cursor, localStart))
      ..write(r'\');
    cursor = localStart;
  }
  output.write(source.substring(cursor));
  return output.toString();
}

List<TextRange> _ianvsMarkdownHighlightCodeRanges(String source) {
  final blockRanges = <TextRange>[];
  final fencePattern = RegExp(r'^ {0,3}(`{3,}|~{3,})');
  final lines = source.split('\n');
  var offset = 0;
  int? fenceStart;
  var fenceCharacter = 0;
  var fenceLength = 0;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final lineEnd = offset + line.length;
    final fence = fencePattern.firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      if (fenceStart == null) {
        fenceStart = offset;
        fenceCharacter = marker.codeUnitAt(0);
        fenceLength = marker.length;
      } else if (marker.codeUnitAt(0) == fenceCharacter &&
          marker.length >= fenceLength) {
        blockRanges.add(TextRange(start: fenceStart, end: lineEnd));
        fenceStart = null;
        fenceCharacter = 0;
        fenceLength = 0;
      }
    } else if (fenceStart == null &&
        (line.startsWith('    ') || line.startsWith('\t'))) {
      blockRanges.add(TextRange(start: offset, end: lineEnd));
    }
    offset = lineEnd + (index + 1 < lines.length ? 1 : 0);
  }
  if (fenceStart != null) {
    blockRanges.add(TextRange(start: fenceStart, end: source.length));
  }

  final protectedRanges = <TextRange>[
    ...blockRanges,
    ...ianvsMarkdownCommentRanges(source),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final inlineRanges = <TextRange>[];
  var protectedIndex = 0;
  var index = 0;
  while (index < source.length) {
    while (protectedIndex < protectedRanges.length &&
        protectedRanges[protectedIndex].end <= index) {
      protectedIndex += 1;
    }
    if (protectedIndex < protectedRanges.length &&
        protectedRanges[protectedIndex].start <= index) {
      index = protectedRanges[protectedIndex].end;
      continue;
    }
    if (source.codeUnitAt(index) != 0x60) {
      index += 1;
      continue;
    }

    final openingStart = index;
    final openingEnd = _characterRunEnd(source, openingStart, 0x60);
    final openingLength = openingEnd - openingStart;
    final inlineLimit = _highlightParagraphEnd(source, openingEnd);
    var search = openingEnd;
    var closingEnd = -1;
    while (search < inlineLimit) {
      final candidate = source.indexOf('`', search);
      if (candidate < 0 || candidate >= inlineLimit) break;
      final candidateEnd = _characterRunEnd(source, candidate, 0x60);
      if (candidateEnd - candidate == openingLength &&
          !_overlapsHighlightRange(candidate, candidateEnd, protectedRanges)) {
        closingEnd = candidateEnd;
        break;
      }
      search = candidateEnd;
    }
    if (closingEnd < 0) {
      index = openingEnd;
      continue;
    }
    inlineRanges.add(TextRange(start: openingStart, end: closingEnd));
    index = closingEnd;
  }
  return <TextRange>[...blockRanges, ...inlineRanges];
}

List<TextRange> _ianvsMarkdownHighlightHigherPriorityRanges(
  String source,
  List<TextRange> baseRanges,
) {
  final ranges = <TextRange>[];
  final protected = <TextRange>[...baseRanges];
  void protect(TextRange range) {
    if (!range.isValid || range.isCollapsed) return;
    ranges.add(range);
    protected.add(range);
  }

  final displayFence = RegExp(r'^ {0,3}\$\$[ \t]*$');
  final lines = source.split('\n');
  var offset = 0;
  int? displayStart;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final lineEnd = offset + line.length;
    if (displayFence.hasMatch(line) &&
        !_overlapsHighlightRange(offset, lineEnd, protected)) {
      if (displayStart == null) {
        displayStart = offset;
      } else {
        protect(TextRange(start: displayStart, end: lineEnd));
        displayStart = null;
      }
    }
    offset = lineEnd + (index + 1 < lines.length ? 1 : 0);
  }

  final mathPatterns = <RegExp>[
    RegExp(r'\$\$(?!\s)((?:\\.|[^\\$`\n])*?(?:\\.|[^\s\\$`\n]))\$\$'),
    RegExp(r'\$(?!\$|\s)((?:\\.|[^\\$`\n])*?(?:\\.|[^\s\\$`\n]))\$(?!\$|\d)'),
  ];
  for (final pattern in mathPatterns) {
    for (final match in pattern.allMatches(source)) {
      if (_highlightDollarOpeningIsEscapedOrContinued(source, match.start) ||
          _overlapsHighlightRange(match.start, match.end, protected)) {
        continue;
      }
      protect(TextRange(start: match.start, end: match.end));
    }
  }

  for (final match in RegExp(r'<[^>\n]+>').allMatches(source)) {
    if (!_overlapsHighlightRange(match.start, match.end, protected)) {
      protect(TextRange(start: match.start, end: match.end));
    }
  }

  final definitionPattern = RegExp(
    r'^ {0,3}\[[^\]\r\n]+\]:[^\r\n]*$',
    multiLine: true,
  );
  for (final match in definitionPattern.allMatches(source)) {
    if (!_overlapsHighlightRange(match.start, match.end, protected)) {
      protect(TextRange(start: match.start, end: match.end));
    }
  }

  var bracket = source.indexOf('[');
  while (bracket >= 0) {
    if (_highlightOffsetIsEscaped(source, bracket) ||
        _overlapsHighlightRange(bracket, bracket + 1, protected)) {
      bracket = source.indexOf('[', bracket + 1);
      continue;
    }
    if (bracket + 1 < source.length && source.codeUnitAt(bracket + 1) == 0x5b) {
      final close = source.indexOf(']]', bracket + 2);
      if (close >= 0 && !source.substring(bracket + 2, close).contains('\n')) {
        final bodyStart = bracket + 2;
        final body = source.substring(bodyStart, close);
        final separator = body.indexOf('|');
        final targetEnd = separator > 0 ? bodyStart + separator : close;
        protect(TextRange(start: bodyStart, end: targetEnd));
        bracket = source.indexOf('[', close + 2);
        continue;
      }
    }

    final labelEnd = findIanvsMarkdownLinkLabelEnd(source, bracket);
    final suffixStart = labelEnd == null ? -1 : labelEnd + 1;
    if (suffixStart >= 0 &&
        suffixStart < source.length &&
        source.codeUnitAt(suffixStart) == 0x28) {
      final linkEnd = findIanvsMarkdownInlineLinkEnd(source, suffixStart);
      if (linkEnd != null) {
        protect(TextRange(start: suffixStart, end: linkEnd));
        bracket = source.indexOf('[', linkEnd);
        continue;
      }
    }
    bracket = source.indexOf('[', bracket + 1);
  }

  return ranges;
}

bool _highlightDollarOpeningIsEscapedOrContinued(String source, int offset) {
  if (offset <= 0) return false;
  if (source.codeUnitAt(offset - 1) == 0x24) return true;
  return _highlightOffsetIsEscaped(source, offset);
}

bool _highlightOffsetIsEscaped(String source, int offset) {
  var backslashes = 0;
  for (var index = offset - 1; index >= 0; index -= 1) {
    if (source.codeUnitAt(index) != 0x5c) break;
    backslashes += 1;
  }
  return backslashes.isOdd;
}

int _characterRunEnd(String source, int start, int character) {
  var end = start;
  while (end < source.length && source.codeUnitAt(end) == character) {
    end += 1;
  }
  return end;
}

final class _IanvsMarkdownHighlightDocumentScan {
  const _IanvsMarkdownHighlightDocumentScan({
    required this.matches,
    required this.crossParagraphLiteralRuns,
  });

  final List<IanvsMarkdownHighlightMatch> matches;
  final List<TextRange> crossParagraphLiteralRuns;
}

_IanvsMarkdownHighlightDocumentScan _scanIanvsMarkdownHighlightDocument(
  String source,
  List<TextRange> excludedRanges,
) {
  final matches = <IanvsMarkdownHighlightMatch>[];
  final crossParagraphLiteralRuns = <TextRange>[];
  IanvsMarkdownHighlightMatch? previousMatch;
  var search = 0;
  while (search < source.length) {
    final candidate = source.indexOf('==', search);
    if (candidate < 0) break;
    final runEnd = _equalsRunEnd(source, candidate);
    final openingStart = runEnd - 2;
    if (candidate != openingStart) {
      search = candidate + 1;
      continue;
    }
    final scan = _scanIanvsMarkdownHighlightAt(
      source,
      openingStart,
      excludedRanges,
    );
    final literalOpeningRun = scan.crossParagraphLiteralOpeningRun;
    final literalClosingRun = scan.crossParagraphLiteralClosingRun;
    if (literalOpeningRun != null && literalClosingRun != null) {
      final sharesPreviousClosingRun =
          previousMatch?.closingRun != null &&
          previousMatch!.closingRun == literalOpeningRun;
      if (sharesPreviousClosingRun) {
        search = literalOpeningRun.end;
        continue;
      }
      crossParagraphLiteralRuns
        ..add(literalOpeningRun)
        ..add(literalClosingRun);
    }
    final match = scan.match;
    if (match == null) {
      search = scan.nextSearch > runEnd ? scan.nextSearch : runEnd;
      continue;
    }
    final sharesPreviousClosingRun =
        previousMatch?.closingRun != null &&
        previousMatch!.closingRun == match.openingRun;
    if (sharesPreviousClosingRun && !match.isClosed) {
      search = match.openingRun.end;
      continue;
    }
    matches.add(match);
    previousMatch = match;
    search = match.closingDelimiter?.end ?? match.content.end;
    if (search <= candidate) search = candidate + 2;
  }
  return _IanvsMarkdownHighlightDocumentScan(
    matches: List<IanvsMarkdownHighlightMatch>.unmodifiable(matches),
    crossParagraphLiteralRuns: List<TextRange>.unmodifiable(
      crossParagraphLiteralRuns,
    ),
  );
}

final class _IanvsMarkdownHighlightScan {
  const _IanvsMarkdownHighlightScan({
    this.match,
    this.crossParagraphLiteralOpeningRun,
    this.crossParagraphLiteralClosingRun,
    required this.nextSearch,
  });

  final IanvsMarkdownHighlightMatch? match;
  final TextRange? crossParagraphLiteralOpeningRun;
  final TextRange? crossParagraphLiteralClosingRun;
  final int nextSearch;
}

_IanvsMarkdownHighlightScan _scanIanvsMarkdownHighlightAt(
  String source,
  int openingStart,
  List<TextRange> excludedRanges,
) {
  if (openingStart < 0 || openingStart + 1 >= source.length) {
    return _IanvsMarkdownHighlightScan(nextSearch: openingStart + 1);
  }
  if (source.codeUnitAt(openingStart) != 0x3d ||
      source.codeUnitAt(openingStart + 1) != 0x3d) {
    return _IanvsMarkdownHighlightScan(nextSearch: openingStart + 1);
  }
  final openingRunStart = _equalsRunStart(source, openingStart);
  final openingRunEnd = _equalsRunEnd(source, openingStart);
  if (openingStart != openingRunEnd - 2 ||
      _isEscapedHighlightDelimiter(source, openingRunStart) ||
      _overlapsHighlightRange(openingRunStart, openingRunEnd, excludedRanges)) {
    return _IanvsMarkdownHighlightScan(nextSearch: openingRunEnd);
  }

  final contentStart = openingRunEnd;
  final paragraphEnd = _highlightParagraphEnd(source, contentStart);
  if (contentStart >= source.length ||
      _isHighlightBoundaryWhitespace(source.codeUnitAt(contentStart))) {
    return _IanvsMarkdownHighlightScan(
      nextSearch: _nextHighlightDelimiterRunEnd(
        source,
        contentStart,
        paragraphEnd,
        excludedRanges,
      ),
    );
  }

  var search = contentStart;
  var sawInvalidClosing = false;
  var invalidClosingEnd = openingRunEnd;
  while (search < paragraphEnd) {
    final candidate = source.indexOf('==', search);
    if (candidate < 0 || candidate >= paragraphEnd) break;
    final closingRunStart = _equalsRunStart(source, candidate);
    final closingRunEnd = _equalsRunEnd(source, candidate);
    if (closingRunStart < contentStart) {
      search = closingRunEnd;
      continue;
    }
    if (_isEscapedHighlightDelimiter(source, closingRunStart) ||
        _overlapsHighlightRange(
          closingRunStart,
          closingRunEnd,
          excludedRanges,
        )) {
      search = closingRunEnd;
      continue;
    }
    if (closingRunStart > contentStart &&
        !_isHighlightBoundaryWhitespace(
          source.codeUnitAt(closingRunStart - 1),
        )) {
      final match = IanvsMarkdownHighlightMatch(
        openingRun: TextRange(start: openingRunStart, end: openingRunEnd),
        openingDelimiter: TextRange(start: openingStart, end: openingStart + 2),
        content: TextRange(start: contentStart, end: closingRunStart),
        closingRun: TextRange(start: closingRunStart, end: closingRunEnd),
        closingDelimiter: TextRange(
          start: closingRunStart,
          end: closingRunStart + 2,
        ),
      );
      return _IanvsMarkdownHighlightScan(
        match: match,
        nextSearch: match.readingRange.end,
      );
    }
    sawInvalidClosing = true;
    invalidClosingEnd = closingRunEnd;
    search = closingRunEnd;
  }

  // Obsidian keeps a whitespace-bounded attempted pair literal instead of
  // turning its opening into an unclosed highlight.
  if (sawInvalidClosing) {
    return _IanvsMarkdownHighlightScan(nextSearch: invalidClosingEnd);
  }
  final crossParagraphClosingRun = _isolatedCrossParagraphClosingRun(
    source,
    paragraphEnd,
    excludedRanges,
  );
  if (crossParagraphClosingRun != null) {
    return _IanvsMarkdownHighlightScan(
      crossParagraphLiteralOpeningRun: TextRange(
        start: openingRunStart,
        end: openingRunEnd,
      ),
      crossParagraphLiteralClosingRun: crossParagraphClosingRun,
      nextSearch: crossParagraphClosingRun.end,
    );
  }
  final lineFeed = source.indexOf('\n', contentStart);
  final carriageReturn = source.indexOf('\r', contentStart);
  var contentEnd = paragraphEnd;
  if (lineFeed >= 0 && lineFeed < contentEnd) contentEnd = lineFeed;
  if (carriageReturn >= 0 && carriageReturn < contentEnd) {
    contentEnd = carriageReturn;
  }
  if (contentEnd <= contentStart) {
    return _IanvsMarkdownHighlightScan(nextSearch: openingRunEnd);
  }
  if (openingRunEnd - openingRunStart >= 4) {
    return _IanvsMarkdownHighlightScan(nextSearch: openingRunEnd);
  }
  final match = IanvsMarkdownHighlightMatch(
    openingRun: TextRange(start: openingRunStart, end: openingRunEnd),
    openingDelimiter: TextRange(start: openingStart, end: openingStart + 2),
    content: TextRange(start: contentStart, end: contentEnd),
  );
  return _IanvsMarkdownHighlightScan(
    match: match,
    nextSearch: match.readingRange.end,
  );
}

int _nextHighlightDelimiterRunEnd(
  String source,
  int search,
  int limit,
  List<TextRange> excludedRanges,
) {
  var cursor = search;
  while (cursor < limit) {
    final candidate = source.indexOf('==', cursor);
    if (candidate < 0 || candidate >= limit) return search;
    final runStart = _equalsRunStart(source, candidate);
    final runEnd = _equalsRunEnd(source, candidate);
    if (!_isEscapedHighlightDelimiter(source, runStart) &&
        !_overlapsHighlightRange(runStart, runEnd, excludedRanges)) {
      return runEnd;
    }
    cursor = runEnd;
  }
  return search;
}

TextRange? _isolatedCrossParagraphClosingRun(
  String source,
  int paragraphEnd,
  List<TextRange> excludedRanges,
) {
  if (paragraphEnd >= source.length) return null;
  var nextParagraphStart = paragraphEnd;
  while (nextParagraphStart < source.length &&
      _isHighlightBoundaryWhitespace(source.codeUnitAt(nextParagraphStart))) {
    nextParagraphStart += 1;
  }
  if (nextParagraphStart >= source.length) return null;

  final nextParagraphEnd = _highlightParagraphEnd(source, nextParagraphStart);
  TextRange? onlyRun;
  var search = nextParagraphStart;
  while (search < nextParagraphEnd) {
    final candidate = source.indexOf('==', search);
    if (candidate < 0 || candidate >= nextParagraphEnd) break;
    final runStart = _equalsRunStart(source, candidate);
    final runEnd = _equalsRunEnd(source, candidate);
    search = runEnd;
    if (_isEscapedHighlightDelimiter(source, runStart) ||
        _overlapsHighlightRange(runStart, runEnd, excludedRanges)) {
      continue;
    }
    if (onlyRun != null) return null;
    onlyRun = TextRange(start: runStart, end: runEnd);
  }

  final closingRun = onlyRun;
  if (closingRun == null ||
      closingRun.start <= nextParagraphStart ||
      _isHighlightBoundaryWhitespace(source.codeUnitAt(closingRun.start - 1))) {
    return null;
  }
  return closingRun;
}

int _equalsRunStart(String source, int offset) {
  var start = offset;
  while (start > 0 && source.codeUnitAt(start - 1) == 0x3d) {
    start -= 1;
  }
  return start;
}

int _equalsRunEnd(String source, int offset) {
  var end = offset;
  while (end < source.length && source.codeUnitAt(end) == 0x3d) {
    end += 1;
  }
  return end;
}

bool _isEscapedHighlightDelimiter(String source, int offset) {
  var backslashes = 0;
  for (var index = offset - 1; index >= 0; index -= 1) {
    if (source.codeUnitAt(index) != 0x5c) break;
    backslashes += 1;
  }
  return backslashes.isOdd;
}

bool _isHighlightBoundaryWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0a ||
    codeUnit == 0x0d;

int _highlightParagraphEnd(String source, int start) {
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

bool _overlapsHighlightRange(int start, int end, List<TextRange> ranges) =>
    ranges.any((range) => start < range.end && end > range.start);

enum IanvsMarkdownHighlightPresentation { reading, editing }

/// Parses Obsidian-style highlights such as `==important==`.
class IanvsMarkdownHighlightSyntax extends md.InlineSyntax {
  IanvsMarkdownHighlightSyntax({
    this.presentation = IanvsMarkdownHighlightPresentation.reading,
  }) : super(r'==', startCharacter: 0x3d);

  final IanvsMarkdownHighlightPresentation presentation;

  String? _cachedSource;
  List<IanvsMarkdownHighlightMatch> _cachedMatches =
      const <IanvsMarkdownHighlightMatch>[];

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    if (start != parser.pos) return false;
    if (_cachedSource != parser.source) {
      _cachedSource = parser.source;
      _cachedMatches = ianvsMarkdownHighlightMatches(parser.source);
    }
    IanvsMarkdownHighlightMatch? match;
    for (final candidate in _cachedMatches) {
      final candidateStart =
          presentation == IanvsMarkdownHighlightPresentation.editing
          ? candidate.openingRun.start
          : candidate.openingDelimiter.start;
      if (candidateStart == start) {
        match = candidate;
        break;
      }
      if (candidateStart > start) break;
    }
    if (match == null) return false;
    parser.writeText();
    final content = match.content.textInside(parser.source);
    final childDocument = md.Document(
      inlineSyntaxes: parser.document.inlineSyntaxes.where(
        (syntax) => syntax is! IanvsMarkdownHighlightSyntax,
      ),
      linkResolver: parser.document.linkResolver,
      imageLinkResolver: parser.document.imageLinkResolver,
      encodeHtml: parser.document.encodeHtml,
      withDefaultBlockSyntaxes: false,
      withDefaultInlineSyntaxes: parser.document.withDefaultInlineSyntaxes,
    )..linkReferences.addAll(parser.document.linkReferences);
    parser
      ..addNode(md.Element('mark', childDocument.parseInline(content)))
      ..consume(
        (presentation == IanvsMarkdownHighlightPresentation.editing
                ? match.sourceRange.end
                : match.readingRange.end) -
            start,
      );
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;
}

class IanvsMarkdownHighlightBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHighlightBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final background = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff6b5b22)
        : const Color(0xffffe184);
    return KeyedSubtree(
      child: Text.rich(
        TextSpan(
          style: (parentStyle ?? preferredStyle ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            backgroundColor: background,
          ),
          children: _highlightSpans(element.children, colors),
        ),
        key: const ValueKey('ianvs-markdown-highlight'),
      ),
    );
  }
}

List<InlineSpan> _highlightSpans(
  List<md.Node>? nodes,
  IanvsMarkdownThemeData colors,
) {
  return <InlineSpan>[
    for (final node in nodes ?? const <md.Node>[])
      if (node is md.Text)
        TextSpan(text: node.text)
      else if (node is md.Element)
        TextSpan(
          style: _highlightElementStyle(node.tag, colors),
          children: _highlightSpans(node.children, colors),
        ),
  ];
}

TextStyle? _highlightElementStyle(String tag, IanvsMarkdownThemeData colors) {
  return switch (tag) {
    'strong' || 'ianvs-html-strong' => TextStyle(
      color: colors.strongForeground,
      fontWeight: FontWeight.w600,
    ),
    'em' => TextStyle(
      color: colors.emphasisForeground,
      fontStyle: FontStyle.italic,
    ),
    'del' => const TextStyle(decoration: TextDecoration.lineThrough),
    'code' ||
    'ianvs-inline-code' ||
    'ianvs-html-code' => ianvsMarkdownInlineCodeStyle(colors),
    'a' => TextStyle(
      color: colors.accentDark,
      decoration: TextDecoration.underline,
    ),
    _ => null,
  };
}
