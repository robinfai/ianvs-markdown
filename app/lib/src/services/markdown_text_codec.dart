import 'dart:convert';

/// Strict UTF-8 decoding that retains the optional byte-order mark as source.
/// Dart's Utf8Decoder removes one leading BOM, so restore it deliberately.
String decodeMarkdownUtf8(List<int> bytes) {
  final decoded = utf8.decode(bytes, allowMalformed: false);
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  return hasBom ? '\ufeff$decoded' : decoded;
}
