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
