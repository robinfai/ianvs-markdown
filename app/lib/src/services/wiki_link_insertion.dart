import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

/// A captured UTF-16 source edit. A late picker result must not edit another
/// selection, composition, document revision or editor mode.
class WikiLinkInsertion {
  WikiLinkInsertion._(
    this.value,
    this.mode,
    this.start,
    this.end,
    this.partial,
    this.close,
  );
  final TextEditingValue value;
  final IanvsMarkdownEditorMode mode;
  final int start;
  final int end;
  final bool partial;
  final bool close;

  static WikiLinkInsertion? capture(IanvsMarkdownController controller) {
    final value = controller.value;
    if (controller.mode == IanvsMarkdownEditorMode.preview ||
        (value.composing.isValid && !value.composing.isCollapsed) ||
        !value.selection.isValid ||
        value.selection.end > value.text.length ||
        !_scalarBoundary(value.text, value.selection.start) ||
        !_scalarBoundary(value.text, value.selection.end)) {
      return null;
    }
    final caret = value.selection.extentOffset;
    if (value.selection.isCollapsed) {
      final opening = value.text.lastIndexOf('[[', caret);
      if (opening >= 0 &&
          opening + 2 <= caret &&
          (opening == 0 || !r'\!['.contains(value.text[opening - 1]))) {
        final prefix = value.text.substring(opening + 2, caret);
        if (!prefix.contains(RegExp(r'[\r\n\[\]#|]'))) {
          var end = caret;
          while (end < value.text.length &&
              !RegExp(r'[\r\n\[\]#|]').hasMatch(value.text[end])) {
            end++;
          }
          final hasSuffix =
              end < value.text.length &&
              (value.text[end] == '|' ||
                  value.text[end] == '#' ||
                  value.text.startsWith(']]', end));
          return WikiLinkInsertion._(
            value,
            controller.mode,
            opening + 2,
            hasSuffix ? end : caret,
            true,
            !hasSuffix,
          );
        }
      }
    }
    return WikiLinkInsertion._(
      value,
      controller.mode,
      value.selection.start,
      value.selection.end,
      false,
      false,
    );
  }

  String get query =>
      partial ? value.text.substring(start, value.selection.extentOffset) : '';

  static bool canRepresent(String relativePath) =>
      !relativePath.contains(RegExp(r'[\r\n\[\]#|]')) &&
      relativePath.toLowerCase().endsWith('.md');

  bool apply(IanvsMarkdownController controller, String relativePath) {
    if (controller.mode != mode ||
        controller.value != value ||
        !canRepresent(relativePath)) {
      return false;
    }
    final stem = relativePath.substring(0, relativePath.length - 3);
    // The resolver treats a trailing .md as a complete filename and trims the
    // whole target. Keep the extension whenever omission would change identity.
    final keepExtension =
        stem.toLowerCase().endsWith('.md') || stem.trimRight() != stem;
    final target = '/${keepExtension ? relativePath : stem}';
    final replacement = partial ? '$target${close ? ']]' : ''}' : '[[$target]]';
    controller.commitHistoryGroup();
    controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    controller.commitHistoryGroup();
    return true;
  }
}

// A programmatic selection can be UTF-16-valid but bisect an emoji. Do not
// create an unpaired surrogate when applying a delayed completion.
bool _scalarBoundary(String text, int offset) =>
    offset <= 0 ||
    offset >= text.length ||
    !(text.codeUnitAt(offset - 1) >= 0xd800 &&
        text.codeUnitAt(offset - 1) <= 0xdbff &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff);
