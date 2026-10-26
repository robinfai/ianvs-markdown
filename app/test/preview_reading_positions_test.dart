import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/preview/preview_reading_positions.dart';
import 'package:linefold/src/services/workspace_session_store.dart';
import 'support/fakes.dart';

IanvsMarkdownViewportAnchor anchor(String text, int offset) =>
    IanvsMarkdownViewportAnchor(
      source: text,
      sourceOffset: offset,
      viewportOffset: -9,
    );

void main() {
  test(
    'real persisted positions restore and rebase within distinct roots',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mobile-reading-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = DesktopWorkspaceSessionStore(directory: directory);
      final positions = PreviewReadingPositions(store: store);
      await positions.load();
      positions.remember(
        '/a',
        '/a/note.md',
        anchor('before\nTarget\nafter', 7),
      );
      positions.remember('/b', '/b/note.md', anchor('different', 2));
      await positions.flush();
      positions.dispose();
      final restarted = PreviewReadingPositions(
        store: DesktopWorkspaceSessionStore(directory: directory),
      );
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.lastError, isNull);
      expect(
        restarted
            .lookup('/a', '/a/note.md', 'before\nTarget\nafter')!
            .sourceOffset,
        7,
      );
      expect(
        restarted
            .lookup('/a', '/a/note.md', 'new\nbefore\nTarget\nafter')!
            .sourceOffset,
        11,
      );
      expect(
        restarted
            .lookup('/a', '/a/note.md', 'before\nTarget\nafter')!
            .viewportOffset,
        -9,
      );
      expect(
        restarted.lookup('/b', '/b/note.md', 'different')!.sourceOffset,
        2,
      );
      expect(restarted.lookup('/other', '/a/note.md', 'different'), isNull);
    },
  );

  test(
    'recent entries are bounded and malformed anchors are ignored',
    () async {
      final store = MemoryWorkspaceSessionStore();
      final positions = PreviewReadingPositions(store: store);
      await positions.load();
      for (var i = 0; i < 30; i++) {
        positions.remember('/a', '/a/$i.md', anchor('text', 1));
      }
      await positions.flush();
      expect(positions.lookup('/a', '/a/0.md', 'text'), isNull);
      expect(positions.lookup('/a', '/a/29.md', 'text'), isNotNull);
      final records = store.snapshot!.browserState['readingPositions'] as List;
      expect(records.length, 24);
      records.first['offset'] = -100;
      positions.dispose();
      final restored = PreviewReadingPositions(store: store);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.lookup('/a', '/a/6.md', 'text'), isNull);
      expect(restored.lookup('/a', '/a/29.md', 'text'), isNotNull);
    },
  );

  test(
    'store initialization failure retries and preserves disk plus new positions',
    () async {
      final disk = MemoryWorkspaceSessionStore();
      final seed = PreviewReadingPositions(store: disk);
      await seed.load();
      seed.remember('/a', '/a/old.md', anchor('old text', 2));
      await seed.flush();
      seed.dispose();
      var attempts = 0;
      final positions = PreviewReadingPositions(
        createStore: () {
          if (++attempts == 1) {
            throw const FileSystemException('support directory unavailable');
          }
          return Future.value(disk);
        },
      );
      addTearDown(positions.dispose);
      await positions.load();
      expect(positions.lastError, isNotNull);
      positions.remember('/a', '/a/new.md', anchor('new text', 3));
      await positions.flush();
      expect(attempts, 2);
      expect(positions.lastError, isNull);
      final restored = PreviewReadingPositions(store: disk);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.lookup('/a', '/a/old.md', 'old text')!.sourceOffset, 2);
      expect(restored.lookup('/a', '/a/new.md', 'new text')!.sourceOffset, 3);
    },
  );

  test(
    'failed disk load prevents writes and retries on subsequent flush',
    () async {
      final store = _FailingLoadStore();
      final positions = PreviewReadingPositions(store: store);
      addTearDown(positions.dispose);
      positions.remember('/a', '/a/new.md', anchor('new text', 3));
      await positions.flush();
      expect(store.saves, 0);
      expect(positions.lastError, isNotNull);
      store.fail = false;
      await positions.flush();
      expect(store.loads, 2);
      expect(store.saves, 1);
      expect(positions.lastError, isNull);
    },
  );

  test(
    'dispose drains new positions even before initial load completes',
    () async {
      final store = MemoryWorkspaceSessionStore();
      final positions = PreviewReadingPositions(store: store);
      positions.remember('/a', '/a/new.md', anchor('new text', 3));
      positions.dispose();
      await positions.flush();
      expect(positions.lastError, isNull);
      expect(
        (store.snapshot!.browserState['readingPositions'] as List)
            .single['offset'],
        3,
      );
    },
  );

  test('scroll while loading wins and failed writes can be retried', () async {
    final disk = MemoryWorkspaceSessionStore();
    final old = PreviewReadingPositions(store: disk);
    await old.load();
    old.remember('/a', '/a/a.md', anchor('long text', 1));
    await old.flush();
    old.dispose();
    final delayed = _DelayedStore(disk.snapshot!);
    final positions = PreviewReadingPositions(store: delayed);
    final loading = positions.load();
    positions.remember('/a', '/a/a.md', anchor('long text', 5));
    delayed.ready.complete();
    await loading;
    expect(positions.lookup('/a', '/a/a.md', 'long text')!.sourceOffset, 5);
    await positions.flush();
    expect(positions.lastError, isNotNull);
    delayed.fail = false;
    await positions.flush();
    expect(positions.lastError, isNull);
    expect(
      (delayed.saved!.browserState['readingPositions'] as List)
          .single['offset'],
      5,
    );
    positions.dispose();
  });
}

class _DelayedStore implements WorkspaceSessionStore {
  _DelayedStore(this.snapshot);
  final WorkspaceSnapshot snapshot;
  final ready = Completer<void>();
  bool fail = true;
  WorkspaceSnapshot? saved;
  @override
  Future<WorkspaceSnapshot?> load() async {
    await ready.future;
    return snapshot;
  }

  @override
  Future<void> save(WorkspaceSnapshot value) async {
    if (fail) throw const FileSystemException('write failed');
    saved = value;
  }
}

class _FailingLoadStore extends MemoryWorkspaceSessionStore {
  bool fail = true;
  int loads = 0;
  int saves = 0;
  @override
  Future<WorkspaceSnapshot?> load() async {
    loads++;
    if (fail) throw const FileSystemException('temporarily unavailable');
    return super.load();
  }

  @override
  Future<void> save(WorkspaceSnapshot value) async {
    saves++;
    await super.save(value);
  }
}
