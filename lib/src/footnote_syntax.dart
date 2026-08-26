/// Returns the closing bracket for an Obsidian inline footnote whose body
/// starts at [start], or `-1` when the token is incomplete or crosses a line.
///
/// Balanced brackets allow nested inline footnotes such as
/// `^[outer ^[inner]]`; backslash-escaped brackets remain literal body text.
int findIanvsMarkdownInlineFootnoteEnd(String source, int start) {
  var depth = 1;
  for (var index = start; index < source.length; index += 1) {
    final character = source.codeUnitAt(index);
    if (character == 0x0a || character == 0x0d) return -1;
    if (character == 0x5c && index + 1 < source.length) {
      index += 1;
      continue;
    }
    if (character == 0x5b) {
      depth += 1;
      continue;
    }
    if (character != 0x5d) continue;
    depth -= 1;
    if (depth == 0) return index;
  }
  return -1;
}

bool isIanvsMarkdownEscapedAt(String source, int offset) {
  var backslashes = 0;
  for (
    var index = offset - 1;
    index >= 0 && source.codeUnitAt(index) == 0x5c;
    index -= 1
  ) {
    backslashes += 1;
  }
  return backslashes.isOdd;
}
