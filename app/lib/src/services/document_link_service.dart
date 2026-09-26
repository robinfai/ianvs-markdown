import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import '../controllers/workspace_controller.dart';
import '../models/document_session.dart';
import 'markdown_file_service.dart';

typedef ExternalLinkOpener = Future<void> Function(Uri uri);
typedef LocalImageOpener = Future<void> Function(String path);

/// Resolves links against the document, not the app's working directory.
class DocumentLinkService {
  DocumentLinkService({
    required this.workspace,
    required this.openImage,
    ExternalLinkOpener? openExternal,
  }) : openExternal = openExternal ?? openExternalUri;

  final WorkspaceController workspace;
  final LocalImageOpener openImage;
  final ExternalLinkOpener openExternal;

  static const imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.svg',
  };
  static const _channel = MethodChannel('work.ianvs.linefold/file_access');

  static Future<void> openExternalUri(Uri uri) async {
    await _channel.invokeMethod<void>('openExternal', {'url': uri.toString()});
  }

  Future<void> open(DocumentSession origin, String? href) async {
    if (href == null) return;
    final link = Uri.parse(href);
    if ({'http', 'https', 'mailto'}.contains(link.scheme.toLowerCase())) {
      await openExternal(link);
      return;
    }
    if (link.hasScheme && link.scheme != 'file') {
      if (href == 'app://obsidian.md/index.html') return;
      throw FormatException('Unsupported link type: ${link.scheme}');
    }
    if (link.hasAuthority && link.host.isNotEmpty && link.host != 'localhost') {
      throw const FormatException('Remote file links are not supported.');
    }
    if (link.path.isEmpty) {
      _revealFragment(origin, link.fragment);
      return;
    }
    final basePath = origin.path;
    if (basePath == null && !link.hasScheme && !p.isAbsolute(link.path)) {
      throw const FormatException(
        'Save this document before opening relative links.',
      );
    }
    final resolved = link.hasScheme
        ? link
        : Uri.file(
            basePath ?? p.join(p.current, 'Untitled.md'),
          ).resolveUri(link);
    final path = p.normalize(
      resolved.replace(query: '', fragment: '').toFilePath(),
    );
    if (isMarkdownFileName(path) || p.extension(path).toLowerCase() == '.mmd') {
      final alreadyOpen = workspace.documents.any(
        (document) => document.path == path,
      );
      final target = await workspace.openPath(path);
      if (target != null) {
        // Following a link from Reading should stay in Reading for a new tab.
        if (!alreadyOpen) target.controller.mode = origin.controller.mode;
        _revealFragment(target, resolved.fragment);
      }
    } else if (imageExtensions.contains(p.extension(path).toLowerCase())) {
      await openImage(path);
    } else if ({
      '.html',
      '.htm',
      '.pdf',
    }.contains(p.extension(path).toLowerCase())) {
      await openExternal(resolved);
    } else {
      throw const FormatException(
        'This file type cannot be opened from a document link.',
      );
    }
  }

  void _revealFragment(DocumentSession document, String fragment) {
    if (fragment.isEmpty) return;
    final counts = <String, int>{};
    for (final block in parseMarkdownBlocks(document.controller.text)) {
      if (block.type != IanvsMarkdownBlockType.heading) continue;
      final headings = parseMarkdownHeadings(block.source);
      if (headings.isEmpty) continue;
      final text = headings.first.text;
      final slug = text
          .toLowerCase()
          .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}_\-\s]', unicode: true), '')
          .replaceAll(RegExp(r'\s'), '-');
      final occurrence = counts.update(
        slug,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final uniqueSlug = occurrence == 0 ? slug : '$slug-$occurrence';
      if (fragment == text || fragment.toLowerCase() == uniqueSlug) {
        // A linked tab may not have mounted its editor when openPath completes.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (workspace.activeDocument == document) {
            document.controller.revealHeading(block.start);
          }
        });
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
    }
    throw FormatException('Heading not found: $fragment');
  }
}
