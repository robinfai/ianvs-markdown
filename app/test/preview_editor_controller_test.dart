import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_draft_store.dart';
import 'package:linefold/src/preview/preview_editor_controller.dart';
import 'package:linefold/src/preview/preview_library.dart';

import 'preview_test_support.dart';

void main() {
  late MemoryPreviewLibrary library;
  late MemoryPreviewDraftStore store;
  late PreviewEditorController editor;
  setUp(() async {
    library = MemoryPreviewLibrary();
    store = MemoryPreviewDraftStore();
    editor = PreviewEditorController(library: library, store: store);
    await editor.initialize();
  });
  tearDown(() => editor.dispose());
  Future<void> edit([String text = 'local edit']) async {
    expect(await editor.begin('/vault/note.md'), isTrue);
    editor.source.text = text;
  }

  test(
    'explicit edit and guarded save preserve BOM CRLF emoji and relative attachment source',
    () async {
      const original =
          '\ufeff# Café\r\n- [ ] Task 👩🏽‍💻\r\n![](photos/a%20b.png)\r\n';
      library.files['/vault/note.md'] = original;
      await edit(original.replaceFirst('[ ]', '[x]'));
      expect(editor.dirty, isTrue);
      expect(library.writes, isEmpty);
      expect(
        await editor.save((_) async => PreviewConflictChoice.cancel),
        isTrue,
      );
      expect(library.writes.single.$3, original);
      expect(
        library.files['/vault/note.md'],
        original.replaceFirst('[ ]', '[x]'),
      );
      expect(editor.editing, isFalse);
      expect(store.draft, isNull);
    },
  );

  test(
    'cancel conflict never changes external source and retains local recovery',
    () async {
      await edit();
      library.files['/vault/note.md'] = 'external';
      expect(
        await editor.save((_) async => PreviewConflictChoice.cancel),
        isFalse,
      );
      expect(library.files['/vault/note.md'], 'external');
      expect(store.draft?.text, 'local edit');
      expect(editor.dirty, isTrue);
    },
  );

  test(
    'overwrite approval binds observed bytes and asks again for third version',
    () async {
      await edit();
      library.files['/vault/note.md'] = 'version B';
      final observed = <String?>[];
      expect(
        await editor.save((conflict) async {
          observed.add(conflict.currentContents);
          if (observed.length == 1) {
            library.files['/vault/note.md'] = 'version C';
          }
          return PreviewConflictChoice.overwrite;
        }),
        isTrue,
      );
      expect(observed, ['version B', 'version C']);
      expect(library.writes.map((w) => w.$3).skip(1), [
        'version B',
        'version C',
      ]);
      expect(library.files['/vault/note.md'], 'local edit');
    },
  );

  test(
    'Keep Both exclusively creates a copy and preserves external file',
    () async {
      await edit();
      library.files['/vault/note.md'] = 'external';
      expect(
        await editor.save((_) async => PreviewConflictChoice.keepBoth),
        isTrue,
      );
      expect(library.files['/vault/note.md'], 'external');
      expect(library.creates, hasLength(1));
      expect(library.files[library.creates.single], 'local edit');
      expect(library.writes.last.$3, '');
      expect(editor.path, library.creates.single);
    },
  );

  test(
    'racer occupying Keep Both copy is another conflict, never implicit overwrite',
    () async {
      await edit();
      library.files['/vault/note.md'] = 'external';
      library.beforeWrite = (path, text, expected) async {
        if (path != '/vault/note.md') library.files[path] = 'copy race';
      };
      var prompts = 0;
      expect(
        await editor.save(
          (_) async => ++prompts == 1
              ? PreviewConflictChoice.keepBoth
              : PreviewConflictChoice.cancel,
        ),
        isFalse,
      );
      expect(prompts, 2);
      expect(library.files[library.creates.single], 'copy race');
      expect(editor.dirty, isTrue);
      expect(editor.path, '/vault/note.md');
    },
  );

  test(
    'native pending save blocks discard second save and scope navigation until actual completion',
    () async {
      final preview = PreviewController(library: library);
      addTearDown(preview.dispose);
      await preview.initialize();
      await preview.open('/vault/note.md');
      preview.blocksNavigation = () => editor.editing || editor.busy;
      await edit();
      library.pendingWrite = Completer<void>();
      final saving = editor.save((_) async => PreviewConflictChoice.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(editor.busy, isTrue);
      expect(await editor.discard(), isFalse);
      await preview.receive(['/vault/other.md']);
      await preview.changeWorkspace(useCloud: true);
      preview.showLibrary();
      expect(preview.activePath, '/vault/note.md');
      expect(library.defaultSelections, 1);
      expect(
        await editor.save((_) async => PreviewConflictChoice.cancel),
        isFalse,
      );
      expect(library.writes, hasLength(1));
      library.pendingWrite!.complete();
      expect(await saving, isTrue);
    },
  );

  test(
    'cloud body refresh and queued pre-edit refresh never overwrite source buffer',
    () async {
      final preview = PreviewController(library: library);
      addTearDown(preview.dispose);
      await preview.initialize();
      await preview.open('/vault/note.md');
      preview.blocksNavigation = () => editor.editing || editor.busy;
      await edit();
      library.files['/vault/note.md'] = 'cloud';
      await preview.refresh();
      expect(library.bodyRefreshes, 0);
      expect(editor.source.text, 'local edit');
      expect(preview.contents, isNot('cloud'));
    },
  );

  test(
    'permission/offline failure preserves draft and visible source',
    () async {
      await edit();
      library.writeFailure = true;
      expect(
        await editor.save((_) async => PreviewConflictChoice.cancel),
        isFalse,
      );
      expect(editor.dirty, isTrue);
      expect(store.draft?.text, 'local edit');
      expect(editor.error, contains('未确认'));
      expect(library.files['/vault/note.md'], isNot('local edit'));
    },
  );

  test('scope A B A invalidates editor, even with same final path', () async {
    await edit();
    final original = library.workspace;
    library.workspace = const PreviewWorkspace(
      path: '/other',
      name: 'other',
      isCloud: false,
    );
    library.workspace = original;
    expect(
      await editor.save((_) async => PreviewConflictChoice.overwrite),
      isFalse,
    );
    expect(library.writes, isEmpty);
    expect(editor.source.text, 'local edit');
  });

  test(
    'source changes while save settles remain dirty and persist newer snapshot',
    () async {
      await edit('snapshot A');
      library.pendingWrite = Completer<void>();
      final saving = editor.save((_) async => PreviewConflictChoice.cancel);
      await Future<void>.delayed(Duration.zero);
      editor.source.text = 'newer IME commit';
      library.pendingWrite!.complete();
      expect(await saving, isTrue);
      expect(library.files['/vault/note.md'], 'snapshot A');
      expect(editor.editing, isTrue);
      expect(editor.dirty, isTrue);
      expect(store.draft?.text, 'newer IME commit');
    },
  );

  test(
    'new note rejects paths, hidden names, empty .md and existing destinations',
    () async {
      for (final name in ['../evil', 'a/b', '.hidden', '.md', 'a\\b', 'a:b']) {
        expect(await editor.create(name), isNull, reason: name);
      }
      expect(await editor.create('note.md'), isNull);
      expect(library.creates, isEmpty);
      expect(await editor.create('随手 📝'), '/vault/随手 📝.md');
    },
  );

  test(
    'recovery requires explicit action in same reauthorized root and retains original baseline',
    () async {
      await edit('draft');
      await editor.flushDraft();
      editor.dispose();
      library.files['/vault/note.md'] = 'external after crash';
      editor = PreviewEditorController(library: library, store: store);
      await editor.initialize();
      expect(editor.editing, isFalse);
      expect(editor.canRecover, isTrue);
      expect(await editor.begin('/vault/note.md'), isFalse);
      expect(await editor.begin('/vault/note.md', restore: true), isTrue);
      expect(editor.source.text, 'draft');
      var conflict = false;
      await editor.save((_) async {
        conflict = true;
        return PreviewConflictChoice.cancel;
      });
      expect(conflict, isTrue);
    },
  );

  test(
    'failed draft writes never clear dirty buffer or allow discard',
    () async {
      await edit();
      store.failSave = true;
      expect(await editor.flushDraft(), isFalse);
      expect(await editor.discard(), isFalse);
      expect(editor.dirty, isTrue);
      expect(editor.error, contains('本机'));
    },
  );

  test(
    'isolated reliable draft store survives restart and preserves corrupt original',
    () async {
      final dir = await Directory.systemTemp.createTemp('mobile-recovery-');
      addTearDown(() => dir.delete(recursive: true));
      final reliable = ReliablePreviewDraftStore(directory: dir);
      const draft = PreviewDraft(
        root: '/vault',
        path: '/vault/note.md',
        text: '\ufeffdraft\r\n👩🏽‍💻',
        baseline: '\ufeffbase\r\n',
      );
      await reliable.save(draft);
      expect((await reliable.load())?.text, draft.text);
      final primary = File('${dir.path}/ianvs-markdown/workspace.json');
      await primary.writeAsString('broken');
      final recovered = await reliable.load();
      expect(recovered?.text, draft.text);
      expect(recovered?.notice, isNotNull);
      expect(await primary.readAsString(), 'broken');
      await reliable.save(null);
      expect(await reliable.load(), isNull);
      expect(
        await dir
            .list(recursive: true)
            .where((f) => f.path.endsWith('/original'))
            .length,
        1,
      );
    },
  );
  test(
    'lifecycle flush during initial recovery load cannot erase unseen draft',
    () async {
      editor.dispose();
      store.pendingLoad = Completer<PreviewDraft?>();
      editor = PreviewEditorController(library: library, store: store);
      final loading = editor.initialize();
      expect(await editor.flushDraft(), isFalse);
      expect(store.snapshots, isEmpty);
      const draft = PreviewDraft(
        root: '/old',
        path: '/old/note.md',
        text: 'unseen',
        baseline: 'old',
      );
      store.pendingLoad!.complete(draft);
      await loading;
      expect(editor.recovery, same(draft));
      expect(store.snapshots, isEmpty);
    },
  );

  test(
    'pending pre-edit body refresh cannot replace preview or source after edit begins',
    () async {
      final preview = PreviewController(library: library);
      addTearDown(preview.dispose);
      await preview.initialize();
      await preview.open('/vault/note.md');
      preview.blocksNavigation = () => editor.editing || editor.busy;
      final previous = preview.contents;
      library.pendingRefresh = Completer<String>();
      final refreshing = preview.refresh();
      await edit('IME local');
      library.pendingRefresh!.complete('external cloud');
      await refreshing;
      expect(editor.source.text, 'IME local');
      expect(preview.contents, previous);
    },
  );

  test(
    'serialized recovery snapshots never allow an older write to win',
    () async {
      await edit('first');
      store.pendingSave = Completer<void>();
      final first = editor.flushDraft();
      editor.source.text = 'second';
      final second = editor.flushDraft();
      store.pendingSave!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(store.snapshots.map((d) => d?.text), ['first', 'second']);
      expect(store.draft?.text, 'second');
    },
  );

  test(
    'explicit recovery copy uses only current granted root and keeps old source untouched',
    () async {
      const draft = PreviewDraft(
        root: '/old',
        path: '/old/note.md',
        text: '\ufeffdraft\r\n![](photos/a.png)',
        baseline: 'old',
      );
      editor.recovery = draft;
      expect(editor.canRecover, isFalse);
      expect(library.creates, isEmpty);
      expect(await editor.recoverToNewNote(), isTrue);
      expect(editor.path, startsWith('/vault/Recovered '));
      expect(editor.source.text, draft.text);
      expect(library.writes, isEmpty);
      expect(library.files[editor.path], '');
      expect(
        await editor.save((_) async => PreviewConflictChoice.cancel),
        isTrue,
      );
      expect(library.writes.single.$3, '');
      expect(library.files[editor.path], draft.text);
      expect(library.files.keys, isNot(contains('/old/note.md')));
    },
  );
}
