/// Limits the amount of Markdown syntax parsed by a renderer.
///
/// When the syntax token limit is exceeded, [scanMarkdownForRendering] returns
/// a UTF-8 bounded plain-text prefix. This protects interactive rendering from
/// pathological documents while keeping ordinary large prose intact.
final class IanvsMarkdownRenderBudget {
  const IanvsMarkdownRenderBudget({
    this.maxSyntaxTokens = 4096,
    this.maxFallbackBytes = 64 * 1024,
  }) : assert(maxSyntaxTokens >= 0),
       assert(maxFallbackBytes >= 0);

  final int maxSyntaxTokens;
  final int maxFallbackBytes;
}

final class IanvsMarkdownRenderDecision {
  const IanvsMarkdownRenderDecision({
    required this.text,
    required this.useMarkdown,
    required this.syntaxTokens,
    required this.truncated,
  });

  final String text;
  final bool useMarkdown;
  final int syntaxTokens;
  final bool truncated;
}

IanvsMarkdownRenderDecision scanMarkdownForRendering(
  String source, {
  required IanvsMarkdownRenderBudget budget,
}) {
  var tokens = 0;
  var syntaxExceeded = false;
  final lineScanner = _MarkdownLineScanner();
  final fallback = StringBuffer();
  var fallbackBytes = 0;
  var fallbackNextIndex = 0;
  var fallbackFull = false;

  for (var index = 0; index < source.length; index += 1) {
    final codeUnit = source.codeUnitAt(index);
    if (!fallbackFull && index == fallbackNextIndex) {
      final scalar = _plainFallbackScalar(source, index);
      if (scalar.bytes > budget.maxFallbackBytes - fallbackBytes) {
        fallbackFull = true;
      } else {
        fallback.write(scalar.text);
        fallbackBytes += scalar.bytes;
        fallbackNextIndex += scalar.codeUnits;
      }
    }
    if (!syntaxExceeded) {
      tokens += lineScanner.consume(codeUnit);
      if (_isMarkdownSyntaxCodeUnit(codeUnit)) tokens += 1;
      if (tokens > budget.maxSyntaxTokens) syntaxExceeded = true;
    }
    if (syntaxExceeded && fallbackFull) break;
  }

  if (!syntaxExceeded) {
    tokens += lineScanner.finish();
    syntaxExceeded = tokens > budget.maxSyntaxTokens;
  }

  if (!syntaxExceeded) {
    return IanvsMarkdownRenderDecision(
      text: source,
      useMarkdown: true,
      syntaxTokens: tokens,
      truncated: false,
    );
  }

  return IanvsMarkdownRenderDecision(
    text: fallback.toString(),
    useMarkdown: false,
    syntaxTokens: tokens,
    truncated: fallbackNextIndex < source.length,
  );
}

bool _isMarkdownSyntaxCodeUnit(int codeUnit) {
  return switch (codeUnit) {
    0x21 ||
    0x24 ||
    0x28 ||
    0x29 ||
    0x2a ||
    0x3c ||
    0x5b ||
    0x5c ||
    0x5d ||
    0x5f ||
    0x60 ||
    0x7c ||
    0x7e => true,
    _ => false,
  };
}

final class _MarkdownLineScanner {
  var _indent = 0;
  var _prefixOpen = true;
  var _orderedDigits = 0;
  int? _pendingOrderedDelimiter;
  var _equalsUnderline = false;
  var _equalsUnderlineValid = false;
  var _equalsTrailingWhitespace = false;
  var _currentLineHasContent = false;
  var _previousLineHasContent = false;
  var _previousWasCR = false;

  int consume(int codeUnit) {
    if (codeUnit == 0x0a && _previousWasCR) {
      _previousWasCR = false;
      return 0;
    }
    if (codeUnit == 0x0a || codeUnit == 0x0d) {
      final tokens = _finishLine();
      _previousWasCR = codeUnit == 0x0d;
      return tokens;
    }
    _previousWasCR = false;

    var tokens = 0;
    final pendingDelimiter = _pendingOrderedDelimiter;
    if (pendingDelimiter != null) {
      if (_isMarkdownSpace(codeUnit) && pendingDelimiter == 0x2e) tokens += 1;
      _pendingOrderedDelimiter = null;
    }

    if (_prefixOpen) {
      if (codeUnit == 0x20 && _orderedDigits == 0) {
        _indent += 1;
        if (_indent > 3) _prefixOpen = false;
        return tokens;
      }
      if (_isAsciiDigit(codeUnit)) {
        _currentLineHasContent = true;
        _orderedDigits += 1;
        if (_orderedDigits > 9) _prefixOpen = false;
        return tokens;
      }
      if (_orderedDigits > 0 && (codeUnit == 0x2e || codeUnit == 0x29)) {
        _currentLineHasContent = true;
        _pendingOrderedDelimiter = codeUnit;
        _prefixOpen = false;
        return tokens;
      }

      _prefixOpen = false;
      if (!_isMarkdownSpace(codeUnit)) _currentLineHasContent = true;
      if (codeUnit == 0x3d) {
        _equalsUnderline = true;
        _equalsUnderlineValid = true;
        return tokens;
      }
      if (codeUnit == 0x23 ||
          codeUnit == 0x3e ||
          codeUnit == 0x2b ||
          codeUnit == 0x2d) {
        return tokens + 1;
      }
      return tokens;
    }

    if (!_isMarkdownSpace(codeUnit)) _currentLineHasContent = true;
    if (_equalsUnderline && _equalsUnderlineValid) {
      if (codeUnit == 0x3d && !_equalsTrailingWhitespace) return tokens;
      if (_isMarkdownSpace(codeUnit)) {
        _equalsTrailingWhitespace = true;
      } else {
        _equalsUnderlineValid = false;
      }
    }
    return tokens;
  }

  int finish() => _finishLine();

  int _finishLine() {
    var tokens = 0;
    if (_pendingOrderedDelimiter == 0x2e) tokens += 1;
    final isSetextUnderline =
        _equalsUnderline && _equalsUnderlineValid && _previousLineHasContent;
    if (isSetextUnderline) tokens += 1;
    _previousLineHasContent = _currentLineHasContent && !isSetextUnderline;
    _indent = 0;
    _prefixOpen = true;
    _orderedDigits = 0;
    _pendingOrderedDelimiter = null;
    _equalsUnderline = false;
    _equalsUnderlineValid = false;
    _equalsTrailingWhitespace = false;
    _currentLineHasContent = false;
    return tokens;
  }
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

bool _isMarkdownSpace(int codeUnit) => codeUnit == 0x20 || codeUnit == 0x09;

({String text, int bytes, int codeUnits}) _plainFallbackScalar(
  String source,
  int index,
) {
  final first = source.codeUnitAt(index);
  if (_isHighSurrogate(first) &&
      index + 1 < source.length &&
      _isLowSurrogate(source.codeUnitAt(index + 1))) {
    return (text: source.substring(index, index + 2), bytes: 4, codeUnits: 2);
  }
  if (_isHighSurrogate(first) || _isLowSurrogate(first)) {
    return (text: '\uFFFD', bytes: 3, codeUnits: 1);
  }
  return (
    text: source.substring(index, index + 1),
    bytes: first <= 0x7f
        ? 1
        : first <= 0x7ff
        ? 2
        : 3,
    codeUnits: 1,
  );
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xd800 && codeUnit <= 0xdbff;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xdc00 && codeUnit <= 0xdfff;
