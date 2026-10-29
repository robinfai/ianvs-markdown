import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import '../models/document_analysis.dart';
import 'outline_operations.dart';
import 'wiki_link_insertion.dart';

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
String extractedNoteContent(
  String source,
  int start,
  int end, {
  String? originRelativePath,
}) {
  final definitions = <int, String>{};
  for (final reference in parseIanvsMarkdownNoteSemantics(source).references) {
    if (reference.range.start < start || reference.range.end > end) continue;
    final definition = reference.definitionRange;
    if (definition == null ||
        (definition.start >= start && definition.end <= end)) {
      continue;
    }
    definitions[definition.start] = source.substring(
      definition.start,
      definition.end,
    );
  }
  final selected = source.substring(start, end);
  final extracted = definitions.isEmpty
      ? selected
      : '$selected\n\n${definitions.values.join('\n')}\n';
  return _preserveExtractedFragments(
    source,
    extracted,
    start,
    end,
    originRelativePath,
  );
}

String _preserveExtractedFragments(
  String original,
  String extracted,
  int selectionStart,
  int selectionEnd,
  String? originRelativePath,
) {
  final semantics = parseIanvsMarkdownNoteSemantics(extracted);
  if (!semantics.complete) {
    throw const FormatException(
      'This selection has unsupported references. Extract it in Source mode manually.',
    );
  }
  final originalHeadings = DocumentAnalysis().headings(original);
  final extractedHeadings = DocumentAnalysis().headings(extracted);
  final blocks = parseMarkdownBlocks(original);
  final identifiers = ianvsMarkdownBlockIdRanges(original);
  final edits = <int, ({int end, String text})>{};
  for (final reference in semantics.references) {
    final fragment = reference.fragment;
    if (reference.target.isNotEmpty || fragment == null || fragment.isEmpty) {
      continue;
    }
    if (originRelativePath == null) {
      throw const FormatException(
        'Save the source note before extracting fragment references.',
      );
    }
    final wiki =
        reference.kind == IanvsMarkdownSourceReferenceKind.wikiLink ||
        reference.kind == IanvsMarkdownSourceReferenceKind.wikiEmbed;
    int? targetStart;
    int? targetEnd;
    int? headingIndex;
    if (fragment.startsWith('^')) {
      final matching = identifiers
          .where((range) => range.textInside(original).trim() == fragment)
          .toList();
      if (matching.length != 1) {
        throw FormatException(
          'Cannot uniquely resolve block #$fragment. Keep the selection in the original note.',
        );
      }
      for (final block in blocks) {
        if (block.start <= matching.single.start &&
            block.end >= matching.single.end) {
          targetStart = block.start;
          targetEnd = block.end;
          // A standalone ID belongs to the preceding structured block.
          if (block.source.trim() == fragment) {
            final preceding = blocks.take(blocks.indexOf(block)).where(
              (candidate) => candidate.source.trim().isNotEmpty,
            ).toList();
            if (preceding.isEmpty) {
              throw const FormatException('This standalone block ID has no target. Use Source mode.');
            }
            targetStart = preceding.last.start;
          }
          break;
        }
      }
    } else {
      for (var i = 0; i < originalHeadings.length; i++) {
        if (originalHeadings[i].text == fragment ||
            (wiki
                ? originalHeadings[i].text.toLowerCase() ==
                      fragment.toLowerCase()
                : chapterLinkFragment(originalHeadings, i) ==
                      fragment.toLowerCase())) {
          headingIndex = i;
          targetStart = originalHeadings[i].offset;
          targetEnd = blocks
              .firstWhere((block) => block.start == targetStart)
              .end;
          break;
        }
      }
    }
    if (targetStart == null || targetEnd == null) {
      throw FormatException(
        'Cannot resolve #$fragment as a heading or block. Extract this format in Source mode manually.',
      );
    }
    final moved = targetStart >= selectionStart && targetEnd <= selectionEnd;
    if (!moved && targetStart < selectionEnd && targetEnd > selectionStart) {
      throw const FormatException(
        'Select the complete referenced heading or block before extracting.',
      );
    }
    final raw = reference.rawDestination;
    final range = reference.destinationRange;
    final rawEnd = range.start + raw.length;
    if (rawEnd > extracted.length ||
        extracted.substring(range.start, rawEnd) != raw) {
      throw const FormatException(
        'This fragment spelling cannot be moved safely. Use Source mode.',
      );
    }
    String replacement;
    if (!moved) {
      if (wiki && !WikiLinkInsertion.canRepresent(originRelativePath)) {
        throw const FormatException(
          'The original filename cannot be represented in a wiki link. Use Source mode.',
        );
      }
      final path = wiki
          ? '/$originRelativePath'
          : Uri.encodeComponent(p.basename(originRelativePath));
      replacement = '$path$raw';
    } else if (headingIndex != null) {
      final movedHeadingOffset = targetStart - selectionStart;
      final index = extractedHeadings.indexWhere(
        (heading) => heading.offset == movedHeadingOffset,
      );
      if (index < 0) {
        throw const FormatException(
          'The selected heading would lose its Markdown structure. Select a complete heading.',
        );
      }
      final slug = chapterLinkFragment(extractedHeadings, index);
      final target = wiki || slug.isEmpty
          ? extractedHeadings[index].text
          : slug;
      final hash = raw.indexOf('#');
      if (hash < 0 || (hash > 0 && raw[hash - 1] == '&')) {
        throw const FormatException(
          'Unsupported escaped fragment. Use Source mode.',
        );
      }
      replacement =
          '${raw.substring(0, hash + 1)}${wiki ? target : Uri.encodeComponent(target)}';
    } else {
      replacement = raw;
    }
    edits[range.start] = (end: rawEnd, text: replacement);
  }
  var result = extracted;
  final offsets = edits.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final start in offsets) {
    final edit = edits[start]!;
    result = result.replaceRange(start, edit.end, edit.text);
  }
  return result;
}
