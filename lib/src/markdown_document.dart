import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'front_matter.dart';
import 'editor/editor_diagnostics.dart';
import 'render_budget.dart';
import 'syntax_preset.dart';

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
    this.parseDecision,
  });

  factory IanvsMarkdownDocument.parse(
    String source, {
    bool parseFrontMatter = true,
    int maximumHeadingLevel = 6,
    IanvsMarkdownRenderBudget? budget = const IanvsMarkdownRenderBudget(),
    IanvsMarkdownSyntaxPreset syntaxPreset = IanvsMarkdownSyntaxPreset.obsidian,
  }) {
    final decision = scanMarkdownForRendering(
      source,
      budget: budget,
      syntaxPreset: syntaxPreset,
    );
    if (!decision.useMarkdown) {
      return IanvsMarkdownDocument(
        source: source,
        body: source,
        metadata: const [],
        headings: const [],
        hasFrontMatter: false,
        parseDecision: decision,
      );
    }
    final frontMatter = parseFrontMatter
        ? IanvsMarkdownEditorDiagnostics.measure(
            'document.frontMatter',
            () => parseMarkdownFrontMatter(source),
          )
        : MarkdownFrontMatterDocument(
            body: source,
            entries: const <MarkdownMetadataEntry>[],
            hasFrontMatter: false,
          );
    return IanvsMarkdownDocument(
      source: source,
      body: frontMatter.body,
      metadata: frontMatter.entries,
      headings: IanvsMarkdownEditorDiagnostics.measure(
        'document.headings',
        () => parseMarkdownHeadings(
          frontMatter.body,
          maximumLevel: maximumHeadingLevel,
          budget: null, // The complete source has already passed preflight.
        ),
      ),
      hasFrontMatter: frontMatter.hasFrontMatter,
      parseDecision: decision,
    );
  }

  final String source;
  final String body;
  final List<MarkdownMetadataEntry> metadata;
  final List<IanvsMarkdownHeading> headings;
  final bool hasFrontMatter;

  /// Null only for manually constructed documents. On rejection [body] is the
  /// complete source; YAML and headings have not been parsed.
  final IanvsMarkdownRenderDecision? parseDecision;
}

List<IanvsMarkdownHeading> parseMarkdownHeadings(
  String source, {
  int maximumLevel = 6,
  IanvsMarkdownRenderBudget? budget = const IanvsMarkdownRenderBudget(),
}) {
  assert(maximumLevel >= 1 && maximumLevel <= 6);
  if (!scanMarkdownForRendering(source, budget: budget).useMarkdown) {
    return const [];
  }
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  final lines = const LineSplitter().convert(source);
  // Footnote numbers depend on references throughout the document, including
  // ordinary paragraphs and headings excluded by maximumLevel. Keep the full
  // parser whenever footnote syntax may be present. Otherwise block parsing
  // collects forward link definitions before parsing only heading inlines.
  final parseWholeDocument = source.contains('[^');
  final nodes = parseWholeDocument
      ? document.parseLines(lines)
      : md.BlockParser(lines.map(md.Line.new).toList(), document).parseLines();
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
    if (level == null || level > maximumLevel) continue;
    final text =
        (parseWholeDocument
                ? node.textContent
                : document
                      .parseInline(node.textContent)
                      .map((inline) => inline.textContent)
                      .join())
            .trim();
    if (text.isEmpty) continue;
    result.add(IanvsMarkdownHeading(level: level, text: text));
  }
  return List<IanvsMarkdownHeading>.unmodifiable(result);
}
