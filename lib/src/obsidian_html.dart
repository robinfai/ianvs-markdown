import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'obsidian_metadata.dart';
import 'theme.dart';

/// Inline HTML behavior sampled from Obsidian's live preview and reading view.
///
/// This deliberately implements a small, inert subset. It never executes HTML,
/// keeps no event attributes, and only forwards a checked link destination and
/// a single safe `color` declaration to Flutter widgets.
List<md.InlineSyntax> ianvsMarkdownInlineHtmlSyntaxes(
  IanvsMarkdownObsidianMetadataMode mode,
) => <md.InlineSyntax>[
  _IanvsMarkdownEscapedHtmlSyntax(mode),
  _IanvsMarkdownAngleWwwPrefixSyntax(),
  _IanvsMarkdownDangerousHtmlSyntax(mode),
  _IanvsMarkdownPairedHtmlSyntax(mode),
  _IanvsMarkdownBreakHtmlSyntax(mode),
  _IanvsMarkdownStandaloneHtmlSyntax(mode),
];

/// Leaves the opening angle of Obsidian's `<www…>` bare-link fallback
/// literal instead of letting the standalone-HTML sanitizer consume it.
/// The following `www` token is handled by the bare-link syntax.
final class _IanvsMarkdownAngleWwwPrefixSyntax extends md.InlineSyntax {
  _IanvsMarkdownAngleWwwPrefixSyntax()
    : super(r'<(?=www\.[^\s<>]+>)', startCharacter: 0x3c, caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text('<'));
    return true;
  }
}

final class _IanvsMarkdownEscapedHtmlSyntax extends md.InlineSyntax {
  _IanvsMarkdownEscapedHtmlSyntax(this.mode)
    : super(
        r'\\</?[A-Za-z][A-Za-z0-9-]*(?:\s[^>\n]*)?>',
        startCharacter: 0x5c,
        caseSensitive: false,
      );

  final IanvsMarkdownObsidianMetadataMode mode;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Text(
        mode == IanvsMarkdownObsidianMetadataMode.editing
            ? match.group(0)!
            : r'\',
      ),
    );
    return true;
  }
}

final class _IanvsMarkdownDangerousHtmlSyntax extends md.InlineSyntax {
  _IanvsMarkdownDangerousHtmlSyntax(this.mode)
    : super(
        r'<!--[\s\S]*?-->|<(script|style)\b[^>\n]*>[\s\S]*?</\1\s*>',
        startCharacter: 0x3c,
        caseSensitive: false,
      );

  final IanvsMarkdownObsidianMetadataMode mode;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (mode == IanvsMarkdownObsidianMetadataMode.editing) {
      parser.addNode(md.Text(match.group(0)!));
    }
    return true;
  }
}

final class _IanvsMarkdownPairedHtmlSyntax extends md.InlineSyntax {
  _IanvsMarkdownPairedHtmlSyntax(this.mode)
    : super(
        r'<([A-Za-z][A-Za-z0-9-]*)\b([^>\n]*)>([\s\S]*?)</\1\s*>',
        startCharacter: 0x3c,
        caseSensitive: false,
      );

  final IanvsMarkdownObsidianMetadataMode mode;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final source = match.group(0)!;
    final tag = match.group(1)!.toLowerCase();
    final attributes = match.group(2) ?? '';
    final content = match.group(3) ?? '';
    if (tag == 'script' || tag == 'style') {
      if (mode == IanvsMarkdownObsidianMetadataMode.editing) {
        parser.addNode(md.Text(source));
      }
      return true;
    }

    final children = parser.document.parseInline(content);
    md.Element? element;
    switch (tag) {
      case 'strong':
      case 'b':
        element = md.Element(
          mode == IanvsMarkdownObsidianMetadataMode.editing
              ? 'ianvs-html-strong'
              : 'strong',
          children,
        );
      case 'em':
      case 'i':
        element = md.Element(
          mode == IanvsMarkdownObsidianMetadataMode.editing
              ? 'ianvs-html-em'
              : 'em',
          children,
        );
      case 's':
      case 'del':
        element = md.Element('ianvs-html-s', children);
      case 'code':
        element = md.Element('ianvs-html-code', children);
      case 'sup':
        element = md.Element('ianvs-html-sup', children);
      case 'mark':
        element = md.Element('ianvs-html-mark', children);
      case 'u':
        element = md.Element('ianvs-html-u', children);
      case 'sub':
        element = md.Element('ianvs-html-sub', children);
      case 'kbd':
        element = md.Element('ianvs-html-kbd', children);
      case 'small':
        element = md.Element('ianvs-html-small', children);
      case 'q':
        element = md.Element('ianvs-html-q', children);
      case 'abbr':
        element = md.Element('ianvs-html-abbr', children);
      case 'span':
        final color = ianvsMarkdownSafeHtmlColor(attributes);
        if (color != null) {
          element = md.Element('ianvs-html-span', children)
            ..attributes['data-color'] = color.toARGB32().toRadixString(16);
        }
      case 'a':
        final href = _safeHtmlHref(_htmlAttribute(attributes, 'href'));
        if (href != null) {
          element = md.Element('a', children)
            ..attributes['href'] = href
            ..attributes['data-ianvs-html-link'] = 'true';
          final title = _htmlAttribute(attributes, 'title')?.trim();
          if (title != null && title.isNotEmpty) {
            element.attributes['title'] = title;
          }
        }
    }

    if (element != null) {
      parser.addNode(element);
    } else {
      for (final child in children) {
        parser.addNode(child);
      }
    }
    return true;
  }
}

final class _IanvsMarkdownBreakHtmlSyntax extends md.InlineSyntax {
  _IanvsMarkdownBreakHtmlSyntax(this.mode)
    : super(r'<br\s*/?>', startCharacter: 0x3c, caseSensitive: false);

  final IanvsMarkdownObsidianMetadataMode mode;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final source = match.group(0)!;
    if (mode == IanvsMarkdownObsidianMetadataMode.editing &&
        source.contains('/')) {
      parser.addNode(md.Text(source));
    } else {
      parser.addNode(md.Element.empty('br'));
    }
    return true;
  }
}

final class _IanvsMarkdownStandaloneHtmlSyntax extends md.InlineSyntax {
  _IanvsMarkdownStandaloneHtmlSyntax(this.mode)
    : super(
        r'</?[A-Za-z][^>\n]*>|<[^>\n]+>',
        startCharacter: 0x3c,
        caseSensitive: false,
      );

  final IanvsMarkdownObsidianMetadataMode mode;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (mode == IanvsMarkdownObsidianMetadataMode.editing) {
      parser.addNode(md.Text(match.group(0)!));
    }
    return true;
  }
}

/// Returns the one CSS color declaration allowed by the safe HTML subset.
Color? ianvsMarkdownSafeHtmlColor(String attributes) {
  final style = _htmlAttribute(attributes, 'style');
  if (style == null) return null;
  final colorMatch = RegExp(
    r'(?:^|;)\s*color\s*:\s*([^;]+)',
    caseSensitive: false,
  ).firstMatch(style);
  final value = colorMatch?.group(1)?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  const named = <String, Color>{
    'black': Color(0xff000000),
    'white': Color(0xffffffff),
    'red': Color(0xffff0000),
    'green': Color(0xff008000),
    'blue': Color(0xff0000ff),
    'yellow': Color(0xffffff00),
    'orange': Color(0xffffa500),
    'purple': Color(0xff800080),
    'gray': Color(0xff808080),
    'grey': Color(0xff808080),
  };
  final namedColor = named[value];
  if (namedColor != null) return namedColor;
  if (!value.startsWith('#')) return null;
  final hex = value.substring(1);
  if (RegExp(r'^[0-9a-f]{3}$').hasMatch(hex)) {
    final expanded = hex.split('').map((digit) => '$digit$digit').join();
    return Color(int.parse('ff$expanded', radix: 16));
  }
  if (RegExp(r'^[0-9a-f]{6}$').hasMatch(hex)) {
    return Color(int.parse('ff$hex', radix: 16));
  }
  return null;
}

String? _safeHtmlHref(String? source) {
  final href = source?.trim();
  if (href == null || href.isEmpty || href.contains(RegExp(r'[\x00-\x1f]'))) {
    return null;
  }
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  if (!uri.hasScheme) return href.startsWith('//') ? null : href;
  return const <String>{
        'http',
        'https',
        'mailto',
      }.contains(uri.scheme.toLowerCase())
      ? href
      : null;
}

String? _htmlAttribute(String source, String name) {
  final match = RegExp(
    '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*'
    '(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(source);
  return match?.group(1) ?? match?.group(2) ?? match?.group(3);
}

enum IanvsMarkdownHtmlInlineKind {
  strong,
  emphasis,
  underline,
  strikethrough,
  superscript,
  subscript,
  keyboard,
  small,
  quotation,
  abbreviation,
  mark,
  span,
}

/// Returns Text.rich so flutter_markdown_plus can merge the styled span back
/// into the surrounding RichText instead of splitting the paragraph's Wrap.
class IanvsMarkdownHtmlInlineBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlInlineBuilder({
    required this.kind,
    this.consumeTap = false,
    this.theme,
  });

  final IanvsMarkdownHtmlInlineKind kind;
  final bool consumeTap;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final base = parentStyle ?? preferredStyle ?? const TextStyle();
    final style = switch (kind) {
      IanvsMarkdownHtmlInlineKind.strong => base.copyWith(
        color: colors.strongForeground,
        fontWeight: FontWeight.w600,
      ),
      IanvsMarkdownHtmlInlineKind.emphasis => base.copyWith(
        color: colors.emphasisForeground,
        fontStyle: FontStyle.italic,
      ),
      IanvsMarkdownHtmlInlineKind.underline => base.copyWith(
        decoration: TextDecoration.underline,
      ),
      IanvsMarkdownHtmlInlineKind.strikethrough => base.copyWith(
        decoration: TextDecoration.lineThrough,
      ),
      IanvsMarkdownHtmlInlineKind.superscript => base.copyWith(
        fontSize: (base.fontSize ?? 14) * .78,
        fontFeatures: const <FontFeature>[FontFeature.enable('sups')],
      ),
      IanvsMarkdownHtmlInlineKind.subscript => base.copyWith(
        fontSize: (base.fontSize ?? 14) * .78,
        fontFeatures: const <FontFeature>[FontFeature.enable('subs')],
      ),
      IanvsMarkdownHtmlInlineKind.keyboard => base.copyWith(
        color: colors.textPrimary,
        backgroundColor: colors.surfaceRaised,
        fontFamily: colors.monoFontFamily,
        fontFamilyFallback: colors.monoFontFamilyFallback,
        fontSize: (base.fontSize ?? 14) * .84,
      ),
      IanvsMarkdownHtmlInlineKind.small => base.copyWith(
        fontSize: (base.fontSize ?? 14) * .8,
      ),
      IanvsMarkdownHtmlInlineKind.quotation => base,
      IanvsMarkdownHtmlInlineKind.abbreviation => base.copyWith(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
      ),
      IanvsMarkdownHtmlInlineKind.mark => base.copyWith(
        color: colors.textPrimary,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff6b5b22)
            : const Color(0xffffe184),
      ),
      IanvsMarkdownHtmlInlineKind.span => base.copyWith(
        color: Color(
          int.parse(element.attributes['data-color'] ?? 'ff000000', radix: 16),
        ),
      ),
    };
    final text = Text.rich(TextSpan(text: element.textContent, style: style));
    return consumeTap
        ? GestureDetector(
            key: kind == IanvsMarkdownHtmlInlineKind.strong
                ? const ValueKey('ianvs-markdown-html-strong')
                : kind == IanvsMarkdownHtmlInlineKind.emphasis
                ? const ValueKey('ianvs-markdown-html-em')
                : kind == IanvsMarkdownHtmlInlineKind.subscript
                ? const ValueKey('ianvs-markdown-html-subscript')
                : kind == IanvsMarkdownHtmlInlineKind.strikethrough
                ? const ValueKey('ianvs-markdown-html-s')
                : kind == IanvsMarkdownHtmlInlineKind.superscript
                ? const ValueKey('ianvs-markdown-html-sup')
                : kind == IanvsMarkdownHtmlInlineKind.keyboard
                ? const ValueKey('ianvs-markdown-html-kbd')
                : kind == IanvsMarkdownHtmlInlineKind.small
                ? const ValueKey('ianvs-markdown-html-small')
                : kind == IanvsMarkdownHtmlInlineKind.quotation
                ? const ValueKey('ianvs-markdown-html-q')
                : kind == IanvsMarkdownHtmlInlineKind.abbreviation
                ? const ValueKey('ianvs-markdown-html-abbr')
                : kind == IanvsMarkdownHtmlInlineKind.mark
                ? const ValueKey('ianvs-markdown-html-mark')
                : kind == IanvsMarkdownHtmlInlineKind.span
                ? const ValueKey('ianvs-markdown-html-span')
                : null,
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: kind == IanvsMarkdownHtmlInlineKind.quotation
                ? Text.rich(
                    TextSpan(text: '“${element.textContent}”', style: style),
                  )
                : text,
          )
        : kind == IanvsMarkdownHtmlInlineKind.quotation
        ? Text.rich(TextSpan(text: '“${element.textContent}”', style: style))
        : text;
  }
}
