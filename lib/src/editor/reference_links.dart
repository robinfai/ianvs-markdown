import 'package:markdown/markdown.dart' as md;

import '../markdown_link_source.dart';

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
  final escapedTitle = _escapeUnescaped(
    title,
    0x22,
  ).replaceAll('\r', '').replaceAll('\n', ' ');
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
