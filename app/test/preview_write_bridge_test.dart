import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/services/markdown_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late PreviewLibrary library;
  setUp(() {
    calls.clear();
    library = PreviewLibrary(workspaceService: const AppleWorkspaceService())
      ..workspace = const PreviewWorkspace(
        path: '/vault',
        name: 'vault',
        isCloud: false,
        workspaceToken: 'epoch-a',
      );
    messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(
    () =>
        messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, null),
  );

  test(
    'save transfers exact source bytes root-relative token and expected baseline',
    () async {
      const baseline = '\ufeffa\r\n😀';
      const edited = '\ufeffa\r\n😀\r\n- [x] yes';
      await library.writeSource(
        '/vault/nested/note.md',
        edited,
        expectedContents: baseline,
        generation: library.workspaceGeneration,
      );
      final call = calls.single;
      expect(call.method, 'writeWorkspaceNoteGuarded');
      expect(call.arguments['path'], '/vault');
      expect(call.arguments['workspaceToken'], 'epoch-a');
      expect(call.arguments['relativePath'], 'nested/note.md');
      expect(call.arguments['contentsBytes'], utf8.encode(edited));
      expect(call.arguments['expectedContentsBytes'], utf8.encode(baseline));
    },
  );

  test(
    'create is native exclusive root-relative with token, no write fallback',
    () async {
      expect(
        await library.createNote(
          'note.md',
          generation: library.workspaceGeneration,
        ),
        '/vault/note.md',
      );
      expect(calls.single.method, 'createWorkspaceNote');
      expect(calls.single.arguments, {
        'path': '/vault',
        'relativePath': 'note.md',
        'workspaceToken': 'epoch-a',
      });
    },
  );

  test(
    'outside root hidden traversal stale scope and oversize fail before native mutation',
    () async {
      final generation = library.workspaceGeneration;
      for (final path in [
        '/outside.md',
        '/vault/../outside.md',
        '/vault/.private/note.md',
      ]) {
        await expectLater(
          library.writeSource(
            path,
            'a',
            expectedContents: '',
            generation: generation,
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        library.createNote('../outside.md', generation: generation),
        throwsFormatException,
      );
      await expectLater(
        library.writeSource(
          '/vault/note.md',
          'x' * (previewMaximumBytes + 1),
          expectedContents: '',
          generation: generation,
        ),
        throwsFormatException,
      );
      library.workspace = library.workspace;
      await expectLater(
        library.writeSource(
          '/vault/note.md',
          'a',
          expectedContents: '',
          generation: generation,
        ),
        throwsFormatException,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'native conflict preserves typed BOM current bytes and verifies exact target',
    () async {
      messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'workspace_save_conflict',
          details: {
            'path': '/vault/note.md',
            'currentContentsBytes': Uint8List.fromList(
              utf8.encode('\ufeffother\r\n'),
            ),
          },
        );
      });
      await expectLater(
        library.writeSource(
          '/vault/note.md',
          'a',
          expectedContents: 'base',
          generation: library.workspaceGeneration,
        ),
        throwsA(
          isA<MarkdownSaveConflict>().having(
            (e) => e.currentContents,
            'BOM baseline',
            '\ufeffother\r\n',
          ),
        ),
      );
      for (final details in [
        {'path': '/other.md', 'currentContentsBytes': null},
        {'path': '/vault/note.md'},
        {'path': '/vault/note.md', 'currentContentsBytes': 'string not bytes'},
      ]) {
        messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
          _,
        ) async {
          throw PlatformException(
            code: 'workspace_save_conflict',
            details: details,
          );
        });
        await expectLater(
          library.writeSource(
            '/vault/note.md',
            'a',
            expectedContents: 'base',
            generation: library.workspaceGeneration,
          ),
          throwsA(isA<PlatformException>()),
        );
      }
    },
  );

  test(
    'missing or false native success is not reported as a confirmed write',
    () async {
      for (final result in [null, false]) {
        messenger.setMockMethodCallHandler(
          AppleWorkspaceService.channel,
          (_) async => result,
        );
        await expectLater(
          library.writeSource(
            '/vault/note.md',
            '',
            expectedContents: '',
            generation: library.workspaceGeneration,
          ),
          throwsStateError,
        );
        await expectLater(
          library.createNote('new.md', generation: library.workspaceGeneration),
          throwsStateError,
        );
      }
    },
  );

  test(
    'readSource retains source BOM while reader strips presentation BOM',
    () async {
      final root = await Directory.systemTemp.createTemp('preview-raw-');
      addTearDown(() => root.delete(recursive: true));
      final imports = await Directory('${root.path}/Imports').create();
      final file = await File(
        '${imports.path}/note.md',
      ).writeAsBytes(utf8.encode('\ufeff# 原文\r\n😀'));
      final local = PreviewLibrary(documentsDirectory: () async => root);
      expect(await local.readSource(file.path), '\ufeff# 原文\r\n😀');
      expect(await local.read(file.path), '# 原文\r\n😀');
    },
  );
}
