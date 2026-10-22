import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

/// Remembers the last editor-owned input across toolbar/menu focus changes.
/// Local table/property editors do not always project a caret into source.
class DocumentInputTarget {
  DocumentInputTarget({
    required this.mainFocus,
    required this.document,
    required this.onLocalTarget,
  }) {
    FocusManager.instance.addListener(_focusChanged);
  }

  final FocusNode mainFocus;
  final IanvsMarkdownController? Function() document;

  /// Invalidates an in-flight insertion even if focus later returns to body.
  final VoidCallback onLocalTarget;
  bool _local = false;
  bool get isLocal => _local;

  void reset() => _local = false;

  void _focusChanged() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null ||
        !focused.mounted ||
        (focused is Element && focused.renderObject?.attached != true)) {
      return;
    }
    final input = focused.findAncestorStateOfType<EditableTextState>();
    if (input == null) return;
    // Also covers the standalone Source editor used by Find/Replace.
    if (identical(input.widget.focusNode, mainFocus)) {
      _local = false;
      return;
    }
    final live = focused
        .findAncestorWidgetOfExactType<IanvsMarkdownLiveEditor>();
    if (live != null && identical(live.controller, document())) {
      if (!_local) onLocalTarget();
      _local = true;
    }
  }

  void dispose() => FocusManager.instance.removeListener(_focusChanged);
}
