import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import 'attachment_repository.dart';
import 'attachment_resolver.dart';
import 'document_export_service.dart';

const documentExportBundleNotice =
    'Creates a ZIP with document.md, local attachments and a resource manifest. '
    'Attachment references in the copy use portable relative paths. '
    'Local files are copied without conversion. Linked notes are listed but not copied. '
    'Remote and cloud-only resources are never downloaded. '
    'Your original and unsaved edits are not changed.';

/// A portable copy. The editor buffer and original files are never changed.
class MarkdownBundle {
  const MarkdownBundle(this.bytes, this.notices);
  final Uint8List bytes;
  final List<String> notices;
}

/// Copies referenced local attachments through the scoped native reader.
/// Linked notes remain explicit entries in the manifest, without recursive export.
class MarkdownBundleService {
  const MarkdownBundleService({
    this.source = const AppleAttachmentSource(forBundle: true),
    this.maximumBytes = 32 * 1024 * 1024,
    this.maximumAttachments = 256,
  });

  final AttachmentSource source;
  final int maximumBytes;
  final int maximumAttachments;

  Future<MarkdownBundle> build(
    DocumentExportSnapshot snapshot, {
    required bool Function() isCurrent,
  }) async {
    void check() {
      if (!isCurrent()) {
        throw const DocumentExportFailure('Attachment export cancelled.');
      }
    }

    check();
    DocumentExportService(
      maximumOutputBytes: maximumBytes,
    ).buildMarkdown(snapshot, isCurrent: isCurrent);
    final semantics = parseIanvsMarkdownNoteSemantics(snapshot.source);
    if (!semantics.complete) {
      throw const DocumentExportFailure(
        'This document cannot be completely inspected for attachments.',
      );
    }
    final archive = Archive();
    // Stored ZIP entries avoid compression spikes and allow exact size bounds.
    var size = 22;
    void add(String name, Uint8List bytes) {
      size += bytes.length + 76 + utf8.encode(name).length * 2;
      if (size > maximumBytes) {
        throw const DocumentExportFailure(
          'Attachment bundle exceeds its size limit.',
        );
      }
      archive.add(
        ArchiveFile.bytes(name, bytes)..compression = CompressionType.none,
      );
    }

    final notices = <String>[];
    final resources = <Map<String, String>>[];
    final copied = <String, String>{};
    final edits = <(int, int), String>{};
    final processed = <(int, int)>{};
    AttachmentIndex? index;
    final root = snapshot.root;
    final path = snapshot.documentPath;
    final scoped =
        root != null &&
        path != null &&
        p.posix.isAbsolute(root) &&
        p.posix.isWithin(root, path);
    final document = scoped ? p.posix.relative(path, from: root) : null;
    for (final reference in semantics.references) {
      check();
      final target = reference.target;
      final range = reference.destinationRange;
      if (!processed.add((range.start, range.end)) || target.isEmpty) continue;
      final uri = Uri.tryParse(target);
      if (uri != null && (uri.hasScheme || uri.hasAuthority)) {
        resources.add({'target': target, 'status': 'external-not-copied'});
        continue;
      }
      final suffix = p.posix.extension(target).toLowerCase();
      final wiki =
          reference.kind == IanvsMarkdownSourceReferenceKind.wikiLink ||
          reference.kind == IanvsMarkdownSourceReferenceKind.wikiEmbed;
      if ({'.md', '.markdown', '.mdown', '.mkd', '.mmd'}.contains(suffix) ||
          (wiki && suffix.isEmpty)) {
        resources.add({
          'target': target,
          'status': 'local-resource-not-copied',
        });
        notices.add('Local resource not copied: $target');
        continue;
      }
      try {
        if (document == null) {
          throw const AttachmentFailure(AttachmentFailureKind.needsFolder);
        }
        // Semantic paths are already decoded. Re-encode Markdown once before
        // using the renderer's resolver; Wiki percent signs remain literal.
        final attachment = AttachmentReference(
          wiki ? target : target.split('/').map(Uri.encodeComponent).join('/'),
          wiki ? AttachmentLinkKind.wiki : AttachmentLinkKind.markdown,
          allowAnyFile: true,
        );
        if (index == null) {
          final entries = await source.list(root!);
          check();
          index = AttachmentIndex(entries, allowAnyFile: true);
        }
        final normalized = await source.normalize([attachment.path, document]);
        check();
        if (normalized.length != 2) {
          throw const AttachmentFailure(AttachmentFailureKind.invalid);
        }
        final metadata = index.resolve(
          reference: attachment,
          documentRelativePath: document,
          normalizedReference: normalized[0],
          normalizedDocument: normalized[1],
        );
        var destination = copied[metadata.relativePath];
        if (destination == null) {
          if (copied.length >= maximumAttachments) {
            throw const DocumentExportFailure(
              'Too many attachments to export.',
            );
          }
          final remaining = maximumBytes - size;
          if (metadata.size > remaining) {
            throw const DocumentExportFailure(
              'Attachment bundle exceeds its size limit.',
            );
          }
          final bytes = await source.read(
            root!,
            metadata.relativePath,
            remaining,
          );
          check();
          // Numeric names avoid cross-platform case/Unicode/name collisions.
          final extension = p.posix
              .extension(metadata.relativePath)
              .toLowerCase();
          final portableExtension =
              RegExp(r'^\.[a-z0-9]{1,16}$').hasMatch(extension)
              ? extension
              : '';
          destination = 'assets/${copied.length + 1}$portableExtension';
          add(destination, bytes);
          copied[metadata.relativePath] = destination;
        }
        edits[(range.start, range.end)] = './$destination';
        resources.add({
          'target': target,
          'status': 'copied',
          'path': destination,
        });
      } catch (error) {
        check();
        if (error is DocumentExportFailure) rethrow;
        final failure = attachmentFailure(error);
        notices.add('$target: ${failure.message}');
        resources.add({'target': target, 'status': failure.kind.name});
      }
    }
    var markdown = snapshot.source;
    final ordered = edits.keys.toList()..sort((a, b) => b.$1.compareTo(a.$1));
    var boundary = markdown.length;
    for (final range in ordered) {
      if (range.$1 < 0 || range.$2 > boundary || range.$1 > range.$2) {
        throw const DocumentExportFailure('Conflicting attachment references.');
      }
      markdown = markdown.replaceRange(range.$1, range.$2, edits[range]!);
      boundary = range.$1;
    }
    add('document.md', Uint8List.fromList(utf8.encode(markdown)));
    add(
      'manifest.json',
      Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent('  ').convert({
            'version': 1,
            'document': 'document.md',
            'originalTitle': snapshot.title,
            'resources': resources,
            'notices': notices,
          }),
        ),
      ),
    );
    check();
    final bytes = ZipEncoder().encodeBytes(archive);
    if (bytes.length > maximumBytes) {
      throw const DocumentExportFailure(
        'Attachment bundle exceeds its size limit.',
      );
    }
    check();
    return MarkdownBundle(bytes, List.unmodifiable(notices));
  }
}
