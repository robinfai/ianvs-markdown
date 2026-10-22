import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'apple_workspace_service.dart';
import 'markdown_file_service.dart';
import 'markdown_text_codec.dart';

const workspaceTextMaximumBytes = 5 * 1024 * 1024;

enum WorkspaceReadIssue {
  offline,
  denied,
  oversized,
  invalid,
  missing,
  unavailable,
  changed,
  limit,
  cancelled,
}

class WorkspaceIndexFailure implements Exception {
  const WorkspaceIndexFailure(this.issue);
  final WorkspaceReadIssue issue;
  @override
  String toString() => issue.name;
}

WorkspaceReadIssue workspaceReadIssue(Object error) {
  if (error is WorkspaceIndexFailure) return error.issue;
  if (error is FormatException) return WorkspaceReadIssue.invalid;
  if (error is PlatformException) {
    return switch (error.code) {
      'attachment_offline' => WorkspaceReadIssue.offline,
      'attachment_denied' => WorkspaceReadIssue.denied,
      'attachment_too_large' => WorkspaceReadIssue.oversized,
      'attachment_invalid' => WorkspaceReadIssue.invalid,
      'attachment_missing' => WorkspaceReadIssue.missing,
      'attachment_changed' => WorkspaceReadIssue.changed,
      'attachment_index_limit' => WorkspaceReadIssue.limit,
      _ => WorkspaceReadIssue.unavailable,
    };
  }
  return WorkspaceReadIssue.unavailable;
}

bool safeWorkspaceRelativePath(String path, {bool directory = false}) =>
    (directory && path.isEmpty) ||
    (path.isNotEmpty &&
        !p.posix.isAbsolute(path) &&
        !path.contains('\\') &&
        !path.contains('\u0000') &&
        path
            .split('/')
            .every(
              (part) =>
                  part.isNotEmpty &&
                  part != '.' &&
                  part != '..' &&
                  !part.startsWith('.'),
            ));

class WorkspaceMetadata {
  const WorkspaceMetadata({
    required this.relativePath,
    required this.isDirectory,
    this.size = 0,
    this.modified = 0,
    required this.revision,
    this.local = true,
  });
  final String relativePath;
  final bool isDirectory;
  final int size;
  final int modified;
  final String revision;
  final bool local;
  WorkspaceEntry entry(String root) => WorkspaceEntry(
    path: p.posix.join(root, relativePath),
    name: p.posix.basename(relativePath),
    isDirectory: isDirectory,
    modified: DateTime.fromMillisecondsSinceEpoch(modified),
  );
}

class WorkspaceDirectorySnapshot {
  const WorkspaceDirectorySnapshot(
    this.entries, {
    this.complete = true,
    this.reason,
  });
  final List<WorkspaceMetadata> entries;
  final bool complete;
  final String? reason;
}

class WorkspaceTextRead {
  const WorkspaceTextRead(this.text, this.revision);
  final String text;
  final String revision;
}

/// Root-relative capability: no absolute-path or ordinary Markdown read fallback.
/// Listing is metadata only and reading must never materialize provider files.
abstract class WorkspaceIndexSource {
  Future<WorkspaceDirectorySnapshot> listWorkspaceDirectory(
    String root,
    String relativePath,
  );
  Future<WorkspaceTextRead> readWorkspaceText(
    String root,
    String relativePath,
    int maximumBytes,
  );
}

class AppleWorkspaceIndexSource implements WorkspaceIndexSource {
  const AppleWorkspaceIndexSource();
  @override
  Future<WorkspaceDirectorySnapshot> listWorkspaceDirectory(
    String root,
    String relativePath,
  ) async {
    final data = await AppleWorkspaceService.channel
        .invokeMapMethod<String, dynamic>('listWorkspaceDirectory', {
          'path': root,
          'relativePath': relativePath,
        });
    if (data == null || data['entries'] is! List || data['complete'] is! bool) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.unavailable);
    }
    return WorkspaceDirectorySnapshot(
      [
        for (final item in data['entries'] as List)
          WorkspaceMetadata(
            relativePath: (item as Map)['relativePath'] as String,
            isDirectory: item['isDirectory'] == true,
            size: (item['size'] as num?)?.toInt() ?? 0,
            modified: (item['modified'] as num?)?.toInt() ?? 0,
            revision: item['revision'] as String,
            local: item['local'] != false,
          ),
      ],
      complete: data['complete'] as bool,
      reason: data['reason'] as String?,
    );
  }

  @override
  Future<WorkspaceTextRead> readWorkspaceText(
    String root,
    String relativePath,
    int maximumBytes,
  ) async {
    final data = await AppleWorkspaceService.channel
        .invokeMapMethod<String, dynamic>('readWorkspaceTextBytes', {
          'path': root,
          'relativePath': relativePath,
          'maximumBytes': maximumBytes,
        });
    final bytes = data?['bytes'];
    if (bytes is! Uint8List || data?['revision'] is! String) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.unavailable);
    }
    if (bytes.length > maximumBytes) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.oversized);
    }
    return WorkspaceTextRead(
      decodeMarkdownUtf8(bytes),
      data!['revision'] as String,
    );
  }
}
