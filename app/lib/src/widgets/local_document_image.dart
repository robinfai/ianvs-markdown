import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/markdown_file_service.dart';
import 'svg_document_view.dart';

/// A user-opened local image. Reading bytes here never loads remote resources.
class LocalDocumentImage extends StatefulWidget {
  const LocalDocumentImage({
    super.key,
    required this.path,
    this.onOpenExternal,
  });
  final String path;
  final VoidCallback? onOpenExternal;

  @override
  State<LocalDocumentImage> createState() => _LocalDocumentImageState();
}

class _LocalDocumentImageState extends State<LocalDocumentImage> {
  late final _bytes = _read();

  Future<Uint8List> _read() async {
    final file = await File(widget.path).open();
    try {
      const limit = 32 * 1024 * 1024;
      if (await file.length() > limit) {
        throw const FormatException('Image exceeds the 32 MiB preview limit.');
      }
      final bytes = await file.read(limit + 1);
      if (bytes.length > limit) {
        throw const FormatException('Image is too large.');
      }
      return bytes;
    } finally {
      await file.close();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SelectableText(describeFileError(snapshot.error!));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return InteractiveViewer(
        minScale: 0.25,
        maxScale: 6,
        child: p.extension(widget.path).toLowerCase() == '.svg'
            ? SvgDocumentView(
                svg: utf8.decode(snapshot.data!),
                onOpenExternal: widget.onOpenExternal,
              )
            : Image.memory(
                snapshot.data!,
                cacheWidth: 2048,
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) =>
                    Text('Unable to decode image: $error'),
              ),
      );
    },
  );
}
