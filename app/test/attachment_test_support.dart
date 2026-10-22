import 'dart:convert';
import 'dart:typed_data';

import 'package:linefold/src/services/attachment_repository.dart';
import 'package:linefold/src/services/attachment_resolver.dart';

final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

class FakeAttachmentSource implements AttachmentSource {
  final files = <String, Uint8List>{'assets/image.png': tinyPng};
  final reads = <String>[];
  final roots = <String>[];
  int listCalls = 0;
  int revision = 1;
  Object? listError;
  Object? imageError;
  Future<void>? beforeList;
  Future<void>? beforeRead;
  Uint8List settings = Uint8List.fromList(
    utf8.encode('{"attachmentFolderPath":"elsewhere"}'),
  );

  @override
  Future<List<AttachmentMetadata>> list(String root) async {
    ++listCalls;
    roots.add(root);
    await beforeList;
    if (listError != null) throw listError!;
    return [
      for (final file in files.entries)
        AttachmentMetadata(
          relativePath: file.key,
          comparisonPath: file.key.replaceAll('e\u0301', 'é').toLowerCase(),
          size: file.value.length,
          modified: revision,
        ),
    ];
  }

  @override
  Future<List<String>> normalize(List<String> paths) async => [
    for (final path in paths) path.replaceAll('e\u0301', 'é').toLowerCase(),
  ];
  @override
  Future<Uint8List> read(
    String root,
    String relativePath,
    int maximumBytes,
  ) async {
    reads.add(relativePath);
    if (relativePath == '.obsidian/app.json') return settings;
    await beforeRead;
    if (imageError != null) throw imageError!;
    final bytes = files[relativePath];
    if (bytes == null) {
      throw const AttachmentFailure(AttachmentFailureKind.missing);
    }
    return bytes;
  }
}
