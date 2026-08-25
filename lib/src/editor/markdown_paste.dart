import 'package:flutter/services.dart';

/// Returns an Obsidian-style Markdown link replacement when [pastedText] is a
/// single HTTP(S) URL and [value] has a non-empty selection.
TextEditingValue? smartUrlPasteValue(
  TextEditingValue value,
  String pastedText,
) {
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) return null;
  if (!_isHttpUrl(pastedText)) return null;

  final start = selection.start;
  final end = selection.end;
  if (start < 0 || end > value.text.length) return null;
  final selected = value.text.substring(start, end);
  final replacement = '[$selected]($pastedText)';
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
