import 'dart:convert';

import 'workspace_index_source.dart';
import 'attachment_resolver.dart';

/// A single simultaneous namespace transform. Comparison keys are never paths.
/// The component boundary deliberately keeps `a` distinct from `ab`.
class WorkspaceMoveNamespace {
  WorkspaceMoveNamespace({required this.source, required this.destination}) {
    if (!isSupportedWorkspaceMovePath(source, directory: true) ||
        !isSupportedWorkspaceMovePath(destination, directory: true) ||
        source.isEmpty ||
        destination.isEmpty ||
        contains(source, destination) ||
        contains(destination, source)) {
      throw const FormatException('Invalid or overlapping move namespaces.');
    }
  }

  final String source;
  final String destination;

  static bool contains(String root, String path) =>
      path == root || path.startsWith('$root/');

  bool moves(String path) => contains(source, path);
  String map(String path) =>
      moves(path) ? '$destination${path.substring(source.length)}' : path;
}

/// Conservative output limits for this directory preview only. These do not
/// widen or change the existing catalog/navigation/native v1 path protocols.
/// Native parents allow 64 directory components and 65 components for a file;
/// UTF-8 ceilings also avoid proposing unrepresentable destination filenames.
bool isSupportedWorkspaceMovePath(String path, {required bool directory}) =>
    path.isNotEmpty &&
    safeWorkspaceRelativePath(path, directory: directory) &&
    isScalarAttachmentPath(path) &&
    utf8.encode(path).length <= 4096 &&
    path.split('/').every((component) => utf8.encode(component).length <= 255);

/// Simultaneous mapping from original paths, never a chain of moves.
class WorkspaceBatchMoveNamespace extends WorkspaceMoveNamespace {
  factory WorkspaceBatchMoveNamespace(List<WorkspaceMoveNamespace> roots) {
    if (roots.length < 2 || roots.length > 8) {
      throw const FormatException('A batch needs 2–8 roots.');
    }
    return WorkspaceBatchMoveNamespace._(roots);
  }
  WorkspaceBatchMoveNamespace._(List<WorkspaceMoveNamespace> roots)
    : roots = List.unmodifiable(roots),
      super(source: roots.first.source, destination: roots.first.destination) {
    if (roots.length < 2 || roots.length > 8) {
      throw const FormatException('A batch needs 2–8 roots.');
    }
    for (var i = 0; i < roots.length; i++) {
      for (var j = 0; j < roots.length; j++) {
        if (i != j &&
            (WorkspaceMoveNamespace.contains(
                  roots[i].source,
                  roots[j].source,
                ) ||
                WorkspaceMoveNamespace.contains(
                  roots[i].destination,
                  roots[j].destination,
                ))) {
          throw const FormatException('Batch roots overlap.');
        }
        if (WorkspaceMoveNamespace.contains(
              roots[i].source,
              roots[j].destination,
            ) ||
            WorkspaceMoveNamespace.contains(
              roots[j].destination,
              roots[i].source,
            )) {
          throw const FormatException('Batch source and destination overlap.');
        }
      }
    }
  }
  final List<WorkspaceMoveNamespace> roots;
  @override
  bool moves(String path) => roots.any((root) => root.moves(path));
  @override
  String map(String path) {
    for (final root in roots) {
      if (root.moves(path)) return root.map(path);
    }
    return path;
  }
}
