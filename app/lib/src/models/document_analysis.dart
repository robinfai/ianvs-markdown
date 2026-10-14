import 'package:ianvs_markdown/ianvs_markdown.dart';

/// Per-document derived UI data. No source, selection or history is changed.
class DocumentAnalysis {
  String? _outlineSource;
  List<DocumentHeading> _headings = const [];
  Map<String, IanvsMarkdownHeading?> _labels = {};
  String? _statisticsSource;
  DocumentStatistics? _statistics;

  List<DocumentHeading> headings(String source) {
    if (_outlineSource == source) return _headings;
    final labels = <String, IanvsMarkdownHeading?>{};
    final headings = <DocumentHeading>[];
    // Retain the component's block boundaries, including fences, YAML, HTML,
    // tables and setext headings. Only unchanged heading inlines are reused.
    for (final block in parseMarkdownBlocks(source)) {
      if (block.type != IanvsMarkdownBlockType.heading) continue;
      final IanvsMarkdownHeading? label;
      if (labels.containsKey(block.source)) {
        label = labels[block.source];
      } else if (_labels.containsKey(block.source)) {
        label = _labels[block.source];
      } else {
        final parsed = parseMarkdownHeadings(block.source);
        label = parsed.isEmpty ? null : parsed.first;
      }
      labels[block.source] = label;
      if (label != null) {
        headings.add(DocumentHeading(offset: block.start, label: label));
      }
    }
    // Keep only the current document's heading sources, not editing history.
    _labels = labels;
    _outlineSource = source;
    return _headings = List.unmodifiable(headings);
  }

  DocumentStatistics statistics(String source) {
    if (_statisticsSource == source) return _statistics!;
    final result = DocumentStatistics.scan(source);
    _statisticsSource = source;
    return _statistics = result;
  }
}

class DocumentHeading {
  const DocumentHeading({required this.offset, required this.label});
  final int offset;
  final IanvsMarkdownHeading label;
  int get level => label.level;
  String get text => label.text;
}

class DocumentStatistics {
  const DocumentStatistics({required this.words, required this.characters});
  final int words;
  // Preserve the previous status bar's Unicode scalar count (String.runes),
  // not grapheme clusters. CRLF counts as two, a surrogate pair as one.
  final int characters;

  factory DocumentStatistics.scan(String source) {
    var words = 0;
    var characters = 0;
    var inWord = false;
    for (var i = 0; i < source.length; i++) {
      final unit = source.codeUnitAt(i);
      characters++;
      final whitespace = _isRegExpWhitespace(unit);
      if (!whitespace && !inWord) words++;
      inWord = !whitespace;
      if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < source.length) {
        final next = source.codeUnitAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) i++;
      }
    }
    return DocumentStatistics(words: words, characters: characters);
  }
}

// ECMAScript \s, matching the status bar's previous RegExp(r'\S+').
// U+0085/U+180E/U+200B are deliberately not whitespace in that contract.
bool _isRegExpWhitespace(int unit) => unit <= 0x20
    ? unit == 0x20 || (unit >= 0x09 && unit <= 0x0d)
    : unit == 0xa0 ||
          unit == 0x1680 ||
          (unit >= 0x2000 && unit <= 0x200a) ||
          unit == 0x2028 ||
          unit == 0x2029 ||
          unit == 0x202f ||
          unit == 0x205f ||
          unit == 0x3000 ||
          unit == 0xfeff;
