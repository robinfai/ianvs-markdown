part of '../ianvs_markdown.dart';

List<md.BlockSyntax> _readingBlockSyntaxes(
  IanvsMarkdownObsidianMetadataMode obsidianMetadataMode,
  List<md.BlockSyntax>? blockSyntaxes,
) => <md.BlockSyntax>[
  ...?blockSyntaxes,
  const IanvsMarkdownIndentedCodeBlockSyntax(),
  const IanvsMarkdownHtmlHorizontalRuleSyntax(),
  const IanvsMarkdownHtmlButtonSyntax(),
  const IanvsMarkdownHtmlCheckboxSyntax(),
  const IanvsMarkdownHtmlDateInputSyntax(),
  if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.reading)
    const IanvsMarkdownHtmlMeterSyntax(),
  const IanvsMarkdownHtmlNumberInputSyntax(),
  const IanvsMarkdownHtmlPasswordInputSyntax(),
  const IanvsMarkdownHtmlPreSyntax(),
  const IanvsMarkdownHtmlProgressSyntax(),
  const IanvsMarkdownHtmlRadioGroupSyntax(),
  const IanvsMarkdownHtmlRangeInputSyntax(),
  const IanvsMarkdownHtmlSelectSyntax(),
  const IanvsMarkdownHtmlTextareaSyntax(),
  const IanvsMarkdownHtmlFieldsetSyntax(),
  const IanvsMarkdownHtmlBlockquoteSyntax(),
  const IanvsMarkdownHtmlCenterSyntax(),
  const IanvsMarkdownHtmlDefinitionListSyntax(),
  const IanvsMarkdownHtmlFigureSyntax(),
  const IanvsMarkdownHtmlTableSyntax(),
  const IanvsMarkdownHtmlTemporalInputSyntax(),
  const IanvsMarkdownHtmlTextInputSyntax(),
  const IanvsMarkdownHtmlTimeInputSyntax(),
  const IanvsMarkdownHtmlUnorderedListSyntax(),
  const IanvsMarkdownHtmlOrderedListSyntax(),
  const IanvsMarkdownHtmlDetailsSyntax(),
  if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing)
    const IanvsMarkdownEditingCommentBlockSyntax(),
  if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing)
    const IanvsMarkdownEditingFootnoteDefinitionSyntax(),
  const IanvsMarkdownDisplayMathSyntax(),
  const IanvsMarkdownWikiEmbedSyntax(),
  const IanvsMarkdownCalloutSyntax(),
];

List<md.InlineSyntax> _readingInlineSyntaxes(
  IanvsMarkdownObsidianMetadataMode obsidianMetadataMode,
  List<md.InlineSyntax>? inlineSyntaxes,
) => <md.InlineSyntax>[
  ...?inlineSyntaxes,
  IanvsMarkdownCodeSpanSyntax(
    presentation:
        obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
        ? IanvsMarkdownCodeSpanPresentation.editing
        : IanvsMarkdownCodeSpanPresentation.reading,
  ),
  IanvsMarkdownInlineDisplayMathSyntax(),
  IanvsMarkdownInlineMathSyntax(),
  IanvsMarkdownEntitySyntax(
    presentation:
        obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
        ? IanvsMarkdownEntityPresentation.editing
        : IanvsMarkdownEntityPresentation.reading,
  ),
  // Angle autolinks are syntactically more specific than raw HTML.
  // Giving them first refusal keeps `<https:…>`, `<user@example.com>`,
  // and custom schemes from being consumed by the safe HTML fallback.
  IanvsMarkdownAutolinkSyntax(),
  ...ianvsMarkdownInlineHtmlSyntaxes(obsidianMetadataMode),
  if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing) ...[
    IanvsMarkdownEditingMetadataInlineSyntax.comment(),
    IanvsMarkdownEditingMetadataInlineSyntax.blockId(),
    IanvsMarkdownEditingMetadataInlineSyntax.standardFootnote(),
    IanvsMarkdownEditingMetadataInlineSyntax.inlineFootnote(),
  ],
  IanvsMarkdownLiteralReferenceWhitespaceSyntax(),
  // Metadata syntaxes such as block IDs include their leading space, so
  // they must get first refusal before rendered whitespace is collapsed.
  IanvsMarkdownRenderedWhitespaceSyntax(),
  IanvsMarkdownEmphasisSyntax(
    presentation:
        obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
        ? IanvsMarkdownEmphasisPresentation.editing
        : IanvsMarkdownEmphasisPresentation.reading,
  ),
  IanvsMarkdownHighlightSyntax(
    presentation:
        obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
        ? IanvsMarkdownHighlightPresentation.editing
        : IanvsMarkdownHighlightPresentation.reading,
  ),
  IanvsMarkdownStrikethroughSyntax(
    presentation:
        obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
        ? IanvsMarkdownStrikethroughPresentation.editing
        : IanvsMarkdownStrikethroughPresentation.reading,
  ),
  IanvsMarkdownWikiLinkSyntax(
    presentation:
        obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
        ? IanvsMarkdownWikiLinkPresentation.editing
        : IanvsMarkdownWikiLinkPresentation.reading,
  ),
  IanvsMarkdownTagSyntax(),
];

/// Internal entry point for application search. Null means the render budget
/// rejected Markdown; callers must explicitly offer source search instead.
MarkdownReadingTextIndex? buildMarkdownReadingTextIndex(
  String source, {
  IanvsMarkdownSyntaxPreset syntaxPreset = IanvsMarkdownSyntaxPreset.obsidian,
  IanvsMarkdownRenderBudget? budget = const IanvsMarkdownRenderBudget(),
}) {
  final obsidian = syntaxPreset == IanvsMarkdownSyntaxPreset.obsidian;
  final parsed = IanvsMarkdownDocument.parse(
    source,
    parseFrontMatter: obsidian,
    syntaxPreset: syntaxPreset,
    budget: budget,
  );
  if (parsed.parseDecision?.useMarkdown != true) return null;
  String prepare(String body) => obsidian
      ? projectObsidianTaskMarkers(
          projectObsidianInlineLinkDestinationBackslashesForRendering(
            projectObsidianCrossParagraphHighlightsForRendering(
              _projectIrregularObsidianTables(
                prepareObsidianMarkdownForRendering(body),
              ),
            ),
          ),
        ).data
      : body;
  SourceMappedMarkdownDocument parser() => SourceMappedMarkdownDocument(
    blockSyntaxes: obsidian
        ? _readingBlockSyntaxes(IanvsMarkdownObsidianMetadataMode.reading, null)
        : null,
    inlineSyntaxes: obsidian
        ? _readingInlineSyntaxes(
            IanvsMarkdownObsidianMetadataMode.reading,
            null,
          )
        : null,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final document = parser();
  final nodes = document.parseLines(
    const LineSplitter().convert(prepare(parsed.body)),
  );
  final bodyStart = source.length - parsed.body.length;
  final lineOffsets = <int>[
    bodyStart,
    for (final newline in RegExp(r'\r\n|\r|\n').allMatches(parsed.body))
      bodyStart + newline.end,
  ];
  final itemNavigation = Map<md.Node, TextRange>.identity();
  for (final node in nodes) {
    if (node is! md.Element || (node.tag != 'ul' && node.tag != 'ol')) continue;
    final lines = document.ranges[node];
    if (lines == null || lines.start >= lineOffsets.length) continue;
    final start = lineOffsets[lines.start];
    final end = lines.end < lineOffsets.length
        ? lineOffsets[lines.end]
        : source.length;
    final blocks = parseMarkdownBlocks(
      source.substring(start, end),
      splitListItems: true,
    );
    final items = <md.Element>[];
    void collect(md.Node node) {
      if (node is! md.Element) return;
      if (node.tag == 'li') items.add(node);
      for (final child in node.children ?? const <md.Node>[]) {
        collect(child);
      }
    }

    collect(node);
    // Both parsers must agree on item count and order. Otherwise retain the
    // whole-list anchor rather than guessing from repeated visible text.
    final listBlocks = blocks
        .where(
          (block) => const {
            IanvsMarkdownBlockType.unorderedList,
            IanvsMarkdownBlockType.orderedList,
            IanvsMarkdownBlockType.taskList,
          }.contains(block.type),
        )
        .toList();
    if (items.length != listBlocks.length ||
        listBlocks.length != blocks.length) {
      continue;
    }
    for (var i = 0; i < items.length; i++) {
      itemNavigation[items[i]] = TextRange(
        start: start + listBlocks[i].start,
        end: start + listBlocks[i].end,
      );
    }
  }
  return MarkdownReadingTextIndex.fromDocument(
    source: source,
    nodes: nodes,
    document: document,
    navigationRange: (node) => itemNavigation[node],
    lineOffsets: lineOffsets,
    expandedChildren: (node) {
      if (node.tag == 'pre') {
        return [
          for (final child in node.children ?? const <md.Node>[])
            if (child is md.Element && child.tag == 'code')
              (md.Element.text(
                'code',
                markdownCodeExpandTabs(child.textContent),
              )..attributes.addAll(child.attributes))
            else
              child,
        ];
      }
      if (node.tag != 'ianvs-callout') return null;
      return [
        // Default titles are localized by the host. Explicit titles share the
        // renderer's inline syntax; source block anchors remain the callout's.
        if (node.attributes['data-default-title'] != 'true')
          md.Element(
            'p',
            parser().parseInline(node.attributes['data-title'] ?? ''),
          ),
        ...parser().parseLines(
          const LineSplitter().convert(
            prepare(node.attributes['data-body'] ?? ''),
          ),
        ),
      ];
    },
  );
}

/// Snapshot of searchable rendered text, with source-block navigation anchors.
/// A match's source range is not a replacement range.
class IanvsMarkdownReadingSearch {
  IanvsMarkdownReadingSearch._(this._index);
  final MarkdownReadingTextIndex _index;

  /// Returns null when the document exceeds the Markdown rendering budget.
  static IanvsMarkdownReadingSearch? parse(
    String source, {
    IanvsMarkdownSyntaxPreset syntaxPreset = IanvsMarkdownSyntaxPreset.obsidian,
    IanvsMarkdownRenderBudget? budget = const IanvsMarkdownRenderBudget(),
  }) {
    final index = buildMarkdownReadingTextIndex(
      source,
      syntaxPreset: syntaxPreset,
      budget: budget,
    );
    return index == null ? null : IanvsMarkdownReadingSearch._(index);
  }

  String get source => _index.source;

  List<IanvsMarkdownReadingMatch> find(String query, {bool matchCase = false}) {
    final segments = _index.segments;
    return List.unmodifiable([
      for (final match in _index.find(query, matchCase: matchCase))
        IanvsMarkdownReadingMatch(
          sourceRange: match.sourceRange,
          navigationRange: match.navigationRange,
          segmentIndex: match.segmentIndex,
          textRange: match.textRange,
          text: segments[match.segmentIndex].text,
        ),
    ]);
  }
}

/// A literal hit in one rendered text flow (paragraph, cell, or list item).
class IanvsMarkdownReadingMatch {
  const IanvsMarkdownReadingMatch({
    required this.sourceRange,
    required this.segmentIndex,
    required this.textRange,
    required this.text,
    this._navigationRange,
  });
  final TextRange? _navigationRange;
  TextRange get navigationRange => _navigationRange ?? sourceRange;
  final TextRange sourceRange;
  final int segmentIndex;
  final TextRange textRange;
  final String text;
}

/// Matches belonging to one immutable source snapshot, plus the active hit.
class IanvsMarkdownReadingHighlights {
  IanvsMarkdownReadingHighlights({
    required this.source,
    required List<IanvsMarkdownReadingMatch> matches,
    this.activeIndex = -1,
  }) : matches = List.unmodifiable(matches);
  final String source;
  final List<IanvsMarkdownReadingMatch> matches;
  final int activeIndex;
  Map<TextRange, List<MarkdownReadingHighlightFlow>>? _cachedFlows;
  Map<TextRange, List<MarkdownReadingHighlightFlow>>? _cachedNavigationFlows;

  Map<TextRange, List<MarkdownReadingHighlightFlow>> _flowsFor(
    String current, {
    bool navigation = false,
  }) {
    if (source != current) return const {};
    final cached = navigation ? _cachedNavigationFlows : _cachedFlows;
    if (cached != null) return cached;
    final groups = <TextRange, Map<int, List<int>>>{};
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      groups
          .putIfAbsent(
            navigation ? match.navigationRange : match.sourceRange,
            () => {},
          )
          .putIfAbsent(match.segmentIndex, () => [])
          .add(i);
    }
    final result = {
      for (final block in groups.entries)
        block.key: [
          for (final indices in block.value.values)
            MarkdownReadingHighlightFlow(
              text: matches[indices.first].text,
              ranges: [for (final i in indices) matches[i].textRange],
              activeRange: indices.contains(activeIndex)
                  ? matches[activeIndex].textRange
                  : null,
            ),
        ],
    };
    if (navigation) {
      _cachedNavigationFlows = result;
    } else {
      _cachedFlows = result;
    }
    return result;
  }
}

/// Internal bridge for independently laid-out Live blocks. Only complete source
/// regions are admitted; a split list must not reuse another item's hit ordinal.
List<MarkdownReadingHighlightFlow> markdownReadingHighlightFlowsForRange(
  IanvsMarkdownReadingHighlights? highlights,
  String source,
  int start,
  int end,
) {
  if (highlights == null || highlights.source != source) return const [];
  return [
    for (final entry in highlights._flowsFor(source, navigation: true).entries)
      if (entry.key.start >= start &&
          entry.key.start < end &&
          (entry.key.end <= end ||
              (entry.key.end <= source.length &&
                  source.substring(end, entry.key.end).trim().isEmpty)))
        ...entry.value,
  ];
}
