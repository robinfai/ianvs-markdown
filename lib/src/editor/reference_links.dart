import 'package:markdown/markdown.dart' as md;

import '../markdown_link_source.dart';

final class MarkdownLinkReferenceDefinition {
  const MarkdownLinkReferenceDefinition({
    required this.label,
    required this.destination,
    required this.title,
  });

  final String label;
  final String destination;
  final String? title;
}

/// Returns parsed definitions only when [source] contains no visible Markdown
/// nodes. Live Preview uses this to project otherwise parser-hidden definition
/// blocks without treating mixed paragraphs as metadata.
List<MarkdownLinkReferenceDefinition> parseMarkdownLinkReferenceDefinitions(
  String source,
) {
  if (source.isEmpty) return const <MarkdownLinkReferenceDefinition>[];
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  final nodes = document.parseLines(source.split('\n'));
  if (nodes.isNotEmpty || document.linkReferences.isEmpty) {
    return const <MarkdownLinkReferenceDefinition>[];
  }
  final rawLabels = _rawMarkdownLinkReferenceLabels(source);
  return <MarkdownLinkReferenceDefinition>[
    for (final entry in document.linkReferences.entries)
      MarkdownLinkReferenceDefinition(
        label: rawLabels[entry.key] ?? entry.value.label,
        destination: entry.value.destination,
        title: entry.value.title,
      ),
  ];
}

Map<String, String> _rawMarkdownLinkReferenceLabels(String source) {
  final labels = <String, String>{};
  var lineStart = 0;
  while (lineStart < source.length) {
    final lineEnd = source.indexOf('\n', lineStart);
    final end = lineEnd < 0 ? source.length : lineEnd;
    var opening = lineStart;
    while (opening < end &&
        opening - lineStart < 3 &&
        source.codeUnitAt(opening) == 0x20) {
      opening += 1;
    }
    if (opening < end && source.codeUnitAt(opening) == 0x5b) {
      final match = findIanvsMarkdownReferenceLabel(source, opening);
      if (match != null &&
          match.end < end &&
          source.codeUnitAt(match.end) == 0x3a) {
        labels.putIfAbsent(
          normalizeMarkdownLinkReferenceLabel(match.label),
          () => match.label,
        );
      }
    }
    if (lineEnd < 0) break;
    lineStart = lineEnd + 1;
  }
  return labels;
}

/// Document-wide Markdown link references needed by block-based live preview.
final class MarkdownLinkReferenceContext {
  MarkdownLinkReferenceContext._(this.references);

  factory MarkdownLinkReferenceContext.parse(String source) {
    if (source.isEmpty) return MarkdownLinkReferenceContext._(const {});
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    document.parseLines(source.split('\n'));
    return MarkdownLinkReferenceContext._(
      Map<String, md.LinkReference>.unmodifiable(document.linkReferences),
    );
  }

  final Map<String, md.LinkReference> references;

  Set<String> get labels => references.keys.toSet();

  /// Appends only the definitions a source fragment may reference.
  ///
  /// Link reference definitions do not render visible output, but placing them
  /// in the same parse unit lets an otherwise isolated live-preview block use
  /// the complete document's reference map.
  String appendDefinitionsTo(String source) {
    if (source.isEmpty || references.isEmpty) return source;
    final labels = <String>{};
    for (final label in findIanvsMarkdownReferencedLabels(source)) {
      final normalized = normalizeMarkdownLinkReferenceLabel(label);
      if (references.containsKey(normalized)) labels.add(normalized);
    }
    if (labels.isEmpty) return source;
    final definitions = labels
        .map((label) => _serializeDefinition(references[label]!))
        .join('\n');
    return '$source\n\n$definitions';
  }
}

/// CommonMark link-label normalization for editor-side syntax matching.
///
/// The Markdown parser remains the rendering authority. This lightweight form
/// mirrors its whitespace and case behavior for the source-decoration pass.
String normalizeMarkdownLinkReferenceLabel(String label) =>
    label.trim().replaceAll(RegExp(r'[ \n\r\t]+'), ' ').toLowerCase();

String _serializeDefinition(md.LinkReference reference) {
  final label = _escapeUnescaped(reference.label, 0x5d);
  final destination = _escapeUnescaped(
    reference.destination,
    0x3e,
  ).replaceAll('\r', '').replaceAll('\n', ' ');
  final title = reference.title;
  if (title == null || title.isEmpty) return '[$label]: <$destination>';
  final escapedTitle = _escapeUnescaped(title, 0x22).replaceAll('\r', '');
  return '[$label]: <$destination> "$escapedTitle"';
}

String _escapeUnescaped(String source, int character) {
  final output = StringBuffer();
  var backslashes = 0;
  for (var index = 0; index < source.length; index += 1) {
    final current = source.codeUnitAt(index);
    if (current == character && backslashes.isEven) output.write(r'\');
    output.writeCharCode(current);
    backslashes = current == 0x5c ? backslashes + 1 : 0;
  }
  return output.toString();
}
