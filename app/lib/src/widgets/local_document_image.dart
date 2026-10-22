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
  late var _image = _read();

  @override
  void didUpdateWidget(covariant LocalDocumentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _image = _read();
  }

  Future<({Uint8List bytes, String? svg})> _read() async {
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
      // Decode inside the future so malformed text uses the same recoverable
      // error surface as missing or oversized files, instead of failing build.
      return (
        bytes: bytes,
        svg: p.extension(widget.path).toLowerCase() == '.svg'
            ? utf8.decode(bytes)
            : null,
      );
    } finally {
      await file.close();
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({Uint8List bytes, String? svg})>(
        key: ValueKey(widget.path),
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SelectableText(describeFileError(snapshot.error!));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final image = snapshot.requireData;
          return InteractiveViewer(
            minScale: 0.25,
            maxScale: 6,
            child: image.svg != null
                ? SvgDocumentView(
                    svg: image.svg!,
                    onOpenExternal: widget.onOpenExternal,
                  )
                : Image.memory(
                    image.bytes,
                    cacheWidth: 2048,
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, stack) =>
                        Text('Unable to decode image: $error'),
                  ),
          );
        },
      );
}
