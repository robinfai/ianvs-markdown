import 'dart:convert';

import 'package:path/path.dart' as p;

const attachmentExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
const attachmentMaximumBytes = 32 * 1024 * 1024;
const attachmentSettingsMaximumBytes = 64 * 1024;

enum AttachmentFailureKind {
  needsFolder,
  missing,
  ambiguous,
  denied,
  offline,
  invalid,
  unsupported,
  tooLarge,
  indexLimit,
  unavailable,
  cancelled,
}

class AttachmentFailure implements Exception {
  const AttachmentFailure(this.kind);
  final AttachmentFailureKind kind;

  String get message => switch (kind) {
    AttachmentFailureKind.needsFolder =>
      'Open the vault or folder containing this note and its images. '
          'Importing a single note does not import its attachments.',
    AttachmentFailureKind.missing => 'Image not found in the current folder.',
    AttachmentFailureKind.ambiguous =>
      'Several images match. Use the full path from the vault root.',
    AttachmentFailureKind.denied =>
      'Image access denied. Reopen the vault or folder to grant access.',
    AttachmentFailureKind.offline =>
      'This cloud image is not available offline. Download it and retry.',
    AttachmentFailureKind.invalid =>
      'Blocked image path. Images must stay inside the current vault, without symbolic links.',
    AttachmentFailureKind.unsupported =>
      'Automatic preview supports PNG, JPEG, GIF, WebP and BMP only. Remote images are not loaded.',
    AttachmentFailureKind.tooLarge => 'Image exceeds the preview memory limit.',
    AttachmentFailureKind.indexLimit =>
      'This folder is too large to index safely. Open a smaller folder.',
    AttachmentFailureKind.unavailable => 'Image could not be loaded. Retry.',
    AttachmentFailureKind.cancelled => 'Image loading cancelled.',
  };

  @override
  String toString() => message;
}

enum AttachmentFolderKind { vaultRoot, fixedFolder, noteFolder, noteSubfolder }

/// A read-only interpretation of app.json's one attachment field. This is a
/// destination preference for FUTURE imports, never a restriction on old files.
/// Raw spellings are adapter fixtures, not an Obsidian settings-file API.
class ObsidianAttachmentSettings {
  const ObsidianAttachmentSettings({this.folderPath, this.malformed = false});
  final String? folderPath;
  final bool malformed;

  factory ObsidianAttachmentSettings.parse(List<int> bytes) {
    if (bytes.length > attachmentSettingsMaximumBytes) {
      return const ObsidianAttachmentSettings(malformed: true);
    }
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map) {
        return const ObsidianAttachmentSettings(malformed: true);
      }
      final path = json['attachmentFolderPath'];
      if (path == null) return const ObsidianAttachmentSettings();
      if (path is! String || path.length > 4096) {
        return const ObsidianAttachmentSettings(malformed: true);
      }
      if (path.isNotEmpty && path != '/' && path != './') {
        final relative = path.startsWith('./') ? path.substring(2) : path;
        if (!isSafeAttachmentRelativePath(relative, allowHidden: false)) {
          return const ObsidianAttachmentSettings(malformed: true);
        }
      }
      return ObsidianAttachmentSettings(folderPath: path);
    } on Object {
      return const ObsidianAttachmentSettings(malformed: true);
    }
  }

  AttachmentFolderKind get kind {
    final path = folderPath ?? '';
    if (path.isEmpty || path == '/') return AttachmentFolderKind.vaultRoot;
    if (path == './') return AttachmentFolderKind.noteFolder;
    if (path.startsWith('./')) return AttachmentFolderKind.noteSubfolder;
    return AttachmentFolderKind.fixedFolder;
  }
}

class AttachmentMetadata {
  const AttachmentMetadata({
    required this.relativePath,
    required this.comparisonPath,
    required this.size,
    required this.modified,
    this.revision,
  });
  final String relativePath;

  /// Native NFC + lowercase, for normalization-safe unique fallback only.
  final String comparisonPath;
  final int size;
  final int modified;
  final String? revision;
  String get version => '$relativePath\u0000${revision ?? '$size:$modified'}';
}

bool isSafeAttachmentRelativePath(String path, {bool allowHidden = false}) =>
    path.isNotEmpty &&
    path.length <= 4096 &&
    !path.startsWith('/') &&
    !path.contains(RegExp(r'[\\:\x00-\x1f]')) &&
    path
        .split('/')
        .every(
          (part) =>
              part.isNotEmpty &&
              part != '.' &&
              part != '..' &&
              (allowHidden || !part.startsWith('.')),
        );

enum AttachmentLinkKind { markdown, wiki }

class AttachmentReference {
  AttachmentReference(String source, this.kind) {
    if (source.length > 4096 ||
        source.contains(RegExp(r'[\\\x00-\x1f]')) ||
        source.startsWith('//')) {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    }
    final uri = Uri.tryParse(source);
    if (uri == null || uri.hasScheme || uri.hasAuthority) {
      throw const AttachmentFailure(AttachmentFailureKind.unsupported);
    }
    // No network, file:, query-driven endpoints, or image subresources.
    if (uri.hasQuery || uri.hasFragment) {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    }
    try {
      // Decode percent sequences once without losing literal Unicode or ./.
      // Passing a mixed Unicode string directly to decodeComponent is invalid.
      // Wiki targets are literal filesystem names, not Markdown URI values.
      // In particular, ![[literal%20.png]] must not select literal space.png.
      path = kind == AttachmentLinkKind.wiki
          ? source
          : source.replaceAllMapped(
              RegExp(r'(?:%[0-9a-fA-F]{2})+'),
              (match) => Uri.decodeComponent(match[0]!),
            );
    } on ArgumentError {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    } on FormatException {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    }
    if (path.isEmpty || path.contains(RegExp(r'[\\:\x00-\x1f]'))) {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    }
    if (!attachmentExtensions.contains(p.posix.extension(path).toLowerCase())) {
      throw const AttachmentFailure(AttachmentFailureKind.unsupported);
    }
  }

  final AttachmentLinkKind kind;
  late final String path;
}

/// Pure resolver. Normalization is supplied by the platform adapter, not by
/// filesystem reads, and filenames returned here always come from the index.
class AttachmentIndex {
  AttachmentIndex(Iterable<AttachmentMetadata> entries)
    : entries = List.unmodifiable(entries) {
    if (this.entries.length > 10000 ||
        this.entries.any(
          (entry) =>
              !isSafeAttachmentRelativePath(entry.relativePath) ||
              !attachmentExtensions.contains(
                p.posix.extension(entry.relativePath).toLowerCase(),
              ) ||
              entry.size < 0,
        )) {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    }
  }

  final List<AttachmentMetadata> entries;

  AttachmentMetadata resolve({
    required AttachmentReference reference,
    required String documentRelativePath,
    required String normalizedReference,
    required String normalizedDocument,
  }) {
    if (!isSafeAttachmentRelativePath(documentRelativePath)) {
      throw const AttachmentFailure(AttachmentFailureKind.needsFolder);
    }
    final raw = reference.path;
    final explicitRelative = raw.startsWith('./') || raw.startsWith('../');
    final rooted = raw.startsWith('/');
    String normalizedJoin(String document, String link) =>
        p.posix.normalize(p.posix.join(p.posix.dirname(document), link));
    String rootPath(String link) =>
        p.posix.normalize(link.startsWith('/') ? link.substring(1) : link);

    AttachmentMetadata? exact(String candidate, String canonical) {
      if (!isSafeAttachmentRelativePath(candidate)) {
        throw const AttachmentFailure(AttachmentFailureKind.invalid);
      }
      final literal = entries.where((entry) => entry.relativePath == candidate);
      if (literal.length == 1) return literal.single;
      final matches = entries.where(
        (entry) => entry.comparisonPath == canonical,
      );
      if (matches.length > 1) {
        throw const AttachmentFailure(AttachmentFailureKind.ambiguous);
      }
      return matches.firstOrNull;
    }

    if (reference.kind == AttachmentLinkKind.markdown || explicitRelative) {
      final candidate = rooted
          ? rootPath(raw)
          : normalizedJoin(documentRelativePath, raw);
      final canonical = rooted
          ? rootPath(normalizedReference)
          : normalizedJoin(normalizedDocument, normalizedReference);
      final found = exact(candidate, canonical);
      if (found != null) return found;
      if (!rooted && !explicitRelative) {
        final fromRoot = exact(rootPath(raw), rootPath(normalizedReference));
        if (fromRoot != null) return fromRoot;
      }
    } else {
      final candidate = rootPath(raw);
      final canonical = rootPath(normalizedReference);
      if (!isSafeAttachmentRelativePath(candidate)) {
        throw const AttachmentFailure(AttachmentFailureKind.invalid);
      }
      // A full vault path disambiguates; a bare basename never prefers a file
      // merely because it happens to be at the vault root or next to the note.
      if (rooted || candidate.contains('/')) {
        final found = exact(candidate, canonical);
        if (found != null) return found;
      }
      final matches = entries.where(
        (entry) =>
            entry.comparisonPath == canonical ||
            entry.comparisonPath.endsWith('/$canonical'),
      );
      if (matches.length > 1) {
        throw const AttachmentFailure(AttachmentFailureKind.ambiguous);
      }
      if (matches.isNotEmpty) return matches.single;
    }
    throw const AttachmentFailure(AttachmentFailureKind.missing);
  }
}
