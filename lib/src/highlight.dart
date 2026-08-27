import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'inline_code.dart';
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
}) {
  final matches = <IanvsMarkdownHighlightMatch>[];
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
  return List<IanvsMarkdownHighlightMatch>.unmodifiable(matches);
}

final class _IanvsMarkdownHighlightScan {
  const _IanvsMarkdownHighlightScan({this.match, required this.nextSearch});

  final IanvsMarkdownHighlightMatch? match;
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
    'strong' => TextStyle(
      color: colors.strongForeground,
      fontWeight: FontWeight.w600,
    ),
    'em' => TextStyle(
      color: colors.emphasisForeground,
      fontStyle: FontStyle.italic,
    ),
    'del' => const TextStyle(decoration: TextDecoration.lineThrough),
    'code' || 'ianvs-inline-code' => ianvsMarkdownInlineCodeStyle(colors),
    'a' => TextStyle(
      color: colors.accentDark,
      decoration: TextDecoration.underline,
    ),
    _ => null,
  };
}
