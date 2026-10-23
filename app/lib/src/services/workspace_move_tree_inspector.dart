import 'dart:convert';
import 'package:flutter/services.dart';

import 'apple_workspace_service.dart';
import 'workspace_index_source.dart';
import 'workspace_move_tree.dart';

/// Cancellation only abandons a read-only preview. It never cancels or retries
/// a file mutation, and it cannot interrupt a blocked filesystem system call.
class WorkspaceMovePreviewCancellation {
  bool _cancelled = false;
  final Set<VoidCallback> _listeners = {};

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  VoidCallback listen(VoidCallback listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_cancelled) throw const WorkspaceMovePreviewCancelled();
  }
}

class WorkspaceMovePreviewCancelled implements Exception {
  const WorkspaceMovePreviewCancelled();

  @override
  String toString() => 'The read-only move preview was cancelled.';
}

abstract interface class WorkspaceMoveTreeInspector {
  Future<WorkspaceMoveTreeSnapshot> inspect(
    String root,
    String relativePath,
    String requestId,
  );

  Future<void> cancel(String requestId);
}

/// Uses the existing selected workspace grant. There is no Dart filesystem
/// fallback and no journal/reconciliation method in this service.
class AppleWorkspaceMoveTreeInspector implements WorkspaceMoveTreeInspector {
  const AppleWorkspaceMoveTreeInspector({
    this.channel = AppleWorkspaceService.channel,
  });

  final MethodChannel channel;

  static bool _validRequestId(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);

  @override
  Future<WorkspaceMoveTreeSnapshot> inspect(
    String root,
    String relativePath,
    String requestId,
  ) async {
    if (root.length > 4096 ||
        relativePath.length > 4096 ||
        utf8.encode(root).length > 4096 ||
        utf8.encode(relativePath).length > 4096 ||
        !root.startsWith('/') ||
        root.contains('\u0000') ||
        !safeWorkspaceRelativePath(relativePath) ||
        !_validRequestId(requestId)) {
      throw const FormatException('Invalid directory preview request.');
    }
    final raw = await channel.invokeMethod<Object?>(
      'inspectWorkspaceDirectoryMoveTree',
      {'path': root, 'relativePath': relativePath, 'requestId': requestId},
    );
    final snapshot = WorkspaceMoveTreeSnapshot.fromNative(raw);
    if (snapshot.root != root ||
        snapshot.sourcePath != relativePath ||
        snapshot.requestId != requestId) {
      throw const FormatException('The directory preview scope changed.');
    }
    return snapshot;
  }

  @override
  Future<void> cancel(String requestId) async {
    if (!_validRequestId(requestId)) {
      throw const FormatException('Invalid directory preview cancellation.');
    }
    await channel.invokeMethod<void>('cancelWorkspaceDirectoryMoveInspection', {
      'requestId': requestId,
    });
  }
}
