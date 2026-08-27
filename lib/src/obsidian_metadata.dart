import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'editor/editor_models.dart';
import 'footnote_syntax.dart';
import 'markdown_link_source.dart';
import 'theme.dart';

/// Determines whether Obsidian editing metadata is shown or consumed.
enum IanvsMarkdownObsidianMetadataMode {
  /// Omit comments and block IDs, and collect inline footnotes at the end.
  reading,

  /// Preserve source-like metadata so a live editor can display it dimmed.
  editing,
}

final RegExp _obsidianCommentFencePattern = RegExp(
  r'^ {0,3}(`{3,}|~{3,})(.*)$',
);

/// Finds paired Obsidian `%%...%%` comments outside code spans and blocks.
///
/// Delimiters are paired from left to right. An odd run of preceding
/// backslashes escapes a delimiter, and an opening delimiter without a later
/// unescaped close remains ordinary source text.
List<TextRange> ianvsMarkdownCommentRanges(String source) {
  final ranges = <TextRange>[];
  final indentedCodeRanges = parseMarkdownBlocks(source)
      .where((block) => block.type == IanvsMarkdownBlockType.indentedCode)
      .map((block) => TextRange(start: block.start, end: block.end))
      .toList(growable: false);
  var index = 0;
  var indentedCodeIndex = 0;
  var lineStart = true;
  var fenceCharacter = 0;
  var fenceLength = 0;

  while (index < source.length) {
    while (indentedCodeIndex < indentedCodeRanges.length &&
        index >= indentedCodeRanges[indentedCodeIndex].end) {
      indentedCodeIndex += 1;
    }
    if (indentedCodeIndex < indentedCodeRanges.length) {
      final range = indentedCodeRanges[indentedCodeIndex];
      if (index >= range.start && index < range.end) {
        index = range.end;
        lineStart = false;
        continue;
      }
    }

    if (lineStart) {
      final lineEnd = source.indexOf('\n', index);
      final end = lineEnd < 0 ? source.length : lineEnd;
      final line = source.substring(index, end);
      final fence = _obsidianCommentFencePattern.firstMatch(line);
      if (fenceLength > 0) {
        if (fence != null) {
          final marker = fence.group(1)!;
          if (marker.codeUnitAt(0) == fenceCharacter &&
              marker.length >= fenceLength &&
              fence.group(2)!.trim().isEmpty) {
            fenceCharacter = 0;
            fenceLength = 0;
          }
        }
        index = lineEnd < 0 ? source.length : lineEnd + 1;
        lineStart = true;
        continue;
      }
      if (fence != null) {
        final marker = fence.group(1)!;
        fenceCharacter = marker.codeUnitAt(0);
        fenceLength = marker.length;
        index = lineEnd < 0 ? source.length : lineEnd + 1;
        lineStart = true;
        continue;
      }
    }

    final character = source.codeUnitAt(index);
    if (character == 0x60 && !isIanvsMarkdownEscapedAt(source, index)) {
      final runLength = _characterRunLength(source, index, 0x60);
      final close = _matchingCodeSpanClose(
        source,
        index + runLength,
        runLength,
      );
      if (close >= 0) {
        index = close + runLength;
        lineStart = false;
        continue;
      }
      index += runLength;
      lineStart = false;
      continue;
    }

    if (character == 0x25 &&
        index + 1 < source.length &&
        source.codeUnitAt(index + 1) == 0x25 &&
        isIanvsMarkdownEscapedAt(source, index)) {
      // Escaping an opening delimiter makes its matching delimiter literal as
      // well (`\%%x%%`). Do not reinterpret that close as the start of a
      // comment on the following text.
      final lineEnd = source.indexOf('\n', index + 2);
      final close = _nextUnescapedCommentDelimiter(source, index + 2);
      if (close >= 0 && (lineEnd < 0 || close < lineEnd)) {
        index = close + _characterRunLength(source, close, 0x25);
      } else {
        index += 2;
      }
      lineStart = false;
      continue;
    }

    if (character == 0x25 &&
        index + 1 < source.length &&
        source.codeUnitAt(index + 1) == 0x25) {
      final close = _nextUnescapedCommentDelimiter(source, index + 2);
      if (close >= 0) {
        ranges.add(TextRange(start: index, end: close + 2));
        // Any percent signs left in the same closing run are literal residue,
        // as in `%%%x%%%` and `%%%%%%`; they do not open a new comment.
        index = close + _characterRunLength(source, close, 0x25);
        lineStart = false;
        continue;
      }
      // With no later delimiter this marker is literal, and there cannot be
      // another unescaped comment pair after it.
      break;
    }

    lineStart = character == 0x0a;
    index += 1;
  }
  return List<TextRange>.unmodifiable(ranges);
}

int _matchingCodeSpanClose(String source, int start, int openingLength) {
  var index = start;
  while (index < source.length) {
    final next = source.indexOf('`', index);
    if (next < 0) return -1;
    final length = _characterRunLength(source, next, 0x60);
    if (length == openingLength) return next;
    index = next + length;
  }
  return -1;
}

int _nextUnescapedCommentDelimiter(String source, int start) {
  var index = source.indexOf('%%', start);
  while (index >= 0) {
    if (!isIanvsMarkdownEscapedAt(source, index)) return index;
    index = source.indexOf('%%', index + 2);
  }
  return -1;
}

final RegExp _obsidianBlockIdFencePattern = RegExp(
  r'^ {0,3}(`{3,}|~{3,})(.*)$',
);
final RegExp _obsidianTrailingBlockIdPattern = RegExp(r'\^[A-Za-z0-9_-]+ *$');
final RegExp _obsidianTableBlockIdPattern = RegExp(
  r'\|([ \t]*)(\\*)\^([A-Za-z0-9_-]+)([ \t]*)(?=\|)',
);

/// Finds Obsidian block identifiers outside comments and fenced code.
///
/// A normal identifier ends its Markdown block, may be followed by ASCII
/// spaces, and is either standalone or separated from preceding content by
/// whitespace. An even backslash run may appear before the caret; it remains
/// literal while the identifier is consumed. A table cell containing only an
/// identifier is handled as the equivalent standalone form.
List<TextRange> ianvsMarkdownBlockIdRanges(String source) {
  final ranges = <TextRange>[];
  final commentRanges = ianvsMarkdownCommentRanges(source);
  final blocks = parseMarkdownBlocks(source);
  final lines = source.split('\n');
  var offset = 0;
  var fenceCharacter = 0;
  var fenceLength = 0;

  for (final line in lines) {
    final fence = _obsidianBlockIdFencePattern.firstMatch(line);
    if (fenceLength > 0) {
      if (fence != null) {
        final marker = fence.group(1)!;
        if (marker.codeUnitAt(0) == fenceCharacter &&
            marker.length >= fenceLength &&
            fence.group(2)!.trim().isEmpty) {
          fenceCharacter = 0;
          fenceLength = 0;
        }
      }
      offset += line.length + 1;
      continue;
    }
    if (fence != null) {
      final marker = fence.group(1)!;
      fenceCharacter = marker.codeUnitAt(0);
      fenceLength = marker.length;
      offset += line.length + 1;
      continue;
    }

    for (final match in _obsidianTableBlockIdPattern.allMatches(line)) {
      final slashes = match.group(2)!;
      if (slashes.length.isOdd) continue;
      final caret = line.indexOf('^', match.start);
      final range = TextRange(
        start: offset + caret,
        end: offset + caret + 1 + match.group(3)!.length,
      );
      if (!_overlapsMetadataRange(range, commentRanges)) ranges.add(range);
    }

    final trailing = _obsidianTrailingBlockIdPattern.firstMatch(line);
    if (trailing != null) {
      final start = _blockIdRangeStart(line, trailing.start);
      if (start != null) {
        final range = TextRange(
          start: offset + start,
          end: offset + trailing.end,
        );
        if (!_overlapsMetadataRange(range, commentRanges) &&
            !_overlapsMetadataRange(range, ranges) &&
            _endsMarkdownBlock(range.end, blocks)) {
          ranges.add(range);
        }
      }
    }
    offset += line.length + 1;
  }

  ranges.sort((a, b) => a.start.compareTo(b.start));
  return List<TextRange>.unmodifiable(ranges);
}

bool _endsMarkdownBlock(int offset, List<IanvsMarkdownBlock> blocks) {
  for (final block in blocks) {
    if (offset < block.start) return false;
    if (offset <= block.end) return offset == block.end;
  }
  return false;
}

int? _blockIdRangeStart(String line, int caret) {
  if (caret == 0) return 0;
  var slashStart = caret;
  while (slashStart > 0 && line.codeUnitAt(slashStart - 1) == 0x5c) {
    slashStart -= 1;
  }
  if (slashStart < caret) {
    final slashCount = caret - slashStart;
    if (slashCount.isOdd ||
        slashStart > 0 &&
            !_isBlockIdWhitespace(line.codeUnitAt(slashStart - 1))) {
      return null;
    }
    return caret;
  }
  if (!_isBlockIdWhitespace(line.codeUnitAt(caret - 1))) return null;
  var start = caret;
  while (start > 0 && _isBlockIdWhitespace(line.codeUnitAt(start - 1))) {
    start -= 1;
  }
  return start;
}

bool _isBlockIdWhitespace(int codeUnit) => codeUnit == 0x20 || codeUnit == 0x09;

bool _overlapsMetadataRange(TextRange range, Iterable<TextRange> others) {
  for (final other in others) {
    if (range.start < other.end && range.end > other.start) return true;
  }
  return false;
}

/// Converts Obsidian-only metadata syntax into Markdown understood by the
/// renderer.
///
/// Obsidian comments (`%%...%%`) and trailing block identifiers (`^block-id`)
/// are editing metadata, so they are omitted from rendered output. Inline
/// footnotes (`^[body]`) are expanded to ordinary GFM footnotes so they share
/// numbering and the footer section with standard `[^label]` references.
String prepareObsidianMarkdownForRendering(
  String source, {
  IanvsMarkdownObsidianMetadataMode mode =
      IanvsMarkdownObsidianMetadataMode.reading,
}) {
  if (source.isEmpty) return source;
  if (mode == IanvsMarkdownObsidianMetadataMode.editing) return source;

  final withoutComments = _stripObsidianComments(source);
  final withoutBlockIds = _stripBlockIdentifiers(withoutComments);
  final withObsidianFootnoteDefinitions =
      _applyObsidianFootnoteDefinitionPrecedence(withoutBlockIds);
  return _expandInlineFootnotes(withObsidianFootnoteDefinitions);
}

/// Projects literal backslashes in Obsidian inline-link destinations without
/// changing the document source exposed by Live Preview or source mode.
///
/// CommonMark consumes the final backslash in a run as punctuation escaping,
/// while each preceding pair represents one literal backslash. The Markdown
/// package currently drops those literal pairs for parenthesis destinations;
/// percent-encoding them in the rendering-only copy preserves the target.
/// Code spans, fenced code, comments, images, malformed links, and titles are
/// deliberately left byte-for-byte unchanged.
String projectObsidianInlineLinkDestinationBackslashesForRendering(
  String source,
) {
  if (source.isEmpty || !source.contains(r'\\\')) return source;

  final comments = ianvsMarkdownCommentRanges(source);
  final output = StringBuffer();
  var cursor = 0;
  var index = 0;
  var commentIndex = 0;
  var fenceCharacter = 0;
  var fenceLength = 0;
  var lineStart = true;

  while (index < source.length) {
    while (commentIndex < comments.length &&
        comments[commentIndex].end <= index) {
      commentIndex += 1;
    }
    if (commentIndex < comments.length &&
        comments[commentIndex].start == index) {
      index = comments[commentIndex].end;
      lineStart = index == 0 || source.codeUnitAt(index - 1) == 0x0a;
      continue;
    }

    if (lineStart) {
      final lineEnd = source.indexOf('\n', index);
      final end = lineEnd < 0 ? source.length : lineEnd;
      final line = source.substring(index, end);
      final fence = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
      if (fence != null) {
        final marker = fence.group(1)!;
        if (fenceLength == 0) {
          fenceCharacter = marker.codeUnitAt(0);
          fenceLength = marker.length;
        } else if (marker.codeUnitAt(0) == fenceCharacter &&
            marker.length >= fenceLength) {
          fenceCharacter = 0;
          fenceLength = 0;
        }
        index = lineEnd < 0 ? source.length : lineEnd + 1;
        lineStart = true;
        continue;
      }
    }

    final character = source.codeUnitAt(index);
    if (fenceLength > 0) {
      lineStart = character == 0x0a;
      index += 1;
      continue;
    }
    if (character == 0x60) {
      final runLength = _characterRunLength(source, index, 0x60);
      final codeEnd = _ianvsMarkdownInlineCodeSpanEnd(source, index);
      if (codeEnd != null) {
        index = codeEnd;
        lineStart = false;
        continue;
      }
      index += runLength;
      lineStart = false;
      continue;
    }

    final imageLabel =
        index > 0 &&
        source.codeUnitAt(index - 1) == 0x21 &&
        !isIanvsMarkdownEscapedAt(source, index - 1);
    if (character == 0x5b &&
        !imageLabel &&
        !isIanvsMarkdownEscapedAt(source, index)) {
      final labelEnd = findIanvsMarkdownLinkLabelEnd(source, index);
      final suffixStart = labelEnd == null ? -1 : labelEnd + 1;
      if (suffixStart >= 0 &&
          suffixStart < source.length &&
          source.codeUnitAt(suffixStart) == 0x28) {
        final linkEnd = findIanvsMarkdownInlineLinkEnd(source, suffixStart);
        if (linkEnd != null) {
          final destination = _bareInlineLinkDestinationRange(
            source,
            suffixStart,
            linkEnd,
          );
          if (destination != null) {
            final original = destination.textInside(source);
            final projected = _projectInlineLinkDestinationBackslashes(
              original,
            );
            if (projected != original) {
              output
                ..write(source.substring(cursor, destination.start))
                ..write(projected);
              cursor = destination.end;
            }
          }
          index = linkEnd;
          lineStart = false;
          continue;
        }
      }
    }

    lineStart = character == 0x0a;
    index += 1;
  }

  if (cursor == 0) return source;
  output.write(source.substring(cursor));
  return output.toString();
}

TextRange? _bareInlineLinkDestinationRange(
  String source,
  int openingParenthesis,
  int linkEnd,
) {
  var index = openingParenthesis + 1;
  while (index < linkEnd &&
      _isIanvsMarkdownLinkWhitespace(source.codeUnitAt(index))) {
    index += 1;
  }
  if (index >= linkEnd || source.codeUnitAt(index) == 0x3c) return null;

  final start = index;
  var depth = 1;
  while (index < linkEnd) {
    final character = source.codeUnitAt(index);
    if (character == 0x5c && index + 1 < linkEnd) {
      index += 2;
      continue;
    }
    if (_isIanvsMarkdownLinkDestinationSeparator(character)) {
      return depth == 1 ? TextRange(start: start, end: index) : null;
    }
    if (character == 0x28) {
      depth += 1;
    } else if (character == 0x29) {
      depth -= 1;
      if (depth == 0) return TextRange(start: start, end: index);
    }
    index += 1;
  }
  return null;
}

bool _isIanvsMarkdownLinkWhitespace(int character) =>
    character == 0x20 ||
    character == 0x09 ||
    character == 0x0a ||
    character == 0x0b ||
    character == 0x0c ||
    character == 0x0d;

bool _isIanvsMarkdownLinkDestinationSeparator(int character) =>
    character == 0x20 ||
    character == 0x0a ||
    character == 0x0c ||
    character == 0x0d;

String _projectInlineLinkDestinationBackslashes(String destination) {
  final output = StringBuffer();
  var cursor = 0;
  var index = 0;
  while (index < destination.length) {
    if (destination.codeUnitAt(index) != 0x5c) {
      index += 1;
      continue;
    }
    final runStart = index;
    while (index < destination.length &&
        destination.codeUnitAt(index) == 0x5c) {
      index += 1;
    }
    final runLength = index - runStart;
    final following = index < destination.length
        ? destination.codeUnitAt(index)
        : -1;
    if (runLength < 3 ||
        runLength.isEven ||
        (following != 0x28 && following != 0x29)) {
      continue;
    }
    output
      ..write(destination.substring(cursor, runStart))
      ..write('%5C' * (runLength ~/ 2))
      ..write(r'\');
    cursor = index;
  }
  if (cursor == 0) return destination;
  output.write(destination.substring(cursor));
  return output.toString();
}

/// Parses editing-only inline metadata into a styled renderer element while
/// retaining the exact source text, including its delimiters.
final class IanvsMarkdownEditingMetadataInlineSyntax extends md.InlineSyntax {
  IanvsMarkdownEditingMetadataInlineSyntax.comment()
    : kind = 'comment',
      super(r'%%', startCharacter: 0x25);

  IanvsMarkdownEditingMetadataInlineSyntax.blockId()
    : kind = 'block-id',
      super(r'[ \t]*\\*\^[A-Za-z0-9_-]+(?:[ \t]*(?=\|)| *(?=\n|$))');

  IanvsMarkdownEditingMetadataInlineSyntax.standardFootnote()
    : kind = 'footnote-ref',
      super(r'\[\^[^\] \r\n\x00\t]+\](?!:)', startCharacter: 0x5b);

  IanvsMarkdownEditingMetadataInlineSyntax.inlineFootnote()
    : kind = 'inline-footnote',
      super(r'\^\[', startCharacter: 0x5e);

  final String kind;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    if (kind == 'comment') {
      final start = startMatchPos ?? parser.pos;
      if (start != parser.pos) return false;
      TextRange? comment;
      for (final range in ianvsMarkdownCommentRanges(parser.source)) {
        if (range.start == start) {
          comment = range;
          break;
        }
        if (range.start > start) break;
      }
      if (comment == null) return false;
      parser.writeText();
      final literal = parser.source.substring(comment.start, comment.end);
      final element = md.Element.text('ianvs-editing-metadata', literal)
        ..attributes['kind'] = kind;
      parser
        ..addNode(element)
        ..consume(comment.end - comment.start);
      return true;
    }
    if (kind == 'block-id') {
      final start = startMatchPos ?? parser.pos;
      if (start != parser.pos) return false;
      TextRange? blockId;
      for (final range in ianvsMarkdownBlockIdRanges(parser.source)) {
        if (range.start == start) {
          blockId = range;
          break;
        }
        if (range.start > start) break;
      }
      if (blockId == null) return false;
      parser.writeText();
      final literal = parser.source.substring(blockId.start, blockId.end);
      final element = md.Element.text('ianvs-editing-metadata', literal)
        ..attributes['kind'] = kind;
      parser
        ..addNode(element)
        ..consume(blockId.end - blockId.start);
      return true;
    }
    if (kind != 'inline-footnote') {
      return super.tryMatch(parser, startMatchPos);
    }
    final start = startMatchPos ?? parser.pos;
    final source = parser.source;
    if (start != parser.pos ||
        start + 1 >= source.length ||
        source.codeUnitAt(start) != 0x5e ||
        source.codeUnitAt(start + 1) != 0x5b ||
        isIanvsMarkdownEscapedAt(source, start)) {
      return false;
    }
    final close = findIanvsMarkdownInlineFootnoteEnd(source, start + 2);
    if (close < 0) return false;
    parser.writeText();
    final literal = source.substring(start, close + 1);
    final element = md.Element.text('ianvs-editing-metadata', literal)
      ..attributes['kind'] = kind;
    parser
      ..addNode(element)
      ..consume(close + 1 - start);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('ianvs-editing-metadata', match.group(0)!)
      ..attributes['kind'] = kind;
    parser.addNode(element);
    return true;
  }
}

/// Keeps a paired standalone comment visible as one source block in editing
/// mode, including blank lines inside it.
final class IanvsMarkdownEditingCommentBlockSyntax extends md.BlockSyntax {
  const IanvsMarkdownEditingCommentBlockSyntax();

  static final RegExp _delimiter = RegExp(r'^ {0,3}%%[ \t]*$');

  @override
  RegExp get pattern => _delimiter;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    for (var offset = 1; ; offset += 1) {
      final line = parser.peek(offset);
      if (line == null) return false;
      if (_delimiter.hasMatch(line.content)) return true;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final lines = <String>[parser.current.content];
    parser.advance();
    while (!parser.isDone) {
      final line = parser.current.content;
      lines.add(line);
      parser.advance();
      if (_delimiter.hasMatch(line)) break;
    }
    return md.Element('ianvs-editing-metadata-block', <md.Node>[
      md.Text(lines.join('\n')),
    ])..attributes['kind'] = 'comment';
  }
}

/// Keeps an isolated footnote definition visible in block-based live preview.
///
/// A normal GFM parser discards a definition when its reference lives in a
/// different lazily-rendered block. This syntax preserves that source instead.
final class IanvsMarkdownEditingFootnoteDefinitionSyntax
    extends md.BlockSyntax {
  const IanvsMarkdownEditingFootnoteDefinitionSyntax();

  @override
  RegExp get pattern => RegExp(r'^[ ]{0,3}\[\^([^\] \r\n\x00\t]+)\]:[ \t]*');

  @override
  md.Node parse(md.BlockParser parser) {
    final source = parser.current.content;
    parser.advance();
    return md.Element('ianvs-editing-metadata-block', <md.Node>[
      md.Text(source),
    ])..attributes['kind'] = 'footnote-definition';
  }
}

/// Paints source-like Obsidian metadata with the same subdued treatment used
/// by the editor while leaving it available for selection and activation.
final class IanvsMarkdownEditingMetadataBuilder extends MarkdownElementBuilder {
  IanvsMarkdownEditingMetadataBuilder({this.theme, this.block = false});

  final IanvsMarkdownThemeData? theme;
  final bool block;

  @override
  bool isBlockElement() => block;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final kind = element.attributes['kind'] ?? 'metadata';
    final text = Text(
      element.textContent,
      semanticsLabel: 'Obsidian $kind editing metadata',
      style: (parentStyle ?? preferredStyle ?? const TextStyle()).copyWith(
        color: colors.textTertiary,
        fontFamily: colors.monoFontFamily,
        fontFamilyFallback: colors.monoFontFamilyFallback,
        height: 1.45,
      ),
    );
    return block ? Align(alignment: Alignment.centerLeft, child: text) : text;
  }
}

/// Renders Reading-mode footnote references with Obsidian occurrence labels.
///
/// The Markdown AST numbers every repeated reference with the same visible
/// ordinal but records its occurrence in the anchor id. Obsidian presents the
/// first reference as `[N]`, then `[N-1]`, `[N-2]`, while keeping every link
/// pointed at the same definition.
final class IanvsMarkdownFootnoteSuperscriptBuilder
    extends MarkdownElementBuilder {
  IanvsMarkdownFootnoteSuperscriptBuilder({
    required this.onTapLink,
    this.superscriptFontFeatureTag,
    this.theme,
  });

  final MarkdownTapLinkCallback? onTapLink;
  final String? superscriptFontFeatureTag;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final base =
        parentStyle ?? preferredStyle ?? DefaultTextStyle.of(context).style;
    final superscriptStyle = base.copyWith(
      fontFeatures: <FontFeature>[
        const FontFeature.enable('sups'),
        if (superscriptFontFeatureTag != null)
          FontFeature.enable(superscriptFontFeatureTag!),
      ],
    );
    final reference = _obsidianFootnoteReferencePresentation(element);
    if (reference == null) {
      return Text.rich(
        TextSpan(text: element.textContent, style: superscriptStyle),
      );
    }

    final enabled = onTapLink != null;
    final link = Semantics(
      key: const ValueKey('ianvs-markdown-footnote-reference'),
      link: true,
      enabled: enabled,
      label: reference.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () =>
                    onTapLink!(reference.label, reference.href, reference.title)
              : null,
          child: Text(
            reference.label,
            style: superscriptStyle.copyWith(
              color: colors.accentDark,
              backgroundColor: Colors.transparent,
              decoration: TextDecoration.none,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: link,
          ),
        ],
      ),
    );
  }
}

final class _ObsidianFootnoteReferencePresentation {
  const _ObsidianFootnoteReferencePresentation({
    required this.label,
    required this.href,
    required this.title,
  });

  final String label;
  final String href;
  final String title;
}

_ObsidianFootnoteReferencePresentation? _obsidianFootnoteReferencePresentation(
  md.Element element,
) {
  if (element.attributes['class'] != 'footnote-ref') return null;
  md.Element? anchor;
  for (final child in element.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == 'a') {
      anchor = child;
      break;
    }
  }
  if (anchor == null) return null;
  final href = anchor.attributes['href']?.trim();
  final id = anchor.attributes['id']?.trim();
  final ordinal = anchor.textContent.trim();
  if (href == null ||
      id == null ||
      ordinal.isEmpty ||
      !href.startsWith('#fn-')) {
    return null;
  }
  final referencePrefix = 'fnref-${href.substring(4)}';
  if (!id.startsWith(referencePrefix)) return null;
  final suffix = id.substring(referencePrefix.length);
  var occurrence = 1;
  if (suffix.isNotEmpty) {
    final match = RegExp(r'^-(\d+)$').firstMatch(suffix);
    occurrence = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
    if (occurrence < 2) return null;
  }
  final label = occurrence == 1 ? '[$ordinal]' : '[$ordinal-${occurrence - 1}]';
  return _ObsidianFootnoteReferencePresentation(
    label: label,
    href: href,
    title: anchor.attributes['title'] ?? '',
  );
}

/// Returns a standard footnote definition formatted as the numbered list item
/// Obsidian shows in editing view, or null when [source] is not a referenced
/// definition.
String? prepareObsidianFootnoteDefinitionForEditing(
  String source, {
  required String document,
}) {
  final match = RegExp(
    r'^[ ]{0,3}\[\^([^\] \r\n\x00\t]+)\]:[ \t]*(.*)$',
    dotAll: true,
  ).firstMatch(source);
  if (match == null) return null;
  final label = match.group(1)!.toLowerCase();
  final ordinal = collectObsidianStandardFootnoteOrdinals(document)[label];
  if (ordinal == null) return null;
  return '$ordinal. ${match.group(2) ?? ''}';
}

/// Collects referenced standard footnote labels using Obsidian's shared
/// standard/inline footnote order.
///
/// Undefined standard references do not consume an ordinal. Comments and
/// inline or fenced code are excluded from the scan.
Map<String, int> collectObsidianStandardFootnoteOrdinals(String source) {
  final content = _stripObsidianComments(source);
  final collector = _ObsidianFootnoteOrdinalCollector(
    _collectStandardFootnoteDefinitionLabels(content),
  )..scan(content);
  return Map<String, int>.unmodifiable(collector.standardOrdinals);
}

/// One footnote reference projected as a compact ordinal in inactive Live
/// Preview while the exact Markdown remains owned by the editor controller.
@immutable
final class IanvsMarkdownLivePreviewFootnoteReference {
  const IanvsMarkdownLivePreviewFootnoteReference({
    required this.sourceRange,
    required this.ordinal,
    required this.occurrence,
  });

  final TextRange sourceRange;
  final int ordinal;
  final int occurrence;

  /// Obsidian labels the first occurrence `[N]`, then `[N-1]`, `[N-2]`.
  String get label =>
      occurrence == 1 ? '[$ordinal]' : '[$ordinal-${occurrence - 1}]';
}

/// Collects the source ranges and shared ordinals shown by inactive Live
/// Preview for standard and inline footnotes.
///
/// Undefined standard references remain literal and do not consume an
/// ordinal. Comments and code retain their higher parsing priority. Nested
/// inline footnotes still consume shared ordinals, but only the outer source
/// range is projected in the document body.
List<IanvsMarkdownLivePreviewFootnoteReference>
ianvsMarkdownLivePreviewFootnoteReferences(String source) {
  if (!source.contains('^')) {
    return const <IanvsMarkdownLivePreviewFootnoteReference>[];
  }
  final content = _maskObsidianComments(source);
  final collector = _ObsidianFootnoteOrdinalCollector(
    _collectStandardFootnoteDefinitionLabels(content),
  )..scan(content, collectPresentations: true);
  return List<IanvsMarkdownLivePreviewFootnoteReference>.unmodifiable(
    collector.presentations,
  );
}

Set<String> _collectStandardFootnoteDefinitionLabels(String source) {
  return _standardFootnoteDefinitions(
    source,
  ).map((definition) => definition.normalizedLabel).toSet();
}

final class _ObsidianStandardFootnoteDefinition {
  const _ObsidianStandardFootnoteDefinition({
    required this.labelStart,
    required this.labelEnd,
    required this.normalizedLabel,
  });

  final int labelStart;
  final int labelEnd;
  final String normalizedLabel;
}

/// Makes the last case-insensitive standard-footnote definition authoritative.
///
/// The underlying Markdown parser already resolves references without case,
/// but retains the first matching definition. Obsidian 1.13.7 instead uses the
/// last definition. Earlier definitions are therefore assigned collision-free
/// unreferenced labels in the Reading-only copy; Live Preview and source mode
/// keep every original byte.
String _applyObsidianFootnoteDefinitionPrecedence(String source) {
  final definitions = _standardFootnoteDefinitions(source);
  if (definitions.length < 2) return source;

  final lastByLabel = <String, int>{};
  for (var index = 0; index < definitions.length; index += 1) {
    lastByLabel[definitions[index].normalizedLabel] = index;
  }
  if (lastByLabel.length == definitions.length) return source;

  final reservedLabels = RegExp(
    r'\[\^([^\] \r\n\x00\t]+)\]',
  ).allMatches(source).map((match) => match.group(1)!.toLowerCase()).toSet();
  var nextShadowOrdinal = 1;
  String allocateShadowLabel() {
    var label = 'ianvs-shadowed-footnote-$nextShadowOrdinal';
    while (reservedLabels.contains(label)) {
      nextShadowOrdinal += 1;
      label = 'ianvs-shadowed-footnote-$nextShadowOrdinal';
    }
    nextShadowOrdinal += 1;
    reservedLabels.add(label);
    return label;
  }

  final output = StringBuffer();
  var cursor = 0;
  for (var index = 0; index < definitions.length; index += 1) {
    final definition = definitions[index];
    if (lastByLabel[definition.normalizedLabel] == index) continue;
    output
      ..write(source.substring(cursor, definition.labelStart))
      ..write(allocateShadowLabel());
    cursor = definition.labelEnd;
  }
  output.write(source.substring(cursor));
  return output.toString();
}

List<_ObsidianStandardFootnoteDefinition> _standardFootnoteDefinitions(
  String source,
) {
  final definitions = <_ObsidianStandardFootnoteDefinition>[];
  final definitionPattern = RegExp(
    r'^[ ]{0,3}\[\^([^\] \r\n\x00\t]+)\]:[ \t]*',
  );
  var fenceCharacter = 0;
  var fenceLength = 0;
  var lineStart = 0;
  while (lineStart <= source.length) {
    final newline = source.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? source.length : newline;
    final line = source.substring(lineStart, lineEnd);
    final fence = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      if (fenceLength == 0) {
        fenceCharacter = marker.codeUnitAt(0);
        fenceLength = marker.length;
      } else if (marker.codeUnitAt(0) == fenceCharacter &&
          marker.length >= fenceLength) {
        fenceCharacter = 0;
        fenceLength = 0;
      }
    } else if (fenceLength == 0) {
      final definition = definitionPattern.firstMatch(line);
      if (definition != null) {
        final label = definition.group(1)!;
        final labelStart =
            lineStart +
            definition.start +
            definition.group(0)!.indexOf('[^') +
            2;
        definitions.add(
          _ObsidianStandardFootnoteDefinition(
            labelStart: labelStart,
            labelEnd: labelStart + label.length,
            normalizedLabel: label.toLowerCase(),
          ),
        );
      }
    }
    if (newline < 0) break;
    lineStart = newline + 1;
  }
  return definitions;
}

final class _ObsidianFootnoteOrdinalCollector {
  _ObsidianFootnoteOrdinalCollector(this.definedLabels);

  final Set<String> definedLabels;
  final Map<String, int> standardOrdinals = <String, int>{};
  final Map<String, int> _standardOccurrences = <String, int>{};
  final List<IanvsMarkdownLivePreviewFootnoteReference> presentations =
      <IanvsMarkdownLivePreviewFootnoteReference>[];
  int _nextOrdinal = 1;

  void scan(
    String source, {
    bool allowFences = true,
    int sourceOffset = 0,
    bool collectPresentations = false,
  }) {
    var index = 0;
    var fenceCharacter = 0;
    var fenceLength = 0;
    var lineStart = true;

    while (index < source.length) {
      if (allowFences && lineStart) {
        final lineEnd = source.indexOf('\n', index);
        final end = lineEnd < 0 ? source.length : lineEnd;
        final line = source.substring(index, end);
        final fence = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
        if (fence != null) {
          final marker = fence.group(1)!;
          if (fenceLength == 0) {
            fenceCharacter = marker.codeUnitAt(0);
            fenceLength = marker.length;
          } else if (marker.codeUnitAt(0) == fenceCharacter &&
              marker.length >= fenceLength) {
            fenceCharacter = 0;
            fenceLength = 0;
          }
          index = lineEnd < 0 ? source.length : lineEnd + 1;
          lineStart = true;
          continue;
        }
      }

      final character = source.codeUnitAt(index);
      if (fenceLength > 0) {
        lineStart = character == 0x0a;
        index += 1;
        continue;
      }
      if (character == 0x60) {
        final runLength = _characterRunLength(source, index, 0x60);
        final codeEnd = _ianvsMarkdownInlineCodeSpanEnd(source, index);
        if (codeEnd != null) {
          index = codeEnd;
          lineStart = false;
          continue;
        }
        index += runLength;
        lineStart = false;
        continue;
      }
      if (character == 0x5e &&
          index + 1 < source.length &&
          source.codeUnitAt(index + 1) == 0x5b &&
          !isIanvsMarkdownEscapedAt(source, index)) {
        final close = findIanvsMarkdownInlineFootnoteEnd(source, index + 2);
        if (close >= 0) {
          final ordinal = _nextOrdinal;
          _nextOrdinal += 1;
          if (collectPresentations) {
            presentations.add(
              IanvsMarkdownLivePreviewFootnoteReference(
                sourceRange: TextRange(
                  start: sourceOffset + index,
                  end: sourceOffset + close + 1,
                ),
                ordinal: ordinal,
                occurrence: 1,
              ),
            );
          }
          scan(
            source.substring(index + 2, close),
            allowFences: false,
            sourceOffset: sourceOffset + index + 2,
          );
          index = close + 1;
          lineStart = false;
          continue;
        }
      }
      if (character == 0x5b &&
          index + 2 < source.length &&
          source.codeUnitAt(index + 1) == 0x5e &&
          !isIanvsMarkdownEscapedAt(source, index)) {
        final close = source.indexOf(']', index + 2);
        if (close >= 0 &&
            !source.substring(index + 2, close).contains('\n') &&
            (close + 1 >= source.length ||
                source.codeUnitAt(close + 1) != 0x3a)) {
          final label = source.substring(index + 2, close).toLowerCase();
          if (label.isNotEmpty &&
              !label.contains(RegExp(r'[ \t]')) &&
              definedLabels.contains(label)) {
            final ordinal = standardOrdinals.putIfAbsent(
              label,
              () => _nextOrdinal++,
            );
            final occurrence = (_standardOccurrences[label] ?? 0) + 1;
            _standardOccurrences[label] = occurrence;
            if (collectPresentations) {
              presentations.add(
                IanvsMarkdownLivePreviewFootnoteReference(
                  sourceRange: TextRange(
                    start: sourceOffset + index,
                    end: sourceOffset + close + 1,
                  ),
                  ordinal: ordinal,
                  occurrence: occurrence,
                ),
              );
            }
            index = close + 1;
            lineStart = false;
            continue;
          }
        }
      }
      lineStart = character == 0x0a;
      index += 1;
    }
  }
}

String _stripObsidianComments(String source) {
  final output = StringBuffer();
  var cursor = 0;
  for (final range in ianvsMarkdownCommentRanges(source)) {
    output.write(source.substring(cursor, range.start));
    for (var index = range.start; index < range.end; index += 1) {
      if (source.codeUnitAt(index) == 0x0a) output.write('\n');
    }
    cursor = range.end;
  }
  output.write(source.substring(cursor));
  return output.toString();
}

String _maskObsidianComments(String source) {
  final output = StringBuffer();
  var cursor = 0;
  for (final range in ianvsMarkdownCommentRanges(source)) {
    output.write(source.substring(cursor, range.start));
    for (var index = range.start; index < range.end; index += 1) {
      final character = source.codeUnitAt(index);
      output.writeCharCode(
        character == 0x0a || character == 0x0d ? character : 0x20,
      );
    }
    cursor = range.end;
  }
  output.write(source.substring(cursor));
  return output.toString();
}

String _stripBlockIdentifiers(String source) {
  final output = StringBuffer();
  var cursor = 0;
  for (final range in ianvsMarkdownBlockIdRanges(source)) {
    output.write(source.substring(cursor, range.start));
    cursor = range.end;
  }
  output.write(source.substring(cursor));
  return output.toString();
}

String _expandInlineFootnotes(String source) {
  final labels = RegExp(
    r'\[\^([^\] \r\n\x00\t]+)\]',
  ).allMatches(source).map((match) => match.group(1)!.toLowerCase()).toSet();
  final expansion = _InlineFootnoteExpansion(labels);
  final transformed = expansion.expand(source);
  if (expansion.definitions.isEmpty) return transformed;
  final result = StringBuffer(transformed);
  if (!transformed.endsWith('\n\n')) {
    result.write(transformed.endsWith('\n') ? '\n' : '\n\n');
  }
  for (final definition in expansion.definitions) {
    result.writeln('[^${definition.label}]: ${definition.body}');
  }
  return result.toString().trimRight();
}

final class _ExpandedInlineFootnoteDefinition {
  _ExpandedInlineFootnoteDefinition(this.label);

  final String label;
  String body = '';
}

final class _InlineFootnoteExpansion {
  _InlineFootnoteExpansion(this.labels);

  final Set<String> labels;
  final List<_ExpandedInlineFootnoteDefinition> definitions = [];
  int _nextLabelOrdinal = 1;

  String expand(String source, {bool allowFences = true}) {
    final output = StringBuffer();
    var index = 0;
    var fenceCharacter = 0;
    var fenceLength = 0;
    var lineStart = true;

    while (index < source.length) {
      if (allowFences && lineStart) {
        final lineEnd = source.indexOf('\n', index);
        final end = lineEnd < 0 ? source.length : lineEnd;
        final line = source.substring(index, end);
        final fence = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
        if (fence != null) {
          final marker = fence.group(1)!;
          if (fenceLength == 0) {
            fenceCharacter = marker.codeUnitAt(0);
            fenceLength = marker.length;
          } else if (marker.codeUnitAt(0) == fenceCharacter &&
              marker.length >= fenceLength) {
            fenceLength = 0;
            fenceCharacter = 0;
          }
          output.write(line);
          if (lineEnd >= 0) output.write('\n');
          index = lineEnd < 0 ? source.length : lineEnd + 1;
          lineStart = true;
          continue;
        }
      }

      final character = source.codeUnitAt(index);
      if (fenceLength > 0) {
        output.writeCharCode(character);
        lineStart = character == 0x0a;
        index += 1;
        continue;
      }

      if (character == 0x60) {
        final runLength = _characterRunLength(source, index, 0x60);
        final codeEnd = _ianvsMarkdownInlineCodeSpanEnd(source, index);
        if (codeEnd != null) {
          output.write(source.substring(index, codeEnd));
          index = codeEnd;
          lineStart = false;
          continue;
        }
        output.write(source.substring(index, index + runLength));
        index += runLength;
        lineStart = false;
        continue;
      }

      final canStartFootnote =
          character == 0x5e &&
          index + 1 < source.length &&
          source.codeUnitAt(index + 1) == 0x5b &&
          !isIanvsMarkdownEscapedAt(source, index);
      if (canStartFootnote) {
        final close = findIanvsMarkdownInlineFootnoteEnd(source, index + 2);
        if (close >= 0) {
          final body = source.substring(index + 2, close).trim();
          final label = _allocateLabel();
          final definition = _ExpandedInlineFootnoteDefinition(label);
          definitions.add(definition);
          definition.body = expand(body, allowFences: false);
          output.write('[^$label]');
          index = close + 1;
          lineStart = false;
          continue;
        }
      }

      output.writeCharCode(character);
      lineStart = character == 0x0a;
      index += 1;
    }

    return output.toString();
  }

  String _allocateLabel() {
    var label = 'ianvs-inline-footnote-$_nextLabelOrdinal';
    while (labels.contains(label)) {
      _nextLabelOrdinal += 1;
      label = 'ianvs-inline-footnote-$_nextLabelOrdinal';
    }
    _nextLabelOrdinal += 1;
    labels.add(label);
    return label;
  }
}

int _characterRunLength(String source, int start, int character) {
  var end = start;
  while (end < source.length && source.codeUnitAt(end) == character) {
    end += 1;
  }
  return end - start;
}

int? _ianvsMarkdownInlineCodeSpanEnd(String source, int openingStart) {
  if (openingStart < 0 ||
      openingStart >= source.length ||
      source.codeUnitAt(openingStart) != 0x60 ||
      (openingStart > 0 && source.codeUnitAt(openingStart - 1) == 0x60)) {
    return null;
  }
  final openingLength = _characterRunLength(source, openingStart, 0x60);
  var search = openingStart + openingLength;
  while (search < source.length) {
    final candidate = source.indexOf('`', search);
    if (candidate < 0) return null;
    final candidateLength = _characterRunLength(source, candidate, 0x60);
    if (candidateLength == openingLength) {
      return candidate + candidateLength;
    }
    search = candidate + candidateLength;
  }
  return null;
}
