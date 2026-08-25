import 'package:flutter/foundation.dart';

import 'editor/editor_models.dart';
import 'markdown_document.dart';

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
  });

  factory IanvsMarkdownHeadingFoldModel.parse(
    String source, {
    bool splitListItems = false,
  }) {
    return IanvsMarkdownHeadingFoldModel.fromBlocks(
      source,
      parseMarkdownBlocks(source, splitListItems: splitListItems),
    );
  }

  factory IanvsMarkdownHeadingFoldModel.fromBlocks(
    String source,
    List<IanvsMarkdownBlock> blocks,
  ) {
    final headings =
        <({int blockIndex, int level, String text, String source})>[];
    for (var index = 0; index < blocks.length; index += 1) {
      final block = blocks[index];
      if (block.type != IanvsMarkdownBlockType.heading) continue;
      final parsed = parseMarkdownHeadings(block.source);
      if (parsed.isEmpty) continue;
      headings.add((
        blockIndex: index,
        level: parsed.first.level,
        text: parsed.first.text,
        source: block.source,
      ));
    }

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
