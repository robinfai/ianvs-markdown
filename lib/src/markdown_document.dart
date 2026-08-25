import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'front_matter.dart';

final class IanvsMarkdownHeading {
  IanvsMarkdownHeading({required this.level, required this.text});

  final int level;
  final String text;

  /// Used internally by [IanvsMarkdownView] for outline navigation.
  final GlobalKey anchorKey = GlobalKey();
}

final class IanvsMarkdownDocument {
  IanvsMarkdownDocument({
    required this.source,
    required this.body,
    required this.metadata,
    required this.headings,
    required this.hasFrontMatter,
  });

  factory IanvsMarkdownDocument.parse(
    String source, {
    bool parseFrontMatter = true,
    int maximumHeadingLevel = 6,
  }) {
    final frontMatter = parseFrontMatter
        ? parseMarkdownFrontMatter(source)
        : MarkdownFrontMatterDocument(
            body: source,
            entries: const <MarkdownMetadataEntry>[],
            hasFrontMatter: false,
          );
    return IanvsMarkdownDocument(
      source: source,
      body: frontMatter.body,
      metadata: frontMatter.entries,
      headings: parseMarkdownHeadings(
        frontMatter.body,
        maximumLevel: maximumHeadingLevel,
      ),
      hasFrontMatter: frontMatter.hasFrontMatter,
    );
  }

  final String source;
  final String body;
  final List<MarkdownMetadataEntry> metadata;
  final List<IanvsMarkdownHeading> headings;
  final bool hasFrontMatter;
}

List<IanvsMarkdownHeading> parseMarkdownHeadings(
  String source, {
  int maximumLevel = 6,
}) {
  assert(maximumLevel >= 1 && maximumLevel <= 6);
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  final nodes = document.parseLines(source.split('\n'));
  final result = <IanvsMarkdownHeading>[];
  for (final node in nodes) {
    if (node is! md.Element || node.tag.length != 2) continue;
    final level = switch (node.tag) {
      'h1' => 1,
      'h2' => 2,
      'h3' => 3,
      'h4' => 4,
      'h5' => 5,
      'h6' => 6,
      _ => null,
    };
    final text = node.textContent.trim();
    if (level == null || level > maximumLevel || text.isEmpty) continue;
    result.add(IanvsMarkdownHeading(level: level, text: text));
  }
  return List<IanvsMarkdownHeading>.unmodifiable(result);
}
