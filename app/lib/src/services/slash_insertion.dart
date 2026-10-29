import 'package:flutter/services.dart';

/// Trigger only a freshly typed slash on an otherwise empty line.
/// Pasting paths, moving the caret and typing inside prose do not open a menu.
int? slashInsertionStart(String previous, TextEditingValue value) {
  final caret = value.selection.extentOffset;
  if (!value.selection.isValid ||
      !value.selection.isCollapsed ||
      caret <= 0 ||
      caret > value.text.length ||
      value.text.length != previous.length + 1 ||
      (value.composing.isValid && !value.composing.isCollapsed) ||
      value.text[caret - 1] != '/' ||
      value.text.replaceRange(caret - 1, caret, '') != previous) {
    return null;
  }
  final start = value.text.lastIndexOf('\n', caret - 1) + 1;
  final end = value.text.indexOf('\n', caret);
  final line = value.text.substring(start, end < 0 ? value.text.length : end);
  if (line.trim() != '/') return null;
  return caret - 1;
}

const slashSnippets = <String, String>{
  'Heading 1': '# ',
  'Heading 2': '## ',
  'Task list': '- [ ] ',
  'Quote': '> ',
  'Code block': '```\n\n```\n',
};
