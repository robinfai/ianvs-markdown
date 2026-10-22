import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/controllers/workspace_search_controller.dart';
import 'package:linefold/src/services/literal_source_matcher.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_index_source.dart';

import 'support/fakes.dart';

class FakeIndexSource implements WorkspaceIndexSource {
  final directories = <String, WorkspaceDirectorySnapshot>{};
  final texts = <String, WorkspaceTextRead>{};
  final issues = <String, WorkspaceReadIssue>{};
  final listCounts = <String, int>{};
  final readCounts = <String, int>{};
  Future<WorkspaceDirectorySnapshot> Function(String, String)? onList;
  Future<WorkspaceTextRead> Function(String, String)? onRead;
  int activeReads = 0;
  int peakReads = 0;
  int downloads = 0;
  void note(
    String name,
    String text, {
    String revision = 'v1',
    bool local = true,
    int? size,
  }) {
    final entries = [...?directories['/vault/']?.entries];
    entries.removeWhere((entry) => entry.relativePath == name);
    entries.add(
      WorkspaceMetadata(
        relativePath: name,
        isDirectory: false,
        revision: revision,
        size: size ?? text.length,
        local: local,
      ),
    );
    directories['/vault/'] = WorkspaceDirectorySnapshot(entries);
    texts['/vault/$name'] = WorkspaceTextRead(text, revision);
  }

  @override
  Future<WorkspaceDirectorySnapshot> listWorkspaceDirectory(
    String root,
    String relativePath,
  ) async {
    final key = '$root/$relativePath';
    listCounts[key] = (listCounts[key] ?? 0) + 1;
    if (onList != null) return onList!(root, relativePath);
    return directories[key] ?? const WorkspaceDirectorySnapshot([]);
  }

  @override
  Future<WorkspaceTextRead> readWorkspaceText(
    String root,
    String relativePath,
    int maximumBytes,
  ) async {
    final key = '$root/$relativePath';
    readCounts[key] = (readCounts[key] ?? 0) + 1;
    activeReads++;
    if (activeReads > peakReads) peakReads = activeReads;
    try {
      if (issues[key] case final issue?) throw WorkspaceIndexFailure(issue);
      if (onRead != null) return await onRead!(root, relativePath);
      return texts[key]!;
    } finally {
      activeReads--;
    }
  }
}

Future<void> runSearch(
  WorkspaceSearchController search,
  String query, {
  bool refresh = false,
}) async {
  search.search(query, immediate: true, refresh: refresh);
  await search.completion;
}

void main() {
  late FakeIndexSource source;
  late WorkspaceIndex index;
  late WorkspaceSearchController search;
  setUp(() {
    source = FakeIndexSource();
    index = WorkspaceIndex(source: source);
    search = WorkspaceSearchController(index);
  });
  tearDown(() {
    search.dispose();
    index.dispose();
  });

  test(
    'single-file and draft search use buffers; never list the parent',
    () async {
      index.updateBuffer(
        sessionId: 'one',
        path: '/private/notes/one.md',
        name: 'one.md',
        text: 'needle',
      );
      index.updateBuffer(
        sessionId: 'draft',
        path: null,
        name: 'draft',
        text: 'needle',
      );
      await runSearch(search, 'needle');
      expect(search.matchCount, 2);
      expect(source.listCounts, isEmpty);
      expect(source.readCounts, isEmpty);
    },
  );

  test(
    'root-relative catalog refuses traversal and malicious child entries',
    () async {
      index.configure('/vault');
      await expectLater(
        index.directory('../other'),
        throwsA(isA<WorkspaceIndexFailure>()),
      );
      source.directories['/vault/'] = const WorkspaceDirectorySnapshot([
        WorkspaceMetadata(
          relativePath: '../other/private.md',
          isDirectory: false,
          revision: '1',
        ),
      ]);
      await runSearch(search, 'secret');
      expect(search.issues[WorkspaceReadIssue.denied], 1);
      expect(source.readCounts, isEmpty);
      expect(
        () => index.relativeDirectory('/vault2'),
        throwsA(isA<WorkspaceIndexFailure>()),
      );
    },
  );

  test('two consumers share catalog and body in-flight work', () async {
    index.configure('/vault');
    final listing = Completer<WorkspaceDirectorySnapshot>();
    source.onList = (_, _) => listing.future;
    final first = index.directory('');
    final second = index.directory('');
    expect(identical(first, second), isTrue);
    const note = WorkspaceMetadata(
      relativePath: 'a.md',
      isDirectory: false,
      revision: '1',
    );
    listing.complete(const WorkspaceDirectorySnapshot([note]));
    await Future.wait([first, second]);
    final reading = Completer<WorkspaceTextRead>();
    source.onRead = (_, _) => reading.future;
    final a = index.read(note);
    final b = index.read(note);
    expect(identical(a, b), isTrue);
    reading.complete(const WorkspaceTextRead('same', '1'));
    await Future.wait([a, b]);
    expect(source.listCounts['/vault/'], 1);
    expect(source.readCounts['/vault/a.md'], 1);
    expect(index.cachedBytes, 8);
  });

  test(
    'refresh while listing coalesces and does not lose the last invalidation',
    () async {
      index.configure('/vault');
      final first = Completer<WorkspaceDirectorySnapshot>();
      var calls = 0;
      source.onList = (_, _) async => ++calls == 1
          ? await first.future
          : const WorkspaceDirectorySnapshot([
              WorkspaceMetadata(
                relativePath: 'new.md',
                isDirectory: false,
                revision: '2',
              ),
            ]);
      final pending = index.directory('');
      final refreshed = index.directory('', refresh: true);
      index.directory('', refresh: true);
      first.complete(const WorkspaceDirectorySnapshot([]));
      final result = await pending;
      await refreshed;
      expect(calls, 2);
      expect(result.entries.single.relativePath, 'new.md');
    },
  );

  test(
    'root A to B to A rejects old IO without clearing the new singleflight',
    () async {
      final old = Completer<WorkspaceDirectorySnapshot>();
      final fresh = Completer<WorkspaceDirectorySnapshot>();
      var calls = 0;
      source.onList = (_, _) => ++calls == 1 ? old.future : fresh.future;
      index.configure('/vault');
      final a = index.directory('');
      final caught = expectLater(a, throwsA(isA<WorkspaceIndexFailure>()));
      index.configure('/other');
      index.configure('/vault');
      final b = index.directory('');
      old.complete(const WorkspaceDirectorySnapshot([]));
      await caught;
      expect(identical(b, index.directory('')), isTrue);
      fresh.complete(const WorkspaceDirectorySnapshot([]));
      await b;
      expect(calls, 2);
    },
  );

  test(
    'buffers supersede pending disk reads and remain preferred when clean',
    () async {
      index.configure('/vault');
      source.note('a.md', 'disk');
      final read = Completer<WorkspaceTextRead>();
      source.onRead = (_, _) => read.future;
      final pending = index.read(source.directories['/vault/']!.entries.single);
      await Future<void>.delayed(Duration.zero);
      index.updateBuffer(
        sessionId: 'one',
        path: '/vault/a.md',
        name: 'a.md',
        text: 'buffer',
        externalConflict: true,
      );
      read.complete(const WorkspaceTextRead('disk', 'v1'));
      expect((await pending).text, 'buffer');
      await runSearch(search, 'buffer');
      expect(search.results.single.externalConflict, isTrue);
      expect(source.readCounts['/vault/a.md'], 1);
    },
  );

  test(
    'ten dirty revisions update immediately, while cursor and save baselines do not',
    () async {
      final files = MemoryMarkdownFileService()..files['/notes/a.md'] = 'saved';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      await workspace.initialize();
      final document = (await workspace.openPath('/notes/a.md'))!;
      final live = WorkspaceSearchController(workspace.index);
      for (var n = 1; n <= 10; n++) {
        document.controller.text = 'dirty $n';
      }
      expect(workspace.index.bufferForSession(document.id)!.text, 'dirty 10');
      final revision = workspace.index.contentRevision;
      document.controller.selection = const TextSelection.collapsed(offset: 2);
      document.markSaved(savedText: 'dirty 1');
      expect(workspace.index.contentRevision, revision);
      expect(document.controller.isDirty, isTrue);
      await runSearch(live, 'dirty 10');
      expect(live.matchCount, 1);
      live.dispose();
      workspace.dispose();
      await files.dispose();
    },
  );

  test(
    'offline and oversized notes are explicit without any download/read',
    () async {
      index.configure('/vault');
      source.note('online.md', 'needle');
      source.note('cloud.md', 'needle', local: false);
      source.note('large.md', 'needle', size: workspaceTextMaximumBytes + 1);
      source.note('denied.md', 'needle');
      source.issues['/vault/denied.md'] = WorkspaceReadIssue.denied;
      await runSearch(search, 'absent');
      expect(search.partial, isTrue);
      expect(search.matchCount, 0);
      expect(search.scanned, 1);
      expect(search.known, 4);
      expect(
        search.issues.keys,
        containsAll([
          WorkspaceReadIssue.offline,
          WorkspaceReadIssue.oversized,
          WorkspaceReadIssue.denied,
        ]),
      );
      expect(source.readCounts['/vault/cloud.md'], isNull);
      expect(source.readCounts['/vault/large.md'], isNull);
      expect(source.downloads, 0);
    },
  );

  test(
    'partial reconciliation retains old children, never means deletion',
    () async {
      index.configure('/vault');
      source.note('a.md', 'needle');
      await runSearch(search, 'needle');
      source.directories['/vault/'] = const WorkspaceDirectorySnapshot(
        [],
        complete: false,
        reason: 'deadline',
      );
      await runSearch(search, 'needle', refresh: true);
      expect(search.matchCount, 1);
      expect(search.partial, isTrue);
      expect(index.cachedDirectory('')!.entries.single.relativePath, 'a.md');
    },
  );

  test(
    'query cancellation does not publish late IO and cached next query reuses it',
    () async {
      index.configure('/vault');
      source.note('a.md', 'old new');
      final read = Completer<WorkspaceTextRead>();
      source.onRead = (_, _) => read.future;
      search.search('old', immediate: true);
      await Future<void>.delayed(Duration.zero);
      search.search('new', immediate: true);
      read.complete(const WorkspaceTextRead('old new', 'v1'));
      await search.completion;
      expect(search.results.single.range.start, 4);
      expect(search.results.single.query, 'new');
      expect(source.readCounts['/vault/a.md'], 1);
    },
  );

  test(
    'cancel clears running state immediately and old results cannot land',
    () async {
      index.configure('/vault');
      source.note('a.md', 'needle');
      final read = Completer<WorkspaceTextRead>();
      source.onRead = (_, _) => read.future;
      search.search('needle', immediate: true);
      await Future<void>.delayed(Duration.zero);
      search.cancel();
      expect(search.searching, isFalse);
      expect(search.cancelled, isTrue);
      read.complete(const WorkspaceTextRead('needle', 'v1'));
      await search.completion;
      expect(search.results, isEmpty);
    },
  );

  test(
    'click resolution rejects changed buffer revisions and changed disk stamps',
    () async {
      index.updateBuffer(
        sessionId: 'a',
        path: '/vault/a.md',
        name: 'a',
        text: 'needle',
      );
      await runSearch(search, 'needle');
      final hit = search.results.single;
      index.updateBuffer(
        sessionId: 'a',
        path: '/vault/a.md',
        name: 'a',
        text: 'shift needle',
      );
      expect(await search.resolve(hit), isNull);
      index.removeBuffer('a');
      index.configure('/vault');
      source.note('a.md', 'needle');
      await runSearch(search, 'needle');
      final diskHit = search.results.single;
      source.note('a.md', 'shift needle', revision: 'v2');
      expect(await search.resolve(diskHit), isNull);
    },
  );

  test(
    'a disk read overtaken by metadata reconciliation cannot enter the cache',
    () async {
      index.configure('/vault');
      source.note('a.md', 'old');
      final directory = await index.directory('');
      final delayed = Completer<WorkspaceTextRead>();
      source.onRead = (_, _) => delayed.future;
      final pending = index.read(directory.entries.single);
      final caught = expectLater(
        pending,
        throwsA(isA<WorkspaceIndexFailure>()),
      );
      await Future<void>.delayed(Duration.zero);
      source.note('a.md', 'new', revision: 'v2');
      await index.directory('', refresh: true);
      delayed.complete(const WorkspaceTextRead('old', 'v1'));
      await caught;
      expect(index.cachedBytes, 0);
    },
  );

  test(
    'deleted subtrees reject already-running child catalog commits',
    () async {
      index.configure('/vault');
      source.directories['/vault/'] = const WorkspaceDirectorySnapshot([
        WorkspaceMetadata(
          relativePath: 'folder',
          isDirectory: true,
          revision: '1',
        ),
      ]);
      await index.directory('');
      final delayed = Completer<WorkspaceDirectorySnapshot>();
      source.onList = (root, relative) => relative == 'folder'
          ? delayed.future
          : Future.value(const WorkspaceDirectorySnapshot([]));
      final pending = index.directory('folder');
      final caught = expectLater(
        pending,
        throwsA(isA<WorkspaceIndexFailure>()),
      );
      await index.directory('', refresh: true);
      delayed.complete(
        const WorkspaceDirectorySnapshot([
          WorkspaceMetadata(
            relativePath: 'folder/a.md',
            isDirectory: false,
            revision: '1',
          ),
        ]),
      );
      await caught;
      expect(index.cachedDirectory('folder'), isNull);
    },
  );

  test('actual save A plus later B and external C retains indexed B', () async {
    final files = _DelayedSaveFiles()..files['/notes/a.md'] = 'original';
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    await workspace.initialize();
    final document = (await workspace.openPath('/notes/a.md'))!;
    document.controller.text = 'saved A';
    final saving = workspace.saveDocument(document);
    await files.started.future;
    document.controller.text = 'unsaved B';
    files.finish.complete();
    await saving;
    expect(files.files['/notes/a.md'], 'saved A');
    expect(workspace.index.bufferForSession(document.id)!.text, 'unsaved B');
    files.files['/notes/a.md'] = 'external C';
    files.events.add(FileSystemModifyEvent('/notes/a.md', false, true));
    await Future<void>.delayed(Duration.zero);
    expect(document.hasExternalChanges, isTrue);
    expect(workspace.index.bufferForSession(document.id)!.text, 'unsaved B');
    expect(
      workspace.index.bufferForSession(document.id)!.externalConflict,
      isTrue,
    );
    workspace.dispose();
    await files.dispose();
  });

  test(
    'query budget is explicit and snippets stay bounded for long literal hits',
    () async {
      index.updateBuffer(
        sessionId: 'a',
        path: null,
        name: 'draft',
        text: 'x' * 20000,
      );
      await runSearch(search, 'x' * 10000);
      expect(search.matchCount, 2);
      expect(
        search.results.every((result) => result.snippet.length <= 168),
        isTrue,
      );
      await runSearch(search, 'x' * 65537);
      expect(search.partial, isTrue);
      expect(search.error, contains('shorter'));
      expect(search.searching, isFalse);
    },
  );

  test(
    'body LRU stays bounded and read concurrency never exceeds two',
    () async {
      final bounded = WorkspaceIndex(source: source, maximumCacheBytes: 12)
        ..configure('/vault');
      for (var n = 0; n < 8; n++) {
        source.note('$n.md', 'text');
      }
      source.onRead = (root, name) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return source.texts['$root/$name']!;
      };
      await Future.wait(
        source.directories['/vault/']!.entries.map(bounded.read),
      );
      expect(source.peakReads, 2);
      expect(bounded.cachedBytes, lessThanOrEqualTo(12));
      expect(bounded.cachedDocuments, 1);
      bounded.dispose();
    },
  );

  for (final count in [1000, 10000]) {
    test(
      '$count synthetic notes: complete scan, capped display, warm zero body IO',
      () async {
        index.configure('/vault');
        final entries = <WorkspaceMetadata>[];
        for (var n = 0; n < count; n++) {
          entries.add(
            WorkspaceMetadata(
              relativePath: '$n.md',
              isDirectory: false,
              revision: 'v1',
              size: 6,
            ),
          );
          source.texts['/vault/$n.md'] = const WorkspaceTextRead(
            'needle',
            'v1',
          );
        }
        source.directories['/vault/'] = WorkspaceDirectorySnapshot(entries);
        await runSearch(search, 'needle');
        expect(search.scanned, count);
        expect(search.matchCount, count);
        expect(search.results.length, 500);
        expect(search.partial, isFalse);
        expect(search.displayLimited, isTrue);
        expect(source.listCounts['/vault/'], 1);
        expect(source.readCounts.values.fold(0, (a, b) => a + b), count);
        await runSearch(search, 'need');
        expect(source.readCounts.values.fold(0, (a, b) => a + b), count);
        expect(index.cachedBytes, count * 12);
      },
    );
  }

  test(
    'literal UTF-16 scanner agrees with Unicode RegExp across all boundaries',
    () {
      final examples = [
        ('${'x' * 16383}😀KKk\r\ne\u0301é\ufeff', '😀K'),
        ('${'x' * 16383}KKk', 'k'),
        ('${'a' * 16383}ababababab', 'abab'),
        ('${'x' * 16383}${'q' * 20000}', 'q' * 17000),
        ('one\r\ntwo\ufeffe\u0301', 'e\u0301'),
        ('${'x' * 50000}no', 'absent'),
      ];
      for (final (text, query) in examples) {
        for (final matchCase in [true, false]) {
          final scanner = LiteralSourceMatcher(
            text,
            query,
            matchCase: matchCase,
          );
          final ranges = <TextRange>[];
          while (!scanner.complete) {
            ranges.addAll(scanner.next());
          }
          final expected = RegExp(
            RegExp.escape(query),
            unicode: true,
            caseSensitive: matchCase,
          ).allMatches(text).map((m) => TextRange(start: m.start, end: m.end));
          expect(ranges, expected.toList(), reason: '$query case=$matchCase');
        }
      }
    },
  );
}

class _DelayedSaveFiles extends MemoryMarkdownFileService {
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    started.complete();
    await finish.future;
    files[path] = contents;
  }
}
