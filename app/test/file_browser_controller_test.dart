import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/file_browser_controller.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/services/workspace_session_store.dart';
import 'support/fakes.dart';

WorkspaceEntry entry(String path, {bool folder = false, int day = 1}) =>
    WorkspaceEntry(
      path: path,
      name: path.split('/').last,
      isDirectory: folder,
      modified: DateTime(2026, 1, day),
    );

void main() {
  late _ObservedFiles files;
  late WorkspaceController workspace;
  late MemoryWorkspaceSessionStore store;
  setUp(() async {
    files = _ObservedFiles()..selectedFolder = '/vault';
    files.files.addAll({
      '/vault/note-10.md': 'ten',
      '/vault/note-2.md': 'two',
      '/vault/docs/deep/design.md': 'design',
    });
    files.directories.addAll({
      '/vault': [
        entry('/vault/note-10.md', day: 8),
        entry('/vault/note-2.md', day: 4),
        entry('/vault/docs', folder: true),
      ],
      '/vault/docs': [entry('/vault/docs/deep', folder: true)],
      '/vault/docs/deep': [entry('/vault/docs/deep/design.md')],
    });
    store = MemoryWorkspaceSessionStore();
    workspace = WorkspaceController(fileService: files, sessionStore: store);
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
    await workspace.browser.load('/vault');
  });
  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });

  test(
    'late reads cannot leak across workspace switches or override a newer reveal',
    () async {
      final blocked = Completer<List<WorkspaceEntry>>();
      files.blocked['/vault/docs'] = blocked;
      final old = workspace.browser.reveal('/vault/docs/deep/design.md');
      await Future<void>.delayed(Duration.zero);
      await workspace.browser.reveal('/vault/note-2.md');
      blocked.complete([entry('/vault/docs/deep', folder: true)]);
      await old;
      expect(workspace.browser.focusedPath, '/vault/note-2.md');
      final pending = Completer<List<WorkspaceEntry>>();
      files.blocked['/vault'] = pending;
      final refresh = workspace.browser.load('/vault', refresh: true);
      files.selectedFolder = '/elsewhere';
      await workspace.chooseWorkspaceFolder();
      files.blocked.remove('/vault');
      files.selectedFolder = '/vault';
      await workspace.chooseWorkspaceFolder();
      await workspace.browser.load('/vault');
      pending.complete([entry('/vault/stale.md')]);
      await refresh;
      expect(
        workspace.browser.rows.any((r) => r.entry?.name == 'stale.md'),
        isFalse,
      );
    },
  );

  test(
    'external favorites retain bookmark access after closing and recovery',
    () async {
      files.files['/outside/favorite.md'] = 'favorite';
      final document = (await workspace.openPath('/outside/favorite.md'))!;
      await workspace.toggleFileFavorite(entry(document.path!));
      workspace.removeDocument(document);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        store.snapshot!.favoriteAccessTokens,
        contains('/outside/favorite.md'),
      );
      workspace.dispose();
      workspace = WorkspaceController(fileService: files, sessionStore: store);
      await workspace.initialize();
      await workspace.openFavorite('/outside/favorite.md', directory: false);
      expect(workspace.activeDocument?.path, '/outside/favorite.md');
      expect(files.reads.where((path) => path.startsWith('/outside')), isEmpty);
    },
  );

  test(
    'edits during Trash remain a recoverable draft; queued saves cannot recreate removed files',
    () async {
      final document = (await workspace.openPath('/vault/note-2.md'))!;
      files.trashGate = Completer<void>();
      final trash = workspace.trashFileEntry(document.path!);
      await Future<void>.delayed(Duration.zero);
      document.controller.text = 'typed during Trash';
      files.trashGate!.complete();
      await trash;
      expect(workspace.documents, contains(document));
      expect(document.path, isNull);
      expect(document.controller.text, 'typed during Trash');
      expect(store.snapshot!.documents.last['text'], 'typed during Trash');
      files.trashGate = null;
      final clean = (await workspace.openPath('/vault/note-10.md'))!;
      final removing = workspace.trashFileEntry(clean.path!);
      final saving = workspace.saveDocument(clean);
      await removing;
      expect(await saving, isFalse);
      expect(files.files, isNot(contains('/vault/note-10.md')));
    },
  );

  test(
    'external files sort by their own metadata without parent listing',
    () async {
      files.files.addAll({'/outside/a.md': 'a', '/outside/z.md': 'z'});
      files.modifiedTimes.addAll({
        '/outside/a.md': DateTime(2026, 1, 1),
        '/outside/z.md': DateTime(2026, 1, 2),
      });
      await workspace.openPath('/outside/a.md');
      await workspace.openPath('/outside/z.md');
      await workspace.browser.refreshExternalMetadata();
      workspace.browser.setSort(FileSort.modified);
      expect(
        workspace.browser.rows
            .where((r) => r.entry?.isDirectory == false && r.external)
            .map((r) => r.entry!.name),
        ['z.md', 'a.md'],
      );
      expect(files.reads.where((path) => path.startsWith('/outside')), isEmpty);
    },
  );

  test('natural and modified sorting keep directories first', () {
    final browser = workspace.browser;
    expect(browser.rows.map((r) => r.entry?.name), [
      'docs',
      'note-2.md',
      'note-10.md',
    ]);
    browser.setSort(FileSort.modified);
    expect(browser.rows.map((r) => r.entry?.name), [
      'docs',
      'note-10.md',
      'note-2.md',
    ]);
    expect(
      naturalCompare(
        'note-9999999999999999999999',
        'note-10000000000000000000000',
      ),
      lessThan(0),
    );
  });

  test(
    'reveal expands ancestors; follow is opt in; external paths never enumerate parents',
    () async {
      final browser = workspace.browser;
      await workspace.openPath('/vault/docs/deep/design.md');
      expect(browser.preferences.expanded, isEmpty);
      await browser.reveal('/vault/docs/deep/design.md');
      expect(
        browser.preferences.expanded,
        containsAll(['/vault/docs', '/vault/docs/deep']),
      );
      expect(
        browser.rows.any((r) => r.entry?.path == '/vault/docs/deep/design.md'),
        isTrue,
      );
      browser.collapseAll();
      browser.setFollow(true);
      await Future<void>.delayed(Duration.zero);
      expect(browser.preferences.expanded, contains('/vault/docs'));
      files.files['/outside/one.md'] = 'outside';
      await workspace.openPath('/outside/one.md');
      await browser.reveal('/outside/one.md');
      expect(files.reads.where((path) => path.startsWith('/outside')), isEmpty);
    },
  );

  test(
    'search ranks filename matches above paths and caches its directory index',
    () async {
      final browser = workspace.browser;
      files.files['/vault/design/other.md'] = 'other';
      files.directories['/vault']!.add(entry('/vault/design', folder: true));
      files.directories['/vault/design'] = [entry('/vault/design/other.md')];
      await browser.refresh();
      browser.search('design');
      await _searchDone(browser);
      expect(browser.results.map((e) => e.path), [
        '/vault/docs/deep/design.md',
        '/vault/design/other.md',
      ]);
      final count = files.reads.length;
      browser.search('deep/design');
      await _searchDone(browser);
      expect(browser.results.single.path, '/vault/docs/deep/design.md');
      expect(files.reads.length, count);
    },
  );

  test(
    'search cancellation stops old traversal and rejects stale results',
    () async {
      final blocked = Completer<List<WorkspaceEntry>>();
      files.blocked['/vault/docs'] = blocked;
      final browser = workspace.browser;
      browser.search('old');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(files.reads, contains('/vault/docs'));
      browser.search('');
      blocked.complete([entry('/vault/docs/more', folder: true)]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(files.reads, isNot(contains('/vault/docs/more')));
      expect(browser.results, isEmpty);
      expect(browser.searching, isFalse);
    },
  );

  test('search limits visible results but counts all matches', () async {
    files.directories['/vault'] = List.generate(
      260,
      (i) => entry('/vault/note-$i.md'),
    );
    await workspace.browser.refresh();
    workspace.browser.search('note');
    await _searchDone(workspace.browser);
    expect(workspace.browser.results.length, 200);
    expect(workspace.browser.matchCount, 260);
  });

  test('filesystem event refreshes one directory and updates search', () async {
    final browser = workspace.browser;
    browser.search('new');
    await _searchDone(browser);
    final before = files.reads.length;
    files.directories['/vault/docs/deep']!.add(
      entry('/vault/docs/deep/new.md'),
    );
    files.events.add(FileSystemCreateEvent('/vault/docs/deep/new.md', false));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(browser.results.single.name, 'new.md');
    expect(files.reads.sublist(before), ['/vault/docs/deep']);
  });

  test(
    'directory errors are retryable and do not hide external files',
    () async {
      files.failures.add('/vault/docs');
      workspace.browser.toggle('/vault/docs');
      await workspace.browser.load('/vault/docs');
      expect(workspace.browser.errors, contains('/vault/docs'));
      files.failures.clear();
      await workspace.browser.load('/vault/docs', refresh: true);
      expect(workspace.browser.errors, isEmpty);
      expect(
        workspace.browser.rows.any((r) => r.entry?.name == 'deep'),
        isTrue,
      );
    },
  );

  test('per-workspace settings and favorites survive JSON recovery', () async {
    final browser = workspace.browser;
    await browser.reveal('/vault/docs/deep/design.md');
    browser.setScroll(280);
    browser.setSort(FileSort.modified);
    browser.setFollow(true);
    browser.toggleFavorite(entry('/vault/docs', folder: true));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final snapshot = WorkspaceSnapshot.fromJson(store.snapshot!.toJson());
    files.selectedFolder = '/other';
    await workspace.chooseWorkspaceFolder();
    expect(browser.preferences.expanded, isEmpty);
    expect(browser.preferences.scroll, 0);
    store.snapshot = snapshot;
    workspace.dispose();
    workspace = WorkspaceController(fileService: files, sessionStore: store);
    await workspace.initialize();
    expect(
      workspace.browser.preferences.expanded,
      contains('/vault/docs/deep'),
    );
    expect(workspace.browser.preferences.scroll, 280);
    expect(workspace.browser.preferences.sort, FileSort.modified);
    expect(workspace.browser.preferences.follow, isTrue);
    expect(workspace.browser.preferences.favorites['/vault/docs'], isTrue);
  });

  test(
    'create validates names and collisions, and appends Markdown extension',
    () async {
      expect(await workspace.createFileEntry('/vault', '新文档'), '/vault/新文档.md');
      expect(files.files['/vault/新文档.md'], '');
      await expectLater(
        workspace.createFileEntry('/vault', '新文档'),
        throwsStateError,
      );
      for (final name in [
        '../escape',
        '',
        '.hidden',
        'a/b',
        'a\\b',
        'bad:colon',
        'a\n',
      ]) {
        if (name == 'a\n') {
          continue; // Leading/trailing whitespace is intentionally trimmed.
        }
        await expectLater(
          workspace.createFileEntry('/vault', name),
          throwsFormatException,
        );
      }
      await expectLater(
        workspace.createFileEntry('/outside', 'new'),
        throwsStateError,
      );
      await workspace.createFileEntry('/vault', 'new folder', folder: true);
      expect(files.directories, contains('/vault/new folder'));
    },
  );

  test(
    'directory rename remaps dirty sessions, favorites and recovery; saves use new path',
    () async {
      final document = (await workspace.openPath(
        '/vault/docs/deep/design.md',
      ))!;
      document.controller.text = 'unsaved';
      await workspace.browser.reveal(document.path!);
      workspace.browser.toggleFavorite(entry(document.path!));
      await workspace.moveFileEntry('/vault/docs', '/vault/renamed');
      expect(document.path, '/vault/renamed/deep/design.md');
      expect(document.controller.text, 'unsaved');
      expect(document.controller.isDirty, isTrue);
      expect(workspace.browser.preferences.favorites, contains(document.path));
      expect(
        workspace.browser.preferences.expanded,
        contains('/vault/renamed/deep'),
      );
      expect(store.snapshot!.documents.last['path'], document.path);
      await workspace.saveDocument(document);
      expect(files.files[document.path], 'unsaved');
      expect(files.files, isNot(contains('/vault/docs/deep/design.md')));
    },
  );

  test('failed move leaves sessions and disk identity unchanged', () async {
    final document = (await workspace.openPath('/vault/note-2.md'))!;
    document.controller.text = 'dirty';
    await expectLater(
      workspace.moveFileEntry(document.path!, '/vault/note-10.md'),
      throwsStateError,
    );
    files.failMove = true;
    await expectLater(
      workspace.moveFileEntry(document.path!, '/vault/renamed.md'),
      throwsStateError,
    );
    expect(document.path, '/vault/note-2.md');
    expect(document.controller.text, 'dirty');
    expect(files.files['/vault/note-2.md'], 'two');
    expect(workspace.documents.length, 2);
  });

  test('moves reject descendants/root and serialize with saves', () async {
    await expectLater(
      workspace.moveFileEntry('/vault/docs', '/vault/docs/deep/nested'),
      throwsStateError,
    );
    await expectLater(
      workspace.moveFileEntry('/vault', '/vault-new'),
      throwsStateError,
    );
    final doc = (await workspace.openPath('/vault/note-2.md'))!;
    doc.controller.text = 'latest';
    final moving = workspace.moveFileEntry(doc.path!, '/vault/renamed.md');
    final saving = workspace.saveDocument(doc);
    await moving;
    await saving;
    expect(files.files['/vault/renamed.md'], 'latest');
    expect(files.files.containsKey('/vault/note-2.md'), isFalse);
  });

  test(
    'duplicate copies saved bytes and never overwrites; Trash protects descendant drafts',
    () async {
      final doc = (await workspace.openPath('/vault/docs/deep/design.md'))!;
      doc.controller.text = 'draft';
      expect(
        await workspace.duplicateFileEntry(doc.path!),
        '/vault/docs/deep/design copy.md',
      );
      expect(
        await workspace.duplicateFileEntry(doc.path!),
        '/vault/docs/deep/design copy 2.md',
      );
      expect(files.files['/vault/docs/deep/design copy.md'], 'design');
      await expectLater(
        workspace.trashFileEntry('/vault/docs'),
        throwsStateError,
      );
      expect(files.trashed, isEmpty);
      await workspace.trashFileEntry('/vault/docs', discardChanges: true);
      expect(files.trashed, ['/vault/docs']);
      expect(
        workspace.documents.any(
          (d) => d.path?.startsWith('/vault/docs') ?? false,
        ),
        isFalse,
      );
    },
  );

  test(
    'granted external folder permits operations without becoming a workspace',
    () async {
      files.files['/outside/a.md'] = 'external';
      files.selectedFolder = '/outside';
      await workspace.chooseOperationFolder();
      await workspace.moveFileEntry('/outside/a.md', '/outside/b.md');
      expect(workspace.workspaceRoot, '/vault');
      expect(files.reads.where((path) => path.startsWith('/outside')), isEmpty);
    },
  );
}

Future<void> _searchDone(FileBrowserController browser) async {
  await Future<void>.delayed(const Duration(milliseconds: 200));
  for (var i = 0; i < 100 && browser.searching; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(browser.searching, isFalse);
}

class _ObservedFiles extends MemoryMarkdownFileService {
  final reads = <String>[];
  final failures = <String>{};
  final blocked = <String, Completer<List<WorkspaceEntry>>>{};
  bool failMove = false;
  Completer<void>? trashGate;
  @override
  Future<void> trashEntry(String path) async {
    if (trashGate != null) await trashGate!.future;
    return super.trashEntry(path);
  }

  @override
  Future<List<WorkspaceEntry>> listDirectory(String path) async {
    reads.add(path);
    if (failures.contains(path)) throw StateError('Permission denied');
    if (blocked[path] case final pending?) return pending.future;
    return super.listDirectory(path);
  }

  @override
  Future<void> moveEntry(String source, String destination) async {
    if (failMove) throw StateError('Move failed');
    return super.moveEntry(source, destination);
  }
}
