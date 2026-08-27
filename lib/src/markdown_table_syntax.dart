/// Counts cells in a Markdown table row without treating escaped pipes as
/// separators.
///
/// A leading or trailing pipe only frames the row and does not create an
/// additional empty cell. A pipe preceded by an odd number of backslashes is
/// escaped; an even number leaves it active as a separator.
int countMarkdownTableCells(String source) {
  final pipes = <int>[];
  for (var index = 0; index < source.length; index += 1) {
    if (source.codeUnitAt(index) != 0x7c) continue;
    var slashes = 0;
    for (
      var cursor = index - 1;
      cursor >= 0 && source.codeUnitAt(cursor) == 0x5c;
      cursor -= 1
    ) {
      slashes += 1;
    }
    if (slashes.isEven) pipes.add(index);
  }
  if (pipes.isEmpty) return 1;

  final trimmedLeft = source.length - source.trimLeft().length;
  final trimmedRight = source.trimRight().length;
  final leading = trimmedLeft < source.length && source[trimmedLeft] == '|';
  final trailing = trimmedRight > 0 && source[trimmedRight - 1] == '|';
  return pipes.length + 1 - (leading ? 1 : 0) - (trailing ? 1 : 0);
}
