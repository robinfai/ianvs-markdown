import 'package:flutter/services.dart' show TextRange;
import 'package:markdown/markdown.dart' as md;

import 'source_mapped_document.dart';

/// Internal semantic index. Ranges identify source blocks, never replacement
/// spans: rendered text can differ in both length and order from its source.
class MarkdownReadingTextIndex {
  MarkdownReadingTextIndex.fromNodes(
    List<md.Node> nodes, {
    required this.source,
    this.expandedChildren,
    this.navigationRange,
    required TextRange? Function(md.Node node) sourceRange,
  }) {
    for (final node in nodes) {
      _visit(node, null, sourceRange, null);
      _flush();
    }
  }

  /// Uses the same parsed nodes and projected-line mapping as the renderer.
  /// The caller supplies original source offsets; projection bytes must never
  /// be mistaken for offsets in the original document.
  factory MarkdownReadingTextIndex.fromDocument({
    required String source,
    required List<md.Node> nodes,
    required SourceMappedMarkdownDocument document,
    required List<int> lineOffsets,
    List<md.Node>? Function(md.Element node)? expandedChildren,
    TextRange? Function(md.Node node)? navigationRange,
  }) => MarkdownReadingTextIndex.fromNodes(
    nodes,
    source: source,
    expandedChildren: expandedChildren,
    navigationRange: navigationRange,
    sourceRange: (node) {
      final lines = document.ranges[node];
      if (lines == null ||
          lines.start < 0 ||
          lines.start >= lineOffsets.length) {
        return null;
      }
      return TextRange(
        start: lineOffsets[lines.start],
        end: lines.end < lineOffsets.length
            ? lineOffsets[lines.end]
            : source.length,
      );
    },
  );

  final String source;
  final TextRange? Function(md.Node node)? navigationRange;
  TextRange? _pendingNavigation;
  final List<md.Node>? Function(md.Element node)? expandedChildren;
  final _segments = <MarkdownReadingTextSegment>[];
  final _pending = StringBuffer();
  TextRange? _pendingRange;

  List<MarkdownReadingTextSegment> get segments => List.unmodifiable(_segments);

  /// Literal, non-overlapping matches. Each segment is an independent visible
  /// text flow, so a phrase cannot accidentally cross table cells or paragraphs.
  List<MarkdownReadingTextMatch> find(String query, {bool matchCase = false}) {
    if (query.isEmpty) return const [];
    final expression = RegExp(
      RegExp.escape(query),
      caseSensitive: matchCase,
      unicode: true,
    );
    return [
      for (var i = 0; i < _segments.length; i++)
        for (final match in expression.allMatches(_segments[i].text))
          if (_scalarBoundary(_segments[i].text, match.start) &&
              _scalarBoundary(_segments[i].text, match.end))
            MarkdownReadingTextMatch(
              segmentIndex: i,
              textRange: TextRange(start: match.start, end: match.end),
              sourceRange: _segments[i].sourceRange,
              navigationRange: _segments[i].navigationRange,
            ),
    ];
  }

  void _visit(
    md.Node node,
    TextRange? inheritedRange,
    TextRange? Function(md.Node node) sourceRange,
    TextRange? inheritedNavigation,
  ) {
    final range = sourceRange(node) ?? inheritedRange;
    final navigation =
        navigationRange?.call(node) ?? inheritedNavigation ?? range;
    if (node is md.Text) {
      if (range == null || !_validRange(range)) return;
      if (_pendingRange != range || _pendingNavigation != navigation) _flush();
      _pendingRange = range;
      _pendingNavigation = navigation;
      _pending.write(node.textContent);
      return;
    }
    if (node is! md.Element) return;
    final tag = node.tag;
    // These surfaces show graphics, controls, or generated navigation rather
    // than their source text. A separator prevents matching across them.
    if (tag == 'img' ||
        tag == 'input' ||
        tag.startsWith('ianvs-inline-math') ||
        tag == 'ianvs-inline-display-math' ||
        tag == 'ianvs-display-math' ||
        tag == 'ianvs-wiki-embed' ||
        tag.startsWith('ianvs-editing-metadata') ||
        node.attributes['class'] == 'footnote-backref' ||
        (tag == 'code' &&
            (node.attributes['class'] ?? '')
                .split(' ')
                .contains('language-mermaid'))) {
      _flush();
      return;
    }
    if (tag == 'br') {
      if (_pending.isNotEmpty) _pending.write('\n');
      return;
    }
    final expanded = expandedChildren?.call(node);
    final block =
        expanded != null ||
        const {
          'p',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'pre',
          'li',
          'td',
          'th',
          'blockquote',
          'div',
          'section',
          'ul',
          'ol',
          'table',
          'tr',
          'dt',
          'dd',
        }.contains(tag);
    if (block) _flush();
    for (final child in expanded ?? node.children ?? const <md.Node>[]) {
      _visit(child, range, sourceRange, navigation);
    }
    if (block) _flush();
  }

  bool _validRange(TextRange range) =>
      range.start >= 0 && range.end > range.start && range.end <= source.length;

  void _flush() {
    if (_pending.isNotEmpty && _pendingRange != null) {
      _segments.add(
        MarkdownReadingTextSegment(
          text: _pending.toString(),
          sourceRange: _pendingRange!,
          navigationRange: _pendingNavigation,
        ),
      );
    }
    _pending.clear();
    _pendingRange = null;
    _pendingNavigation = null;
  }

  static bool _scalarBoundary(String text, int offset) =>
      offset == 0 ||
      offset == text.length ||
      !(text.codeUnitAt(offset - 1) >= 0xd800 &&
          text.codeUnitAt(offset - 1) <= 0xdbff &&
          text.codeUnitAt(offset) >= 0xdc00 &&
          text.codeUnitAt(offset) <= 0xdfff);
}

class MarkdownReadingTextSegment {
  const MarkdownReadingTextSegment({
    required this.text,
    required this.sourceRange,
    this.navigationRange,
  });
  final String text;
  final TextRange sourceRange;
  final TextRange? navigationRange;
}

class MarkdownReadingTextMatch {
  const MarkdownReadingTextMatch({
    required this.segmentIndex,
    required this.textRange,
    required this.sourceRange,
    this.navigationRange,
  });
  final int segmentIndex;
  final TextRange textRange;
  final TextRange sourceRange;
  final TextRange? navigationRange;
}
