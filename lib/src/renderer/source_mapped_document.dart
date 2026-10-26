// Copyright (c) 2012, the Dart project authors.
// BSD license: LICENSE.markdown in this directory.
// Parser orchestration derived from markdown 7.3.1 block_parser.dart and
// document.dart. Syntax implementations and inline parsing remain upstream.

import 'package:flutter/services.dart' show TextRange;
import 'package:markdown/markdown.dart' as md;

/// Internal parser that retains top-level source line ranges on AST identities.
/// No attributes or marker text are inserted into Markdown or its AST.
class SourceMappedMarkdownDocument extends md.Document {
  SourceMappedMarkdownDocument({
    super.blockSyntaxes,
    super.inlineSyntaxes,
    super.extensionSet,
    super.encodeHtml,
  });

  final ranges = Map<md.Node, TextRange>.identity();

  @override
  List<md.Node> parseLineList(List<md.Line> lines) {
    ranges.clear();
    final nodes = _SourceBlockParser(lines, this, ranges).parseLines();
    _parseInlineContent(nodes);
    return _filterFootnotes(nodes);
  }

  void _parseInlineContent(List<md.Node> nodes) {
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is md.UnparsedContent) {
        final inlineNodes = parseInline(node.textContent);
        nodes.removeAt(i);
        nodes.insertAll(i, inlineNodes);
        i += inlineNodes.length - 1;
      } else if (node is md.Element && node.children != null) {
        _parseInlineContent(node.children!);
      }
    }
  }

  /// Footnotes could be defined in arbitrary positions of a document, we need
  /// to distinguish them and put them behind; and every footnote definition
  /// may have multiple backrefs, we need to append backrefs for it.
  List<md.Node> _filterFootnotes(List<md.Node> nodes) {
    final footnotes = <md.Element>[];
    final blocks = <md.Node>[];
    for (final node in nodes) {
      if (node is md.Element &&
          node.tag == 'li' &&
          footnoteReferences.containsKey(node.footnoteLabel)) {
        final label = node.footnoteLabel;
        var count = 0;
        if (label != null && (count = footnoteReferences[label] ?? 0) > 0) {
          footnotes.add(node);
          final children = node.children;
          if (children != null) {
            _appendBackref(children, Uri.encodeComponent(label), count);
          }
        }
      } else {
        blocks.add(node);
      }
    }

    if (footnotes.isNotEmpty) {
      // Sort footnotes by appearing order.
      final ordinal = {
        for (var i = 0; i < footnoteLabels.length; i++)
          'fn-${footnoteLabels[i]}': i,
      };
      footnotes.sort((l, r) {
        final idl = l.attributes['id']?.toLowerCase() ?? '';
        final idr = r.attributes['id']?.toLowerCase() ?? '';
        return (ordinal[idl] ?? 0) - (ordinal[idr] ?? 0);
      });
      final list = md.Element('ol', footnotes);

      // Ignore GFM attribute: <data-footnotes>.
      final section = md.Element('section', [list])
        ..attributes['class'] = 'footnotes';
      blocks.add(section);
    }
    return blocks;
  }

  /// Generate backref nodes, append them to footnote definition's last child.
  void _appendBackref(List<md.Node> children, String ref, int count) {
    final refs = [
      for (var i = 0; i < count; i++) ...[
        md.Text(' '),
        _footnoteAnchor(ref, i),
      ],
    ];
    if (children.isEmpty) {
      children.addAll(refs);
    } else {
      final last = children.last;
      if (last is md.Element) {
        last.children?.addAll(refs);
      } else {
        children.last = md.Element('p', [last, ...refs]);
      }
    }
  }

  static md.Element _footnoteAnchor(String ref, int i) {
    final num = '${i + 1}';
    final suffix = i > 0 ? '-$num' : '';
    return md.Element('a', [
        md.Text('\u21a9'),
        if (i > 0)
          md.Element('sup', [md.Text(num)])
            ..attributes['class'] = 'footnote-ref',
      ])
      // Ignore GFM's attributes:
      // <data-footnote-backref aria-label="Back to content">.
      ..attributes['href'] = '#fnref-$ref$suffix'
      ..attributes['class'] = 'footnote-backref';
  }
}

class _SourceBlockParser extends md.BlockParser {
  _SourceBlockParser(super.lines, super.document, this.ranges);
  final Map<md.Node, TextRange> ranges;
  int _position = 0;
  int _start = 0;
  md.BlockSyntax? _current;
  md.BlockSyntax? _previous;
  md.BlockSyntax? _parent;
  bool _disabledSetext = false;

  @override
  md.BlockSyntax? get currentSyntax => _current;
  @override
  md.BlockSyntax? get previousSyntax => _previous;
  @override
  md.BlockSyntax? get parentSyntax => _parent;
  @override
  bool get setextHeadingDisabled => _disabledSetext;
  @override
  List<md.Line> get linesToConsume =>
      lines.getRange(_start, _position + 1).toList();
  @override
  void advance() {
    super.advance();
    _position++;
  }

  @override
  void retreat() {
    super.retreat();
    _position--;
  }

  @override
  void retreatBy(int count) {
    super.retreatBy(count);
    _position -= count;
  }

  @override
  List<md.Node> parseLines({
    md.BlockSyntax? parentSyntax,
    bool disabledSetextHeading = false,
  }) {
    _parent = parentSyntax;
    _disabledSetext = disabledSetextHeading;
    final blocks = <md.Node>[];
    md.BlockSyntax? neverMatch;
    var iterationsWithoutProgress = 0;
    while (!isDone) {
      final before = _position;
      for (final syntax in blockSyntaxes) {
        if (neverMatch == syntax) continue;
        if (syntax.canParse(this)) {
          _previous = _current;
          _current = syntax;
          final blockStart = _start;
          final block = syntax.parse(this);
          if (block != null) {
            blocks.add(block);
            ranges[block] = TextRange(start: blockStart, end: _position);
          }
          neverMatch = _position != before ? null : syntax;
          if (block != null ||
              syntax is md.EmptyBlockSyntax ||
              syntax is md.LinkReferenceDefinitionSyntax) {
            _start = _position;
          }
          break;
        }
      }
      if (before == _position) {
        iterationsWithoutProgress++;
        if (iterationsWithoutProgress > 2) {
          throw AssertionError('BlockParser.parseLines is not advancing');
        }
      } else {
        iterationsWithoutProgress = 0;
      }
    }
    return blocks;
  }
}
