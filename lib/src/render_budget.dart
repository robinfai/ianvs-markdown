import 'syntax_preset.dart';

/// Input limits checked before Markdown preprocessing, rendering or copying.
///
/// When an input limit is exceeded, [scanMarkdownForRendering] returns
/// a UTF-8 bounded plain-text prefix. This protects interactive rendering from
/// oversized documents. These are input bounds, not latency or heap limits.
/// UTF-16 lengths use Dart string offsets; fallback bytes use UTF-8 scalars.
final class IanvsMarkdownRenderBudget {
  const IanvsMarkdownRenderBudget({
    this.maxSyntaxTokens = 4096,
    this.maxSyntaxTokensBetweenBlankLines,
    this.maxDenseSyntaxTokensBetweenBlankLines,
    this.maxCodeUnitsBetweenBlankLines,
    this.maxFallbackBytes = 64 * 1024,
    this.maxSourceCodeUnits = 1024 * 1024,
    this.maxLineCodeUnits = 4 * 1024,
  }) : assert(maxSyntaxTokens >= 0),
       assert(
         maxSyntaxTokensBetweenBlankLines == null ||
             maxSyntaxTokensBetweenBlankLines >= 0,
       ),
       assert(
         maxCodeUnitsBetweenBlankLines == null ||
             maxCodeUnitsBetweenBlankLines >= 0,
       ),
       assert(
         maxDenseSyntaxTokensBetweenBlankLines == null ||
             maxDenseSyntaxTokensBetweenBlankLines >= 0,
       ),
       assert(maxFallbackBytes >= 0),
       assert(maxSourceCodeUnits >= 0),
       assert(maxLineCodeUnits >= 0);

  final int maxSyntaxTokens;

  /// Optional density bound for a run of nonblank LF-delimited lines.
  /// This is a conservative input guard, not Markdown block parsing. Blank
  /// lines containing only spaces, tabs or CR reset the counter. Hosts can
  /// raise the document-wide budget without accepting a single enormous
  /// paragraph of links/emphasis. Null preserves the document-only policy.
  final int? maxSyntaxTokensBetweenBlankLines;

  /// Additional syntax bound when a nonblank run contains more than one
  /// charged syntax unit per four UTF-16 units. This catches densely styled
  /// soft-wrapped paragraphs while allowing large tables with long cell text.
  final int? maxDenseSyntaxTokensBetweenBlankLines;

  /// Optional UTF-16 bound for the same nonblank line run. Prevents a single
  /// very long soft-wrapped paragraph from bypassing the physical line bound.
  /// Rejection reports [IanvsMarkdownBudgetExceeded.sourceLength].
  final int? maxCodeUnitsBetweenBlankLines;
  final int maxFallbackBytes;
  final int maxSourceCodeUnits;

  /// Longest LF-delimited line, excluding a CR immediately before LF.
  /// A lone CR counts as content because not every parser splits on it.
  final int maxLineCodeUnits;
}

enum IanvsMarkdownBudgetExceeded { sourceLength, lineLength, syntaxTokens }

final class IanvsMarkdownRenderDecision {
  const IanvsMarkdownRenderDecision({
    required this.text,
    required this.useMarkdown,
    required this.syntaxTokens,
    required this.truncated,
    this.budgetExceeded,
  });

  final String text;
  final bool useMarkdown;
  final int syntaxTokens;
  final bool truncated;
  final IanvsMarkdownBudgetExceeded? budgetExceeded;
}

IanvsMarkdownRenderDecision scanMarkdownForRendering(
  String source, {
  required IanvsMarkdownRenderBudget? budget,
  IanvsMarkdownSyntaxPreset syntaxPreset = IanvsMarkdownSyntaxPreset.obsidian,
}) {
  if (budget == null) {
    return IanvsMarkdownRenderDecision(
      text: source,
      useMarkdown: true,
      syntaxTokens: 0,
      truncated: false,
    );
  }
  var tokens = 0;
  var exceeded = source.length > budget.maxSourceCodeUnits
      ? IanvsMarkdownBudgetExceeded.sourceLength
      : null;
  var lineCodeUnits = 0;
  var groupTokens = 0;
  var groupCodeUnits = 0;
  var lineHasContent = false;
  final lineScanner = _MarkdownLineScanner();
  // Accepted documents need no fallback allocation. Stop scanning as soon as
  // a bound fails; construct the bounded UTF-8 prefix only on that path.
  for (var index = 0; index < source.length && exceeded == null; index += 1) {
    final codeUnit = source.codeUnitAt(index);
    if (exceeded == null) {
      if (codeUnit == 0x0a) {
        lineCodeUnits = 0;
      } else if (!(codeUnit == 0x0d &&
          index + 1 < source.length &&
          source.codeUnitAt(index + 1) == 0x0a)) {
        lineCodeUnits += 1;
      }
      if (lineCodeUnits > budget.maxLineCodeUnits) {
        exceeded = IanvsMarkdownBudgetExceeded.lineLength;
      }
      final added =
          lineScanner.consume(codeUnit) +
          (_isMarkdownSyntaxCodeUnit(codeUnit, syntaxPreset) ? 1 : 0);
      tokens += added;
      if (budget.maxSyntaxTokensBetweenBlankLines != null ||
          budget.maxDenseSyntaxTokensBetweenBlankLines != null ||
          budget.maxCodeUnitsBetweenBlankLines != null) {
        groupTokens += added;
        groupCodeUnits++;
        if (codeUnit == 0x0a) {
          if (!lineHasContent) {
            groupTokens = 0;
            groupCodeUnits = 0;
          }
          lineHasContent = false;
        } else if (codeUnit != 0x20 && codeUnit != 0x09 && codeUnit != 0x0d) {
          lineHasContent = true;
        }
        if (budget.maxSyntaxTokensBetweenBlankLines case final limit?
            when groupTokens > limit) {
          exceeded ??= IanvsMarkdownBudgetExceeded.syntaxTokens;
        }
        if (budget.maxDenseSyntaxTokensBetweenBlankLines case final limit?
            when groupTokens > limit && groupTokens * 4 > groupCodeUnits) {
          exceeded ??= IanvsMarkdownBudgetExceeded.syntaxTokens;
        }
        if (budget.maxCodeUnitsBetweenBlankLines case final limit?
            when groupCodeUnits > limit) {
          exceeded ??= IanvsMarkdownBudgetExceeded.sourceLength;
        }
      }
      if (tokens > budget.maxSyntaxTokens) {
        exceeded ??= IanvsMarkdownBudgetExceeded.syntaxTokens;
      }
    }
  }

  if (exceeded == null) {
    final finalTokens = lineScanner.finish();
    tokens += finalTokens;
    if (budget.maxSyntaxTokensBetweenBlankLines case final limit?
        when groupTokens + finalTokens > limit) {
      exceeded = IanvsMarkdownBudgetExceeded.syntaxTokens;
    }
    if (budget.maxDenseSyntaxTokensBetweenBlankLines case final limit?
        when groupTokens + finalTokens > limit &&
            (groupTokens + finalTokens) * 4 > groupCodeUnits) {
      exceeded = IanvsMarkdownBudgetExceeded.syntaxTokens;
    }
    if (tokens > budget.maxSyntaxTokens) {
      exceeded = IanvsMarkdownBudgetExceeded.syntaxTokens;
    }
  }

  if (exceeded == null) {
    return IanvsMarkdownRenderDecision(
      text: source,
      useMarkdown: true,
      syntaxTokens: tokens,
      truncated: false,
    );
  }

  final fallback = StringBuffer();
  var fallbackBytes = 0;
  var fallbackNextIndex = 0;
  while (fallbackNextIndex < source.length) {
    final scalar = _plainFallbackScalar(source, fallbackNextIndex);
    if (scalar.bytes > budget.maxFallbackBytes - fallbackBytes) break;
    fallback.write(scalar.text);
    fallbackBytes += scalar.bytes;
    fallbackNextIndex += scalar.codeUnits;
  }

  return IanvsMarkdownRenderDecision(
    text: fallback.toString(),
    useMarkdown: false,
    syntaxTokens: tokens,
    truncated: fallbackNextIndex < source.length,
    budgetExceeded: exceeded,
  );
}

bool _isMarkdownSyntaxCodeUnit(
  int codeUnit,
  IanvsMarkdownSyntaxPreset syntaxPreset,
) {
  return switch (codeUnit) {
    0x24 => syntaxPreset == IanvsMarkdownSyntaxPreset.obsidian,
    0x21 ||
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
