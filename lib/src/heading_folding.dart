import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md;

import 'editor/editor_models.dart';
import 'markdown_document.dart';
import 'render_budget.dart';
import 'syntax_preset.dart';

/// Keeps heading-fold state independent from Markdown source mutations.
///
/// Identities are derived from heading source and duplicate occurrence rather
/// than UTF-16 offsets, so inserting prose before a folded section does not
/// unexpectedly expand it.
final class IanvsMarkdownHeadingFoldController extends ChangeNotifier {
  final Set<String> _collapsedIdentities = <String>{};

  bool isCollapsed(String identity) => _collapsedIdentities.contains(identity);

  void toggleIdentity(String identity) {
    if (!_collapsedIdentities.add(identity)) {
      _collapsedIdentities.remove(identity);
    }
    notifyListeners();
  }

  void expandIdentities(Iterable<String> identities) {
    var changed = false;
    for (final identity in identities) {
      changed = _collapsedIdentities.remove(identity) || changed;
    }
    if (changed) notifyListeners();
  }

  void expandAll() {
    if (_collapsedIdentities.isEmpty) return;
    _collapsedIdentities.clear();
    notifyListeners();
  }

  void retainIdentities(Set<String> available) {
    final before = _collapsedIdentities.length;
    _collapsedIdentities.retainAll(available);
    if (_collapsedIdentities.length != before) notifyListeners();
  }
}

@immutable
final class IanvsMarkdownHeadingSection {
  const IanvsMarkdownHeadingSection({
    required this.identity,
    required this.headingBlockIndex,
    required this.endBlockIndex,
    required this.level,
    required this.text,
  });

  final String identity;
  final int headingBlockIndex;

  /// Exclusive block index at the next heading of equal or higher rank.
  final int endBlockIndex;
  final int level;
  final String text;

  bool get canFold => endBlockIndex > headingBlockIndex + 1;

  bool containsDescendantBlock(int blockIndex) =>
      blockIndex > headingBlockIndex && blockIndex < endBlockIndex;
}

@immutable
final class IanvsMarkdownHeadingFoldProjection {
  const IanvsMarkdownHeadingFoldProjection({
    required this.source,
    required this.visibleHeadingIdentities,
  });

  final String source;
  final Set<String> visibleHeadingIdentities;
}

/// Source-preserving structural model used by both live and reading views.
final class IanvsMarkdownHeadingFoldModel {
  IanvsMarkdownHeadingFoldModel._({
    required this.source,
    required this.blocks,
    required this.sections,
    this.budgetExceeded,
  });

  /// An unparsed source-preserving model with no headings or block projection.
  factory IanvsMarkdownHeadingFoldModel.unparsed(
    String source, {
    IanvsMarkdownBudgetExceeded? budgetExceeded,
  }) => IanvsMarkdownHeadingFoldModel._(
    source: source,
    blocks: const [],
    sections: const [],
    budgetExceeded: budgetExceeded,
  );

  /// Uses top-level GFM headings in [IanvsMarkdownSyntaxPreset.standard].
  /// Non-heading content is retained as opaque ranges in that preset;
  /// [splitListItems] applies only to the Obsidian block model.
  factory IanvsMarkdownHeadingFoldModel.parse(
    String source, {
    bool splitListItems = false,
    IanvsMarkdownSyntaxPreset syntaxPreset = IanvsMarkdownSyntaxPreset.obsidian,
    IanvsMarkdownRenderBudget? budget = const IanvsMarkdownRenderBudget(),
  }) {
    final decision = scanMarkdownForRendering(
      source,
      budget: budget,
      syntaxPreset: syntaxPreset,
    );
    if (!decision.useMarkdown) {
      return IanvsMarkdownHeadingFoldModel.unparsed(
        source,
        budgetExceeded: decision.budgetExceeded,
      );
    }
    if (syntaxPreset == IanvsMarkdownSyntaxPreset.standard) {
      return _parseStandardHeadingModel(source);
    }
    return IanvsMarkdownHeadingFoldModel.fromBlocks(
      source,
      parseMarkdownBlocks(source, splitListItems: splitListItems),
      budget: null,
    );
  }

  factory IanvsMarkdownHeadingFoldModel.fromBlocks(
    String source,
    List<IanvsMarkdownBlock> blocks, {
    IanvsMarkdownRenderBudget? budget = const IanvsMarkdownRenderBudget(),
  }) {
    final decision = scanMarkdownForRendering(source, budget: budget);
    if (!decision.useMarkdown) {
      return IanvsMarkdownHeadingFoldModel.unparsed(
        source,
        budgetExceeded: decision.budgetExceeded,
      );
    }
    final headings = <_ParsedHeading>[];
    for (var index = 0; index < blocks.length; index += 1) {
      final block = blocks[index];
      if (block.type != IanvsMarkdownBlockType.heading) continue;
      final parsed = parseMarkdownHeadings(block.source, budget: null);
      if (parsed.isEmpty) continue;
      headings.add((
        blockIndex: index,
        level: parsed.first.level,
        text: parsed.first.text,
        source: block.source,
      ));
    }

    return IanvsMarkdownHeadingFoldModel._fromHeadings(
      source,
      blocks,
      headings,
    );
  }

  factory IanvsMarkdownHeadingFoldModel._fromHeadings(
    String source,
    List<IanvsMarkdownBlock> blocks,
    List<_ParsedHeading> headings,
  ) {
    final occurrences = <String, int>{};
    final sections = <IanvsMarkdownHeadingSection>[];
    for (
      var headingIndex = 0;
      headingIndex < headings.length;
      headingIndex += 1
    ) {
      final heading = headings[headingIndex];
      final baseIdentity = '${heading.level}\u0000${heading.source.trim()}';
      final occurrence = occurrences.update(
        baseIdentity,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      var endBlockIndex = blocks.length;
      for (var next = headingIndex + 1; next < headings.length; next += 1) {
        if (headings[next].level <= heading.level) {
          endBlockIndex = headings[next].blockIndex;
          break;
        }
      }
      sections.add(
        IanvsMarkdownHeadingSection(
          identity: '$baseIdentity\u0000$occurrence',
          headingBlockIndex: heading.blockIndex,
          endBlockIndex: endBlockIndex,
          level: heading.level,
          text: heading.text,
        ),
      );
    }
    return IanvsMarkdownHeadingFoldModel._(
      source: source,
      blocks: List<IanvsMarkdownBlock>.unmodifiable(blocks),
      sections: List<IanvsMarkdownHeadingSection>.unmodifiable(sections),
    );
  }

  final String source;
  final List<IanvsMarkdownBlock> blocks;
  final List<IanvsMarkdownHeadingSection> sections;
  final IanvsMarkdownBudgetExceeded? budgetExceeded;

  Set<String> get identities =>
      sections.map((section) => section.identity).toSet();

  IanvsMarkdownHeadingSection? sectionAtBlockIndex(int blockIndex) {
    for (final section in sections) {
      if (section.headingBlockIndex == blockIndex) return section;
    }
    return null;
  }

  Set<int> hiddenBlockIndices(IanvsMarkdownHeadingFoldController controller) {
    final hidden = <int>{};
    for (final section in sections) {
      if (!section.canFold || !controller.isCollapsed(section.identity)) {
        continue;
      }
      for (
        var index = section.headingBlockIndex + 1;
        index < section.endBlockIndex;
        index += 1
      ) {
        hidden.add(index);
      }
    }
    return hidden;
  }

  Iterable<String> collapsedAncestorIdentities(
    int blockIndex,
    IanvsMarkdownHeadingFoldController controller,
  ) sync* {
    for (final section in sections) {
      if (section.containsDescendantBlock(blockIndex) &&
          controller.isCollapsed(section.identity)) {
        yield section.identity;
      }
    }
  }

  IanvsMarkdownHeadingFoldProjection project(
    IanvsMarkdownHeadingFoldController controller,
  ) {
    if (sections.isEmpty) {
      return IanvsMarkdownHeadingFoldProjection(
        source: source,
        visibleHeadingIdentities: const <String>{},
      );
    }
    final hidden = hiddenBlockIndices(controller);
    final visibleIdentities = sections
        .where((section) => !hidden.contains(section.headingBlockIndex))
        .map((section) => section.identity)
        .toSet();
    final outerCollapsed = sections.where(
      (section) =>
          section.canFold &&
          controller.isCollapsed(section.identity) &&
          !hidden.contains(section.headingBlockIndex),
    );
    if (outerCollapsed.isEmpty) {
      return IanvsMarkdownHeadingFoldProjection(
        source: source,
        visibleHeadingIdentities: visibleIdentities,
      );
    }

    final buffer = StringBuffer();
    var cursor = 0;
    for (final section in outerCollapsed) {
      final heading = blocks[section.headingBlockIndex];
      final hiddenEnd = section.endBlockIndex < blocks.length
          ? blocks[section.endBlockIndex].start
          : source.length;
      if (heading.end < cursor) continue;
      buffer.write(source.substring(cursor, heading.end));
      if (hiddenEnd < source.length) buffer.write('\n\n');
      cursor = hiddenEnd;
    }
    buffer.write(source.substring(cursor));
    return IanvsMarkdownHeadingFoldProjection(
      source: buffer.toString(),
      visibleHeadingIdentities: visibleIdentities,
    );
  }
}

typedef _ParsedHeading = ({
  int blockIndex,
  int level,
  String text,
  String source,
});
typedef _HeadingRange = ({int first, int last});
typedef _RecordHeading =
    void Function(
      md.BlockParser parser,
      md.Node? node,
      md.Line first,
      md.Line last,
    );

// Let the same GFM parser used by the renderer decide which lines are headings.
// Recording source lines avoids interpreting YAML, math, or Obsidian comments
// as special blocks and preserves original UTF-16 offsets (including CRLF).
IanvsMarkdownHeadingFoldModel _parseStandardHeadingModel(String source) {
  final rawLines = <String>[];
  final starts = <int>[];
  var offset = 0;
  for (final separator in RegExp(r'\r\n|\r|\n').allMatches(source)) {
    starts.add(offset);
    rawLines.add(source.substring(offset, separator.start));
    offset = separator.end;
  }
  starts.add(offset);
  rawLines.add(source.substring(offset));
  final lines = rawLines.map(md.Line.new).toList(growable: false);
  final indices = Map<md.Line, int>.identity();
  for (var i = 0; i < lines.length; i += 1) {
    indices[lines[i]] = i;
  }
  final ranges = Map<md.Node, _HeadingRange>.identity();
  void record(
    md.BlockParser parser,
    md.Node? node,
    md.Line first,
    md.Line last,
  ) {
    if (node == null || parser.parentSyntax != null) return;
    final start = indices[first];
    final end = indices[last];
    if (start != null && end != null) ranges[node] = (first: start, last: end);
  }

  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    blockSyntaxes: [
      // Preserve upstream precedence: GFM extensions and HTML precede headings.
      ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      const md.EmptyBlockSyntax(),
      const md.HtmlBlockSyntax(),
      _RecordingSetextHeader(record),
      _RecordingHeader(record),
    ],
  );
  final nodes = document.parseLineList(lines);
  final blocks = <IanvsMarkdownBlock>[];
  final headings = <_ParsedHeading>[];
  void addBlock(int first, int last, IanvsMarkdownBlockType type) {
    while (first <= last && rawLines[first].trim().isEmpty) {
      first += 1;
    }
    while (last >= first && rawLines[last].trim().isEmpty) {
      last -= 1;
    }
    if (first > last) return;
    final end = starts[last] + rawLines[last].length;
    blocks.add(
      IanvsMarkdownBlock(
        type: type,
        start: starts[first],
        end: end,
        firstLine: first,
        lastLine: last,
        source: source.substring(starts[first], end),
      ),
    );
  }

  var nextLine = 0;
  for (final node in nodes) {
    final range = ranges[node];
    if (range == null ||
        node is! md.Element ||
        node.textContent.trim().isEmpty) {
      continue;
    }
    addBlock(nextLine, range.first - 1, IanvsMarkdownBlockType.paragraph);
    addBlock(range.first, range.last, IanvsMarkdownBlockType.heading);
    headings.add((
      blockIndex: blocks.length - 1,
      level: int.parse(node.tag.substring(1)),
      text: node.textContent.trim(),
      source: blocks.last.source,
    ));
    nextLine = range.last + 1;
  }
  addBlock(nextLine, lines.length - 1, IanvsMarkdownBlockType.paragraph);
  return IanvsMarkdownHeadingFoldModel._fromHeadings(source, blocks, headings);
}

final class _RecordingHeader extends md.HeaderSyntax {
  const _RecordingHeader(this.record);
  final _RecordHeading record;

  @override
  md.Node parse(md.BlockParser parser) {
    final line = parser.current;
    final node = super.parse(parser);
    record(parser, node, line, line);
    return node;
  }
}

final class _RecordingSetextHeader extends md.SetextHeaderSyntax {
  const _RecordingSetextHeader(this.record);
  final _RecordHeading record;

  @override
  md.Node? parse(md.BlockParser parser) {
    final first = parser.linesToConsume.first;
    final last = parser.current;
    final node = super.parse(parser);
    record(parser, node, first, last);
    return node;
  }
}
