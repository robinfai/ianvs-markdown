import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/wiki_note_resolver.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_index_source.dart';

class WikiCatalogSource implements WorkspaceIndexSource {
  final directories = <String, WorkspaceDirectorySnapshot>{};
  int lists = 0;
  int reads = 0;
  Future<WorkspaceDirectorySnapshot> Function(String path)? onList;
  @override
  Future<WorkspaceDirectorySnapshot> listWorkspaceDirectory(
    String root,
    String relativePath,
  ) async {
    lists++;
    return onList == null
        ? directories[relativePath] ?? const WorkspaceDirectorySnapshot([])
        : onList!(relativePath);
  }

  @override
  Future<WorkspaceTextRead> readWorkspaceText(
    String root,
    String relativePath,
    int maximumBytes,
  ) async {
    reads++;
    return const WorkspaceTextRead('body', '1');
  }
}

WorkspaceMetadata note(String path, {bool local = true, String? key}) =>
    WorkspaceMetadata(
      relativePath: path,
      isDirectory: false,
      revision: '1',
      local: local,
      comparisonPath: key,
    );
WorkspaceMetadata folder(String path) =>
    WorkspaceMetadata(relativePath: path, isDirectory: true, revision: '1');

void main() {
  late WikiCatalogSource source;
  late WorkspaceIndex index;
  late WikiNoteResolver resolver;
  setUp(() {
    source = WikiCatalogSource()
      ..directories[''] = WorkspaceDirectorySnapshot([
        note('Root.md'),
        folder('notes'),
        folder('archive'),
        folder('other'),
      ])
      ..directories['notes'] = WorkspaceDirectorySnapshot([
        note('notes/Origin.md'),
        note('notes/Unique.md'),
        note('notes/Duplicate.md'),
      ])
      ..directories['archive'] = WorkspaceDirectorySnapshot([
        note('archive/Duplicate.md'),
        folder('archive/notes'),
      ])
      ..directories['archive/notes'] = WorkspaceDirectorySnapshot([
        note('archive/notes/Shadow.md'),
      ])
      ..directories['other'] = const WorkspaceDirectorySnapshot([]);
    index = WorkspaceIndex(source: source)..configure('/vault');
    resolver = WikiNoteResolver(
      index,
      normalize: (values) async => values
          .map((s) => s.replaceAll('e\u0301', 'é').toLowerCase())
          .toList(),
    );
  });
  tearDown(() => index.dispose());
  Future<WikiNoteResolution> resolve(
    String target, {
    String? origin = '/vault/notes/Origin.md',
  }) => resolver.resolve(target, originPath: origin);

  test(
    'bare unique, optional md, full root path and relative resolve',
    () async {
      for (final target in [
        'Unique',
        'Unique.md',
        'notes/Unique',
        '/notes/Unique.md',
        './Unique',
        '../notes/Unique',
      ]) {
        final result = await resolve(target);
        expect(result.status, WikiNoteStatus.resolved, reason: target);
        expect(result.candidates.single.relativePath, 'notes/Unique.md');
      }
      expect(source.reads, 0);
      expect(
        source.lists,
        5,
        reason: 'All consumers reuse the one directory catalog',
      );
    },
  );
  test(
    'duplicate basenames are never silently ranked by origin proximity',
    () async {
      final result = await resolve('Duplicate');
      expect(result.status, WikiNoteStatus.ambiguous);
      expect(result.candidates.map((c) => c.relativePath), [
        'archive/Duplicate.md',
        'notes/Duplicate.md',
      ]);
      expect(
        (await resolve('/notes/Duplicate')).status,
        WikiNoteStatus.resolved,
      );
    },
  );
  test('root explicit missing never suffix falls back', () async {
    for (final target in ['/notes/Shadow', 'notes/Shadow']) {
      final result = await resolve(target);
      expect(result.status, WikiNoteStatus.missing);
      expect(result.createPath, 'notes/Shadow.md');
    }
    expect(
      (await resolve('Shadow')).candidates.single.relativePath,
      'archive/notes/Shadow.md',
    );
  });
  test(
    'canonical case collision remains ambiguous even with exact spelling',
    () async {
      source.directories['other'] = WorkspaceDirectorySnapshot([
        note('other/Foo.md'),
        note('other/foo.md'),
      ]);
      final result = await resolve('/other/Foo.md');
      expect(result.status, WikiNoteStatus.ambiguous);
      expect(result.candidates.length, 2);
    },
  );
  test(
    'NFC lookup preserves source spelling and colliding identities',
    () async {
      source.directories['other'] = WorkspaceDirectorySnapshot([
        note('other/Cafe\u0301.md'),
      ]);
      expect(
        (await resolve('/other/Café')).candidates.single.relativePath,
        'other/Cafe\u0301.md',
      );
      source.directories['other'] = WorkspaceDirectorySnapshot([
        note('other/Cafe\u0301.md'),
        note('other/Café.md'),
      ]);
      await index.directory('other', refresh: true);
      expect((await resolve('/other/Café')).status, WikiNoteStatus.ambiguous);
    },
  );
  test(
    'Wiki percent sequences are literal filenames, not URL decoded',
    () async {
      source.directories['other'] = WorkspaceDirectorySnapshot([
        note('other/100%20.md'),
        note('other/100 .md'),
      ]);
      expect(
        (await resolve('/other/100%20')).candidates.single.relativePath,
        'other/100%20.md',
      );
    },
  );
  test(
    'CJK emoji names and dot-bearing titles remain ordinary note names',
    () async {
      source.directories['other'] = WorkspaceDirectorySnapshot([
        note('other/中文😀.v2.md'),
      ]);
      expect(
        (await resolve('中文😀.v2')).candidates.single.relativePath,
        'other/中文😀.v2.md',
      );
    },
  );
  test('unavailable partial catalog cannot prove missing or unique', () async {
    source.directories['other'] = const WorkspaceDirectorySnapshot(
      [],
      complete: false,
      reason: 'offline',
    );
    for (final target in ['Missing', 'Unique']) {
      final result = await resolve(target);
      expect(result.status, WikiNoteStatus.unavailable);
      expect(result.createPath, isNull);
    }
  });
  test(
    'listing error remains unknown even when previous metadata exists',
    () async {
      await index.catalog();
      source.onList = (_) async =>
          throw const WorkspaceIndexFailure(WorkspaceReadIssue.denied);
      final result = await resolver.resolve(
        'Missing',
        originPath: '/vault/notes/Origin.md',
        refresh: true,
      );
      expect(result.status, WikiNoteStatus.unavailable);
      expect(index.catalogSnapshot.complete, isFalse);
    },
  );
  test(
    'standalone paths and drafts never enumerate parent or operation grants',
    () async {
      for (final origin in [null, '/outside/Origin.md']) {
        expect(
          (await resolve('Missing', origin: origin)).status,
          WikiNoteStatus.unavailable,
        );
      }
      index.configure(null);
      expect((await resolve('Missing')).status, WikiNoteStatus.unavailable);
      expect(source.lists, 0);
    },
  );
  test(
    'unsafe destinations and fragments explicitly unavailable without IO',
    () async {
      for (final target in [
        '../..//secret',
        '../../secret',
        '.hidden/a',
        '/.obsidian/config',
        'file:///secret',
        'a\\b',
        'a\u0000b',
        'a|alias',
        'a[bad]',
        '#Heading',
        'Root#^block',
      ]) {
        expect(
          (await resolve(target)).status,
          WikiNoteStatus.unsupported,
          reason: target,
        );
      }
      expect(source.lists, 0);
    },
  );
  test(
    'missing parent cannot be automatically created and case parent resolves',
    () async {
      expect((await resolve('/new/folder/note')).createPath, isNull);
      expect((await resolve('/NOTES/new')).createPath, 'notes/new.md');
      expect((await resolve('new')).createPath, 'new.md');
      expect((await resolve('./new')).createPath, 'notes/new.md');
    },
  );
  test(
    'open buffer wins metadata including externally deleted dirty note',
    () async {
      index.updateBuffer(
        sessionId: 'open',
        path: '/vault/notes/Unique.md',
        name: 'Unique.md',
        text: 'new unsaved',
      );
      final found = await resolve('Unique');
      expect(found.candidates.single.sessionId, 'open');
      index.updateBuffer(
        sessionId: 'deleted',
        path: '/vault/notes/Deleted.md',
        name: 'Deleted.md',
        text: 'dirty',
      );
      expect((await resolve('Deleted')).candidates.single.sessionId, 'deleted');
      index.updateBuffer(
        sessionId: 'external',
        path: '/outside/External.md',
        name: 'External.md',
        text: 'secret',
      );
      expect((await resolve('External')).status, WikiNoteStatus.missing);
    },
  );
  test('late catalog result cannot resolve into a different vault', () async {
    final gate = Completer<WorkspaceDirectorySnapshot>();
    source.onList = (_) => gate.future;
    final result = resolve('Root');
    index.configure('/different');
    gate.complete(const WorkspaceDirectorySnapshot([]));
    expect((await result).status, WikiNoteStatus.unavailable);
  });
  test(
    'catalog snapshot hydrates existing tree/search cache and invalidations',
    () async {
      await index.directory('');
      await index.directory('notes');
      expect(index.catalogSnapshot.complete, isFalse);
      await index.catalog();
      expect(index.catalogSnapshot.complete, isTrue);
      final lists = source.lists;
      await index.catalog();
      expect(source.lists, lists);
      source.directories['notes'] = const WorkspaceDirectorySnapshot([]);
      await index.directory('notes', refresh: true);
      expect((await resolve('Unique')).status, WikiNoteStatus.missing);
    },
  );
}
