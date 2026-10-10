import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_library.dart';

void main() {
  late Directory root;
  late PreviewLibrary library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('linefold-preview-');
    library = PreviewLibrary(documentsDirectory: () async => root);
  });
  tearDown(() => root.delete(recursive: true));

  Future<File> document(String path, String text) async {
    final file = File('${root.path}/Imports/$path');
    await file.parent.create(recursive: true);
    return file.writeAsString(text);
  }

  test(
    'imports survive restart, retain duplicate names and accept UTF-8 BOM',
    () async {
      final first = await document('one/文档.MD', '\uFEFF# 第一篇');
      await document('two/文档.MD', '# 第二篇');
      await document('two/ignore.pdf', 'ignored');
      expect(await library.read(first.path), '# 第一篇');
      final reopened = PreviewLibrary(documentsDirectory: () async => root);
      final entries = await reopened.list();
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.name), everyElement('文档.MD'));
      expect(
        entries.first.path,
        first.path,
        reason: entries
            .map((e) => '${e.path}: ${e.openedAt.toIso8601String()}')
            .join('\n'),
      );
    },
  );

  test(
    'rejects invalid encoding, oversized files, and paths outside imports',
    () async {
      final file = await document('one/bad.md', '');
      await file.writeAsBytes([0xff, 0xff]);
      await expectLater(library.read(file.path), throwsFormatException);
      await file.writeAsBytes(List.filled(previewMaximumBytes + 1, 65));
      await expectLater(library.read(file.path), throwsFormatException);
      final outside = await File(
        '${root.path}/outside.md',
      ).writeAsString('# Outside');
      await expectLater(library.read(outside.path), throwsFormatException);
      final link = await Link(
        '${root.path}/Imports/link.md',
      ).create(outside.path);
      await expectLater(library.read(link.path), throwsFormatException);
      expect(
        (await library.list()).map((e) => e.path),
        isNot(contains(link.path)),
      );
    },
  );

  test(
    'one broken delivery does not prevent later files, and errors remain visible',
    () async {
      final file = await document('good/note.md', '# Shared');
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.receive(['${root.path}/missing.md', file.path]);
      expect(controller.contents, '# Shared');
      expect(controller.error, contains('missing.md'));
      expect(controller.busy, isFalse);
    },
  );

  test(
    'a slower earlier open cannot replace a later document or return from library',
    () async {
      final slow = _DelayedLibrary();
      final controller = PreviewController(library: slow);
      addTearDown(controller.dispose);
      final oldOpen = controller.open('/old.md');
      await controller.open('/new.md');
      slow.old.complete('# Old');
      await oldOpen;
      expect(controller.contents, '# New');
      final pending = controller.open('/pending.md');
      controller.showLibrary();
      slow.pending.complete('# Pending');
      await pending;
      expect(controller.contents, isNull);
      expect(controller.busy, isFalse);
    },
  );
}

class _DelayedLibrary extends PreviewLibrary {
  final old = Completer<String>();
  final pending = Completer<String>();

  @override
  Future<String> read(String path) => switch (path) {
    '/old.md' => old.future,
    '/pending.md' => pending.future,
    _ => Future.value('# New'),
  };

  @override
  Future<List<PreviewDocument>> list() async => [];
}
