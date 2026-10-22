import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_session_store.dart';

WorkspaceSnapshot _snapshot(String text) => WorkspaceSnapshot(
  documents: [
    {
      'id': 'document-1',
      'name': 'Untitled.md',
      'path': null,
      'accessToken': null,
      'text': text,
      'persistedText': '',
      'mode': 'source',
      'encoding': 'UTF-8',
      'lineEnding': 'CRLF',
    },
  ],
  activeDocumentId: 'document-1',
  workspaceRoot: null,
  workspaceAccessToken: null,
  sidebarVisible: true,
  outlineVisible: true,
);

void main() {
  late Directory directory;
  late File primary;
  late File backup;
  late DesktopWorkspaceSessionStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('workspace-safety-');
    primary = File('${directory.path}/ianvs-markdown/workspace.json');
    backup = File('${primary.path}.bak');
    store = DesktopWorkspaceSessionStore(directory: directory);
    await primary.parent.create(recursive: true);
  });

  tearDown(() => directory.delete(recursive: true));

  Future<void> writeSnapshot(File file, WorkspaceSnapshot snapshot) => file
      .writeAsString(jsonEncode(snapshot.toJson()), flush: true)
      .then((_) {});

  Future<List<List<int>>> archivedBytes() async {
    final archives = <List<int>>[];
    await for (final entry in primary.parent.list(recursive: true)) {
      if (entry is File && entry.path.endsWith('/original')) {
        archives.add(await entry.readAsBytes());
      }
    }
    return archives;
  }

  Future<void> expectNoStaging() async {
    expect(
      await primary.parent
          .list()
          .where((entry) => entry.path.contains('.staging-'))
          .toList(),
      isEmpty,
    );
  }

  test('only absent primary and backup are an empty session', () async {
    expect(await store.load(), isNull);
    await File('${primary.path}.tmp').writeAsString('incomplete old save');
    expect(await store.load(), isNull);
  });

  test(
    'saves retain the previous valid snapshot with exact source text',
    () async {
      final first = _snapshot('first 中文😀\r\nno final newline');
      final second = _snapshot('second 中文😀\r\n\r\n');
      final third = _snapshot('third');
      await store.save(first);
      final firstBytes = await primary.readAsBytes();
      expect(await backup.readAsBytes(), firstBytes);
      await store.save(second);
      expect((await store.load())!.toJson(), second.toJson());
      expect(await backup.readAsBytes(), firstBytes);
      final secondBytes = await primary.readAsBytes();
      await store.save(third);
      expect(await backup.readAsBytes(), secondBytes);
      expect((await store.load())!.recoveryNotice, isNull);
      await expectNoStaging();
    },
  );

  final invalidJson = <String, Object?>{
    'null': null,
    'array': [],
    'number': 42,
    'missing documents': {},
    'null documents': {'documents': null},
    'object documents': {'documents': {}},
    'non-map document': {
      'documents': [42],
    },
    'empty document': {
      'documents': [{}],
    },
    'missing draft text': {
      'documents': [
        {'id': 'document-1', 'name': 'draft.md', 'persistedText': ''},
      ],
    },
    'missing saved baseline': {
      'documents': [
        {'id': 'document-1', 'name': 'draft.md', 'text': 'draft'},
      ],
    },
    'empty document ID': {
      'documents': [
        {'id': '', 'name': 'draft.md', 'text': 'draft', 'persistedText': ''},
      ],
    },
    'wrong document field type': {
      'documents': [
        {
          'id': 'document-1',
          'name': 'draft.md',
          'text': 'draft',
          'persistedText': '',
          'path': 42,
        },
      ],
    },
    'unknown mode': {
      'documents': [
        {..._snapshot('draft').documents.single, 'mode': 'invalid'},
      ],
    },
    'mixed records must not discard the invalid draft': {
      'documents': [_snapshot('draft').documents.single, 'other draft'],
    },
    'duplicate document IDs': {
      'documents': [
        _snapshot('draft').documents.single,
        _snapshot('another draft').documents.single,
      ],
    },
    'missing active document': {
      'documents': [],
      'activeDocumentId': 'document-1',
    },
    'invalid grant': {
      'documents': [],
      'operationGrants': {'/file.md': 42},
    },
    'invalid visibility': {'documents': [], 'sidebarVisible': 'yes'},
  };
  for (final entry in invalidJson.entries) {
    test('${entry.key} cannot load empty or be overwritten', () async {
      final original = utf8.encode(jsonEncode(entry.value));
      await primary.writeAsBytes(original, flush: true);
      await expectLater(
        store.load(),
        throwsA(isA<WorkspaceSessionException>()),
      );
      await expectLater(
        store.save(_snapshot('new draft')),
        throwsA(isA<WorkspaceSessionException>()),
      );
      expect(await primary.readAsBytes(), original);
      expect(await backup.exists(), isFalse);
    });
  }

  for (final corrupt in [
    utf8.encode('{"documents":['),
    [0xff, 0xfe, 0x00],
  ]) {
    test(
      'corrupt bytes survive recovery and the next successful save',
      () async {
        final previous = _snapshot('backup 中文😀\r\n');
        await writeSnapshot(backup, previous);
        final backupBytes = await backup.readAsBytes();
        await primary.writeAsBytes(corrupt, flush: true);
        final recovered = (await store.load())!;
        expect(recovered.toJson(), previous.toJson());
        expect(recovered.recoveryNotice, contains('last valid backup'));
        expect(recovered.toJson(), isNot(contains('recoveryNotice')));
        expect(await primary.readAsBytes(), corrupt);
        expect(await backup.readAsBytes(), backupBytes);

        await store.save(_snapshot('recovered and edited'));
        expect(await archivedBytes(), contains(orderedEquals(corrupt)));
        expect(await backup.readAsBytes(), backupBytes);
        expect(
          (await store.load())!.documents.single['text'],
          'recovered and edited',
        );
        expect((await store.load())!.recoveryNotice, isNull);
        await expectNoStaging();
      },
    );
  }

  test(
    'two damaged copies remain untouched after load and save fail',
    () async {
      final primaryBytes = utf8.encode('primary broken');
      final backupBytes = utf8.encode('backup broken');
      await primary.writeAsBytes(primaryBytes);
      await backup.writeAsBytes(backupBytes);
      await expectLater(
        store.load(),
        throwsA(isA<WorkspaceSessionException>()),
      );
      await expectLater(
        store.save(_snapshot('new draft')),
        throwsA(isA<WorkspaceSessionException>()),
      );
      expect(await primary.readAsBytes(), primaryBytes);
      expect(await backup.readAsBytes(), backupBytes);
    },
  );

  test('a missing primary recovers from backup without replacing it', () async {
    final previous = _snapshot('backup draft');
    await writeSnapshot(backup, previous);
    final backupBytes = await backup.readAsBytes();
    expect((await store.load())!.toJson(), previous.toJson());
    expect((await store.load())!.recoveryNotice, isNotNull);
    expect(await primary.exists(), isFalse);
    await store.save(_snapshot('next draft'));
    expect(await backup.readAsBytes(), backupBytes);
  });

  test('a malformed backup is not treated as an absent session', () async {
    await backup.writeAsString('{"documents":[{"text":"lost draft"}]}');
    final original = await backup.readAsBytes();
    await expectLater(store.load(), throwsA(isA<WorkspaceSessionException>()));
    await expectLater(
      store.save(_snapshot('new draft')),
      throwsA(isA<WorkspaceSessionException>()),
    );
    expect(await primary.exists(), isFalse);
    expect(await backup.readAsBytes(), original);
  });

  test('a damaged backup is archived before copying a valid primary', () async {
    await writeSnapshot(primary, _snapshot('current draft'));
    final original = await primary.readAsBytes();
    final corrupt = [0xff, 0xfe, 0x01];
    await backup.writeAsBytes(corrupt);
    expect((await store.load())!.recoveryNotice, isNull);
    await store.save(_snapshot('next draft'));
    expect(await archivedBytes(), contains(orderedEquals(corrupt)));
    expect(await backup.readAsBytes(), original);
  });

  for (final hasBackup in [false, true]) {
    test('unreadable original is never replaced; backup=$hasBackup', () async {
      // A directory at the file path fails deterministically even under root,
      // unlike chmod-based permission tests.
      await Directory(primary.path).create();
      final sentinel = File('${primary.path}/keep.txt');
      await sentinel.writeAsString('original contents');
      if (hasBackup) await writeSnapshot(backup, _snapshot('backup draft'));
      final backupBytes = hasBackup ? await backup.readAsBytes() : null;
      if (hasBackup) {
        expect((await store.load())!.recoveryNotice, isNotNull);
      } else {
        await expectLater(
          store.load(),
          throwsA(isA<WorkspaceSessionException>()),
        );
      }
      await expectLater(
        store.save(_snapshot('new draft')),
        throwsA(isA<WorkspaceSessionException>()),
      );
      expect(await sentinel.readAsString(), 'original contents');
      if (hasBackup) expect(await backup.readAsBytes(), backupBytes);
    });
  }

  test(
    'an unreadable backup prevents replacing the readable primary',
    () async {
      await writeSnapshot(primary, _snapshot('current draft'));
      final original = await primary.readAsBytes();
      await Directory(backup.path).create();
      final sentinel = File('${backup.path}/keep.txt');
      await sentinel.writeAsString('original backup');
      await expectLater(
        store.save(_snapshot('next draft')),
        throwsA(isA<WorkspaceSessionException>()),
      );
      expect(await primary.readAsBytes(), original);
      expect(await sentinel.readAsString(), 'original backup');
    },
  );

  for (final failBackup in [false, true]) {
    test(
      'rename failure never truncates originals; backup=$failBackup',
      () async {
        await writeSnapshot(primary, _snapshot('current draft'));
        await writeSnapshot(backup, _snapshot('previous draft'));
        final original = await primary.readAsBytes();
        final originalBackup = await backup.readAsBytes();
        final failedPath = failBackup ? backup.path : primary.path;
        final failingStore = DesktopWorkspaceSessionStore(
          directory: directory,
          atomicReplace: (temporary, destination) async {
            if (destination.path == failedPath) {
              throw FileSystemException(
                'Injected atomic rename failure',
                failedPath,
              );
            }
            await temporary.rename(destination.path);
          },
        );
        await expectLater(
          failingStore.save(_snapshot('next draft')),
          throwsA(isA<FileSystemException>()),
        );
        expect(await primary.readAsBytes(), original);
        expect(
          await backup.readAsBytes(),
          failBackup ? originalBackup : original,
        );
        expect((await store.load())!.documents.single['text'], 'current draft');
        await expectNoStaging();
      },
    );
  }

  test('first primary rename failure still leaves a valid backup', () async {
    final failingStore = DesktopWorkspaceSessionStore(
      directory: directory,
      atomicReplace: (temporary, destination) async {
        if (destination.path == primary.path) {
          throw FileSystemException('Injected primary rename failure');
        }
        await temporary.rename(destination.path);
      },
    );
    await expectLater(
      failingStore.save(_snapshot('first draft')),
      throwsA(isA<FileSystemException>()),
    );
    expect(await primary.exists(), isFalse);
    expect((await store.load())!.documents.single['text'], 'first draft');
    expect((await store.load())!.recoveryNotice, isNotNull);
    await expectNoStaging();
  });

  test(
    'failed repair keeps both the corrupt original and valid backup',
    () async {
      final corrupt = [0xff, 0xfe, 0x01];
      await primary.writeAsBytes(corrupt);
      await writeSnapshot(backup, _snapshot('backup draft'));
      final originalBackup = await backup.readAsBytes();
      final failingStore = DesktopWorkspaceSessionStore(
        directory: directory,
        atomicReplace: (temporary, destination) async {
          throw FileSystemException(
            'Injected repair failure',
            destination.path,
          );
        },
      );
      await expectLater(
        failingStore.save(_snapshot('next draft')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await primary.readAsBytes(), corrupt);
      expect(await backup.readAsBytes(), originalBackup);
      expect(await archivedBytes(), contains(orderedEquals(corrupt)));
      expect((await store.load())!.documents.single['text'], 'backup draft');
      await expectNoStaging();
    },
  );

  test('invalid outgoing snapshot cannot replace either good copy', () async {
    await store.save(_snapshot('valid draft'));
    final original = await primary.readAsBytes();
    final originalBackup = await backup.readAsBytes();
    final invalid = _snapshot('invalid draft');
    invalid.documents.single.remove('text');
    await expectLater(store.save(invalid), throwsA(isA<FormatException>()));
    expect(await primary.readAsBytes(), original);
    expect(await backup.readAsBytes(), originalBackup);
  });
}
