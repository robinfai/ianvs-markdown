import 'package:flutter/services.dart' show TextRange;
import 'package:markdown/markdown.dart' as md;

/// The presentation applied by a matched Markdown emphasis delimiter pair.
enum IanvsMarkdownEmphasisKind { emphasis, strong }

/// The Obsidian surface whose long-run marker projection should be used.
enum IanvsMarkdownEmphasisPresentation { reading, editing }

/// One delimiter pair consumed by Obsidian's emphasis/strong parser.
///
/// Multiple entries may share the same content range. For example,
/// `***text***` consumes a strong pair and an emphasis pair around `text`.
final class IanvsMarkdownEmphasisMatch {
  const IanvsMarkdownEmphasisMatch({
    required this.marker,
    required this.kind,
    required this.openingDelimiter,
    required this.content,
    required this.closingDelimiter,
    required this.sourceRange,
  });

  /// The delimiter character (`*` or `_`).
  final String marker;

  final IanvsMarkdownEmphasisKind kind;

  /// The exact opening marker characters consumed by this pair.
  final TextRange openingDelimiter;

  /// The original source between the complete opening and closing runs.
  final TextRange content;

  /// The exact closing marker characters consumed by this pair.
  final TextRange closingDelimiter;

  /// The contiguous source range exposed when this pair is edited.
  ///
  /// It includes any delimiter surplus that lies between a consumed opening
  /// prefix and the formatted content. Surplus after the consumed closing
  /// prefix remains outside this range.
  final TextRange sourceRange;
}

/// The delimiter pairs and marker ranges produced by one emphasis scan.
final class IanvsMarkdownEmphasisScan {
  const IanvsMarkdownEmphasisScan({
    required this.matches,
    required this.hiddenMarkerRanges,
  });

  final List<IanvsMarkdownEmphasisMatch> matches;

  /// Exact delimiter characters consumed by the shared source-range stack.
  /// Unmatched and surplus characters are deliberately omitted. Rendered
  /// Reading and inactive Live Preview surfaces can apply their own long-run
  /// projection through [IanvsMarkdownEmphasisSyntax].
  final List<TextRange> hiddenMarkerRanges;
}

/// Applies Obsidian's presentation-specific marker projection for a single
/// `*` or `_` delimiter-run pair.
///
/// Obsidian's Reading and inactive Live Preview surfaces deliberately expose
/// different subsets of long runs. Complex same-character nesting and
/// crossing continue through Markdown's delimiter stack; this syntax takes
/// first refusal only when one run pair contains no further copy of its own
/// marker.
final class IanvsMarkdownEmphasisSyntax extends md.InlineSyntax {
  IanvsMarkdownEmphasisSyntax({required this.presentation}) : super(r'[*_]+');

  final IanvsMarkdownEmphasisPresentation presentation;
  String? _cachedSource;
  IanvsMarkdownEmphasisScan? _cachedScan;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    if (start != parser.pos || start >= parser.source.length) return false;
    final markerCode = parser.source.codeUnitAt(start);
    if (markerCode != 0x2a && markerCode != 0x5f) return false;
    final marker = String.fromCharCode(markerCode);
    final scan = _scan(parser.source);
    final groups = <(int, int), List<IanvsMarkdownEmphasisMatch>>{};
    for (final match in scan.matches) {
      if (match.marker != marker || match.openingDelimiter.start < start) {
        continue;
      }
      groups
          .putIfAbsent((match.content.start, match.content.end), () => [])
          .add(match);
    }
    if (groups.isEmpty) return false;

    (int, int)? selectedKey;
    for (final entry in groups.entries) {
      final firstOpening = entry.value
          .map((match) => match.openingDelimiter.start)
          .reduce((a, b) => a < b ? a : b);
      if (firstOpening != start) continue;
      if (selectedKey == null || entry.key.$2 < selectedKey.$2) {
        selectedKey = entry.key;
      }
    }
    if (selectedKey == null) return false;
    final matches = groups[selectedKey]!;
    final contentStart = selectedKey.$1;
    final contentEnd = selectedKey.$2;
    if (contentStart <= start || contentEnd < contentStart) return false;
    final content = parser.source.substring(contentStart, contentEnd);
    if (content.contains(marker)) return false;

    var openingEnd = start;
    while (openingEnd < parser.source.length &&
        parser.source.codeUnitAt(openingEnd) == markerCode) {
      openingEnd += 1;
    }
    if (openingEnd != contentStart) return false;
    var closingEnd = contentEnd;
    while (closingEnd < parser.source.length &&
        parser.source.codeUnitAt(closingEnd) == markerCode) {
      closingEnd += 1;
    }
    if (closingEnd == contentEnd) return false;

    final policy = _emphasisPresentationPolicy(
      openingLength: openingEnd - start,
      closingLength: closingEnd - contentEnd,
      presentation: presentation,
      fallbackKinds: matches.map((match) => match.kind).toSet(),
      fallbackOpeningConsumed: matches.fold<int>(
        0,
        (sum, match) =>
            sum + match.openingDelimiter.end - match.openingDelimiter.start,
      ),
      fallbackClosingConsumed: matches.fold<int>(
        0,
        (sum, match) =>
            sum + match.closingDelimiter.end - match.closingDelimiter.start,
      ),
    );
    parser.writeText();
    if (policy.visibleOpening > 0) {
      parser.addNode(
        md.Text(List<String>.filled(policy.visibleOpening, marker).join()),
      );
    }
    final children = parser.document.parseInline(content);
    final styled = _emphasisNodes(children, policy.kinds);
    for (final node in styled) {
      parser.addNode(node);
    }
    if (policy.visibleClosing > 0) {
      parser.addNode(
        md.Text(List<String>.filled(policy.visibleClosing, marker).join()),
      );
    }
    parser.consume(closingEnd - start);
    return true;
  }

  IanvsMarkdownEmphasisScan _scan(String source) {
    if (_cachedSource != source || _cachedScan == null) {
      _cachedSource = source;
      _cachedScan = ianvsMarkdownEmphasisScan(source);
    }
    return _cachedScan!;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;
}

List<md.Node> _emphasisNodes(
  List<md.Node> children,
  Set<IanvsMarkdownEmphasisKind> kinds,
) {
  if (kinds.isEmpty) return children;
  md.Node node;
  if (kinds.contains(IanvsMarkdownEmphasisKind.strong)) {
    node = md.Element('strong', children);
  } else {
    node = md.Element('em', children);
  }
  if (kinds.length > 1) {
    node = md.Element('em', <md.Node>[node]);
  }
  return <md.Node>[node];
}

_EmphasisPresentationPolicy _emphasisPresentationPolicy({
  required int openingLength,
  required int closingLength,
  required IanvsMarkdownEmphasisPresentation presentation,
  required Set<IanvsMarkdownEmphasisKind> fallbackKinds,
  required int fallbackOpeningConsumed,
  required int fallbackClosingConsumed,
}) {
  final reading = presentation == IanvsMarkdownEmphasisPresentation.reading;
  if (openingLength == closingLength) {
    final length = openingLength;
    switch (length) {
      case 1:
        return const _EmphasisPresentationPolicy(
          visibleOpening: 0,
          visibleClosing: 0,
          kinds: <IanvsMarkdownEmphasisKind>{
            IanvsMarkdownEmphasisKind.emphasis,
          },
        );
      case 2:
        return const _EmphasisPresentationPolicy(
          visibleOpening: 0,
          visibleClosing: 0,
          kinds: <IanvsMarkdownEmphasisKind>{IanvsMarkdownEmphasisKind.strong},
        );
      case 3:
        return const _EmphasisPresentationPolicy(
          visibleOpening: 0,
          visibleClosing: 0,
          kinds: <IanvsMarkdownEmphasisKind>{
            IanvsMarkdownEmphasisKind.emphasis,
            IanvsMarkdownEmphasisKind.strong,
          },
        );
      case 4:
        return _EmphasisPresentationPolicy(
          visibleOpening: reading ? 2 : 1,
          visibleClosing: reading ? 2 : 1,
          kinds: <IanvsMarkdownEmphasisKind>{
            reading
                ? IanvsMarkdownEmphasisKind.strong
                : IanvsMarkdownEmphasisKind.emphasis,
          },
        );
      case 5:
        return _EmphasisPresentationPolicy(
          visibleOpening: reading ? 1 : 2,
          visibleClosing: reading ? 1 : 2,
          kinds: <IanvsMarkdownEmphasisKind>{
            reading
                ? IanvsMarkdownEmphasisKind.emphasis
                : IanvsMarkdownEmphasisKind.strong,
          },
        );
      case 6:
        return _EmphasisPresentationPolicy(
          visibleOpening: reading ? 2 : 3,
          visibleClosing: reading ? 2 : 3,
          kinds: const <IanvsMarkdownEmphasisKind>{
            IanvsMarkdownEmphasisKind.emphasis,
            IanvsMarkdownEmphasisKind.strong,
          },
        );
      case 7:
        return _EmphasisPresentationPolicy(
          visibleOpening: reading ? 3 : 0,
          visibleClosing: reading ? 3 : 0,
          kinds: const <IanvsMarkdownEmphasisKind>{},
        );
      case 8 when reading:
        return const _EmphasisPresentationPolicy(
          visibleOpening: 4,
          visibleClosing: 4,
          kinds: <IanvsMarkdownEmphasisKind>{},
        );
    }
  }

  _EmphasisPresentationPolicy? observed(
    int visibleOpening,
    int visibleClosing,
    Set<IanvsMarkdownEmphasisKind> kinds,
  ) => _EmphasisPresentationPolicy(
    visibleOpening: visibleOpening,
    visibleClosing: visibleClosing,
    kinds: kinds,
  );

  const emphasis = <IanvsMarkdownEmphasisKind>{
    IanvsMarkdownEmphasisKind.emphasis,
  };
  const strong = <IanvsMarkdownEmphasisKind>{IanvsMarkdownEmphasisKind.strong};
  const both = <IanvsMarkdownEmphasisKind>{
    IanvsMarkdownEmphasisKind.emphasis,
    IanvsMarkdownEmphasisKind.strong,
  };
  final exact = switch ((openingLength, closingLength)) {
    (3, 2) || (2, 3) => observed(0, 0, strong),
    (4, 1) => observed(1, 0, emphasis),
    (1, 4) => observed(0, 1, emphasis),
    (2, 4) => observed(0, reading ? 2 : 1, strong),
    (4, 2) => observed(reading ? 2 : 1, 0, strong),
    (3, 4) => observed(reading ? 1 : 0, reading ? 2 : 1, both),
    (4, 3) => observed(reading ? 2 : 1, reading ? 1 : 0, both),
    (6, 9) => observed(3, 3, both),
    _ => null,
  };
  if (exact != null) return exact;
  return _EmphasisPresentationPolicy(
    visibleOpening: openingLength - fallbackOpeningConsumed,
    visibleClosing: closingLength - fallbackClosingConsumed,
    kinds: fallbackKinds,
  );
}

final class _EmphasisPresentationPolicy {
  const _EmphasisPresentationPolicy({
    required this.visibleOpening,
    required this.visibleClosing,
    required this.kinds,
  });

  final int visibleOpening;
  final int visibleClosing;
  final Set<IanvsMarkdownEmphasisKind> kinds;
}

/// Scans `*` and `_` delimiter runs using the same stack rules as Markdown
/// emphasis. Asterisks may pair inside words; underscores retain CommonMark's
/// stricter intraword boundary.
///
/// The scanner retains original source offsets so Reading, Live Preview marker
/// hiding, caret reveal, and source-range selection can share one result.
IanvsMarkdownEmphasisScan ianvsMarkdownEmphasisScan(
  String source, {
  Iterable<TextRange> excludedRanges = const <TextRange>[],
}) {
  final exclusions = excludedRanges.where((range) => range.isValid).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final runs = _collectEmphasisRuns(source, exclusions);
  final stack = <_EmphasisRun>[];
  final matches = <IanvsMarkdownEmphasisMatch>[];

  var stackSegment = -1;
  for (final run in runs) {
    if (run.segment != stackSegment) {
      _processEmphasisStack(stack, matches);
      stack
        ..clear()
        ..add(run);
      stackSegment = run.segment;
      continue;
    }
    stack.add(run);
  }
  _processEmphasisStack(stack, matches);

  final normalizedMatches = _normalizeEmphasisSourceRanges(matches);
  matches
    ..clear()
    ..addAll(normalizedMatches);

  matches.sort((a, b) {
    final openingOrder = a.openingDelimiter.start.compareTo(
      b.openingDelimiter.start,
    );
    if (openingOrder != 0) return openingOrder;
    final closingOrder = a.closingDelimiter.start.compareTo(
      b.closingDelimiter.start,
    );
    if (closingOrder != 0) return closingOrder;
    return b.openingDelimiter.end.compareTo(a.openingDelimiter.end);
  });
  final hidden = <TextRange>[
    for (final match in matches) ...<TextRange>[
      match.openingDelimiter,
      match.closingDelimiter,
    ],
  ]..sort((a, b) => a.start.compareTo(b.start));

  return IanvsMarkdownEmphasisScan(
    matches: List<IanvsMarkdownEmphasisMatch>.unmodifiable(matches),
    hiddenMarkerRanges: List<TextRange>.unmodifiable(_mergeRanges(hidden)),
  );
}

List<IanvsMarkdownEmphasisMatch> _normalizeEmphasisSourceRanges(
  List<IanvsMarkdownEmphasisMatch> matches,
) {
  final bounds = <(String, int, int), TextRange>{};
  for (final match in matches) {
    final key = (match.marker, match.content.start, match.content.end);
    final previous = bounds[key];
    bounds[key] = previous == null
        ? match.sourceRange
        : TextRange(
            start: previous.start < match.sourceRange.start
                ? previous.start
                : match.sourceRange.start,
            end: previous.end > match.sourceRange.end
                ? previous.end
                : match.sourceRange.end,
          );
  }
  return <IanvsMarkdownEmphasisMatch>[
    for (final match in matches)
      IanvsMarkdownEmphasisMatch(
        marker: match.marker,
        kind: match.kind,
        openingDelimiter: match.openingDelimiter,
        content: match.content,
        closingDelimiter: match.closingDelimiter,
        sourceRange:
            bounds[(match.marker, match.content.start, match.content.end)]!,
      ),
  ];
}

List<_EmphasisRun> _collectEmphasisRuns(
  String source,
  List<TextRange> exclusions,
) {
  final runs = <_EmphasisRun>[];
  final paragraphBreaks = RegExp(r'\n[ \t]*\n').allMatches(source).toList();
  var paragraphIndex = 0;
  var segment = 0;
  var offset = 0;
  while (offset < source.length) {
    while (paragraphIndex < paragraphBreaks.length &&
        offset >= paragraphBreaks[paragraphIndex].end) {
      paragraphIndex += 1;
      segment += 1;
    }
    final marker = source.codeUnitAt(offset);
    if (marker != 0x2a && marker != 0x5f) {
      offset += 1;
      continue;
    }
    final rawStart = offset;
    while (offset < source.length && source.codeUnitAt(offset) == marker) {
      offset += 1;
    }
    final rawEnd = offset;
    if (_overlapsRange(rawStart, rawEnd, exclusions) ||
        _isThematicBreakRun(source, rawStart, rawEnd)) {
      continue;
    }

    final escaped = _backslashCountBefore(source, rawStart).isOdd;
    final start = rawStart + (escaped ? 1 : 0);
    if (start >= rawEnd) continue;
    final flanking = _emphasisFlanking(source, start, rawEnd, marker);
    final canOpen =
        flanking.isLeftFlanking &&
        (!flanking.isRightFlanking ||
            marker == 0x2a ||
            flanking.precededByPunctuation);
    final canClose =
        flanking.isRightFlanking &&
        (!flanking.isLeftFlanking ||
            marker == 0x2a ||
            flanking.followedByPunctuation);
    if (!canOpen && !canClose) continue;
    runs.add(
      _EmphasisRun(
        marker: marker,
        start: start,
        end: rawEnd,
        segment: segment,
        canOpen: canOpen,
        canClose: canClose,
      ),
    );
  }
  return runs;
}

void _processEmphasisStack(
  List<_EmphasisRun> input,
  List<IanvsMarkdownEmphasisMatch> output,
) {
  if (input.isEmpty) return;
  final stack = List<_EmphasisRun>.of(input);
  var currentIndex = 0;
  while (currentIndex < stack.length) {
    final closer = stack[currentIndex];
    if (!closer.canClose) {
      currentIndex += 1;
      continue;
    }
    var openerIndex = -1;
    for (var index = currentIndex - 1; index >= 0; index -= 1) {
      final opener = stack[index];
      if (opener.marker != closer.marker ||
          !opener.canOpen ||
          !_canFormEmphasis(opener, closer)) {
        continue;
      }
      openerIndex = index;
      break;
    }
    if (openerIndex < 0) {
      if (!closer.canOpen) {
        stack.removeAt(currentIndex);
      } else {
        currentIndex += 1;
      }
      continue;
    }

    final opener = stack[openerIndex];
    final indicatorLength = opener.remaining >= 2 && closer.remaining >= 2
        ? 2
        : 1;
    final openingStart = opener.start + opener.consumed;
    final closingStart = closer.start + closer.consumed;
    final openingDelimiter = TextRange(
      start: openingStart,
      end: openingStart + indicatorLength,
    );
    final closingDelimiter = TextRange(
      start: closingStart,
      end: closingStart + indicatorLength,
    );
    output.add(
      IanvsMarkdownEmphasisMatch(
        marker: String.fromCharCode(opener.marker),
        kind: indicatorLength == 2
            ? IanvsMarkdownEmphasisKind.strong
            : IanvsMarkdownEmphasisKind.emphasis,
        openingDelimiter: openingDelimiter,
        content: TextRange(start: opener.end, end: closer.start),
        closingDelimiter: closingDelimiter,
        sourceRange: TextRange(
          start: openingDelimiter.start,
          end: closingDelimiter.end,
        ),
      ),
    );
    opener.consumed += indicatorLength;
    closer.consumed += indicatorLength;

    stack.removeRange(openerIndex + 1, currentIndex);
    currentIndex = openerIndex + 1;
    if (opener.remaining == 0) {
      stack.removeAt(openerIndex);
      currentIndex -= 1;
    }
    if (closer.remaining == 0) {
      stack.removeAt(currentIndex);
    }
  }
}

bool _canFormEmphasis(_EmphasisRun opener, _EmphasisRun closer) {
  if ((opener.canOpen && opener.canClose) ||
      (closer.canOpen && closer.canClose)) {
    return (opener.remaining + closer.remaining) % 3 != 0 ||
        (opener.remaining % 3 == 0 && closer.remaining % 3 == 0);
  }
  return true;
}

_EmphasisFlanking _emphasisFlanking(
  String source,
  int start,
  int end,
  int marker,
) {
  final precededByWhitespace =
      start == 0 || _isMarkdownWhitespaceAt(source, start - 1);
  final followedByWhitespace =
      end == source.length || _isMarkdownWhitespaceAt(source, end);
  final precededByPunctuation =
      start > 0 &&
      !precededByWhitespace &&
      _isMarkdownPunctuationAt(source, start - 1);
  final followedByPunctuation =
      end < source.length &&
      !followedByWhitespace &&
      _isMarkdownPunctuationAt(source, end);
  final isLeftFlanking =
      !followedByWhitespace &&
      (!followedByPunctuation || precededByWhitespace || precededByPunctuation);
  final isRightFlanking =
      !precededByWhitespace &&
      (!precededByPunctuation || followedByWhitespace || followedByPunctuation);
  return _EmphasisFlanking(
    isLeftFlanking: isLeftFlanking,
    isRightFlanking: isRightFlanking,
    precededByPunctuation: precededByPunctuation,
    followedByPunctuation: followedByPunctuation,
  );
}

bool _isMarkdownWhitespaceAt(String source, int offset) => md
    .DelimiterRun
    .unicodeWhitespace
    .contains(source.substring(offset, offset + 1));

bool _isMarkdownPunctuationAt(String source, int offset) => md
    .DelimiterRun
    .unicodePunctuationPattern
    .hasMatch(source.substring(offset, offset + 1));

int _backslashCountBefore(String source, int offset) {
  var count = 0;
  for (
    var index = offset - 1;
    index >= 0 && source.codeUnitAt(index) == 0x5c;
    index -= 1
  ) {
    count += 1;
  }
  return count;
}

bool _overlapsRange(int start, int end, List<TextRange> ranges) {
  for (final range in ranges) {
    if (range.start >= end) break;
    if (range.end > start) return true;
  }
  return false;
}

bool _isThematicBreakRun(String source, int start, int end) {
  final lineStart = start == 0 ? 0 : source.lastIndexOf('\n', start - 1) + 1;
  var lineEnd = source.indexOf('\n', end);
  if (lineEnd < 0) lineEnd = source.length;
  final line = source.substring(lineStart, lineEnd);
  return RegExp(
    r'^ {0,3}(?:\*(?:[ \t]*\*){2,}|_(?:[ \t]*_){2,})[ \t]*$',
  ).hasMatch(line);
}

List<TextRange> _mergeRanges(List<TextRange> ranges) {
  if (ranges.isEmpty) return const <TextRange>[];
  final merged = <TextRange>[ranges.first];
  for (final range in ranges.skip(1)) {
    final previous = merged.last;
    if (range.start <= previous.end) {
      merged[merged.length - 1] = TextRange(
        start: previous.start,
        end: range.end > previous.end ? range.end : previous.end,
      );
    } else {
      merged.add(range);
    }
  }
  return merged;
}

final class _EmphasisRun {
  _EmphasisRun({
    required this.marker,
    required this.start,
    required this.end,
    required this.segment,
    required this.canOpen,
    required this.canClose,
  });

  final int marker;
  final int start;
  final int end;
  final int segment;
  final bool canOpen;
  final bool canClose;
  int consumed = 0;

  int get remaining => end - start - consumed;
}

final class _EmphasisFlanking {
  const _EmphasisFlanking({
    required this.isLeftFlanking,
    required this.isRightFlanking,
    required this.precededByPunctuation,
    required this.followedByPunctuation,
  });

  final bool isLeftFlanking;
  final bool isRightFlanking;
  final bool precededByPunctuation;
  final bool followedByPunctuation;
}
