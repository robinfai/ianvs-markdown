import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Literal Unicode simple-case-fold matching in UTF-16 source coordinates.
/// This deliberately does not normalize, expand case folds, or parse Markdown.
/// Both in-document Find and workspace search use exactly this scanner.
class LiteralSourceMatcher {
  LiteralSourceMatcher(this.source, this.query, {required bool matchCase})
    : pattern = RegExp(
        RegExp.escape(query),
        caseSensitive: matchCase,
        unicode: true,
      );

  final String source;
  final String query;
  final RegExp pattern;
  int _offset = 0;
  bool get complete => query.isEmpty || _offset >= source.length;

  List<TextRange> next({int chunkSize = 16 * 1024}) {
    if (complete) return const [];
    final offset = _offset;
    final end = scalarBoundary(
      source,
      math.min(offset + chunkSize, source.length),
    );
    final windowEnd = scalarBoundary(
      source,
      math.min(end + query.length - 1, source.length),
    );
    var nextOffset = end;
    final matches = <TextRange>[];
    for (final match in pattern.allMatches(
      source.substring(offset, windowEnd),
    )) {
      if (offset + match.start >= end) break;
      final range = TextRange(
        start: offset + match.start,
        end: offset + match.end,
      );
      matches.add(range);
      nextOffset = math.max(nextOffset, range.end);
    }
    _offset = nextOffset;
    return matches;
  }

  static int scalarBoundary(String source, int offset) {
    if (offset > 0 && offset < source.length) {
      final previous = source.codeUnitAt(offset - 1);
      final next = source.codeUnitAt(offset);
      if (previous >= 0xD800 &&
          previous <= 0xDBFF &&
          next >= 0xDC00 &&
          next <= 0xDFFF) {
        return offset + 1;
      }
    }
    return offset;
  }
}
