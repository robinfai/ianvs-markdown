import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

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

/// Matches Obsidian's asymmetric intraword underscore behavior.
///
/// Obsidian keeps a single underscore literal inside a word (`foo_bar_baz`),
/// while a double-underscore run still forms strong text
/// (`foo__bar__baz`). CommonMark deliberately rejects both intraword forms,
/// so this syntax gets first refusal for the Obsidian-only strong variant.
class IanvsMarkdownIntrawordStrongSyntax extends md.InlineSyntax {
  IanvsMarkdownIntrawordStrongSyntax()
    : super(
        r'(?<=[A-Za-z0-9])__(\S(?:[^\n]*?\S)?)(?<!\\)__(?=[A-Za-z0-9])',
        startCharacter: 0x5f,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(1)!;
    parser.addNode(md.Element('strong', parser.document.parseInline(content)));
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
    final separator = source.indexOf('|');
    final target = (separator < 0 ? source : source.substring(0, separator))
        .trim();
    var label = (separator < 0 ? source : source.substring(separator + 1))
        .trim();
    if (target.isEmpty || label.isEmpty) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }
    if (separator < 0) {
      label = _wikiLinkLabel(target, presentation);
    }

    final anchor = md.Element.text('a', label)
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

/// Parses Obsidian-style tags, including nested tags such as `#work/project`.
class IanvsMarkdownTagSyntax extends md.InlineSyntax {
  IanvsMarkdownTagSyntax()
    : super(r'#([A-Za-z0-9_\-/\u3400-\u9fff]+)', startCharacter: 0x23);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (match.start > 0) {
      final previous = parser.source.substring(match.start - 1, match.start);
      if (RegExp(r'[A-Za-z0-9_/]').hasMatch(previous)) {
        parser.advanceBy(1);
        return false;
      }
    }

    final label = match.group(0)!;
    final anchor = md.Element.text('a', label)
      ..attributes['href'] = 'tag:$label'
      ..attributes['data-ianvs-tag'] = 'true';
    parser.addNode(anchor);
    return true;
  }
}
