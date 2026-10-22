import 'dart:convert';

import 'package:flutter/services.dart' show TextRange;
import 'package:markdown/markdown.dart' as md;
import 'package:yaml/yaml.dart';

import 'editor/editor_models.dart';
import 'editor/markdown_code_ranges.dart';
import 'front_matter.dart' show markdownFrontMatterByteLimit;
import 'markdown_link_source.dart';
import 'math.dart';
import 'obsidian_autolink.dart';
import 'obsidian_inline.dart';
import 'obsidian_metadata.dart';
import 'render_budget.dart';
import 'wiki_link_reference.dart';

/// The source syntax of a note reference, independent of host resolution.
enum IanvsMarkdownSourceReferenceKind {
  markdownLink,
  markdownImage,
  markdownReferenceLink,
  markdownReferenceImage,
  markdownDefinition,
  wikiLink,
  wikiEmbed,
}

/// An exact source occurrence. Ranges use original UTF-16 code-unit offsets.
final class IanvsMarkdownSourceReference {
  const IanvsMarkdownSourceReference({
    required this.range,
    required this.destinationRange,
    required this.rawDestination,
    required this.target,
    required this.kind,
    this.fragment,
    this.query,
    this.alias,
    this.title,
    this.definitionIdentity,
    this.definitionRange,
  });

  /// Complete occurrence, including delimiters, label, fragment and title.
  final TextRange range;

  /// Only the path in its original spelling, excluding brackets, query, fragment,
  /// alias and title. A reference use points to its effective definition's
  /// destination, never to the use's display label.
  final TextRange destinationRange;

  /// Exact full destination including fragment, excluding wrappers and title.
  final String rawDestination;

  /// Semantic path before query and fragment. Markdown URI escaping is decoded once;
  /// Wiki paths retain literal percent sequences. Hosts must not decode again.
  final String target;
  final String? fragment;
  final String? query;
  final String? alias;
  final String? title;
  final IanvsMarkdownSourceReferenceKind kind;

  /// Effective normalized label plus its original definition source range.
  final String? definitionIdentity;
  final TextRange? definitionRange;
}

final class IanvsMarkdownSourceTag {
  const IanvsMarkdownSourceTag({required this.name, required this.range});

  /// Tag name without an optional leading hash.
  final String name;

  /// Original inline tag or YAML scalar range, including its source delimiters.
  final TextRange range;
}

/// A coverage limitation, not a claim that the note contains no references.
final class IanvsMarkdownSemanticIssue {
  const IanvsMarkdownSemanticIssue({
    required this.code,
    required this.message,
    this.range,
  });
  final String code;
  final String message;
  final TextRange? range;
}

/// Storage-agnostic, immutable semantic snapshot of one exact source revision.
final class IanvsMarkdownNoteSemantics {
  IanvsMarkdownNoteSemantics({
    required List<IanvsMarkdownSourceReference> references,
    required List<IanvsMarkdownSourceTag> tags,
    required List<String> aliases,
    required List<IanvsMarkdownSemanticIssue> issues,
    required this.aliasesComplete,
  }) : references = List.unmodifiable(references),
       tags = List.unmodifiable(tags),
       aliases = List.unmodifiable(aliases),
       issues = List.unmodifiable(issues);

  final List<IanvsMarkdownSourceReference> references;
  final List<IanvsMarkdownSourceTag> tags;
  final List<String> aliases;
  final List<IanvsMarkdownSemanticIssue> issues;

  /// Independent YAML alias coverage, even if body parsing is unsupported.
  final bool aliasesComplete;
  bool get complete => issues.isEmpty;
}

/// Parses bounded, source-preserving note references and metadata.
///
/// No files are read, targets resolved, or source rewritten. CommonMark link
/// recognition and definition precedence belong to package:markdown, while
/// container/code, Wiki and comment grammar reuse the editor/renderer helpers.
/// Unsupported or over-budget input is explicitly incomplete, never a silently
/// empty authoritative result. See doc/NOTE_SEMANTICS.md for coverage limits.
IanvsMarkdownNoteSemantics parseIanvsMarkdownNoteSemantics(String source) {
  final collector = _SemanticCollector(source);
  final bodyStart = collector.frontMatter();
  final decision = scanMarkdownForRendering(
    source,
    budget: const IanvsMarkdownRenderBudget(),
  );
  if (!decision.useMarkdown) {
    collector.issue(
      'bodyBudget',
      'Markdown input exceeds ${decision.budgetExceeded?.name}.',
    );
    return collector.finish();
  }
  try {
    final excluded = <TextRange>[
      if (bodyStart > 0) TextRange(start: 0, end: bodyStart),
    ];
    var projected = _mask(source, excluded);
    final comments = ianvsMarkdownCommentRanges(projected);
    // A BOM has no semantic content but remains one source code unit.
    if (source.startsWith('\ufeff')) {
      excluded.add(const TextRange(start: 0, end: 1));
    }
    projected = _mask(source, excluded);
    final regions = ianvsMarkdownSemanticSourceRegions(
      projected,
      removedRanges: comments,
    );
    final active = <IanvsMarkdownSemanticSourceRegion>[];
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    for (final region in regions) {
      final unsupportedContext = region.unsupportedContext;
      if (unsupportedContext != null) {
        collector.issue(
          unsupportedContext,
          unsupportedContext == 'calloutContext'
              ? 'Recursive callout renderer contexts are not source-indexed.'
              : 'Inline footnote expansion is not source-indexed.',
          range: region.originalRange(0, region.source.length),
        );
        continue;
      }
      switch (region.type) {
        case IanvsMarkdownBlockType.fencedCode:
        case IanvsMarkdownBlockType.indentedCode:
        case IanvsMarkdownBlockType.displayMath:
        case IanvsMarkdownBlockType.frontMatter:
          continue;
        case IanvsMarkdownBlockType.table:
          // Each table region is already one native TableSyntax cell. Cells
          // contain inline Markdown, never global reference definitions.
          active.add(region);
          continue;
        case IanvsMarkdownBlockType.html:
          // The renderer has host-extensible HTML blocks. Do not claim complete
          // semantics for their contents or reinterpret raw HTML as Markdown.
          if (!region.source.trimLeft().startsWith('<!--')) {
            collector.issue(
              'htmlContext',
              'HTML block semantics are not indexed.',
              range: region.originalRange(0, region.source.length),
            );
          }
          continue;
        default:
          active.add(region);
      }
      final definitionSyntax = _DefinitionSyntax(collector, region);
      final lines = region.source.split('\n').map(md.Line.new).toList();
      definitionSyntax.lines = lines;
      final parser = md.BlockParser(lines, document);
      final definitionIndex = parser.blockSyntaxes.indexWhere(
        (syntax) => syntax is md.LinkReferenceDefinitionSyntax,
      );
      parser.blockSyntaxes[definitionIndex] = definitionSyntax;
      parser.parseLines();
    }
    for (final region in active) {
      collector.parseInline(region, document.linkReferences);
    }
  } on _SemanticOccurrenceLimit {
    collector.issue(
      'occurrenceBudget',
      'Semantic references, tags and issues exceed the 4096-occurrence limit.',
    );
  } on Object {
    collector.issue(
      'parserLimit',
      'The bounded parser could not establish complete source semantics.',
    );
  }
  return collector.finish();
}

final class _SemanticOccurrenceLimit implements Exception {
  const _SemanticOccurrenceLimit();
}

final class _SemanticCollector {
  _SemanticCollector(this.source);
  final String source;
  final references = <IanvsMarkdownSourceReference>[];
  final tags = <IanvsMarkdownSourceTag>[];
  final aliases = <String>[];
  final issues = <IanvsMarkdownSemanticIssue>[];
  final definitions = <String, IanvsMarkdownSourceReference>{};
  final definitionRanges =
      <IanvsMarkdownSemanticSourceRegion, List<TextRange>>{};
  bool aliasesComplete = true;

  void addReference(IanvsMarkdownSourceReference reference) {
    _checkOccurrenceBudget();
    references.add(reference);
  }

  void addTag(IanvsMarkdownSourceTag tag) {
    _checkOccurrenceBudget();
    tags.add(tag);
  }

  void _checkOccurrenceBudget() {
    if (references.length + tags.length + issues.length >= 4096) {
      throw const _SemanticOccurrenceLimit();
    }
  }

  void issue(String code, String message, {TextRange? range}) {
    // Terminal catch handlers must not themselves throw when the allowance
    // has just been exhausted by the last successfully collected occurrence.
    if (code != 'occurrenceBudget' && code != 'parserLimit') {
      _checkOccurrenceBudget();
    }
    issues.add(
      IanvsMarkdownSemanticIssue(code: code, message: message, range: range),
    );
  }

  IanvsMarkdownNoteSemantics finish() {
    references.sort((a, b) => a.range.start.compareTo(b.range.start));
    tags.sort((a, b) => a.range.start.compareTo(b.range.start));
    return IanvsMarkdownNoteSemantics(
      references: references,
      tags: tags,
      aliases: aliases,
      issues: issues,
      aliasesComplete: aliasesComplete,
    );
  }

  int frontMatter() {
    final firstEnd = source.indexOf('\n');
    final bom = source.startsWith('\ufeff') ? 1 : 0;
    if (firstEnd < 0 ||
        source.substring(bom, firstEnd).replaceAll('\r', '') != '---') {
      return 0;
    }
    final rawStart = firstEnd + 1;
    var lineStart = rawStart;
    var closing = -1;
    var bodyStart = source.length;
    while (lineStart <= source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      if (source.substring(lineStart, lineEnd).replaceAll('\r', '') == '---') {
        closing = lineStart;
        bodyStart = newline < 0 ? source.length : newline + 1;
        break;
      }
      if (lineStart - rawStart > markdownFrontMatterByteLimit || newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    if (closing < 0 || closing - rawStart > markdownFrontMatterByteLimit) {
      aliasesComplete = false;
      issue(
        'frontMatterBoundary',
        'Front matter is unclosed or exceeds the 64 KiB limit.',
      );
      return bodyStart;
    }
    final raw = source.substring(rawStart, closing);
    if (utf8.encode(raw).length > markdownFrontMatterByteLimit) {
      aliasesComplete = false;
      issue('frontMatterBudget', 'Front matter exceeds the 64 KiB limit.');
      return bodyStart;
    }
    final YamlNode root;
    try {
      root = loadYamlNode(raw);
    } on Object {
      aliasesComplete = false;
      issue('frontMatterYaml', 'Front matter is not valid YAML.');
      return bodyStart;
    }
    if (root is YamlScalar && root.value == null) return bodyStart;
    if (root is! YamlMap) {
      aliasesComplete = false;
      issue('frontMatterType', 'Front matter is not a mapping.');
      return bodyStart;
    }
    var aliasCount = 0;
    var tagCount = 0;
    for (final entry in root.nodes.entries) {
      final key = (entry.key as YamlNode).value;
      if (key is! String) continue;
      if (key == '<<') {
        aliasesComplete = false;
        issue('metadataMerge', 'YAML merge metadata is not source-indexed.');
        continue;
      }
      final alias = key == 'aliases' || key == 'alias';
      final tag = key == 'tags' || key == 'tag';
      if (!alias && !tag) continue;
      final value = entry.value;
      final keyNode = entry.key as YamlNode;
      if (value.span.start.offset < keyNode.span.end.offset ||
          _hasYamlAnchor(keyNode) ||
          _hasYamlAnchor(value)) {
        if (alias) aliasesComplete = false;
        issue(
          'metadataAnchor',
          '$key anchors and aliases are not source-indexed.',
        );
        continue;
      }
      final nodes = value is YamlList ? value.nodes : <YamlNode>[value];
      if (alias) aliasCount += nodes.length;
      if (tag) tagCount += nodes.length;
      if (aliasCount > 1024 || tagCount > 1024) {
        if (alias) aliasesComplete = false;
        issue('metadataCount', '$key exceeds the 1024-value semantic limit.');
        continue;
      }
      for (final node in nodes) {
        final text = node.value;
        if (node.span.start.offset < value.span.start.offset ||
            node.span.end.offset > value.span.end.offset ||
            _hasYamlAnchor(node)) {
          if (alias) aliasesComplete = false;
          issue(
            'metadataAnchor',
            '$key anchors and aliases are not source-indexed.',
          );
          continue;
        }
        final range = TextRange(
          start: rawStart + node.span.start.offset,
          end: rawStart + node.span.end.offset,
        );
        if (text is! String ||
            text.length > 1024 ||
            text.contains('\n') ||
            text.contains('\r') ||
            text.trim().isEmpty) {
          if (alias) aliasesComplete = false;
          issue(
            'metadataValue',
            '$key supports bounded nonempty strings or string lists only.',
            range: range,
          );
          continue;
        }
        final name = text.trim();
        if (alias) aliases.add(name);
        if (tag) {
          final spelling = name.startsWith('#') ? name : '#$name';
          final lexical = ianvsMarkdownTagRanges(spelling);
          if (lexical.length != 1 ||
              lexical.single.start != 0 ||
              lexical.single.end != spelling.length) {
            issue(
              'metadataTag',
              'YAML tags must be complete valid inline tag names.',
              range: range,
            );
            continue;
          }
          addTag(
            IanvsMarkdownSourceTag(
              name: name.startsWith('#') ? name.substring(1) : name,
              range: range,
            ),
          );
        }
      }
    }
    return bodyStart;
  }

  void parseInline(
    IanvsMarkdownSemanticSourceRegion region,
    Map<String, md.LinkReference> linkReferences,
  ) {
    if (region.type != IanvsMarkdownBlockType.table &&
        RegExp(
          r'^ {0,3}\[\^[^\]\n]+\]:',
          multiLine: true,
        ).hasMatch(region.source)) {
      issue(
        'footnoteContext',
        'Footnote definition bodies are not source-indexed.',
        range: region.originalRange(0, region.source.length),
      );
      return;
    }
    final localExclusions = definitionRanges[region] ?? const <TextRange>[];
    final input = _mask(region.source, localExclusions);
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [
        IanvsMarkdownCodeSpanSyntax(),
        IanvsMarkdownInlineDisplayMathSyntax(),
        IanvsMarkdownInlineMathSyntax(),
        IanvsMarkdownLiteralReferenceWhitespaceSyntax(),
        _HtmlSyntax(this, region),
        _AutolinkSyntax(this, region),
        _WikiSyntax(this, region),
        _TagSyntax(this, region),
        _LinkSyntax(this, region),
        _ImageSyntax(this, region),
      ],
    )..linkReferences.addAll(linkReferences);
    document.parseInline(input);
  }

  void recordLink(
    IanvsMarkdownSemanticSourceRegion region,
    md.InlineParser parser,
    int start,
    int labelEnd,
    Iterable<md.Node> nodes, {
    required bool image,
  }) {
    final elements = nodes.whereType<md.Element>().toList();
    final expected = image ? 'img' : 'a';
    if (elements.length != 1 || elements.single.tag != expected) return;
    final element = elements.single;
    final end = parser.pos + 1;
    final input = parser.source;
    final suffix = labelEnd + 1;
    final range = region.originalRange(start, end);
    if (image) {
      final labelRange = region.originalRange(start, labelEnd + 1);
      // The renderer flattens image descriptions to alt text, so their nested
      // links and tags do not survive as reference occurrences.
      references.removeWhere(
        (reference) =>
            reference.range.start >= labelRange.start &&
            reference.range.end <= labelRange.end,
      );
      tags.removeWhere(
        (tag) =>
            tag.range.start >= labelRange.start &&
            tag.range.end <= labelRange.end,
      );
    }
    if (suffix < input.length &&
        input.codeUnitAt(suffix) == 0x28 &&
        findIanvsMarkdownInlineLinkEnd(input, suffix) == end) {
      final destination = _destinationRange(input, suffix + 1, end - 1);
      if (destination == null) {
        issue(
          'destinationSpan',
          'The parsed destination cannot be mapped safely.',
          range: range,
        );
        return;
      }
      var semantic = element.attributes[image ? 'src' : 'href'];
      if (!image) {
        final exact = input.substring(start, end);
        final projected =
            projectObsidianInlineLinkDestinationBackslashesForRendering(exact);
        if (projected != exact) {
          final nodes = md.Document()
              .parseInline(projected)
              .whereType<md.Element>();
          if (nodes.length == 1 && nodes.single.tag == 'a') {
            semantic = nodes.single.attributes['href'];
          }
        }
      }
      addDestination(
        region,
        range,
        destination,
        kind: image
            ? IanvsMarkdownSourceReferenceKind.markdownImage
            : IanvsMarkdownSourceReferenceKind.markdownLink,
        semantic: semantic,
        title: element.attributes['title'],
      );
      return;
    }
    final probe = md.Document()
      ..linkReferences.addAll({
        for (final key in definitions.keys)
          key: md.LinkReference(key, key, null),
      });
    final probeNodes = probe.parseInline(input.substring(start, end));
    final probeLinks = probeNodes.whereType<md.Element>().where(
      (node) => node.tag == expected,
    );
    final identity = probeLinks.length == 1
        ? probeLinks.single.attributes[image ? 'src' : 'href']
        : null;
    final definition = identity == null
        ? null
        : definitions[_decodeUriComponent(identity)];
    if (definition == null) {
      issue(
        'definitionSpan',
        'A parsed reference has no authoritative definition span.',
        range: range,
      );
      return;
    }
    addReference(
      IanvsMarkdownSourceReference(
        range: range,
        destinationRange: definition.destinationRange,
        rawDestination: definition.rawDestination,
        target: definition.target,
        fragment: definition.fragment,
        query: definition.query,
        title: definition.title,
        kind: image
            ? IanvsMarkdownSourceReferenceKind.markdownReferenceImage
            : IanvsMarkdownSourceReferenceKind.markdownReferenceLink,
        definitionIdentity: definition.definitionIdentity,
        definitionRange: definition.range,
      ),
    );
  }

  IanvsMarkdownSourceReference? addDestination(
    IanvsMarkdownSemanticSourceRegion region,
    TextRange range,
    TextRange localDestination, {
    required IanvsMarkdownSourceReferenceKind kind,
    String? semantic,
    String? authoritativeRawDestination,
    String? title,
    String? definitionIdentity,
    TextRange? definitionRange,
    String? alias,
  }) {
    final original = region.originalRange(
      localDestination.start,
      localDestination.end,
    );
    final raw = original.textInside(source);
    final projectedRaw = localDestination.textInside(region.source);
    if (!region.matchesOriginalSource(
      localDestination.start,
      localDestination.end,
      source,
    )) {
      issue(
        'nonContiguousDestination',
        'The destination crosses a source transformation that cannot be rewritten safely.',
        range: original,
      );
      return null;
    }
    final wiki =
        kind == IanvsMarkdownSourceReferenceKind.wikiLink ||
        kind == IanvsMarkdownSourceReferenceKind.wikiEmbed;
    final href = semantic ?? projectedRaw;
    if (!wiki &&
        (semantic == null ||
            (authoritativeRawDestination != null
                ? projectedRaw != authoritativeRawDestination
                : !_matchesInlineDestination(
                    projectedRaw,
                    semantic,
                    angle:
                        localDestination.start > 0 &&
                        region.source.codeUnitAt(localDestination.start - 1) ==
                            0x3c,
                    projectBackslashes:
                        kind == IanvsMarkdownSourceReferenceKind.markdownLink,
                  )))) {
      issue(
        'destinationSpan',
        'The raw destination does not match the authoritative renderer target.',
        range: original,
      );
      return null;
    }
    final hash = href.indexOf('#');
    final rawHash = _rawDelimiterOffset(projectedRaw, '#', wiki: wiki);
    final question = wiki ? -1 : href.indexOf('?');
    final query = question >= 0 && (hash < 0 || question < hash)
        ? question
        : -1;
    final rawQuestion = wiki
        ? null
        : _rawDelimiterOffset(projectedRaw, '?', wiki: false);
    final rawQuery = query >= 0 ? rawQuestion : null;
    if ((hash >= 0) != (rawHash != null) || (query >= 0 && rawQuery == null)) {
      issue(
        'destinationSpan',
        'The semantic query or fragment cannot be mapped safely.',
        range: range,
      );
      return null;
    }
    String decode(String value) {
      if (wiki) return value.trim();
      try {
        return _decodeUriComponent(value);
      } on FormatException {
        issue(
          'destinationEncoding',
          'The destination contains invalid URI encoding.',
          range: range,
        );
        return value;
      }
    }

    final ref = IanvsMarkdownSourceReference(
      range: range,
      destinationRange: region.originalRange(
        localDestination.start,
        localDestination.start + (rawQuery ?? rawHash ?? projectedRaw.length),
      ),
      rawDestination: raw,
      target: decode(
        href.substring(
          0,
          query >= 0
              ? query
              : hash >= 0
              ? hash
              : href.length,
        ),
      ),
      query: query < 0
          ? null
          : decode(href.substring(query + 1, hash < 0 ? href.length : hash)),
      fragment: hash < 0 ? null : decode(href.substring(hash + 1)),
      alias: alias,
      title: title,
      kind: kind,
      definitionIdentity: definitionIdentity,
      definitionRange: definitionRange,
    );
    addReference(ref);
    return ref;
  }
}

final class _DefinitionSyntax extends md.LinkReferenceDefinitionSyntax {
  _DefinitionSyntax(this.collector, this.region);
  final _SemanticCollector collector;
  final IanvsMarkdownSemanticSourceRegion region;
  late final List<md.Line> lines;

  @override
  md.Node? parse(md.BlockParser parser) {
    final first = lines.indexOf(parser.current);
    final before = Set<String>.of(parser.document.linkReferences.keys);
    final node = super.parse(parser);
    final next = parser.isDone ? lines.length : lines.indexOf(parser.current);
    if (first < 0 || next < 0) {
      collector.issue(
        'definitionContext',
        'A nested definition could not be source-mapped.',
      );
      return node;
    }
    if (next == first) return node;
    final start = lines
        .take(first)
        .fold<int>(0, (sum, line) => sum + line.content.length + 1);
    final end = lines
        .take(next)
        .fold<int>(0, (sum, line) => sum + line.content.length + 1)
        .clamp(0, region.source.length);
    final range = region.originalRange(start, end);
    collector.definitionRanges
        .putIfAbsent(region, () => [])
        .add(TextRange(start: start, end: end));
    final added = parser.document.linkReferences.keys.where(
      (key) => !before.contains(key),
    );
    for (final key in added) {
      final reference = parser.document.linkReferences[key]!;
      var bracket = start;
      while (bracket < end && region.source.codeUnitAt(bracket) != 0x5b) {
        bracket++;
      }
      final label = findIanvsMarkdownReferenceLabel(region.source, bracket);
      final destination = label == null
          ? null
          : _destinationRange(
              region.source,
              label.end + 1,
              end,
              definition: true,
            );
      if (destination == null) {
        collector.issue(
          'definitionSpan',
          'The definition destination cannot be source-mapped.',
          range: range,
        );
        continue;
      }
      final mdElement = md.LinkSyntax().createNode(
        reference.destination,
        reference.title,
        getChildren: () => const [],
      );
      final effective = collector.addDestination(
        region,
        range,
        destination,
        kind: IanvsMarkdownSourceReferenceKind.markdownDefinition,
        semantic: (mdElement as md.Element).attributes['href'],
        authoritativeRawDestination: reference.destination,
        title: mdElement.attributes['title'],
        definitionIdentity: '$key@${range.start}:${range.end}',
        definitionRange: range,
      );
      if (effective != null) collector.definitions[key] = effective;
    }
    return node;
  }
}

mixin _CaptureLink on md.LinkSyntax {
  _SemanticCollector get collector;
  IanvsMarkdownSemanticSourceRegion get region;
  bool get image;

  @override
  Iterable<md.Node>? close(
    md.InlineParser parser,
    covariant md.SimpleDelimiter opener,
    md.Delimiter? closer, {
    String? tag,
    required List<md.Node> Function() getChildren,
  }) {
    final labelEnd = parser.pos;
    final start = opener.endPos - (image ? 2 : 1);
    final nodes = super.close(
      parser,
      opener,
      closer,
      tag: tag,
      getChildren: getChildren,
    );
    if (nodes != null) {
      collector.recordLink(
        region,
        parser,
        start,
        labelEnd,
        nodes,
        image: image,
      );
    }
    return nodes;
  }
}

final class _LinkSyntax extends md.LinkSyntax with _CaptureLink {
  _LinkSyntax(this.collector, this.region);
  @override
  final _SemanticCollector collector;
  @override
  final IanvsMarkdownSemanticSourceRegion region;
  @override
  bool get image => false;
}

final class _ImageSyntax extends md.ImageSyntax with _CaptureLink {
  _ImageSyntax(this.collector, this.region);
  @override
  final _SemanticCollector collector;
  @override
  final IanvsMarkdownSemanticSourceRegion region;
  @override
  bool get image => true;
}

final class _WikiSyntax extends md.InlineSyntax {
  _WikiSyntax(this.collector, this.region) : super(r'!?\[\[([^\]\n]+)\]\]');
  final _SemanticCollector collector;
  final IanvsMarkdownSemanticSourceRegion region;
  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    // The renderer has a block embed syntax, not an inline embed syntax.
    // Let its normal image/link grammar decide this form inside a table cell.
    if (region.type == IanvsMarkdownBlockType.table &&
        parser.source.startsWith('![[', startMatchPos ?? parser.pos)) {
      return false;
    }
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final body = match.group(1)!;
    final embed = match.group(0)!.startsWith('!');
    final parsed = parseIanvsMarkdownWikiLinkBody(body);
    final embedSeparator = body.indexOf('|');
    final separator = embed
        ? embedSeparator < 0
              ? null
              : embedSeparator
        : parsed?.aliasSeparator;
    final rawTarget = body.substring(0, separator ?? body.length);
    final target = rawTarget.trim();
    final alias = separator == null
        ? null
        : body.substring(separator + 1).trim();
    if (embed ? target.isEmpty : parsed == null) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }
    if (!embed && alias != null && RegExp(r'[\[#<]').hasMatch(alias)) {
      collector.issue(
        'wikiAliasMarkup',
        'Nested links and tags in Wiki aliases are not source-indexed.',
        range: region.originalRange(match.start, match.end),
      );
    }
    final bodyStart = match.start + (embed ? 3 : 2);
    final trimmedStart = rawTarget.length - rawTarget.trimLeft().length;
    final destination = TextRange(
      start: bodyStart + trimmedStart,
      end: bodyStart + rawTarget.trimRight().length,
    );
    collector.addDestination(
      region,
      region.originalRange(match.start, match.end),
      destination,
      kind: embed
          ? IanvsMarkdownSourceReferenceKind.wikiEmbed
          : IanvsMarkdownSourceReferenceKind.wikiLink,
      semantic: target,
      alias: alias == null || alias.isEmpty ? null : alias,
    );
    parser.addNode(md.Text(match.group(0)!));
    return true;
  }
}

final class _AutolinkSyntax extends IanvsMarkdownAutolinkSyntax {
  _AutolinkSyntax(this.collector, this.region);
  final _SemanticCollector collector;
  final IanvsMarkdownSemanticSourceRegion region;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = parser.pos;
    final matched = super.tryMatch(parser, startMatchPos);
    if (matched) {
      collector.issue(
        'autolinkContext',
        'Automatic URL and email links are not source-indexed.',
        range: region.originalRange(start, parser.pos),
      );
    }
    return matched;
  }
}

final class _HtmlSyntax extends md.InlineHtmlSyntax {
  _HtmlSyntax(this.collector, this.region);
  final _SemanticCollector collector;
  final IanvsMarkdownSemanticSourceRegion region;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = parser.pos;
    final matched = super.tryMatch(parser, startMatchPos);
    if (matched && !parser.source.startsWith('<!--', start)) {
      collector.issue(
        'htmlContext',
        'Inline HTML semantics are not indexed.',
        range: region.originalRange(start, parser.pos),
      );
    }
    return matched;
  }
}

final class _TagSyntax extends IanvsMarkdownTagSyntax {
  _TagSyntax(this.collector, this.region);
  final _SemanticCollector collector;
  final IanvsMarkdownSemanticSourceRegion region;
  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = parser.pos;
    final matched = super.tryMatch(parser, startMatchPos);
    if (matched) {
      collector.addTag(
        IanvsMarkdownSourceTag(
          name: parser.source.substring(start + 1, parser.pos),
          range: region.originalRange(start, parser.pos),
        ),
      );
    }
    return matched;
  }
}

TextRange? _destinationRange(
  String source,
  int from,
  int limit, {
  bool definition = false,
}) {
  var start = from;
  while (start < limit && _isMarkdownWhitespace(source.codeUnitAt(start))) {
    start++;
  }
  if (start > limit) return null;
  if (start < limit && source.codeUnitAt(start) == 0x3c) {
    var end = start + 1;
    while (end < limit) {
      if (source.codeUnitAt(end) == 0x5c) {
        end += 2;
        continue;
      }
      if (source.codeUnitAt(end) == 0x3e) {
        return TextRange(start: start + 1, end: end);
      }
      end++;
    }
    return null;
  }
  var end = start;
  var depth = 0;
  while (end < limit) {
    final unit = source.codeUnitAt(end);
    if (unit == 0x5c) {
      end += 2;
      continue;
    }
    if (unit == 0x20 || unit == 0x0a || unit == 0x0d || unit == 0x0c) break;
    if (unit == 0x28) depth++;
    if (unit == 0x29) {
      depth--;
      if (!definition && depth < 0) break;
      if (definition && depth == 0) {
        end++;
        break;
      }
    }
    end++;
  }
  return TextRange(start: start, end: end.clamp(start, limit));
}

// Find URI separators before percent decoding, retaining the source token
// which produced the separator (including a backslash or HTML entity).
int? _rawDelimiterOffset(String raw, String delimiter, {required bool wiki}) {
  if (wiki) {
    final index = raw.indexOf(delimiter);
    return index < 0 ? null : index;
  }
  final entity = RegExp(
    r'&(?:#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);',
  );
  var index = 0;
  while (index < raw.length) {
    final start = index;
    if (raw.codeUnitAt(index) == 0x5c && index + 1 < raw.length) {
      index += 2;
    } else if (raw.codeUnitAt(index) == 0x26) {
      index = entity.matchAsPrefix(raw, index)?.end ?? index + 1;
    } else {
      if (raw[index] == delimiter) return index;
      index++;
      continue;
    }
    final token = raw.substring(start, index);
    final node =
        md.LinkSyntax().createNode(token, null, getChildren: () => const [])
            as md.Element;
    if (node.attributes['href'] == delimiter) return start;
  }
  return null;
}

// Reparse only the selected source destination with the same inline grammar.
// A matching href alone is insufficient if the candidate also swallowed a title.
bool _matchesInlineDestination(
  String raw,
  String semantic, {
  required bool angle,
  required bool projectBackslashes,
}) {
  var probe = '[x](${angle ? '<$raw>' : raw})';
  if (projectBackslashes) {
    probe = projectObsidianInlineLinkDestinationBackslashesForRendering(probe);
  }
  final syntax = _DestinationProbeSyntax();
  final nodes = md.Document(inlineSyntaxes: [syntax]).parseInline(probe);
  return nodes.length == 1 &&
      nodes.single is md.Element &&
      (nodes.single as md.Element).tag == 'a' &&
      syntax.calls == 1 &&
      !syntax.hasTitle &&
      (nodes.single as md.Element).attributes['href'] == semantic;
}

final class _DestinationProbeSyntax extends md.LinkSyntax {
  var calls = 0;
  var hasTitle = false;

  @override
  md.Node createNode(
    String destination,
    String? title, {
    required List<md.Node> Function() getChildren,
  }) {
    calls++;
    hasTitle = title != null;
    return super.createNode(destination, title, getChildren: getChildren);
  }
}

// Dart's UTF-8 URI decoder discards a leading BOM. It is a filename/codepoint
// here, not a transport signature; an ASCII prefix preserves it in one decode.
String _decodeUriComponent(String value) =>
    Uri.decodeComponent('x$value').substring(1);

bool _isMarkdownWhitespace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0d);

bool _hasYamlAnchor(YamlNode node) {
  final spelling = node.span.text;
  var index = 0;
  while (index < spelling.length) {
    // YAML properties may be separated by whitespace and comments. Quoted
    // scalar contents are never scanned as properties.
    if (_isMarkdownWhitespace(spelling.codeUnitAt(index))) {
      index++;
      continue;
    }
    if (spelling[index] == '#') {
      final newline = spelling.indexOf('\n', index);
      if (newline < 0) return false;
      index = newline + 1;
      continue;
    }
    if (spelling[index] == '&' || spelling[index] == '*') return true;
    if (spelling[index] != '!') return false;
    index++;
    if (index < spelling.length && spelling[index] == '<') {
      final end = spelling.indexOf('>', index + 1);
      if (end < 0) {
        return false; // The YAML loader has already validated syntax.
      }
      index = end + 1;
    } else {
      while (index < spelling.length &&
          !_isMarkdownWhitespace(spelling.codeUnitAt(index))) {
        index++;
      }
    }
  }
  return false;
}

String _mask(String source, List<TextRange> ranges) {
  if (ranges.isEmpty) return source;
  final units = source.codeUnits.toList();
  for (final range in ranges) {
    for (var i = range.start; i < range.end; i++) {
      if (units[i] != 0x0a && units[i] != 0x0d) units[i] = 0x20;
    }
  }
  return String.fromCharCodes(units);
}
