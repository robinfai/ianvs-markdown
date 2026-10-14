import 'package:flutter/widgets.dart';

import 'editor_models.dart';

// Internal layout region: offsets are metadata, not widget identity. Keeping
// unchanged blocks mounted also retains their semantics and async child state.
class MarkdownBlockRegion extends StatelessWidget {
  const MarkdownBlockRegion({
    super.key,
    required this.block,
    required this.child,
  });
  final IanvsMarkdownBlock block;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

// Reconcile unchanged prefix/suffix around one changed span. Matching from both
// ends avoids conflating identical paragraphs, and never carries a key twice.
// Changed blocks can keep their old start only if that identity was not moved.
Map<int, int> markdownBlockOrigins(
  List<IanvsMarkdownBlock> previous,
  List<IanvsMarkdownBlock> next,
) {
  final result = <int, int>{};
  final used = <int>{};
  bool equal(IanvsMarkdownBlock a, IanvsMarkdownBlock b) =>
      a.type == b.type && a.source == b.source;
  var prefix = 0;
  while (prefix < previous.length &&
      prefix < next.length &&
      equal(previous[prefix], next[prefix])) {
    result[next[prefix].start] = previous[prefix].start;
    used.add(previous[prefix].start);
    prefix++;
  }
  var oldEnd = previous.length - 1;
  var newEnd = next.length - 1;
  while (oldEnd >= prefix &&
      newEnd >= prefix &&
      equal(previous[oldEnd], next[newEnd])) {
    result[next[newEnd].start] = previous[oldEnd].start;
    used.add(previous[oldEnd].start);
    oldEnd--;
    newEnd--;
  }
  final oldStarts = previous.map((block) => block.start).toSet();
  for (var i = prefix; i <= newEnd; i++) {
    final start = next[i].start;
    if (oldStarts.contains(start) && !used.contains(start)) {
      result[start] = start;
      used.add(start);
    }
  }
  return result;
}
