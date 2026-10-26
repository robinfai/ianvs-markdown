import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import '../editor/editor_models.dart';
import 'viewport_geometry.dart';
import 'reading_highlight.dart';

/// Internal bridge from renderer line ranges to full-document UTF-16 ranges.
class MarkdownSourceRegions {
  MarkdownSourceRegions({
    required this.source,
    required this.lineOffsets,
    this.highlights = const {},
    GlobalKey? plainKey,
  }) : _plainKey = plainKey ?? GlobalKey();
  final Map<TextRange, List<MarkdownReadingHighlightFlow>> highlights;
  final String source;
  final List<int> lineOffsets;
  final regions = <TextRange, GlobalKey>{};

  final _targetKeys = <String, GlobalKey>{};

  Widget wrapTarget(String id, Widget child) {
    final key = GlobalKey();
    _targetKeys[id] = key;
    return KeyedSubtree(key: key, child: child);
  }

  BuildContext? contextForTarget(String? id) =>
      id == null ? null : _targetKeys[id]?.currentContext;

  final GlobalKey _plainKey;
  String? _plainText;
  List<int> _plainLines = const [];

  Widget wrapPlain(String text, Widget child) {
    _plainText = text;
    _plainLines = [
      0,
      for (final match in RegExp(r'\r\n|\r|\n').allMatches(text)) match.end,
    ];
    return KeyedSubtree(key: _plainKey, child: child);
  }

  RenderBox? get _plainRender {
    RenderBox? result;
    void visit(RenderObject node) {
      if (node is RenderParagraph || node is RenderEditable) {
        result = node as RenderBox;
      } else if (result == null) {
        node.visitChildren(visit);
      }
    }

    final root = _plainKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return result;
  }

  RenderBox? _viewport(RenderBox render) {
    RenderBox? result;
    RenderObject? node = render.parent;
    while (node != null) {
      if (node is RenderAbstractViewport && node is RenderBox) {
        result = node as RenderBox;
      }
      node = node.parent;
    }
    return result;
  }

  Rect _caret(RenderBox render, int offset) {
    final position = TextPosition(offset: offset);
    if (render is RenderEditable) return render.getLocalRectForCaret(position);
    final paragraph = render as RenderParagraph;
    return paragraph.getOffsetForCaret(position, Rect.zero) & const Size(1, 1);
  }

  int _sourceOffset(int offset) {
    var line = _plainLines.lastIndexWhere((start) => start <= offset);
    line = line.clamp(0, lineOffsets.length - 1);
    return (lineOffsets[line] + offset - _plainLines[line]).clamp(
      0,
      source.length,
    );
  }

  bool revealPlain(
    IanvsMarkdownSourceNavigation request,
    ScrollController scroll,
  ) {
    final render = _plainRender;
    if (render == null ||
        !render.attached ||
        !render.hasSize ||
        !scroll.hasClients) {
      return false;
    }
    final viewport = _viewport(render);
    if (viewport == null) return false;
    var line = lineOffsets.lastIndexWhere(
      (start) => start <= request.range.start,
    );
    line = line.clamp(0, _plainLines.length - 1);
    final offset = (_plainLines[line] + request.range.start - lineOffsets[line])
        .clamp(0, _plainText!.length);
    final caret = _caret(render, offset);
    final dy =
        render.localToGlobal(caret.topLeft).dy -
        viewport.localToGlobal(Offset.zero).dy;
    final desired =
        request.viewportOffset ?? scroll.position.viewportDimension * .08;
    scroll.jumpTo(
      (scroll.offset + dy - desired).clamp(
        scroll.position.minScrollExtent,
        scroll.position.maxScrollExtent,
      ),
    );
    return true;
  }

  IanvsMarkdownViewportAnchor? capture() {
    final render = _plainRender;
    if (render != null && render.attached && render.hasSize) {
      final viewport = _viewport(render);
      if (viewport != null) {
        final top = viewport.localToGlobal(Offset.zero);
        final point = Offset(render.localToGlobal(Offset.zero).dx, top.dy);
        final position = render is RenderEditable
            ? render.getPositionForPoint(point)
            : (render as RenderParagraph).getPositionForOffset(
                render.globalToLocal(point),
              );
        final offset = position.offset.clamp(0, _plainText!.length);
        return IanvsMarkdownViewportAnchor(
          source: source,
          sourceOffset: _sourceOffset(offset),
          viewportOffset:
              render.localToGlobal(_caret(render, offset).topLeft).dy - top.dy,
        );
      }
    }
    return captureMarkdownViewport(
      source,
      regions.entries.map(
        (entry) => (offset: entry.key.start, key: entry.value),
      ),
    );
  }

  Widget wrap(TextRange lines, Widget child) {
    if (lines.start < 0 || lines.start >= lineOffsets.length) return child;
    final start = lineOffsets[lines.start];
    final end = lines.end < lineOffsets.length
        ? lineOffsets[lines.end]
        : source.length;
    if (start >= end) return child;
    final range = TextRange(start: start, end: end);
    final key = regions.putIfAbsent(range, GlobalKey.new);
    final flows = highlights[range];
    return KeyedSubtree(
      key: key,
      child: flows == null
          ? child
          : MarkdownReadingHighlightOverlay(flows: flows, child: child),
    );
  }

  BuildContext? contextAt(int offset) {
    final ordered = regions.keys.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    TextRange? target;
    for (final range in ordered) {
      if (offset >= range.start && offset < range.end) {
        target = range;
        break;
      }
      if (range.start >= offset) {
        target = range;
        break;
      }
    }
    target ??= ordered.isEmpty ? null : ordered.last;
    return target == null ? null : regions[target]?.currentContext;
  }
}

class MarkdownSourceRegionScope extends InheritedWidget {
  const MarkdownSourceRegionScope({
    super.key,
    required this.regions,
    required super.child,
  });
  final MarkdownSourceRegions? regions;

  static MarkdownSourceRegions? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MarkdownSourceRegionScope>()
      ?.regions;

  @override
  bool updateShouldNotify(MarkdownSourceRegionScope oldWidget) =>
      !identical(regions, oldWidget.regions);
}
