final RegExp _markdownListItemStartPattern = RegExp(
  r'^ {0,3}(?:(\d{1,9})[.)]|[*+-])(?:[ \t]+(.*))?$',
);

/// Whether [source] can start a list that interrupts an open paragraph.
///
/// CommonMark allows only non-empty items to interrupt. An ordered item must
/// additionally start at `1`; other starting numbers remain paragraph text
/// unless a real block boundary precedes them.
bool isMarkdownInterruptingListItemStart(String source) {
  final match = _markdownListItemStartPattern.firstMatch(source);
  if (match == null) return false;
  final orderedStart = match.group(1);
  if (orderedStart != null && orderedStart != '1') return false;
  return match.group(2)?.isNotEmpty ?? false;
}
