import 'dart:convert';

import 'package:path/path.dart' as p;

import 'attachment_resolver.dart';
import 'workspace_move_namespace.dart';

const workspaceMoveTreeMaximumMembers = 256;
const workspaceMoveTreeMaximumDirectories = 64;
const workspaceMoveTreeMaximumMetadataBytes = 1024 * 1024;

enum WorkspaceMoveTreeSourceState {
  directory,
  missing,
  notDirectory,
  unavailable,
}

enum WorkspaceMoveTreeMemberKind {
  directory,
  note,
  image,
  unsupported,
  symlink,
  special,
}

class WorkspaceMoveTreeIssue {
  const WorkspaceMoveTreeIssue(this.code, {this.path});
  final String code;
  final String? path;

  String get message => switch (code) {
    'recoveryArtifact' =>
      'This directory contains retained move-recovery evidence that cannot be relocated safely.',
    'hiddenMember' =>
      'Hidden files or folders prevent complete reference maintenance.',
    'unsupportedMember' || 'unsupported_member' =>
      'This directory contains an unsupported file type, such as PDF. Only supported notes and images are covered.',
    'unsupportedPath' || 'invalidFilename' =>
      'A directory member has a filename that cannot be represented safely.',
    'symlinkMember' =>
      'Symbolic links are not supported by maintained directory moves.',
    'specialMember' =>
      'A special filesystem object prevents complete directory coverage.',
    'packageMember' =>
      'Application bundles and package directories are not supported.',
    'offline' =>
      'A directory member is not locally available. Download it before refreshing the preview.',
    'multiplyLinkedMember' =>
      'A file has multiple hard links, so its identity cannot be relocated safely.',
    'differentDevice' => 'A directory member is on a different filesystem.',
    'entryLimit' => 'The directory exceeds the 256-member preview limit.',
    'directoryLimit' => 'The directory exceeds the 64-folder preview limit.',
    'metadataLimit' =>
      'The directory exceeds the 1 MiB metadata preview limit.',
    'issueLimit' =>
      'The directory has too many inspection problems to report completely.',
    'depthLimit' => 'The directory is nested too deeply for a bounded preview.',
    'treeChanged' =>
      'The directory changed during inspection. Refresh the preview.',
    'cancelled' => 'Directory inspection was cancelled; no files were changed.',
    'deadlineExceeded' =>
      'Directory inspection reached its time limit; coverage is incomplete.',
    'permissionDenied' =>
      'A directory member could not be inspected with the current folder permission.',
    'invalidAncestor' =>
      'A parent folder could not be verified without following an alias or symbolic link.',
    'sourceMissing' => 'The selected directory no longer exists.',
    'sourceNotDirectory' => 'The selected source is not a directory.',
    'invalidRequest' || 'invalidPath' =>
      'The requested directory path could not be verified safely.',
    _ =>
      'A directory member could not be inspected completely. Refresh the preview before continuing.',
  };
}

class WorkspaceMoveTreeMember {
  const WorkspaceMoveTreeMember({
    required this.path,
    required this.kind,
    this.revision,
    this.identity,
    this.local,
    this.size,
  });
  final String path;
  final WorkspaceMoveTreeMemberKind kind;
  final String? revision;
  final String? identity;

  /// Null is unknown, not local.
  final bool? local;
  final int? size;
}

/// Read-only enumeration evidence, independent of the text catalog. `directory`
/// establishes existence; `complete` establishes enumeration, not eligibility.
class WorkspaceMoveTreeSnapshot {
  WorkspaceMoveTreeSnapshot({
    required this.root,
    required this.sourcePath,
    required this.requestId,
    required this.sourceState,
    required this.complete,
    required List<WorkspaceMoveTreeMember> members,
    required List<WorkspaceMoveTreeIssue> issues,
    required this.observedEntryCount,
    this.canonicalRoot,
    this.rootIdentity,
    this.sourceIdentity,
  }) : members = List.unmodifiable(members),
       issues = List.unmodifiable(issues);

  final String root;
  final String? canonicalRoot;
  final String sourcePath;
  final String requestId;
  final WorkspaceMoveTreeSourceState sourceState;
  final String? rootIdentity;
  final String? sourceIdentity;
  final bool complete;
  final List<WorkspaceMoveTreeMember> members;
  final List<WorkspaceMoveTreeIssue> issues;
  final int observedEntryCount;

  factory WorkspaceMoveTreeSnapshot.fromNative(Object? value) {
    Never invalid() =>
        throw const FormatException('Invalid directory tree evidence.');
    if (value is! Map || value.length > 16) invalid();
    final rawMembers = value['members'];
    final rawIssues = value['issues'];
    if (rawMembers is! List ||
        rawMembers.length > workspaceMoveTreeMaximumMembers ||
        rawIssues is! List ||
        rawIssues.length > 1024) {
      invalid();
    }
    // Check collection shapes/counts before serializing so a malformed reply
    // cannot turn an unbounded nested object into an allocation.
    if (rawMembers.any(
          (m) =>
              m is! Map ||
              m.length > 8 ||
              m.keys.any((k) => k is! String) ||
              m.values.any(
                (v) => v != null && v is! String && v is! int && v is! bool,
              ),
        ) ||
        rawIssues.any(
          (i) =>
              i is! Map ||
              i.length > 2 ||
              i.keys.any((k) => k is! String) ||
              i.values.any((v) => v != null && v is! String),
        ) ||
        value.entries.any(
          (e) =>
              e.key is! String ||
              (e.key != 'members' &&
                  e.key != 'issues' &&
                  e.value != null &&
                  e.value is! String &&
                  e.value is! int &&
                  e.value is! bool),
        )) {
      invalid();
    }
    final scalars = <Object?>[
      ...value.values.where((v) => v is! List),
      for (final m in rawMembers) ...(m as Map).values,
      for (final i in rawIssues) ...(i as Map).values,
    ];
    if (scalars.any((v) => v is String && v.length > 4096)) invalid();
    if (utf8.encode(jsonEncode(value)).length >
        workspaceMoveTreeMaximumMetadataBytes) {
      invalid();
    }
    String string(Object? v, {int maximum = 4096}) {
      if (v is! String ||
          v.isEmpty ||
          v.length > maximum ||
          !isScalarAttachmentPath(v) ||
          v.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        invalid();
      }
      return v;
    }

    String relative(Object? v) {
      final s = string(v);
      if (!isSafeAttachmentRelativePath(s, allowHidden: true) ||
          s.split('/').length > 65) {
        invalid();
      }
      return s;
    }

    // Real unsupported names are diagnostics, never execution addresses.
    // Preserve them so a PDF/hidden/invalid-name member is not called missing.
    String diagnosticPath(Object? v) {
      if (v is! String ||
          v.isEmpty ||
          v.length > 4096 ||
          !isScalarAttachmentPath(v) ||
          v.contains('\u0000') ||
          v.startsWith('/') ||
          v.split('/').length > 65 ||
          v
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..')) {
        invalid();
      }
      return v;
    }

    String absolute(Object? v) {
      final s = string(v);
      if (!p.posix.isAbsolute(s) ||
          p.posix.normalize(s) != s ||
          s.contains('\\')) {
        invalid();
      }
      return s;
    }

    String? identity(Object? v) {
      if (v == null) return null;
      final s = string(v, maximum: 128);
      if (!RegExp(r'^\d+:\d+$').hasMatch(s)) invalid();
      return s;
    }

    String? optionalString(Object? v) => v == null ? null : string(v);
    final root = absolute(value['root']);
    final source = relative(value['sourcePath']);
    final state = WorkspaceMoveTreeSourceState.values
        .where((v) => v.name == value['sourceState'])
        .firstOrNull;
    final count = value['observedEntryCount'];
    if (state == null ||
        value['complete'] is! bool ||
        count is! int ||
        count < 0 ||
        count > 0x7fffffff) {
      invalid();
    }
    final paths = <String>{};
    final members = <WorkspaceMoveTreeMember>[];
    var directories = 0;
    for (final raw in rawMembers) {
      final map = raw as Map;
      final path = diagnosticPath(map['path']);
      final kind = WorkspaceMoveTreeMemberKind.values
          .where((v) => v.name == map['kind'])
          .firstOrNull;
      if (kind == null ||
          !WorkspaceMoveNamespace.contains(source, path) ||
          !paths.add(path) ||
          (map['local'] != null && map['local'] is! bool) ||
          (map['size'] != null && (map['size'] is! int || map['size'] < 0))) {
        invalid();
      }
      if (kind == WorkspaceMoveTreeMemberKind.directory &&
          ++directories > workspaceMoveTreeMaximumDirectories) {
        invalid();
      }
      members.add(
        WorkspaceMoveTreeMember(
          path: path,
          kind: kind,
          revision: optionalString(map['revision']),
          identity: identity(map['identity']),
          local: map['local'] as bool?,
          size: map['size'] as int?,
        ),
      );
    }
    if (count < members.length ||
        (value['complete'] == true && count != members.length)) {
      invalid();
    }
    final issues = <WorkspaceMoveTreeIssue>[];
    for (final raw in rawIssues) {
      final map = raw as Map;
      final path = map['path'] == null ? null : diagnosticPath(map['path']);
      issues.add(
        WorkspaceMoveTreeIssue(string(map['code'], maximum: 128), path: path),
      );
    }
    members.sort((a, b) => a.path.compareTo(b.path));
    return WorkspaceMoveTreeSnapshot(
      root: root,
      canonicalRoot: value['canonicalRoot'] == null
          ? null
          : absolute(value['canonicalRoot']),
      sourcePath: source,
      requestId: string(value['requestId'], maximum: 128),
      sourceState: state,
      rootIdentity: identity(value['rootIdentity']),
      sourceIdentity: identity(value['sourceIdentity']),
      complete: value['complete'] as bool,
      members: members,
      issues: issues,
      observedEntryCount: count,
    );
  }
}
