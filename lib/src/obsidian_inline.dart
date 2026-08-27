import 'dart:convert';

import 'package:flutter/services.dart' show TextRange;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import 'wiki_link_reference.dart';

enum IanvsMarkdownEntityPresentation { editing, reading }

/// Preserves entity source in live preview and follows the browser-compatible
/// HTML5 decoding behavior used by Obsidian in reading view.
class IanvsMarkdownEntitySyntax extends md.InlineSyntax {
  IanvsMarkdownEntitySyntax({required this.presentation})
    : super(
        r'&(?:#[xX][A-Za-z0-9]+|#[A-Za-z0-9]+|[A-Za-z][A-Za-z0-9]*);?',
        startCharacter: 0x26,
      );

  final IanvsMarkdownEntityPresentation presentation;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final source = match.group(0)!;
    var text = presentation == IanvsMarkdownEntityPresentation.editing
        ? source
        : html_parser.parseFragment(source).text ?? source;
    if (parser.encodeHtml) text = htmlEscape.convert(text);
    parser.addNode(md.Text(text));
    return true;
  }
}

/// Keeps the source backslash visible while retaining its hard line break in
/// Obsidian's live-preview presentation.
class IanvsMarkdownEditingHardBreakSyntax extends md.InlineSyntax {
  IanvsMarkdownEditingHardBreakSyntax() : super(r'\\\n', startCharacter: 0x5c);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(r'\'));
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

/// Collapses paragraph whitespace the same way Obsidian's rendered surfaces
/// do while leaving trailing hard-break markers available to Markdown.
///
/// The live editor only uses this syntax for inactive rendered blocks. Once a
/// block is focused, its source-backed [TextField] still exposes every space
/// and tab exactly as authored.
class IanvsMarkdownRenderedWhitespaceSyntax extends md.InlineSyntax {
  IanvsMarkdownRenderedWhitespaceSyntax() : super(r'[ \t]+(?=[^ \t\r\n])');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(' '));
    return true;
  }
}

enum IanvsMarkdownCodeSpanPresentation { editing, reading }

/// Matches Obsidian's code-span whitespace behavior in both live preview and
/// reading view. Live preview preserves source whitespace and soft line
/// breaks; reading view trims one shared edge space and normalizes whitespace.
class IanvsMarkdownCodeSpanSyntax extends md.InlineSyntax {
  static const _pattern = r'(`+(?!`))((?:.|\n)*?[^`])\1(?!`)';

  IanvsMarkdownCodeSpanSyntax({
    this.presentation = IanvsMarkdownCodeSpanPresentation.reading,
  }) : super(_pattern);

  final IanvsMarkdownCodeSpanPresentation presentation;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    if (parser.pos > 0 && parser.source.codeUnitAt(parser.pos - 1) == 0x60) {
      return false;
    }
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    var code = match.group(2)!;
    code = code.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (code.trim().isNotEmpty &&
        (code.startsWith(' ') || code.startsWith('\n')) &&
        (code.endsWith(' ') || code.endsWith('\n'))) {
      code = code.substring(1, code.length - 1);
    }
    if (presentation == IanvsMarkdownCodeSpanPresentation.reading) {
      code = code.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');
    }
    if (parser.encodeHtml) code = htmlEscape.convert(code);
    parser.addNode(md.Element.text('ianvs-inline-code', code));
    return true;
  }
}

/// Parses Obsidian-style Wiki links such as `[[Note]]` and
/// `[[path/to/Note|Label]]` as anchors.
enum IanvsMarkdownWikiLinkPresentation { editing, reading }

class IanvsMarkdownWikiLinkSyntax extends md.InlineSyntax {
  IanvsMarkdownWikiLinkSyntax({
    this.presentation = IanvsMarkdownWikiLinkPresentation.reading,
  }) : super(r'\[\[([^\]\n]+)\]\]', startCharacter: 0x5b);

  final IanvsMarkdownWikiLinkPresentation presentation;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final source = match.group(1)!;
    final reference = parseIanvsMarkdownWikiLinkBody(source);
    if (reference == null) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }
    final target = reference.target;
    final label = reference.aliasSeparator == null
        ? _wikiLinkLabel(target, presentation)
        : reference.label;

    final children = reference.aliasSeparator == null
        ? <md.Node>[md.Text(label)]
        : parser.document.parseInline(label);
    final anchor = md.Element('a', children)
      ..attributes['href'] = target
      ..attributes['data-ianvs-wiki-link'] = 'true';
    parser.addNode(anchor);
    return true;
  }
}

String _wikiLinkLabel(
  String target,
  IanvsMarkdownWikiLinkPresentation presentation,
) {
  final hash = target.indexOf('#');
  if (hash < 0 || hash == target.length - 1) return target;
  final note = target.substring(0, hash).trim();
  final subpath = target.substring(hash + 1).trim();
  if (subpath.isEmpty) return target;
  if (note.isEmpty) return subpath;
  return presentation == IanvsMarkdownWikiLinkPresentation.reading
      ? '$note > $subpath'
      : target;
}

final RegExp _obsidianTagPattern = RegExp(
  r'''#[^\u2000-\u206F\u2E00-\u2E7F'!"#$%&()*+,.:;<=>?@^`{|}~\[\]\\\s]+''',
);
final RegExp _obsidianNumericTagPattern = RegExp(r'^#[0-9]+$');
final RegExp _obsidianTagWhitespacePattern = RegExp(r'\s');
const int _obsidianTagFullwidthColon = 0xff1a;

/// Finds the lexical ranges that Obsidian treats as inline tags.
///
/// Tags begin at the start of the document, immediately after whitespace, or
/// after the fullwidth-colon punctuation boundary confirmed in Obsidian 1.13.7.
/// They stop before ASCII punctuation or characters in Obsidian's two excluded
/// Unicode punctuation blocks,
/// and must contain something other than ASCII digits. The allowed remainder
/// deliberately includes `/`, non-ASCII scripts, emoji, and other symbols.
/// An even backslash run preserves the slashes and restores tag parsing, while
/// an odd run escapes the hash. A valid tag can be followed immediately by
/// another tag, as in `#one#two`.
List<TextRange> ianvsMarkdownTagRanges(String source) {
  final ranges = <TextRange>[];
  var start = source.indexOf('#');
  while (start >= 0) {
    final range = _ianvsMarkdownTagRangeAt(source, start);
    if (range != null) ranges.add(range);
    start = source.indexOf('#', range?.end ?? start + 1);
  }
  return List<TextRange>.unmodifiable(ranges);
}

TextRange? _ianvsMarkdownTagRangeAt(String source, int start) {
  final range = _unboundedObsidianTagRangeAt(source, start);
  if (range == null) return null;
  final boundary = _obsidianTagEscapeBoundary(source, start);
  if ((start - boundary).isOdd ||
      !_isObsidianTagStartBoundary(source, boundary)) {
    return null;
  }
  return range;
}

TextRange? _unboundedObsidianTagRangeAt(String source, int start) {
  if (start < 0 || start >= source.length || source.codeUnitAt(start) != 0x23) {
    return null;
  }
  final match = _obsidianTagPattern.matchAsPrefix(source, start);
  if (match == null || _obsidianNumericTagPattern.hasMatch(match.group(0)!)) {
    return null;
  }
  return TextRange(start: start, end: match.end);
}

bool _isObsidianTagStartBoundary(String source, int start) {
  var boundary = start;
  while (true) {
    if (boundary == 0 ||
        _obsidianTagWhitespacePattern.hasMatch(
          source.substring(boundary - 1, boundary),
        ) ||
        source.codeUnitAt(boundary - 1) == _obsidianTagFullwidthColon) {
      return true;
    }
    final previousHash = source.lastIndexOf('#', boundary - 1);
    if (previousHash < 0) return false;
    final previousTag = _unboundedObsidianTagRangeAt(source, previousHash);
    if (previousTag == null || previousTag.end != boundary) return false;
    final previousBoundary = _obsidianTagEscapeBoundary(source, previousHash);
    if ((previousHash - previousBoundary).isOdd) return false;
    boundary = previousBoundary;
  }
}

int _obsidianTagEscapeBoundary(String source, int start) {
  var boundary = start;
  while (boundary > 0 && source.codeUnitAt(boundary - 1) == 0x5c) {
    boundary -= 1;
  }
  return boundary;
}

/// Parses Obsidian-style tags, including nested and Unicode tags.
class IanvsMarkdownTagSyntax extends md.InlineSyntax {
  IanvsMarkdownTagSyntax() : super(r'#', startCharacter: 0x23);

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    if (start != parser.pos) return false;
    final range = _ianvsMarkdownTagRangeAt(parser.source, start);
    if (range == null) return false;
    parser.writeText();
    final label = parser.source.substring(range.start, range.end);
    final anchor = md.Element.text('a', label)
      ..attributes['href'] = 'tag:$label'
      ..attributes['data-ianvs-tag'] = 'true';
    parser
      ..addNode(anchor)
      ..consume(range.end - range.start);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;
}
