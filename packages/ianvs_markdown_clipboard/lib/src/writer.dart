import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// Writes Markdown and HTML to one native clipboard item. If the native writer
/// is unavailable or fails, falls back to the complete Markdown as plain text.
/// A failure of that fallback is reported to the caller.
///
/// Pass HTML produced by the Markdown library or otherwise sanitized by the
/// host. This adapter writes the supplied representations without parsing them.
Future<void> writeIanvsMarkdownRichClipboard({
  required String markdown,
  required String html,
}) => writeClipboardWithFallback(
  markdown: markdown,
  html: html,
  nativeClipboard: () => SystemClipboard.instance,
  plainText: Clipboard.setData,
);

// Internal boundary for testing native availability, multi-format grouping,
// asynchronous failures and fallback errors without touching the OS clipboard.
Future<void> writeClipboardWithFallback({
  required String markdown,
  required String html,
  required ClipboardWriter? Function() nativeClipboard,
  required Future<void> Function(ClipboardData) plainText,
}) async {
  try {
    final clipboard = nativeClipboard();
    if (clipboard != null) {
      final item = DataWriterItem()
        ..add(Formats.plainText(markdown))
        ..add(Formats.htmlText(html));
      await clipboard.write([item]);
      return;
    }
  } on Object {
    // Preserve the old native writer's fallback when plugins are unavailable.
  }
  await plainText(ClipboardData(text: markdown));
}
