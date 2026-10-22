import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/services/attachment_import_service.dart';
import 'package:linefold/src/services/attachment_repository.dart';
import 'package:linefold/src/services/attachment_resolver.dart';

import 'attachment_test_support.dart';

class ImportSource extends FakeAttachmentSource {
  Object? settingsError;
  @override
  Future<Uint8List> read(String root, String path, int maximumBytes) {
    if (path == '.obsidian/app.json' && settingsError != null) {
      return Future.error(settingsError!);
    }
    return super.read(root, path, maximumBytes);
  }
}

class FakeImportPlatform implements AttachmentImportPlatform {
  AttachmentImportPayload? payload = AttachmentImportPayload(tinyPng);
  int picks = 0;
  int clipboardReads = 0;
  int attempts = 0;
  int collisions = 0;
  Object? writeError;
  Future<void>? beforeRead;
  Future<void>? beforeWrite;
  final files = <String, Uint8List>{};
  final roots = <String>[];
  void Function(String, Uint8List)? onCreate;
  @override
  Future<AttachmentImportPayload?> pickImage() async {
    picks++;
    await beforeRead;
    return payload;
  }

  @override
  Future<AttachmentImportPayload?> readClipboardImage() async {
    clipboardReads++;
    await beforeRead;
    return payload;
  }

  @override
  Future<String> create({
    required String root,
    required String relativeDirectory,
    required String filename,
    required Uint8List bytes,
  }) async {
    attempts++;
    roots.add(root);
    await beforeWrite;
    if (writeError != null) throw writeError!;
    if (collisions-- > 0) throw PlatformException(code: 'attachment_collision');
    final path = relativeDirectory.isEmpty
        ? filename
        : '$relativeDirectory/$filename';
    if (files.containsKey(path)) {
      throw PlatformException(code: 'attachment_collision');
    }
    files[path] = Uint8List.fromList(bytes);
    onCreate?.call(path, files[path]!);
    return path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final target = AttachmentImportTarget(
    root: '/vault',
    documentPath: '/vault/notes/Note.md',
  );
  for (final entry in {
    '/': '',
    '': '',
    './': 'notes',
    'assets/资料': 'assets/资料',
    './附件': 'notes/附件',
    './🧪': 'notes/🧪',
  }.entries) {
    test('four raw settings map ${entry.key} to ${entry.value}', () {
      final setting = ObsidianAttachmentSettings.parse(
        utf8.encode(jsonEncode({'attachmentFolderPath': entry.key})),
      );
      expect(target.directory(setting), entry.value);
    });
  }
  test(
    'missing setting defaults to vault root; malformed never chooses a different location',
    () {
      expect(target.directory(const ObsidianAttachmentSettings()), '');
      for (final raw in [
        '../escape',
        '/absolute',
        './a/../b',
        '.secret',
        './.secret',
        'a\\b',
        'https://x',
        'a//b',
      ]) {
        final setting = ObsidianAttachmentSettings.parse(
          utf8.encode(jsonEncode({'attachmentFolderPath': raw})),
        );
        expect(
          () => target.directory(setting),
          throwsA(isA<AttachmentImportFailure>()),
        );
      }
    },
  );
  test('root note attachment subfolder is canonical, not dot-prefixed', () {
    expect(
      AttachmentImportTarget(
        root: '/vault',
        documentPath: '/vault/Note.md',
      ).directory(const ObsidianAttachmentSettings(folderPath: './附件')),
      '附件',
    );
  });
  test('unsaved and individually opened notes do not infer a parent grant', () {
    for (final pair in [
      (null, '/vault/Note.md'),
      ('/vault', null),
      ('/vault', '/other/Note.md'),
      ('/vault', '/vault/../other/Note.md'),
    ]) {
      expect(
        () => AttachmentImportTarget(root: pair.$1, documentPath: pair.$2),
        throwsA(isA<Exception>()),
      );
    }
  });
  test(
    'relative Markdown escapes Unicode URL delimiters and literal percent once',
    () {
      final markdown = target.markdown('附件/图 #%(一)[x].png');
      expect(
        markdown,
        '![](../%E9%99%84%E4%BB%B6/%E5%9B%BE%20%23%25%28%E4%B8%80%29%5Bx%5D.png)',
      );
      // Parentheses must also be encoded: CommonMark would otherwise close the link.
      final same = target.markdown('notes/image.png');
      expect(same, '![](./image.png)');
    },
  );

  testWidgets(
    'import validates and writes byte-identical image; collision never overwrites',
    (tester) async {
      final source = ImportSource()
        ..settings = Uint8List.fromList(
          utf8.encode('{"attachmentFolderPath":"./附件"}'),
        );
      final native = FakeImportPlatform()..collisions = 1;
      var serial = 0;
      final service = AttachmentImportService(
        source: source,
        platform: native,
        identifier: () => '${++serial}',
      );
      final original = Uint8List.fromList(tinyPng);
      final result = await tester.runAsync(
        () => service.import(
          target: target,
          payload: AttachmentImportPayload(tinyPng),
          isCurrent: () => true,
        ),
      );
      expect(result!.relativePath, 'notes/附件/image-2.png');
      expect(result.markdown, '![](./%E9%99%84%E4%BB%B6/image-2.png)');
      expect(native.files.values.single, original);
      expect(tinyPng, original);
      expect(source.reads, ['.obsidian/app.json']);
      expect(source.listCalls, 0);
      source.files.addAll(native.files);
      await tester.runAsync(() async {
        final repository = AttachmentRepository(root: '/vault', source: source);
        final lease = await repository.load(
          documentPath: '/vault/notes/Note.md',
          target: './%E9%99%84%E4%BB%B6/image-2.png',
          kind: AttachmentLinkKind.markdown,
        );
        expect(lease.image.width, 1);
        expect(lease.image.height, 1);
        final rgba = await lease.image.toByteData();
        expect(rgba!.buffer.asUint8List(), [255, 0, 0, 255]);
        lease.dispose();
        repository.dispose();
      });
    },
  );

  testWidgets(
    'bad settings and read-only destination never insert or fallback location',
    (tester) async {
      for (final settings in [
        Uint8List.fromList(utf8.encode('{broken')),
        Uint8List.fromList(utf8.encode('{"attachmentFolderPath":"../escape"}')),
      ]) {
        final native = FakeImportPlatform();
        final service = AttachmentImportService(
          source: ImportSource()..settings = settings,
          platform: native,
        );
        await tester.runAsync(
          () => expectLater(
            service.import(
              target: target,
              payload: AttachmentImportPayload(tinyPng),
              isCurrent: () => true,
            ),
            throwsA(isA<AttachmentImportFailure>()),
          ),
        );
        expect(native.attempts, 0);
      }
      final native = FakeImportPlatform()
        ..writeError = PlatformException(code: 'attachment_denied');
      await tester.runAsync(
        () => expectLater(
          AttachmentImportService(
            source: ImportSource(),
            platform: native,
          ).import(
            target: target,
            payload: AttachmentImportPayload(tinyPng),
            isCurrent: () => true,
          ),
          throwsA(isA<PlatformException>()),
        ),
      );
      expect(native.files, isEmpty);
    },
  );
  testWidgets('inaccessible config fails closed; absent config defaults root', (
    tester,
  ) async {
    for (final kind in [
      AttachmentFailureKind.denied,
      AttachmentFailureKind.offline,
      AttachmentFailureKind.invalid,
      AttachmentFailureKind.unavailable,
      AttachmentFailureKind.tooLarge,
    ]) {
      final native = FakeImportPlatform();
      await tester.runAsync(
        () => expectLater(
          AttachmentImportService(
            source: ImportSource()..settingsError = AttachmentFailure(kind),
            platform: native,
          ).import(
            target: target,
            payload: AttachmentImportPayload(tinyPng),
            isCurrent: () => true,
          ),
          throwsA(isA<AttachmentImportFailure>()),
        ),
      );
      expect(native.files, isEmpty);
    }
    final native = FakeImportPlatform();
    final result = await tester.runAsync(
      () =>
          AttachmentImportService(
            source: ImportSource()
              ..settingsError = const AttachmentFailure(
                AttachmentFailureKind.missing,
              ),
            platform: native,
            identifier: () => 'x',
          ).import(
            target: target,
            payload: AttachmentImportPayload(tinyPng),
            isCurrent: () => true,
          ),
    );
    expect(result!.relativePath, 'image-x.png');
  });
  testWidgets(
    'actual signature and decoder reject unsupported and corrupt before write',
    (tester) async {
      for (final bytes in [
        Uint8List.fromList(utf8.encode('<svg/>')),
        Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        Uint8List(attachmentMaximumBytes + 1),
      ]) {
        final native = FakeImportPlatform();
        await tester.runAsync(
          () => expectLater(
            AttachmentImportService(
              source: ImportSource(),
              platform: native,
            ).import(
              target: target,
              payload: AttachmentImportPayload(bytes),
              isCurrent: () => true,
            ),
            throwsA(isA<Object>()),
          ),
        );
        expect(native.files, isEmpty);
      }
    },
  );
  testWidgets(
    'cancel before write prevents write, cancellation during successful write retains file',
    (tester) async {
      final native = FakeImportPlatform();
      var current = false;
      final service = AttachmentImportService(
        source: ImportSource(),
        platform: native,
      );
      await tester.runAsync(
        () => expectLater(
          service.import(
            target: target,
            payload: AttachmentImportPayload(tinyPng),
            isCurrent: () => current,
          ),
          throwsA(isA<AttachmentFailure>()),
        ),
      );
      expect(native.attempts, 0);
      current = true;
      final operation = tester.runAsync(() async {
        final gate = Completer<void>();
        native.beforeWrite = gate.future;
        final pending = service.import(
          target: target,
          payload: AttachmentImportPayload(tinyPng),
          isCurrent: () => current,
        );
        while (native.attempts == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        current = false;
        gate.complete();
        return pending;
      });
      expect((await operation)!.markdown, startsWith('![]('));
      expect(native.files, hasLength(1));
    },
  );
  test(
    'insertion keeps surrounding source and one undo; composition/selection/mode guarded',
    () {
      final controller = IanvsMarkdownController(
        text: 'before SELECT after',
        mode: IanvsMarkdownEditorMode.source,
      );
      controller.selection = const TextSelection(
        baseOffset: 7,
        extentOffset: 13,
      );
      final edit = AttachmentInsertion.capture(controller)!;
      expect(edit.apply(controller, '![](./image.png)'), isTrue);
      expect(controller.text, 'before ![](./image.png) after');
      controller.undo();
      expect(controller.text, 'before SELECT after');
      final stale = AttachmentInsertion.capture(controller)!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      expect(stale.apply(controller, 'wrong'), isFalse);
      controller.value = const TextEditingValue(
        text: 'x',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      );
      expect(AttachmentInsertion.capture(controller), isNull);
      controller.value = const TextEditingValue(
        text: '😀',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(AttachmentInsertion.capture(controller), isNull);
      controller.mode = IanvsMarkdownEditorMode.preview;
      expect(AttachmentInsertion.capture(controller), isNull);
      controller.dispose();
    },
  );
  test(
    'native bridge uses typed bytes only and verifies returned destination',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppleWorkspaceService.channel, (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'createWorkspaceAttachment') {
              return {'relativePath': 'assets/image.png'};
            }
            return {'bytes': tinyPng};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AppleWorkspaceService.channel, null),
      );
      const platform = AppleAttachmentImportPlatform();
      expect((await platform.pickImage())!.bytes, tinyPng);
      expect((await platform.readClipboardImage())!.bytes, tinyPng);
      expect(
        await platform.create(
          root: '/vault',
          relativeDirectory: 'assets',
          filename: 'image.png',
          bytes: tinyPng,
        ),
        'assets/image.png',
      );
      expect(calls.map((c) => c.method), [
        'pickAttachmentImage',
        'readClipboardAttachmentImage',
        'createWorkspaceAttachment',
      ]);
      expect(calls.last.arguments['bytes'], isA<Uint8List>());
    },
  );
  testWidgets(
    'null and unpaired Unicode folder settings fail closed before any write',
    (tester) async {
      for (final value in [
        null,
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ]) {
        final source = ImportSource()
          ..settings = Uint8List.fromList(
            utf8.encode(jsonEncode({'attachmentFolderPath': value})),
          );
        final native = FakeImportPlatform();
        await tester.runAsync(
          () => expectLater(
            AttachmentImportService(source: source, platform: native).import(
              target: target,
              payload: AttachmentImportPayload(tinyPng),
              isCurrent: () => true,
            ),
            throwsA(isA<AttachmentImportFailure>()),
          ),
        );
        expect(native.attempts, 0);
      }
    },
  );
  test(
    'root and note paths reject unpaired Unicode without UTF-8 replacement',
    () {
      for (final invalid in [
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ]) {
        expect(
          () => AttachmentImportTarget(
            root: '/vault$invalid',
            documentPath: '/vault$invalid/note.md',
          ),
          throwsA(isA<AttachmentImportFailure>()),
        );
        expect(
          () => AttachmentImportTarget(
            root: '/vault',
            documentPath: '/vault/note$invalid.md',
          ),
          throwsA(isA<AttachmentImportFailure>()),
        );
      }
    },
  );
  test('import settings use the dedicated local-only native read', () async {
    final calls = <MethodCall>[];
    final bytes = Uint8List.fromList(utf8.encode('{}'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleWorkspaceService.channel, (call) async {
          calls.add(call);
          return bytes;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppleWorkspaceService.channel, null),
    );
    expect(
      await const AppleAttachmentSource().readImportSettings('/vault'),
      bytes,
    );
    expect(calls.single.method, 'readAttachmentImportSettings');
    expect(calls.single.arguments, {'path': '/vault'});
  });
}
