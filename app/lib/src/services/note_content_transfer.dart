import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

/// Preserve relative Markdown destinations when copying between note folders.
/// Source ranges avoid changing code samples, labels, titles or fragments.
String transferNoteContent(
  String source, {
  required String originPath,
  required String destinationPath,
  Map<String, String> wikiTargets = const {},
}) {
  final semantics = parseIanvsMarkdownNoteSemantics(source);
  if (!semantics.complete) {
    throw const FormatException('Some references cannot be moved safely.');
  }
  final edits = <int, ({int end, String text})>{};
  for (final reference in semantics.references) {
    final target = reference.target;
    final wiki =
        reference.kind == IanvsMarkdownSourceReferenceKind.wikiLink ||
        reference.kind == IanvsMarkdownSourceReferenceKind.wikiEmbed;
    if (wiki) {
      final resolved = wikiTargets[target];
      if (resolved == null) {
        throw const FormatException(
          'Resolve wiki references before inserting this note.',
        );
      }
      final range = reference.destinationRange;
      edits[range.start] = (end: range.end, text: resolved);
      continue;
    }
    if (target.startsWith('/') || Uri.tryParse(target)?.hasScheme == true) {
      continue;
    }
    if (p.dirname(originPath) == p.dirname(destinationPath) &&
        target.isNotEmpty) {
      continue;
    }
    final absolute = target.isEmpty
        ? originPath
        : p.normalize(p.join(p.dirname(originPath), target));
    final relative = p.relative(absolute, from: p.dirname(destinationPath));
    final encoded = relative.split('/').map(Uri.encodeComponent).join('/');
    final range = reference.destinationRange;
    edits[range.start] = (end: range.end, text: encoded);
  }
  var result = source;
  final offsets = edits.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final start in offsets) {
    final edit = edits[start]!;
    result = result.replaceRange(start, edit.end, edit.text);
  }
  return result;
}

String extractionRelativePath(String title, String originPath, String root) {
  if (p.basename(title) != title || title == '.' || title == '..') {
    throw const FormatException(
      'Use a filename; extracted notes stay beside the original.',
    );
  }
  if (!p.isWithin(root, originPath)) {
    throw const FormatException(
      'Save the source note in this workspace first.',
    );
  }
  final name = title.toLowerCase().endsWith('.md') ? title : '$title.md';
  return p.relative(p.join(p.dirname(originPath), name), from: root);
}

/// Carry effective reference definitions when only their uses were selected.
String extractedNoteContent(String source, int start, int end) {
  final definitions = <int, String>{};
  for (final reference in parseIanvsMarkdownNoteSemantics(source).references) {
    if (reference.range.start < start || reference.range.end > end) continue;
    final definition = reference.definitionRange;
    if (definition == null ||
        (definition.start >= start && definition.end <= end)) continue;
    definitions[definition.start] = source.substring(definition.start, definition.end);
  }
  final selected = source.substring(start, end);
  if (definitions.isEmpty) return selected;
  return '$selected\n\n${definitions.values.join('\n')}\n';
}
