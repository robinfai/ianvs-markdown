import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../models/document_analysis.dart';

TextRange chapterRange(
  String source,
  List<DocumentHeading> headings,
  int index,
) {
  final heading = headings[index];
  var end = source.length;
  for (var i = index + 1; i < headings.length; i++) {
    if (headings[i].level <= heading.level) {
      end = headings[i].offset;
      break;
    }
  }
  return TextRange(start: heading.offset, end: end);
}

/// Moves the exact source range including descendants; drops inside itself
/// are no-ops. Add only a missing line separator at a newly formed boundary.
String moveChapter(String source, int index, int destination) {
  final headings = DocumentAnalysis().headings(source);
  if (index < 0 || index >= headings.length) return source;
  final range = chapterRange(source, headings, index);
  final target = destination >= headings.length
      ? source.length
      : headings[destination.clamp(0, headings.length - 1)].offset;
  if (target >= range.start && target <= range.end) return source;
  final chapter = range.textInside(source);
  final rest = source.replaceRange(range.start, range.end, '');
  final insert = target > range.end
      ? target - (range.end - range.start)
      : target;
  final newline = source.contains('\r\n') ? '\r\n' : '\n';
  final prefix = insert > 0 && rest[insert - 1] != '\n' ? newline : '';
  final suffix = insert < rest.length && !chapter.endsWith('\n') ? newline : '';
  return rest.replaceRange(insert, insert, '$prefix$chapter$suffix');
}

String changeChapterLevel(String source, int index, int delta) {
  final headings = DocumentAnalysis().headings(source);
  if (index < 0 || index >= headings.length || delta.abs() != 1) return source;
  final range = chapterRange(source, headings, index);
  final selected = headings.where(
    (h) => h.offset >= range.start && h.offset < range.end,
  );
  if (selected.any((h) => h.level + delta < 1 || h.level + delta > 6)) {
    return source;
  }
  var result = source;
  final blocks = parseMarkdownBlocks(source);
  for (final heading in selected.toList().reversed) {
    final block = blocks.firstWhere((b) => b.start == heading.offset);
    final atx = RegExp(r'^( {0,3})(#{1,6})([ \t]+|$)').firstMatch(block.source);
    final markers = '#' * (heading.level + delta);
    if (atx != null) {
      result = result.replaceRange(
        block.start + atx.group(1)!.length,
        block.start + atx.group(1)!.length + atx.group(2)!.length,
        markers,
      );
    } else {
      // Setext headings become ATX while retaining their literal inline source.
      final newline = block.source.contains('\r\n') ? '\r\n' : '\n';
      final lines = block.source.split(RegExp(r'\r?\n'));
      final underline = lines.indexWhere(
        (line) => RegExp(r'^ {0,3}(=+|-+)[ \t]*$').hasMatch(line),
      );
      if (underline < 1) return source;
      final label = lines.take(underline).join(' ');
      final tail = lines.skip(underline + 1).join(newline);
      result = result.replaceRange(
        block.start,
        block.end,
        '$markers $label$newline$tail',
      );
    }
  }
  return result;
}

bool applyOutlineEdit(
  IanvsMarkdownController controller,
  String before,
  String after,
) {
  if (controller.text != before ||
      before == after ||
      (controller.value.composing.isValid &&
          !controller.value.composing.isCollapsed)) {
    return false;
  }
  controller.commitHistoryGroup();
  controller.value = TextEditingValue(
    text: after,
    selection: TextSelection.collapsed(
      offset: controller.selection.extentOffset.clamp(0, after.length),
    ),
  );
  controller.commitHistoryGroup();
  return true;
}

String chapterLinkFragment(List<DocumentHeading> headings, int index) {
  final counts = <String, int>{};
  for (var i = 0; i <= index; i++) {
    final slug = headings[i].text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}_\-\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s'), '-');
    final count = counts.update(slug, (value) => value + 1, ifAbsent: () => 0);
    if (i == index) return count == 0 ? slug : '$slug-$count';
  }
  throw RangeError.index(index, headings);
}
