import 'package:super_clipboard/super_clipboard.dart';

/// Text representations from one native clipboard item.
///
/// [html] is untrusted input, not sanitized HTML. The host must convert or
/// sanitize it before use. Missing or oversized HTML leaves [plainText] intact.
class IanvsMarkdownClipboardText {
  const IanvsMarkdownClipboardText({this.plainText, this.html});

  final String? plainText;
  final String? html;
}

/// Reads a single native clipboard snapshot without mixing representations
/// from different items. Returns null when native reading is unavailable or
/// the clipboard contains no readable text. Does not read files or images.
Future<IanvsMarkdownClipboardText?> readIanvsMarkdownClipboardText() =>
    readClipboardTextSnapshot(() async => SystemClipboard.instance?.read());

// Injectable native boundary for deterministic tests without OS clipboard IO.
Future<IanvsMarkdownClipboardText?> readClipboardTextSnapshot(
  Future<ClipboardReader?> Function() read,
) async {
  try {
    final snapshot = await read();
    if (snapshot == null) return null;
    for (final item in snapshot.items) {
      if (!item.canProvide(Formats.htmlText) &&
          !item.canProvide(Formats.plainText)) {
        continue;
      }
      String? html;
      String? plain;
      // A failed rich representation must not discard valid plain text from
      // the same item. Never supplement it from a second clipboard snapshot.
      try {
        if (item.canProvide(Formats.htmlText)) {
          html = await item.readValue(Formats.htmlText);
        }
      } on Object {
        html = null;
      }
      try {
        if (item.canProvide(Formats.plainText)) {
          plain = await item.readValue(Formats.plainText);
        }
      } on Object {
        plain = null;
      }
      if (html != null && (html.isEmpty || html.length > 1024 * 1024)) {
        html = null;
      }
      if (plain == null && html == null) return null;
      return IanvsMarkdownClipboardText(plainText: plain, html: html);
    }
  } on Object {
    // Plugin loading and clipboard availability vary across supported hosts.
  }
  return null;
}
