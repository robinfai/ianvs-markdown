import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_clipboard/ianvs_markdown_clipboard.dart';

/// Handles HTML from one native clipboard item. A true result also means a
/// stale request was discarded: the caller must not launch another paste.
Future<bool> pasteClipboardHtml({
  required IanvsMarkdownController controller,
  required bool Function() isCurrent,
  required Future<IanvsMarkdownClipboardText?> Function() read,
}) async {
  final before = controller.value;
  final mode = controller.mode;
  final focus = FocusManager.instance.primaryFocus;
  if (!before.selection.isValid ||
      mode == IanvsMarkdownEditorMode.preview ||
      (before.composing.isValid && !before.composing.isCollapsed)) {
    return true;
  }
  var stale = false;
  void invalidate() => stale = true;
  controller.addListener(invalidate);
  controller.modeListenable.addListener(invalidate);
  focus?.addListener(invalidate);
  try {
    final data = await read();
    if (stale ||
        !isCurrent() ||
        controller.value != before ||
        controller.mode != mode ||
        FocusManager.instance.primaryFocus != focus) {
      return true;
    }
    if (data?.html == null) return false;
    var replacement = ianvsMarkdownHtmlPasteValue(before, data!.html!);
    if (replacement == null) {
      final plain = data.plainText;
      if (plain == null) return true;
      replacement = before
          .replaced(before.selection, plain)
          .copyWith(
            selection: TextSelection.collapsed(
              offset: before.selection.start + plain.length,
            ),
            composing: TextRange.empty,
          );
    }
    controller.commitHistoryGroup();
    controller.value = replacement;
    controller.commitHistoryGroup();
    return true;
  } finally {
    controller.removeListener(invalidate);
    controller.modeListenable.removeListener(invalidate);
    focus?.removeListener(invalidate);
  }
}
