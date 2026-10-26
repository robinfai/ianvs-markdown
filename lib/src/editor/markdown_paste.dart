import 'package:flutter/services.dart';
import 'editor_models.dart';

/// Reads plain text without surfacing platform clipboard availability errors.
Future<ClipboardData?> readPlainTextClipboardSafely() async {
  try {
    return await Clipboard.getData(Clipboard.kTextPlain);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Returns an Obsidian-style Markdown link replacement when [pastedText] is a
/// single HTTP(S) URL and [value] has a non-empty selection.
TextEditingValue? smartUrlPasteValue(
  TextEditingValue value,
  String pastedText, {
  bool escapeTablePipes = false,
}) {
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) return null;
  if (!_isHttpUrl(pastedText)) return null;

  final start = selection.start;
  final end = selection.end;
  if (start < 0 || end > value.text.length) return null;
  final selected = value.text.substring(start, end);
  final destination = escapeTablePipes
      ? pastedText.replaceAll('|', r'\|')
      : pastedText;
  final replacement = '[$selected]($destination)';
  return TextEditingValue(
    text: value.text.replaceRange(start, end, replacement),
    selection: TextSelection.collapsed(offset: start + replacement.length),
  );
}

/// Recognizes a URL-shaped selection replacement delivered through the text
/// input channel. The paste action uses [smartUrlPasteValue] directly; this is
/// a fallback for platforms that deliver paste as a regular editing update.
TextEditingValue? formatSmartUrlPasteEdit(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final selection = oldValue.selection;
  if (!selection.isValid || selection.isCollapsed) return null;

  final start = selection.start;
  final end = selection.end;
  if (start < 0 || end > oldValue.text.length) return null;

  final retainedLength = oldValue.text.length - (end - start);
  final insertedLength = newValue.text.length - retainedLength;
  if (insertedLength <= 0) return null;
  final insertedEnd = start + insertedLength;
  if (insertedEnd > newValue.text.length ||
      !newValue.selection.isValid ||
      !newValue.selection.isCollapsed ||
      newValue.selection.extentOffset != insertedEnd ||
      newValue.text.substring(0, start) != oldValue.text.substring(0, start) ||
      newValue.text.substring(insertedEnd) != oldValue.text.substring(end)) {
    return null;
  }

  final inserted = newValue.text.substring(start, insertedEnd);
  return smartUrlPasteValue(oldValue, inserted);
}

bool _isHttpUrl(String value) {
  if (value.isEmpty || value.trim() != value || value.contains(RegExp(r'\s'))) {
    return false;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

/// Recognizes rectangular spreadsheet text. A single tabbed line is left alone
/// because it commonly represents code or a plain text indentation.
String? markdownTableFromTsv(String source) {
  if (!source.contains('\t') || source.length > 1024 * 1024) return null;
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  var closedQuote = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closedQuote = true;
        }
      } else {
        cell.write(char);
      }
      continue;
    }
    if (char == '"' && cell.isEmpty && !closedQuote) {
      quoted = true;
      continue;
    }
    if (char == '\t' || char == '\n' || char == '\r') {
      row.add(cell.toString());
      cell = StringBuffer();
      closedQuote = false;
      if (char != '\t') {
        rows.add(row);
        row = [];
        if (char == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
      }
    } else {
      if (closedQuote) return null;
      cell.write(char);
    }
  }
  if (quoted) return null;
  if (cell.isNotEmpty || row.isNotEmpty || closedQuote) {
    row.add(cell.toString());
    rows.add(row);
  }
  if (rows.length < 2 ||
      rows.first.length < 2 ||
      rows.any((row) => row.length != rows.first.length)) {
    return null;
  }
  String escape(String cell) => cell
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAllMapped(RegExp(r'[\\`*_{}\[\]()#+.!|~\-]'), (m) => '\\${m[0]}')
      .replaceAll(RegExp(r'\r\n|\r|\n'), '<br>');
  String line(List<String> row) => '| ${row.map(escape).join(' | ')} |';
  return [
    line(rows.first),
    '| ${List.filled(rows.first.length, '---').join(' | ')} |',
    ...rows.skip(1).map(line),
  ].join('\n');
}

TextEditingValue? smartTablePasteValue(TextEditingValue value, String text) {
  final table = markdownTableFromTsv(text);
  return table == null ? null : markdownBlockPasteValue(value, table);
}

TextEditingValue? markdownBlockPasteValue(
  TextEditingValue value,
  String markdown,
) {
  final selection = value.selection;
  if (!selection.isValid ||
      selection.end > value.text.length ||
      (value.composing.isValid && !value.composing.isCollapsed)) {
    return null;
  }
  // Only top-level paragraph/blank locations accept a new block table. Other
  // contexts retain literal paste, including Source code and existing tables.
  final blocks = parseMarkdownBlocks(value.text);
  for (final block in blocks) {
    if (block.end < selection.start || block.start > selection.end) continue;
    if (block.type != IanvsMarkdownBlockType.paragraph) return null;
    // A block insertion inside an inline code span would destroy its literal
    // context. Keep that paste native, including partially selected code.
    for (final code in RegExp(
      r'(`+)[\s\S]*?\1(?!`)',
    ).allMatches(block.source)) {
      if (selection.start < block.start + code.end &&
          selection.end > block.start + code.start) {
        return null;
      }
    }
  }
  final before = value.text.substring(0, selection.start);
  final after = value.text.substring(selection.end);
  final newline = value.text.contains('\r\n') ? '\r\n' : '\n';
  String gap(String text, bool leading) {
    if (text.isEmpty) return '';
    final normalized = text.replaceAll('\r\n', '\n');
    final edge = leading ? normalized : normalized.split('').reversed.join();
    if (edge.endsWith('\n\n')) return '';
    return edge.endsWith('\n') ? newline : '$newline$newline';
  }

  final replacement =
      '${gap(before, true)}${markdown.replaceAll('\n', newline)}${gap(after, false)}';
  return TextEditingValue(
    text: '$before$replacement$after',
    selection: TextSelection.collapsed(
      offset: before.length + replacement.length,
    ),
  );
}
