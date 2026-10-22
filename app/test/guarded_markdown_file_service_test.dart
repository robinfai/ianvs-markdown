import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('guarded local saves', () {
    const service = DesktopMarkdownFileService();
    late Directory root;
    late File target;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('linefold-guarded-save-');
      target = File(p.join(root.path, '设计.md'));
    });
    tearDown(() async => root.delete(recursive: true));

    Future<void> expectNoStaging() async {
      final entries = await root.list().toList();
      expect(entries.where((entry) => entry.path != target.path), isEmpty);
    }

    Matcher conflict(String? expected, String? current) =>
        isA<MarkdownSaveConflict>()
            .having((error) => error.path, 'path', target.path)
            .having((error) => error.expectedContents, 'expected', expected)
            .having((error) => error.currentContents, 'current', current);

    test(
      'creates absent files and replaces the exact matching baseline',
      () async {
        await service.writeMarkdownFileGuarded(
          target.path,
          '# First\r\n中文 😀',
          expectedContents: null,
        );
        expect(await target.readAsString(), '# First\r\n中文 😀');
        await service.writeMarkdownFileGuarded(
          target.path,
          '# Next',
          expectedContents: '# First\r\n中文 😀',
        );
        expect(await target.readAsString(), '# Next');
        await expectNoStaging();
      },
    );

    test('changed and newly created destinations stay untouched', () async {
      await target.writeAsString('external');
      for (final expected in <String?>['baseline', null]) {
        await expectLater(
          service.writeMarkdownFileGuarded(
            target.path,
            'mine',
            expectedContents: expected,
          ),
          throwsA(conflict(expected, 'external')),
        );
        expect(await target.readAsString(), 'external');
        await expectNoStaging();
      }
    });

    test('missing and empty destinations are different baselines', () async {
      await expectLater(
        service.writeMarkdownFileGuarded(
          target.path,
          'mine',
          expectedContents: '',
        ),
        throwsA(conflict('', null)),
      );
      expect(await target.exists(), isFalse);
      await target.writeAsString('');
      await expectLater(
        service.writeMarkdownFileGuarded(
          target.path,
          'mine',
          expectedContents: null,
        ),
        throwsA(conflict(null, '')),
      );
      expect(await target.readAsString(), '');
      await expectNoStaging();
    });

    test('deleted destinations conflict rather than being recreated', () async {
      await target.writeAsString('baseline');
      await target.delete();
      await expectLater(
        service.writeMarkdownFileGuarded(
          target.path,
          'mine',
          expectedContents: 'baseline',
        ),
        throwsA(conflict('baseline', null)),
      );
      expect(await target.exists(), isFalse);
      await expectNoStaging();
    });

    test('BOM, Unicode normalization and line endings remain exact', () async {
      const source = '\ufeff# Café\r\n中文 😀';
      await target.writeAsBytes(utf8.encode(source));
      expect((await service.readMarkdownFile(target.path)).contents, source);
      for (final expected in [
        source.substring(1),
        source.replaceAll('é', 'e\u0301'),
        source.replaceAll('\r\n', '\n'),
      ]) {
        await expectLater(
          service.writeMarkdownFileGuarded(
            target.path,
            'mine',
            expectedContents: expected,
          ),
          throwsA(conflict(expected, source)),
        );
      }
      await service.writeMarkdownFileGuarded(
        target.path,
        '$source\r\nAdded',
        expectedContents: source,
      );
      expect(await target.readAsBytes(), utf8.encode('$source\r\nAdded'));
      await expectNoStaging();
    });

    test('invalid UTF-8 fails closed and leaves all bytes intact', () async {
      const bytes = [0x23, 0xff, 0xfe];
      await target.writeAsBytes(bytes);
      await expectLater(
        service.writeMarkdownFileGuarded(
          target.path,
          'mine',
          expectedContents: null,
        ),
        throwsFormatException,
      );
      expect(await target.readAsBytes(), bytes);
      await expectNoStaging();
    });

    test(
      'directories and dangling symlinks are not absent files',
      () async {
        await Directory(target.path).create();
        await expectLater(
          service.writeMarkdownFileGuarded(
            target.path,
            'mine',
            expectedContents: null,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await Directory(target.path).exists(), isTrue);
        await Directory(target.path).delete();
        await Link(target.path).create(p.join(root.path, 'missing.md'));
        await expectLater(
          service.writeMarkdownFileGuarded(
            target.path,
            'mine',
            expectedContents: null,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await Link(target.path).exists(), isTrue);
        await expectNoStaging();
      },
      skip: Platform.isWindows
          ? 'Creating links needs Windows privileges.'
          : false,
    );

    test(
      'existing symlinks are not replaced or written through',
      () async {
        final linked = File(p.join(root.path, 'linked.md'));
        await linked.writeAsString('linked baseline');
        await Link(target.path).create(linked.path);
        await expectLater(
          service.writeMarkdownFileGuarded(
            target.path,
            'mine',
            expectedContents: 'linked baseline',
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await Link(target.path).exists(), isTrue);
        expect(await linked.readAsString(), 'linked baseline');
        await linked.delete();
        await expectNoStaging();
      },
      skip: Platform.isWindows
          ? 'Creating links needs Windows privileges.'
          : false,
    );

    test(
      'rechecks absent destinations after staging before creating',
      () async {
        final overrides = _SaveIOOverrides(
          afterStage: () async => target.writeAsString('new external file'),
        );
        await expectLater(
          IOOverrides.runWithIOOverrides(
            () => service.writeMarkdownFileGuarded(
              target.path,
              'mine',
              expectedContents: null,
            ),
            overrides,
          ),
          throwsA(conflict(null, 'new external file')),
        );
        expect(await target.readAsString(), 'new external file');
        await expectNoStaging();
      },
    );

    test('checks again after staging, including approved overwrites', () async {
      await target.writeAsString('baseline');
      for (final expected in ['baseline', 'external 1']) {
        final external = expected == 'baseline' ? 'external 1' : 'external 2';
        final overrides = _SaveIOOverrides(
          afterStage: () async => target.writeAsString(external),
        );
        await expectLater(
          IOOverrides.runWithIOOverrides(
            () => service.writeMarkdownFileGuarded(
              target.path,
              'mine',
              expectedContents: expected,
            ),
            overrides,
          ),
          throwsA(conflict(expected, external)),
        );
        expect(await target.readAsString(), external);
        expect(overrides.flushed, isTrue);
        await expectNoStaging();
      }
    });

    test('read failures are errors, never deletion conflicts', () async {
      await target.writeAsString('baseline');
      for (final error in [
        FileSystemException('Denied', target.path, const OSError('Denied', 13)),
        FileSystemException('Unknown read failure', target.path),
      ]) {
        final overrides = _SaveIOOverrides(
          targetPath: target.path,
          readError: error,
        );
        await expectLater(
          IOOverrides.runWithIOOverrides(
            () => service.writeMarkdownFileGuarded(
              target.path,
              'mine',
              expectedContents: 'baseline',
            ),
            overrides,
          ),
          throwsA(same(error)),
        );
        expect(await target.readAsString(), 'baseline');
        await expectNoStaging();
      }
    });

    test(
      'partial staging failures preserve the original and clean up',
      () async {
        await target.writeAsString('baseline');
        final error = FileSystemException('Out of space', target.path);
        await expectLater(
          IOOverrides.runWithIOOverrides(
            () => service.writeMarkdownFileGuarded(
              target.path,
              'mine',
              expectedContents: 'baseline',
            ),
            _SaveIOOverrides(stageError: error),
          ),
          throwsA(same(error)),
        );
        expect(await target.readAsString(), 'baseline');
        await expectNoStaging();
      },
    );

    test('rename failures never fall back to truncating the target', () async {
      await target.writeAsString('baseline');
      for (final guarded in [false, true]) {
        final error = FileSystemException('Rename rejected', target.path);
        await expectLater(
          IOOverrides.runWithIOOverrides(
            () => guarded
                ? service.writeMarkdownFileGuarded(
                    target.path,
                    'mine',
                    expectedContents: 'baseline',
                  )
                : service.writeMarkdownFileAtomic(target.path, 'mine'),
            _SaveIOOverrides(renameError: error),
          ),
          throwsA(same(error)),
        );
        expect(await target.readAsString(), 'baseline');
        await expectNoStaging();
      }
    });
  });

  group('guarded Apple channel saves', () {
    const workspace = AppleWorkspaceService();
    const service = DesktopMarkdownFileService(workspace: workspace);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
    });
    tearDown(
      () => messenger.setMockMethodCallHandler(
        AppleWorkspaceService.channel,
        null,
      ),
    );

    test(
      'legacy payload stays unchanged and guarded baselines are explicit',
      () async {
        await service.writeMarkdownFileAtomic('/notes/a.md', 'legacy');
        expect(calls.last.method, 'writeDocument');
        expect(calls.last.arguments, {
          'path': '/notes/a.md',
          'contents': 'legacy',
        });
        for (final expected in <String?>[null, '', '\ufeff# Existing\r\n']) {
          await service.writeMarkdownFileGuarded(
            '/notes/a.md',
            '\ufeffmine\r\n',
            expectedContents: expected,
          );
          expect(calls.last.method, 'writeDocumentGuarded');
          expect(calls.last.arguments, {
            'path': '/notes/a.md',
            'contentsBytes': Uint8List.fromList(utf8.encode('\ufeffmine\r\n')),
            'expectedContentsBytes': expected == null
                ? null
                : Uint8List.fromList(utf8.encode(expected)),
          });
        }
      },
    );

    test(
      'typed conflicts retain the current version including deletion',
      () async {
        for (final current in <String?>[
          'external',
          '\ufeffé e\u0301\r\n',
          '',
          null,
        ]) {
          messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
            _,
          ) async {
            throw PlatformException(
              code: 'workspace_save_conflict',
              details: {
                'path': '/notes/a.md',
                'currentContentsBytes': current == null
                    ? null
                    : Uint8List.fromList(utf8.encode(current)),
              },
            );
          });
          await expectLater(
            service.writeMarkdownFileGuarded(
              '/notes/a.md',
              'mine',
              expectedContents: 'baseline',
            ),
            throwsA(
              isA<MarkdownSaveConflict>()
                  .having((error) => error.path, 'path', '/notes/a.md')
                  .having(
                    (error) => error.expectedContents,
                    'expected',
                    'baseline',
                  )
                  .having((error) => error.currentContents, 'current', current),
            ),
          );
        }
      },
    );

    test('Apple reads retain exact source through the byte channel', () async {
      for (final source in [
        '',
        '\ufeff# Café\r\n中文 😀',
        '\ufeff\ufefftwo BOMs',
        'e\u0301',
      ]) {
        messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
          call,
        ) async {
          calls.add(call);
          return Uint8List.fromList(utf8.encode(source));
        });
        expect(await workspace.read('/notes/a.md', maximumBytes: 4096), source);
        expect(calls.last.method, 'readDocumentBytes');
        expect(calls.last.arguments, {
          'path': '/notes/a.md',
          'maximumBytes': 4096,
        });
        expect(
          (await service.readMarkdownFile('/notes/a.md')).contents,
          source,
        );
      }
    });

    test('invalid native read or conflict bytes fail closed', () async {
      messenger.setMockMethodCallHandler(
        AppleWorkspaceService.channel,
        (_) async => Uint8List.fromList([0xff, 0xfe]),
      );
      await expectLater(workspace.read('/notes/a.md'), throwsFormatException);
      messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'workspace_save_conflict',
          details: {
            'path': '/notes/a.md',
            'currentContentsBytes': Uint8List.fromList([0xff, 0xfe]),
          },
        );
      });
      await expectLater(
        service.writeMarkdownFileGuarded(
          '/notes/a.md',
          'mine',
          expectedContents: 'baseline',
        ),
        throwsFormatException,
      );
    });

    test('native read errors and malformed conflicts fail closed', () async {
      for (final error in [
        PlatformException(code: 'workspace_unavailable', message: 'Unreadable'),
        PlatformException(code: 'workspace_save_conflict'),
        PlatformException(
          code: 'workspace_save_conflict',
          details: {'path': '/notes/a.md'},
        ),
        PlatformException(
          code: 'workspace_save_conflict',
          details: {
            'path': '/other.md',
            'currentContentsBytes': Uint8List.fromList(utf8.encode('external')),
          },
        ),
        PlatformException(
          code: 'workspace_save_conflict',
          details: {'path': '/notes/a.md', 'currentContentsBytes': 42},
        ),
      ]) {
        messenger.setMockMethodCallHandler(
          AppleWorkspaceService.channel,
          (_) async => throw error,
        );
        await expectLater(
          service.writeMarkdownFileGuarded(
            '/notes/a.md',
            'mine',
            expectedContents: 'baseline',
          ),
          throwsA(isA<PlatformException>()),
        );
      }
    });
  });
}

/// Real temporary-file operations with only a precise failure/race injected.
/// No production hooks are needed, and the comparison/rename paths stay real.
final class _SaveIOOverrides extends IOOverrides {
  _SaveIOOverrides({
    this.targetPath,
    this.readError,
    this.stageError,
    this.renameError,
    this.afterStage,
  });

  final String? targetPath;
  final FileSystemException? readError;
  final FileSystemException? stageError;
  final FileSystemException? renameError;
  final Future<void> Function()? afterStage;
  bool flushed = false;

  @override
  File createFile(String path) => _SaveFile(super.createFile(path), this);
}

class _SaveFile implements File {
  _SaveFile(this.file, this.overrides);

  final File file;
  final _SaveIOOverrides overrides;
  bool get isStaging => p.basename(file.path) == 'document.tmp';

  @override
  Directory get parent => file.parent;

  @override
  Future<Uint8List> readAsBytes() {
    if (file.path == overrides.targetPath && overrides.readError != null) {
      throw overrides.readError!;
    }
    return file.readAsBytes();
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    await file.writeAsBytes(bytes, mode: mode, flush: flush);
    if (isStaging) {
      overrides.flushed = flush;
      if (overrides.stageError != null) throw overrides.stageError!;
      await overrides.afterStage?.call();
    }
    return this;
  }

  @override
  Future<File> rename(String newPath) {
    if (isStaging && overrides.renameError != null) {
      throw overrides.renameError!;
    }
    return file.rename(newPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
