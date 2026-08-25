import 'editor/editor_models.dart';

/// One source-preserving Obsidian task marker discovered during rendering.
final class IanvsMarkdownTaskSourceMarker {
  const IanvsMarkdownTaskSourceMarker({
    required this.marker,
    required this.offset,
  });

  /// The exact single character between `[` and `]`.
  final String marker;

  /// UTF-16 offset of [marker] in the projected source input.
  final int offset;
}

/// Markdown prepared for the GFM parser plus its original Obsidian markers.
final class IanvsMarkdownTaskProjection {
  const IanvsMarkdownTaskProjection({required this.data, required this.tasks});

  /// Source with non-GFM task states projected to `[x]` at equal length.
  final String data;

  /// Task markers in the same order as the renderer invokes its checkbox
  /// builder, including child-before-parent callbacks for nested lists.
  final List<IanvsMarkdownTaskSourceMarker> tasks;
}

/// Projects Obsidian's single-character task states onto GFM `[ ]` / `[x]`.
///
/// The transformation is length preserving and skips fenced/indented code,
/// front matter, tables, and ordinary paragraphs. This lets the upstream GFM
/// renderer build its normal list structure while Ianvs restores the exact
/// marker-specific visuals from [IanvsMarkdownTaskProjection.tasks].
IanvsMarkdownTaskProjection projectObsidianTaskMarkers(String source) {
  if (source.isEmpty) {
    return const IanvsMarkdownTaskProjection(
      data: '',
      tasks: <IanvsMarkdownTaskSourceMarker>[],
    );
  }

  final replacements = <int, String>{};
  final tasks = <IanvsMarkdownTaskSourceMarker>[];
  final blocks = parseMarkdownBlocks(source);
  for (final block in blocks) {
    final scansTaskLines = switch (block.type) {
      IanvsMarkdownBlockType.taskList ||
      IanvsMarkdownBlockType.unorderedList ||
      IanvsMarkdownBlockType.orderedList ||
      IanvsMarkdownBlockType.blockquote => true,
      _ => false,
    };
    if (!scansTaskLines) continue;
    _scanTaskBlock(
      block.source,
      blockOffset: block.start,
      tasks: tasks,
      replacements: replacements,
    );
  }

  if (replacements.isEmpty) {
    return IanvsMarkdownTaskProjection(
      data: source,
      tasks: List<IanvsMarkdownTaskSourceMarker>.unmodifiable(tasks),
    );
  }
  final output = StringBuffer();
  for (var offset = 0; offset < source.length; offset += 1) {
    output.write(replacements[offset] ?? source[offset]);
  }
  return IanvsMarkdownTaskProjection(
    data: output.toString(),
    tasks: List<IanvsMarkdownTaskSourceMarker>.unmodifiable(tasks),
  );
}

final RegExp _listLine = RegExp(
  r'^((?:(?:[ \t]{0,3}>[ \t]?)+)?[ \t]*)(?:[-+*]|\d{1,9}[.)])[ \t]+(?:\[([^\r\n])\](?:[ \t]+|$))?',
);
final RegExp _fenceLine = RegExp(
  r'^(?:(?:[ \t]{0,3}>[ \t]?)+)?[ \t]{0,3}(`{3,}|~{3,})',
);

void _scanTaskBlock(
  String source, {
  required int blockOffset,
  required List<IanvsMarkdownTaskSourceMarker> tasks,
  required Map<int, String> replacements,
}) {
  final roots = <_TaskListNode>[];
  final stack = <_TaskListNode>[];
  var lineStart = 0;
  var fenceCharacter = '';
  var fenceLength = 0;
  while (lineStart <= source.length) {
    final lineBreak = source.indexOf('\n', lineStart);
    final lineEnd = lineBreak < 0 ? source.length : lineBreak;
    final line = source.substring(lineStart, lineEnd);
    final fence = _fenceLine.firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      if (fenceLength == 0) {
        fenceCharacter = marker[0];
        fenceLength = marker.length;
      } else if (marker[0] == fenceCharacter &&
          marker.length >= fenceLength &&
          line.substring(fence.end).trim().isEmpty) {
        fenceCharacter = '';
        fenceLength = 0;
      }
    } else if (fenceLength == 0) {
      final listItem = _listLine.firstMatch(line);
      if (listItem != null) {
        final marker = listItem.group(2);
        final markerOffset = marker == null
            ? null
            : blockOffset +
                  lineStart +
                  listItem.start +
                  listItem.group(0)!.lastIndexOf('[') +
                  1;
        final task = markerOffset == null
            ? null
            : IanvsMarkdownTaskSourceMarker(
                marker: marker!,
                offset: markerOffset,
              );
        final node = _TaskListNode(
          depth: _prefixDepth(listItem.group(1)!),
          task: task,
        );
        while (stack.isNotEmpty && node.depth <= stack.last.depth) {
          stack.removeLast();
        }
        if (stack.isEmpty) {
          roots.add(node);
        } else {
          stack.last.children.add(node);
        }
        stack.add(node);
        if (task != null && marker != ' ' && marker != 'x' && marker != 'X') {
          replacements[markerOffset!] = 'x';
        }
      }
    }
    if (lineBreak < 0) break;
    lineStart = lineBreak + 1;
  }

  for (final root in roots) {
    _appendTasksPostorder(root, tasks);
  }
}

int _prefixDepth(String prefix) {
  var depth = 0;
  for (final codeUnit in prefix.codeUnits) {
    depth = codeUnit == 0x09 ? depth + (4 - depth % 4) : depth + 1;
  }
  return depth;
}

void _appendTasksPostorder(
  _TaskListNode node,
  List<IanvsMarkdownTaskSourceMarker> tasks,
) {
  for (final child in node.children) {
    _appendTasksPostorder(child, tasks);
  }
  final task = node.task;
  if (task != null) tasks.add(task);
}

final class _TaskListNode {
  _TaskListNode({required this.depth, required this.task});

  final int depth;
  final IanvsMarkdownTaskSourceMarker? task;
  final List<_TaskListNode> children = <_TaskListNode>[];
}
