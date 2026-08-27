/// Source-preserving helpers for CommonMark-style inline links.
///
/// Rendering remains owned by `package:markdown`. These helpers mirror the
/// destination and title grammar so live-preview source decoration only hides
/// syntax that the renderer will actually recognize.
int? findIanvsMarkdownLinkLabelEnd(String source, int openingBracket) {
  if (openingBracket < 0 ||
      openingBracket >= source.length ||
      source.codeUnitAt(openingBracket) != 0x5b) {
    return null;
  }

  var depth = 1;
  var index = openingBracket + 1;
  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (character == 0x5c && index + 1 < source.length) {
      index += 2;
      continue;
    }
    if (character == 0x0a || character == 0x0d) {
      final breakEnd =
          character == 0x0d &&
              index + 1 < source.length &&
              source.codeUnitAt(index + 1) == 0x0a
          ? index + 2
          : index + 1;
      var next = breakEnd;
      while (next < source.length) {
        final nextCharacter = source.codeUnitAt(next);
        if (nextCharacter != 0x20 &&
            nextCharacter != 0x09 &&
            nextCharacter != 0x0d) {
          break;
        }
        next += 1;
      }
      if (next < source.length && source.codeUnitAt(next) == 0x0a) {
        return null;
      }
      index = breakEnd;
      continue;
    }
    if (character == 0x5b) {
      depth += 1;
    } else if (character == 0x5d) {
      depth -= 1;
      if (depth == 0) return index;
    }
    index += 1;
  }
  return null;
}

/// Returns the exclusive end of a valid inline-link suffix beginning at `(`.
///
/// Supports empty destinations, balanced or escaped bare destinations,
/// angle-wrapped destinations, all three CommonMark title delimiters, and
/// soft-line whitespace before titles.
int? findIanvsMarkdownInlineLinkEnd(String source, int openingParenthesis) {
  if (openingParenthesis < 0 ||
      openingParenthesis >= source.length ||
      source.codeUnitAt(openingParenthesis) != 0x28) {
    return null;
  }

  var index = _moveThroughMarkdownWhitespace(source, openingParenthesis + 1);
  if (index >= source.length) return null;
  if (source.codeUnitAt(index) == 0x3c) {
    return _findAngleDestinationEnd(source, index);
  }
  return _findBareDestinationEnd(source, index);
}

/// A parsed full-reference label, including its exclusive source end.
final class IanvsMarkdownReferenceLabelMatch {
  const IanvsMarkdownReferenceLabelMatch({
    required this.end,
    required this.label,
  });

  final int end;
  final String label;
}

/// Parses the secondary label in a full reference link.
///
/// Unlike link text, a reference label cannot contain an unescaped `[`, and
/// it must contain at least one non-whitespace character. Escaped `]` and `\`
/// are decoded in the same way as `package:markdown` before normalization.
IanvsMarkdownReferenceLabelMatch? findIanvsMarkdownReferenceLabel(
  String source,
  int openingBracket,
) {
  if (openingBracket < 0 ||
      openingBracket >= source.length ||
      source.codeUnitAt(openingBracket) != 0x5b) {
    return null;
  }

  final label = StringBuffer();
  var index = openingBracket + 1;
  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (character == 0x5c) {
      index += 1;
      if (index >= source.length) return null;
      final escaped = source.codeUnitAt(index);
      if (escaped != 0x5c && escaped != 0x5d) label.writeCharCode(0x5c);
      label.writeCharCode(escaped);
    } else if (character == 0x5b) {
      return null;
    } else if (character == 0x5d) {
      final value = label.toString();
      if (value.trim().isEmpty ||
          _containsMarkdownParagraphBreak(source, openingBracket + 1, index)) {
        return null;
      }
      return IanvsMarkdownReferenceLabelMatch(end: index + 1, label: value);
    } else {
      label.writeCharCode(character);
    }
    index += 1;
  }
  return null;
}

/// Finds document reference labels used by full, collapsed, and shortcut
/// links while excluding valid inline links and definition declarations.
Iterable<String> findIanvsMarkdownReferencedLabels(String source) sync* {
  var index = 0;
  while (index < source.length) {
    final isImage =
        source.codeUnitAt(index) == 0x21 &&
        index + 1 < source.length &&
        source.codeUnitAt(index + 1) == 0x5b;
    final bracketStart = isImage
        ? index + 1
        : source.codeUnitAt(index) == 0x5b
        ? index
        : -1;
    if (bracketStart < 0) {
      index += 1;
      continue;
    }
    if (_isEscapedAt(source, index) || _isEscapedAt(source, bracketStart)) {
      index = bracketStart + 1;
      continue;
    }

    final labelEnd = findIanvsMarkdownLinkLabelEnd(source, bracketStart);
    if (labelEnd == null) {
      index = bracketStart + 1;
      continue;
    }
    final primaryLabel = source.substring(bracketStart + 1, labelEnd);
    var suffixStart = labelEnd + 1;
    if (suffixStart < source.length && source.codeUnitAt(suffixStart) == 0x28) {
      final inlineEnd = findIanvsMarkdownInlineLinkEnd(source, suffixStart);
      if (inlineEnd != null) {
        index = inlineEnd;
        continue;
      }
    }

    if (suffixStart < source.length && source.codeUnitAt(suffixStart) == 0x5b) {
      if (suffixStart + 1 < source.length &&
          source.codeUnitAt(suffixStart + 1) == 0x5d) {
        yield primaryLabel;
        index = suffixStart + 2;
        continue;
      }
      final secondary = findIanvsMarkdownReferenceLabel(source, suffixStart);
      if (secondary != null) {
        yield secondary.label;
        index = secondary.end;
        continue;
      }
      index = suffixStart + 1;
      continue;
    }

    if (suffixStart < source.length && source.codeUnitAt(suffixStart) == 0x3a) {
      index = suffixStart + 1;
      continue;
    }
    if (!_isTaskCheckboxCandidate(source, bracketStart, labelEnd)) {
      yield primaryLabel;
    }
    index = suffixStart;
  }
}

int? _findAngleDestinationEnd(String source, int openingAngle) {
  var index = openingAngle + 1;
  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (character == 0x5c) {
      index += 1;
      if (index >= source.length) return null;
    } else if (character == 0x0a || character == 0x0d || character == 0x0c) {
      return null;
    } else if (character == 0x3e) {
      final afterDestination = index + 1;
      if (afterDestination >= source.length) return null;
      final following = source.codeUnitAt(afterDestination);
      if (following == 0x29) return afterDestination + 1;
      if (!_isLinkDestinationSeparator(following)) return null;
      return _findTitleOrClosingParenthesis(source, afterDestination);
    }
    index += 1;
  }
  return null;
}

int? _findBareDestinationEnd(String source, int destinationStart) {
  var depth = 1;
  var index = destinationStart;
  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (character == 0x5c) {
      index += 1;
      if (index >= source.length) return null;
    } else if (_isLinkDestinationSeparator(character)) {
      if (depth != 1) return null;
      return _findTitleOrClosingParenthesis(source, index);
    } else if (character == 0x28) {
      depth += 1;
    } else if (character == 0x29) {
      depth -= 1;
      if (depth == 0) return index + 1;
    }
    index += 1;
  }
  return null;
}

int? _findTitleOrClosingParenthesis(String source, int whitespaceStart) {
  var index = _moveThroughMarkdownWhitespace(source, whitespaceStart);
  if (_containsMarkdownParagraphBreak(source, whitespaceStart, index)) {
    return null;
  }
  if (index >= source.length) return null;
  if (source.codeUnitAt(index) == 0x29) return index + 1;

  final delimiter = source.codeUnitAt(index);
  if (delimiter != 0x22 && delimiter != 0x27 && delimiter != 0x28) {
    return null;
  }
  final closingDelimiter = delimiter == 0x28 ? 0x29 : delimiter;
  final titleStart = index + 1;
  index = titleStart;
  if (index >= source.length) return null;

  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (character == 0x5c) {
      index += 1;
      if (index >= source.length) return null;
    } else if (character == closingDelimiter) {
      if (_containsMarkdownParagraphBreak(source, titleStart, index)) {
        return null;
      }
      final whitespaceAfterTitle = index + 1;
      index = _moveThroughMarkdownWhitespace(source, index + 1);
      if (_containsMarkdownParagraphBreak(
        source,
        whitespaceAfterTitle,
        index,
      )) {
        return null;
      }
      if (index < source.length && source.codeUnitAt(index) == 0x29) {
        return index + 1;
      }
      return null;
    }
    index += 1;
  }
  return null;
}

int _moveThroughMarkdownWhitespace(String source, int start) {
  var index = start;
  while (index < source.length &&
      _isMarkdownWhitespace(source.codeUnitAt(index))) {
    index += 1;
  }
  return index;
}

bool _isMarkdownWhitespace(int character) =>
    character == 0x20 ||
    character == 0x09 ||
    character == 0x0a ||
    character == 0x0b ||
    character == 0x0c ||
    character == 0x0d;

bool _isLinkDestinationSeparator(int character) =>
    character == 0x20 ||
    character == 0x0a ||
    character == 0x0c ||
    character == 0x0d;

bool _containsMarkdownParagraphBreak(String source, int start, int end) {
  var lineBreak = source.indexOf('\n', start);
  while (lineBreak >= 0 && lineBreak < end) {
    var next = lineBreak + 1;
    while (next < end) {
      final character = source.codeUnitAt(next);
      if (character != 0x20 && character != 0x09 && character != 0x0d) {
        break;
      }
      next += 1;
    }
    if (next < end && source.codeUnitAt(next) == 0x0a) return true;
    lineBreak = source.indexOf('\n', next);
  }
  return false;
}

bool _isEscapedAt(String source, int offset) {
  var backslashes = 0;
  for (var index = offset - 1; index >= 0; index -= 1) {
    if (source.codeUnitAt(index) != 0x5c) break;
    backslashes += 1;
  }
  return backslashes.isOdd;
}

bool _isTaskCheckboxCandidate(String source, int start, int end) {
  final label = source.substring(start + 1, end);
  if (label != ' ' && label != 'x' && label != 'X') return false;
  final lineStart = source.lastIndexOf('\n', start - 1) + 1;
  final prefix = source.substring(lineStart, start);
  return RegExp(r'^ {0,3}(?:[-+*]|\d{1,9}[.)])[ \t]+$').hasMatch(prefix);
}
