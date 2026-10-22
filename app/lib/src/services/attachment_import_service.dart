import 'dart:math';

import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import 'apple_workspace_service.dart';
import 'attachment_repository.dart';
import 'attachment_resolver.dart';

class AttachmentImportFailure implements Exception {
  const AttachmentImportFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class AttachmentImportPayload {
  const AttachmentImportPayload(this.bytes);
  final Uint8List bytes;
}

abstract class AttachmentImportPlatform {
  Future<AttachmentImportPayload?> pickImage();
  Future<AttachmentImportPayload?> readClipboardImage();
  Future<String> create({
    required String root,
    required String relativeDirectory,
    required String filename,
    required Uint8List bytes,
  });
}

/// Clipboard bytes are requested only by the caller's explicit Paste action.
/// There is no timer, startup read, polling, file-URL import or network fallback.
class AppleAttachmentImportPlatform implements AttachmentImportPlatform {
  const AppleAttachmentImportPlatform();

  Future<AttachmentImportPayload?> _read(String method) async {
    final value = await AppleWorkspaceService.channel
        .invokeMapMethod<String, dynamic>(method);
    if (value == null) return null;
    final bytes = value['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      throw const AttachmentFailure(AttachmentFailureKind.unsupported);
    }
    if (bytes.length > attachmentMaximumBytes) {
      throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
    }
    return AttachmentImportPayload(bytes);
  }

  @override
  Future<AttachmentImportPayload?> pickImage() => _read('pickAttachmentImage');
  @override
  Future<AttachmentImportPayload?> readClipboardImage() =>
      _read('readClipboardAttachmentImage');
  @override
  Future<String> create({
    required String root,
    required String relativeDirectory,
    required String filename,
    required Uint8List bytes,
  }) async {
    final result = await AppleWorkspaceService.channel
        .invokeMapMethod<String, dynamic>('createWorkspaceAttachment', {
          'path': root,
          'relativeDirectory': relativeDirectory,
          'filename': filename,
          'bytes': bytes,
        });
    final relativePath = result?['relativePath'];
    final expected = relativeDirectory.isEmpty
        ? filename
        : '$relativeDirectory/$filename';
    if (relativePath != expected) {
      throw const AttachmentImportFailure(
        'The import result could not be verified. Check the attachment folder before retrying.',
      );
    }
    return expected;
  }
}

class AttachmentImportTarget {
  AttachmentImportTarget({
    required String? root,
    required String? documentPath,
  }) {
    if (root == null ||
        documentPath == null ||
        !isScalarAttachmentPath(root) ||
        !isScalarAttachmentPath(documentPath) ||
        !p.posix.isAbsolute(root) ||
        !p.posix.isAbsolute(documentPath) ||
        !p.posix.isWithin(root, documentPath)) {
      throw const AttachmentImportFailure(
        'Save this note inside an opened workspace folder before importing an image. A separately opened file does not grant access to its parent folder.',
      );
    }
    final document = p.posix.relative(documentPath, from: root);
    if (!isSafeAttachmentRelativePath(document)) {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    }
    this.root = root;
    this.document = document;
  }
  late final String root;
  late final String document;

  String directory(ObsidianAttachmentSettings settings) {
    if (settings.malformed) {
      throw const AttachmentImportFailure(
        'The Obsidian attachment setting could not be read safely. Fix .obsidian/app.json or choose a different workspace before importing. Existing images are unchanged.',
      );
    }
    final noteDirectory = p.posix.dirname(document);
    final relative = switch (settings.kind) {
      AttachmentFolderKind.vaultRoot => '',
      AttachmentFolderKind.fixedFolder => settings.folderPath!,
      AttachmentFolderKind.noteFolder =>
        noteDirectory == '.' ? '' : noteDirectory,
      AttachmentFolderKind.noteSubfolder => p.posix.normalize(
        p.posix.join(noteDirectory, settings.folderPath!.substring(2)),
      ),
    };
    if (relative.isNotEmpty && !isSafeAttachmentRelativePath(relative)) {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    }
    return relative;
  }

  String markdown(String relativePath) {
    if (!isSafeAttachmentRelativePath(relativePath)) {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    }
    // Escape each component, including literal %, #, brackets and parentheses.
    // Explicit ./ prevents the loader's vault-root fallback changing identity.
    final relative = p.posix.relative(
      relativePath,
      from: p.posix.dirname(document),
    );
    final encoded = relative
        .split('/')
        .map(
          (part) => Uri.encodeComponent(part).replaceAllMapped(
            RegExp(r"[!'()*]"),
            (match) =>
                '%${match[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
          ),
        )
        .join('/');
    final target = relative.startsWith('../') ? encoded : './$encoded';
    return '![]($target)';
  }
}

class ImportedAttachment {
  const ImportedAttachment({
    required this.relativePath,
    required this.markdown,
  });
  final String relativePath;
  final String markdown;
}

class AttachmentImportService {
  AttachmentImportService({
    this.source = const AppleAttachmentSource(),
    this.platform = const AppleAttachmentImportPlatform(),
    String Function()? identifier,
  }) : identifier = identifier ?? _identifier;
  final AttachmentSource source;
  final AttachmentImportPlatform platform;
  final String Function() identifier;
  static final _random = Random.secure();
  static String _identifier() =>
      '${DateTime.now().toUtc().microsecondsSinceEpoch}-${List.generate(8, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  Future<ImportedAttachment> import({
    required AttachmentImportTarget target,
    required AttachmentImportPayload payload,
    required bool Function() isCurrent,
  }) async {
    void check() {
      if (!isCurrent()) {
        throw const AttachmentFailure(AttachmentFailureKind.cancelled);
      }
    }

    check();
    final validator = AttachmentRepository(root: null);
    late String extension;
    try {
      extension = await validator.validateImport(payload.bytes);
    } finally {
      validator.dispose();
    }
    check();
    ObsidianAttachmentSettings settings;
    try {
      settings = ObsidianAttachmentSettings.parse(
        await source.readImportSettings(target.root),
      );
    } on Object catch (error) {
      if (attachmentFailure(error).kind == AttachmentFailureKind.missing) {
        settings = const ObsidianAttachmentSettings();
      } else {
        throw const AttachmentImportFailure(
          'Cannot safely read the attachment folder setting. No image was imported. Reopen the workspace or make its settings available locally, then retry.',
        );
      }
    }
    check();
    final directory = target.directory(settings);
    for (var attempt = 0; attempt < 8; attempt++) {
      check();
      final filename = 'image-${identifier()}.$extension';
      if (!isSafeAttachmentRelativePath(filename) || filename.contains('/')) {
        throw const AttachmentFailure(AttachmentFailureKind.invalid);
      }
      try {
        final path = await platform.create(
          root: target.root,
          relativeDirectory: directory,
          filename: filename,
          bytes: payload.bytes,
        );
        // Do not delete a successful write just because the document changed.
        // The caller reports this exact path and lets the user recover the link.
        return ImportedAttachment(
          relativePath: path,
          markdown: target.markdown(path),
        );
      } on PlatformException catch (error) {
        if (error.code != 'attachment_collision') rethrow;
      }
    }
    throw const AttachmentImportFailure(
      'Unable to choose a new attachment name. Existing files were not overwritten.',
    );
  }
}

/// A single history group with a captured exact source/selection/mode boundary.
/// Keep a separate host generation token to invalidate switch-away-and-back.
class AttachmentInsertion {
  AttachmentInsertion._(this.value, this.mode);
  final TextEditingValue value;
  final IanvsMarkdownEditorMode mode;
  static AttachmentInsertion? capture(IanvsMarkdownController controller) {
    final value = controller.value;
    if (controller.mode == IanvsMarkdownEditorMode.preview ||
        (value.composing.isValid && !value.composing.isCollapsed) ||
        !value.selection.isValid ||
        value.selection.end > value.text.length ||
        !_scalarBoundary(value.text, value.selection.start) ||
        !_scalarBoundary(value.text, value.selection.end)) {
      return null;
    }
    return AttachmentInsertion._(value, controller.mode);
  }

  bool current(IanvsMarkdownController controller) =>
      controller.mode == mode && controller.value == value;
  bool apply(IanvsMarkdownController controller, String markdown) {
    if (!current(controller)) return false;
    controller.commitHistoryGroup();
    controller.value = TextEditingValue(
      text: value.text.replaceRange(
        value.selection.start,
        value.selection.end,
        markdown,
      ),
      selection: TextSelection.collapsed(
        offset: value.selection.start + markdown.length,
      ),
    );
    controller.commitHistoryGroup();
    return true;
  }
}

bool _scalarBoundary(String text, int offset) =>
    offset <= 0 ||
    offset >= text.length ||
    !(text.codeUnitAt(offset - 1) >= 0xd800 &&
        text.codeUnitAt(offset - 1) <= 0xdbff &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff);
