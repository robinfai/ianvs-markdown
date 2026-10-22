// Catalog reconciliation must update every shared consumer, including a tree
// whose provider does not deliver watcher events.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/file_browser_controller.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'support/fakes.dart';

class CatalogSource implements WorkspaceIndexSource {
  final directories = <String, WorkspaceDirectorySnapshot>{};
  final reads = <String, WorkspaceTextRead>{};
  Future<WorkspaceTextRead> Function(String)? onRead;
  Future<WorkspaceDirectorySnapshot> Function(String)? onList;
  @override
  Future<WorkspaceDirectorySnapshot> listWorkspaceDirectory(
    String root,
    String path,
  ) async => onList == null
      ? directories[path] ?? const WorkspaceDirectorySnapshot([])
      : await onList!(path);
  @override
  Future<WorkspaceTextRead> readWorkspaceText(
    String root,
    String path,
    int maximumBytes,
  ) async => onRead == null ? reads[path]! : await onRead!(path);
}

class CountingIndex extends WorkspaceIndex {
  CountingIndex({required super.source});
  int snapshotLookups = 0;
  @override
  WorkspaceDirectorySnapshot? cachedDirectory(String relativePath) {
    snapshotLookups++;
    return super.cachedDirectory(relativePath);
  }
}

const folder = WorkspaceMetadata(
  relativePath: 'folder',
  isDirectory: true,
  revision: 'folder-1',
);
const oldNote = WorkspaceMetadata(
  relativePath: 'folder/old.md',
  isDirectory: false,
  revision: 'old-1',
);
const newNote = WorkspaceMetadata(
  relativePath: 'folder/new.md',
  isDirectory: false,
  revision: 'new-1',
);

void main() {
  test('deleted parent must reject in-flight descendant body', () async {
    final source = CatalogSource()
      ..directories[''] = const WorkspaceDirectorySnapshot([folder])
      ..directories['folder'] = const WorkspaceDirectorySnapshot([oldNote]);
    final index = WorkspaceIndex(source: source)..configure('/vault');
    await index.directory('');
    await index.directory('folder');
    final pending = Completer<WorkspaceTextRead>();
    final started = Completer<void>();
    source.onRead = (_) {
      started.complete();
      return pending.future;
    };
    final body = index.read(oldNote);
    // Register the expected failure immediately to avoid uncaught future errors.
    final checked = expectLater(body, throwsA(isA<WorkspaceIndexFailure>()));
    await started.future;
    source.directories[''] = const WorkspaceDirectorySnapshot([]);
    await index.directory('', refresh: true);
    expect(index.cachedDirectory('folder'), isNull);
    pending.complete(const WorkspaceTextRead('stale needle', 'old-1'));
    await checked;
    expect(index.cachedDocuments, 0);
    index.dispose();
  });

  test(
    'search partial catalog must update existing tree error state',
    () async {
      final source = CatalogSource()
        ..directories[''] = const WorkspaceDirectorySnapshot([]);
      final index = WorkspaceIndex(source: source)..configure('/vault');
      final files = MemoryMarkdownFileService();
      final browser = FileBrowserController(files, index: index)
        ..configure('/vault', [], null);
      await browser.load('/vault');
      expect(browser.errors, isEmpty);
      source.directories[''] = const WorkspaceDirectorySnapshot(
        [],
        complete: false,
        reason: 'attachment_offline',
      );
      // Search controller accesses the shared index directly, not browser.load.
      await index.directory('', refresh: true);
      expect(browser.errors, contains('/vault'));
      browser.dispose();
      index.dispose();
      await files.dispose();
    },
  );

  test(
    'search deletion then recreation cannot resurrect cached tree children',
    () async {
      final source = CatalogSource()
        ..directories[''] = const WorkspaceDirectorySnapshot([folder])
        ..directories['folder'] = const WorkspaceDirectorySnapshot([oldNote]);
      final index = WorkspaceIndex(source: source)..configure('/vault');
      final files = MemoryMarkdownFileService();
      final browser = FileBrowserController(files, index: index)
        ..configure('/vault', [], null);
      await browser.load('/vault');
      browser.preferences.expanded.add('/vault/folder');
      await browser.load('/vault/folder');
      expect(
        browser.rows.any((r) => r.entry?.path == '/vault/folder/old.md'),
        isTrue,
      );
      source.directories[''] = const WorkspaceDirectorySnapshot([]);
      await index.directory('', refresh: true);
      // No watcher event is guaranteed for providers. Catalog knows it is gone.
      source.directories[''] = const WorkspaceDirectorySnapshot([folder]);
      source.directories['folder'] = const WorkspaceDirectorySnapshot([
        newNote,
      ]);
      await index.directory('', refresh: true);
      await index.directory('folder');
      expect(
        browser.rows.any((r) => r.entry?.path == '/vault/folder/old.md'),
        isFalse,
      );
      expect(
        browser.rows.any((r) => r.entry?.path == '/vault/folder/new.md'),
        isTrue,
      );
      browser.dispose();
      index.dispose();
      await files.dispose();
    },
  );
  test(
    'same-path directory replacement rejects pending descendant body even after relisting',
    () async {
      final source = CatalogSource()
        ..directories[''] = const WorkspaceDirectorySnapshot([folder])
        ..directories['folder'] = const WorkspaceDirectorySnapshot([oldNote]);
      final index = WorkspaceIndex(source: source)..configure('/vault');
      addTearDown(index.dispose);
      await index.directory('');
      await index.directory('folder');
      final pending = Completer<WorkspaceTextRead>();
      final started = Completer<void>();
      source.onRead = (_) {
        started.complete();
        return pending.future;
      };
      final checked = expectLater(
        index.read(oldNote),
        throwsA(isA<WorkspaceIndexFailure>()),
      );
      await started.future;
      source.directories[''] = const WorkspaceDirectorySnapshot(
        [
          WorkspaceMetadata(
            relativePath: 'folder',
            isDirectory: true,
            revision: 'new-directory-identity',
          ),
        ],
        complete: false,
        reason: 'other entries unavailable',
      );
      await index.directory('', refresh: true);
      expect(index.cachedDirectory('folder'), isNull);
      await index.directory('folder');
      pending.complete(const WorkspaceTextRead('stale needle', 'old-1'));
      await checked;
      expect(index.cachedDocuments, 0);
    },
  );

  test(
    'directory to Markdown file replacement releases descendant metadata and bodies',
    () async {
      const directory = WorkspaceMetadata(
        relativePath: 'folder.md',
        isDirectory: true,
        revision: 'directory',
      );
      const child = WorkspaceMetadata(
        relativePath: 'folder.md/child.md',
        isDirectory: false,
        revision: 'child',
      );
      final source = CatalogSource()
        ..directories[''] = const WorkspaceDirectorySnapshot([directory])
        ..directories['folder.md'] = const WorkspaceDirectorySnapshot([child])
        ..reads['folder.md/child.md'] = const WorkspaceTextRead(
          'needle',
          'child',
        );
      final index = WorkspaceIndex(source: source)..configure('/vault');
      addTearDown(index.dispose);
      await index.directory('');
      await index.directory('folder.md');
      await index.read(child);
      expect(index.cachedDocuments, 1);
      source.directories[''] = const WorkspaceDirectorySnapshot([
        WorkspaceMetadata(
          relativePath: 'folder.md',
          isDirectory: false,
          revision: 'file',
        ),
      ]);
      await index.directory('', refresh: true);
      expect(index.cachedDirectory('folder.md'), isNull);
      expect(index.cachedDocuments, 0);
      await expectLater(
        index.read(child),
        throwsA(isA<WorkspaceIndexFailure>()),
      );
    },
  );
  test('search success hydrates tree after its first load failed', () async {
    final source = CatalogSource()
      ..onList = (_) async {
        throw const WorkspaceIndexFailure(WorkspaceReadIssue.offline);
      };
    final index = WorkspaceIndex(source: source)..configure('/vault');
    final files = MemoryMarkdownFileService();
    final browser = FileBrowserController(files, index: index)
      ..configure('/vault', [], null);
    addTearDown(browser.dispose);
    addTearDown(index.dispose);
    addTearDown(files.dispose);
    await browser.load('/vault');
    expect(browser.errors, contains('/vault'));
    source.onList = null;
    source.directories[''] = const WorkspaceDirectorySnapshot([folder]);
    await index.directory('', refresh: true);
    expect(browser.errors, isEmpty);
    expect(
      browser.rows.any((row) => row.entry?.path == '/vault/folder'),
      isTrue,
    );
  });
  test(
    'shared catalog refresh updates existing filename results without watcher or repeated listing',
    () async {
      final source = CatalogSource()
        ..directories[''] = const WorkspaceDirectorySnapshot([folder])
        ..directories['folder'] = const WorkspaceDirectorySnapshot([oldNote]);
      var lists = 0;
      source.onList = (path) async {
        lists++;
        return source.directories[path]!;
      };
      final index = WorkspaceIndex(source: source)..configure('/vault');
      final files = MemoryMarkdownFileService();
      final browser = FileBrowserController(files, index: index)
        ..configure('/vault', [], null);
      addTearDown(browser.dispose);
      addTearDown(index.dispose);
      addTearDown(files.dispose);
      await browser.load('/vault');
      browser.search('old');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(browser.searching, isFalse);
      expect(browser.results.single.path, '/vault/folder/old.md');
      expect(lists, 2);
      source.directories[''] = const WorkspaceDirectorySnapshot([]);
      await index.directory('', refresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(browser.results, isEmpty);
      expect(browser.matchCount, 0);
      expect(browser.searching, isFalse);
      expect(lists, 3);
    },
  );
  for (final count in [1000, 10000]) {
    test(
      '$count collapsed sibling scans do not rebuild or notify unchanged browser snapshots',
      () async {
        final source = CatalogSource();
        source.directories[''] = WorkspaceDirectorySnapshot([
          for (var i = 0; i < count; i++)
            WorkspaceMetadata(
              relativePath: 'folder-$i',
              isDirectory: true,
              revision: 'v1',
            ),
        ]);
        final index = CountingIndex(source: source)..configure('/vault');
        final files = MemoryMarkdownFileService();
        final browser = FileBrowserController(files, index: index)
          ..configure('/vault', [], null);
        addTearDown(browser.dispose);
        addTearDown(index.dispose);
        addTearDown(files.dispose);
        await browser.load('/vault');
        final rootEntry = browser.rows
            .firstWhere((row) => row.entry?.path == '/vault/folder-0')
            .entry;
        index.snapshotLookups = 0;
        var updates = 0;
        browser.addListener(() => updates++);
        for (var i = 0; i < count; i++) {
          await index.directory('folder-$i');
        }
        expect(index.indexedDirectories, count + 1);
        expect(index.snapshotLookups, 0);
        expect(updates, 0);
        expect(
          identical(
            browser.rows
                .firstWhere((row) => row.entry?.path == '/vault/folder-0')
                .entry,
            rootEntry,
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'expanded deep catalog changes only reconcile affected snapshot and preserve partial/error changes',
    () async {
      final source = CatalogSource();
      var parent = '';
      for (var i = 0; i < 48; i++) {
        final child = parent.isEmpty ? 'level' : '$parent/level';
        source.directories[parent] = WorkspaceDirectorySnapshot([
          WorkspaceMetadata(
            relativePath: child,
            isDirectory: true,
            revision: 'v1',
          ),
        ]);
        parent = child;
      }
      source.directories[parent] = WorkspaceDirectorySnapshot([
        WorkspaceMetadata(
          relativePath: '$parent/note.md',
          isDirectory: false,
          revision: 'v1',
        ),
      ]);
      final index = CountingIndex(source: source)..configure('/vault');
      final files = MemoryMarkdownFileService();
      final browser = FileBrowserController(files, index: index)
        ..configure('/vault', [], null);
      addTearDown(browser.dispose);
      addTearDown(index.dispose);
      addTearDown(files.dispose);
      await browser.load('/vault');
      for (final path in source.directories.keys.where(
        (path) => path.isNotEmpty,
      )) {
        browser.preferences.expanded.add('/vault/$path');
        await index.directory(path);
      }
      expect(
        browser.rows.any((row) => row.entry?.path == '/vault/$parent/note.md'),
        isTrue,
      );
      index.snapshotLookups = 0;
      source.directories[parent] = const WorkspaceDirectorySnapshot(
        [],
        complete: false,
        reason: 'provider unavailable',
      );
      await index.directory(parent, refresh: true);
      expect(index.snapshotLookups, 1);
      expect(
        browser.errors['/vault/$parent'].toString(),
        contains('provider unavailable'),
      );
      expect(
        browser.rows.any((row) => row.entry?.path == '/vault/$parent/note.md'),
        isTrue,
      );
      index.snapshotLookups = 0;
      source.directories[parent] = const WorkspaceDirectorySnapshot([]);
      await index.directory(parent, refresh: true);
      expect(index.snapshotLookups, 1);
      expect(browser.errors, isEmpty);
      expect(
        browser.rows.any((row) => row.entry?.path == '/vault/$parent/note.md'),
        isFalse,
      );
    },
  );
  test(
    'selected filesystem root does not evict itself while applying a snapshot',
    () async {
      final source = CatalogSource()
        ..directories[''] = const WorkspaceDirectorySnapshot([
          WorkspaceMetadata(
            relativePath: 'note.md',
            isDirectory: false,
            revision: 'v1',
          ),
        ]);
      final index = WorkspaceIndex(source: source)..configure('/');
      final files = MemoryMarkdownFileService();
      final browser = FileBrowserController(files, index: index)
        ..configure('/', [], null);
      addTearDown(browser.dispose);
      addTearDown(index.dispose);
      addTearDown(files.dispose);
      await browser.load('/');
      expect(browser.rows.any((row) => row.entry?.path == '/note.md'), isTrue);
    },
  );
}
