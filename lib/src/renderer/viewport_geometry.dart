import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../editor/editor_models.dart';

IanvsMarkdownViewportAnchor? captureMarkdownViewport(
  String source,
  Iterable<({int offset, GlobalKey key})> regions,
) {
  IanvsMarkdownViewportAnchor? result;
  for (final region in regions) {
    final render = region.key.currentContext?.findRenderObject();
    if (render is! RenderBox ||
        !render.attached ||
        !render.hasSize ||
        render.size.isEmpty) {
      continue;
    }
    // A focused editor may be retained outside the sliver's painted children.
    // Its old transform is not evidence that it is visible in this viewport.
    var keptAlive = false;
    RenderObject? ancestor = render;
    while (ancestor != null && ancestor is! RenderAbstractViewport) {
      final data = ancestor.parentData;
      if (data is SliverMultiBoxAdaptorParentData && data.keptAlive) {
        keptAlive = true;
        break;
      }
      ancestor = ancestor.parent;
    }
    if (keptAlive) continue;
    final viewport = switch (RenderAbstractViewport.maybeOf(render)) {
      RenderBox box => box,
      _ => null,
    };
    if (viewport == null || !viewport.hasSize) continue;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final dy = render.localToGlobal(Offset.zero).dy - top;
    if (dy + render.size.height <= 0 || dy >= viewport.size.height) continue;
    if (result == null || dy < result.viewportOffset) {
      result = IanvsMarkdownViewportAnchor(
        source: source,
        sourceOffset: region.offset,
        viewportOffset: dy,
      );
    }
  }
  return result;
}

void restoreMarkdownViewport(
  BuildContext target,
  ScrollController scroll,
  double viewportOffset,
) {
  final render = target.findRenderObject();
  if (render == null || !render.attached || !scroll.hasClients) return;
  final viewport = RenderAbstractViewport.maybeOf(render);
  if (viewport == null) return;
  final position = scroll.position;
  scroll.jumpTo(
    (viewport.getOffsetToReveal(render, 0).offset - viewportOffset)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble(),
  );
}
