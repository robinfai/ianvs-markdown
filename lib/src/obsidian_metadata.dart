import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'footnote_syntax.dart';
import 'theme.dart';

/// Determines whether Obsidian editing metadata is shown or consumed.
enum IanvsMarkdownObsidianMetadataMode {
  /// Omit comments and block IDs, and collect inline footnotes at the end.
  reading,

  /// Preserve source-like metadata so a live editor can display it dimmed.
  editing,
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
  return _expandInlineFootnotes(withoutBlockIds);
}

/// Parses editing-only inline metadata into a styled renderer element while
/// retaining the exact source text, including its delimiters.
final class IanvsMarkdownEditingMetadataInlineSyntax extends md.InlineSyntax {
  IanvsMarkdownEditingMetadataInlineSyntax.comment()
    : kind = 'comment',
      super(r'%%(?:[\s\S]*?%%|[\s\S]*)', startCharacter: 0x25);

  IanvsMarkdownEditingMetadataInlineSyntax.blockId()
    : kind = 'block-id',
      super(r'[ \t]+\^[A-Za-z0-9-]+[ \t]*(?=\n|$)');

  IanvsMarkdownEditingMetadataInlineSyntax.standardFootnote()
    : kind = 'footnote-ref',
      super(r'\[\^[^\] \r\n\x00\t]+\](?!:)', startCharacter: 0x5b);

  IanvsMarkdownEditingMetadataInlineSyntax.inlineFootnote()
    : kind = 'inline-footnote',
      super(r'\^\[', startCharacter: 0x5e);

  final String kind;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
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

Set<String> _collectStandardFootnoteDefinitionLabels(String source) {
  final labels = <String>{};
  var fenceCharacter = 0;
  var fenceLength = 0;
  final definitionPattern = RegExp(
    r'^[ ]{0,3}\[\^([^\] \r\n\x00\t]+)\]:[ \t]*',
  );
  for (final line in source.split('\n')) {
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
      continue;
    }
    if (fenceLength > 0) continue;
    final definition = definitionPattern.firstMatch(line);
    if (definition != null) labels.add(definition.group(1)!.toLowerCase());
  }
  return labels;
}

final class _ObsidianFootnoteOrdinalCollector {
  _ObsidianFootnoteOrdinalCollector(this.definedLabels);

  final Set<String> definedLabels;
  final Map<String, int> standardOrdinals = <String, int>{};
  int _nextOrdinal = 1;

  void scan(String source, {bool allowFences = true}) {
    var index = 0;
    var fenceCharacter = 0;
    var fenceLength = 0;
    var inlineCodeLength = 0;
    var lineStart = true;

    while (index < source.length) {
      if (allowFences && lineStart && inlineCodeLength == 0) {
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
        if (inlineCodeLength == 0) {
          inlineCodeLength = runLength;
        } else if (inlineCodeLength == runLength) {
          inlineCodeLength = 0;
        }
        index += runLength;
        lineStart = false;
        continue;
      }
      if (inlineCodeLength == 0 &&
          character == 0x5e &&
          index + 1 < source.length &&
          source.codeUnitAt(index + 1) == 0x5b &&
          !isIanvsMarkdownEscapedAt(source, index)) {
        final close = findIanvsMarkdownInlineFootnoteEnd(source, index + 2);
        if (close >= 0) {
          _nextOrdinal += 1;
          scan(source.substring(index + 2, close), allowFences: false);
          index = close + 1;
          lineStart = false;
          continue;
        }
      }
      if (inlineCodeLength == 0 &&
          character == 0x5b &&
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
            standardOrdinals.putIfAbsent(label, () => _nextOrdinal++);
            index = close + 1;
            lineStart = false;
            continue;
          }
        }
      }
      lineStart = character == 0x0a;
      if (lineStart) inlineCodeLength = 0;
      index += 1;
    }
  }
}

String _stripObsidianComments(String source) {
  final output = StringBuffer();
  var index = 0;
  var inComment = false;
  var fenceCharacter = 0;
  var fenceLength = 0;
  var inlineCodeLength = 0;
  var lineStart = true;

  while (index < source.length) {
    if (lineStart && !inComment && inlineCodeLength == 0) {
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

    if (!inComment && character == 0x60) {
      final runLength = _characterRunLength(source, index, 0x60);
      if (inlineCodeLength == 0) {
        inlineCodeLength = runLength;
      } else if (runLength == inlineCodeLength) {
        inlineCodeLength = 0;
      }
      output.write(source.substring(index, index + runLength));
      index += runLength;
      lineStart = false;
      continue;
    }

    final isCommentMarker =
        inlineCodeLength == 0 &&
        character == 0x25 &&
        index + 1 < source.length &&
        source.codeUnitAt(index + 1) == 0x25;
    if (isCommentMarker) {
      inComment = !inComment;
      index += 2;
      lineStart = false;
      continue;
    }

    if (!inComment) {
      output.writeCharCode(character);
    } else if (character == 0x0a) {
      // Preserve line structure so removing a block comment cannot join the
      // surrounding Markdown blocks together.
      output.write('\n');
    }
    lineStart = character == 0x0a;
    if (lineStart) inlineCodeLength = 0;
    index += 1;
  }
  return output.toString();
}

String _stripBlockIdentifiers(String source) {
  final lines = source.split('\n');
  var fenceCharacter = 0;
  var fenceLength = 0;
  final blockId = RegExp(r'[ \t]+\^[A-Za-z0-9-]+[ \t]*$');

  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
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
      continue;
    }
    if (fenceLength == 0) {
      lines[index] = line.replaceFirst(blockId, '');
    }
  }
  return lines.join('\n');
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
    var inlineCodeLength = 0;
    var lineStart = true;

    while (index < source.length) {
      if (allowFences && lineStart && inlineCodeLength == 0) {
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
        if (inlineCodeLength == 0) {
          inlineCodeLength = runLength;
        } else if (runLength == inlineCodeLength) {
          inlineCodeLength = 0;
        }
        output.write(source.substring(index, index + runLength));
        index += runLength;
        lineStart = false;
        continue;
      }

      final canStartFootnote =
          inlineCodeLength == 0 &&
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
      if (lineStart) inlineCodeLength = 0;
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
