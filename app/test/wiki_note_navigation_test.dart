import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/services/wiki_note_resolver.dart';
import 'support/fakes.dart';

class WikiFiles extends MemoryMarkdownFileService
    implements WorkspaceNoteCreator {
  int ordinaryReads = 0;
  int creates = 0;
  bool failCreate = false;
  Future<WorkspaceTextRead> Function(String)? onText;
  @override
  Future<MarkdownFileData> readMarkdownFile(String path) {
    ordinaryReads++;
    return super.readMarkdownFile(path);
  }

  @override
  Future<WorkspaceTextRead> readWorkspaceText(
    String root,
    String path,
    int maximumBytes,
  ) => onText == null
      ? super.readWorkspaceText(root, path, maximumBytes)
      : onText!(path);
  @override
  Future<void> createWorkspaceNote(String root, String path) async {
    creates++;
    if (failCreate) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.denied);
    }
    final full = '$root/$path';
    final parent = full.substring(0, full.lastIndexOf('/'));
    if (!directories.containsKey(parent)) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.missing);
    }
    await createEntry(full, directory: false);
  }
}

class IdentityWikiFiles extends WikiFiles
    implements WorkspacePathIdentitySource {
  final aliases = <String, String>{};
  @override
  Future<MarkdownFileData> readMarkdownFile(String path) async {
    final actual = aliases[path] ?? path;
    final data = await super.readMarkdownFile(actual);
    return MarkdownFileData(
      path: path,
      name: path.split('/').last,
      contents: data.contents,
    );
  }

  @override
  Future<WorkspacePathIdentity> resolveWorkspacePath(
    String root,
    String relativePath,
  ) async {
    final actual = aliases['$root/$relativePath'] ?? '$root/$relativePath';
    if (!files.containsKey(actual)) {
      throw const WorkspaceIndexFailure(WorkspaceReadIssue.missing);
    }
    return WorkspacePathIdentity(
      relativePath: actual.substring(root.length + 1),
      identity: 'inode:$actual',
    );
  }
}

Future<WorkspaceController> wikiWorkspace(WikiFiles files) async {
  files.selectedFolder = '/vault';
  files.directories['/vault'] = [
    for (final path in files.files.keys.where(
      (p) => p.startsWith('/vault/') && !p.substring(7).contains('/'),
    ))
      WorkspaceEntry(
        path: path,
        name: path.split('/').last,
        isDirectory: false,
      ),
  ];
  final workspace = WorkspaceController(
    fileService: files,
    sessionStore: MemoryWorkspaceSessionStore(),
  );
  await workspace.initialize();
  await workspace.chooseWorkspaceFolder();
  await workspace.openPath('/vault/Origin.md');
  return workspace;
}

void main() {
  late WikiFiles files;
  late WorkspaceController workspace;
  setUp(() async {
    files = WikiFiles()
      ..files.addAll({
        '/vault/Origin.md': '[[Target]]',
        '/vault/Target.md': 'disk',
      });
    workspace = await wikiWorkspace(files);
  });
  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });
  test(
    'verified case alias reuses dirty tab without collapsing two real files',
    () async {
      final identityFiles = IdentityWikiFiles()
        ..files.addAll({
          '/vault/Origin.md': '[[Target]]',
          '/vault/Target.md': 'disk',
        });
      identityFiles.aliases['/vault/target.md'] = '/vault/Target.md';
      final w = await wikiWorkspace(identityFiles);
      addTearDown(w.dispose);
      addTearDown(identityFiles.dispose);
      final dirty = (await w.openPath('/vault/target.md'))!;
      dirty.controller.text = 'dirty';
      final result = await WikiNoteResolver(
        w.index,
      ).resolve('Target', originPath: '/vault/Origin.md');
      expect(result.status, WikiNoteStatus.resolved);
      expect(result.candidates.single.sessionId, dirty.id);
      final actual = await w.openIndexedNote(
        'Target.md',
        epoch: w.index.epoch,
        isCurrent: () => true,
      );
      expect(actual, same(dirty));
      expect(actual!.controller.text, 'dirty');
      identityFiles.aliases.clear();
      await identityFiles.createEntry(
        '/vault/target.md',
        directory: false,
        contents: 'distinct',
      );
      await w.index.directory('', refresh: true);
      final twoFiles = await WikiNoteResolver(
        w.index,
      ).resolve('Target', originPath: '/vault/Origin.md');
      expect(twoFiles.status, WikiNoteStatus.ambiguous);
      expect(twoFiles.candidates, hasLength(2));
      final distinct = await w.openIndexedNote(
        'Target.md',
        epoch: w.index.epoch,
        isCurrent: () => true,
      );
      expect(distinct, isNot(same(dirty)));
      expect(dirty.controller.text, 'dirty');
    },
  );
  test(
    'two pre-existing buffers for one inode fail without silently selecting one',
    () async {
      final identityFiles = IdentityWikiFiles()
        ..files.addAll({
          '/vault/Origin.md': '[[Target]]',
          '/vault/Target.md': 'disk',
        });
      identityFiles.aliases['/vault/target.md'] = '/vault/Target.md';
      final w = await wikiWorkspace(identityFiles);
      addTearDown(w.dispose);
      addTearDown(identityFiles.dispose);
      final first = (await w.openPath('/vault/Target.md'))!;
      first.controller.text = 'first buffer';
      final second = (await w.openPath('/vault/target.md'))!;
      second.controller.text = 'second buffer';
      final result = await WikiNoteResolver(
        w.index,
      ).resolve('Target', originPath: '/vault/Origin.md');
      expect(result.status, WikiNoteStatus.unavailable);
      expect(first.controller.text, 'first buffer');
      expect(second.controller.text, 'second buffer');
      expect(w.activeDocument, same(second));
    },
  );
  test(
    'verified NFC alias preserves dirty source while Unicode-distinct files remain separate',
    () async {
      final identityFiles = IdentityWikiFiles()
        ..files.addAll({
          '/vault/Origin.md': '[[Café]]',
          '/vault/Café.md': 'disk',
        });
      identityFiles.aliases['/vault/Cafe\u0301.md'] = '/vault/Café.md';
      final w = await wikiWorkspace(identityFiles);
      addTearDown(w.dispose);
      addTearDown(identityFiles.dispose);
      final dirty = (await w.openPath('/vault/Cafe\u0301.md'))!;
      dirty.controller.text = 'Unicode dirty';
      final resolver = WikiNoteResolver(
        w.index,
        normalize: (paths) async => paths
            .map((p) => p.replaceAll('e\u0301', 'é').toLowerCase())
            .toList(),
      );
      expect(
        (await resolver.resolve('Café', originPath: '/vault/Origin.md')).status,
        WikiNoteStatus.resolved,
      );
      expect(
        await w.openIndexedNote(
          'Café.md',
          epoch: w.index.epoch,
          isCurrent: () => true,
        ),
        same(dirty),
      );
      identityFiles.aliases.clear();
      await identityFiles.createEntry(
        '/vault/Cafe\u0301.md',
        directory: false,
        contents: 'distinct',
      );
      await w.index.directory('', refresh: true);
      expect(
        (await resolver.resolve('Café', originPath: '/vault/Origin.md')).status,
        WikiNoteStatus.ambiguous,
      );
    },
  );
  test(
    'navigation reads scoped snapshot once and subsequent dirty tab wins',
    () async {
      final reads = files.ordinaryReads;
      final target = await workspace.openIndexedNote(
        'Target.md',
        epoch: workspace.index.epoch,
        isCurrent: () => true,
      );
      expect(target!.controller.text, 'disk');
      expect(files.ordinaryReads, reads);
      target.controller.text = 'dirty buffer';
      files.files['/vault/Target.md'] = 'external';
      target.hasExternalChanges = true;
      final again = await workspace.openIndexedNote(
        'Target.md',
        epoch: workspace.index.epoch,
        isCurrent: () => true,
      );
      expect(again, same(target));
      expect(again!.controller.text, 'dirty buffer');
      expect(again.hasExternalChanges, isTrue);
      expect(files.ordinaryReads, reads);
    },
  );
  test(
    'newer tab navigation cancels late read without opening or selecting',
    () async {
      final gate = Completer<WorkspaceTextRead>();
      files.onText = (_) => gate.future;
      var current = true;
      final opening = workspace.openIndexedNote(
        'Target.md',
        epoch: workspace.index.epoch,
        isCurrent: () => current,
      );
      await Future<void>.delayed(Duration.zero);
      current = false;
      gate.complete(const WorkspaceTextRead('disk', 'disk'));
      expect(await opening, isNull);
      expect(workspace.activeDocument!.path, '/vault/Origin.md');
      expect(
        workspace.documents.where((d) => d.path == '/vault/Target.md'),
        isEmpty,
      );
    },
  );
  test(
    'unsafe path stale vault and cancelled create never reach capability',
    () async {
      final epoch = workspace.index.epoch;
      expect(
        await workspace.createWikiNote(
          'New.md',
          epoch: epoch,
          isCurrent: () => false,
        ),
        isFalse,
      );
      expect(
        await workspace.createWikiNote(
          'New.md',
          epoch: epoch - 1,
          isCurrent: () => true,
        ),
        isFalse,
      );
      for (final path in [
        '../outside.md',
        '.hidden.md',
        '/outside.md',
        'sub/../../outside.md',
      ]) {
        await expectLater(
          workspace.createWikiNote(path, epoch: epoch, isCurrent: () => true),
          throwsFormatException,
        );
      }
      expect(files.creates, 0);
    },
  );
  test(
    'explicit exclusive create preserves all source and follows guarded editing flow',
    () async {
      final origin = workspace.activeDocument!;
      origin.controller.text = 'dirty [[New]]';
      final epoch = workspace.index.epoch;
      expect(
        await workspace.createWikiNote(
          'New.md',
          epoch: epoch,
          isCurrent: () => true,
        ),
        isTrue,
      );
      expect(files.files['/vault/New.md'], '');
      expect(origin.controller.text, 'dirty [[New]]');
      expect(origin.controller.isDirty, isTrue);
      final target = await workspace.openIndexedNote(
        'New.md',
        epoch: epoch,
        isCurrent: () => true,
      );
      expect(target!.controller.isDirty, isFalse);
      target.controller.text = 'new content';
      expect(await workspace.saveDocument(target), isTrue);
      expect(files.files['/vault/New.md'], 'new content');
    },
  );
  test(
    'collision failure and missing parent do not overwrite or create parents',
    () async {
      final epoch = workspace.index.epoch;
      await expectLater(
        workspace.createWikiNote(
          'Target.md',
          epoch: epoch,
          isCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(files.files['/vault/Target.md'], 'disk');
      await expectLater(
        workspace.createWikiNote(
          'missing/New.md',
          epoch: epoch,
          isCurrent: () => true,
        ),
        throwsA(isA<WorkspaceIndexFailure>()),
      );
      expect(files.directories, isNot(contains('/vault/missing')));
      files.failCreate = true;
      await expectLater(
        workspace.createWikiNote(
          'Denied.md',
          epoch: epoch,
          isCurrent: () => true,
        ),
        throwsA(isA<WorkspaceIndexFailure>()),
      );
      expect(files.files, isNot(contains('/vault/Denied.md')));
    },
  );
  test(
    'offline scoped read never falls back to ordinary downloading reader',
    () async {
      final ordinary = files.ordinaryReads;
      files.onText = (_) async =>
          throw const WorkspaceIndexFailure(WorkspaceReadIssue.offline);
      await expectLater(
        workspace.openIndexedNote(
          'Target.md',
          epoch: workspace.index.epoch,
          isCurrent: () => true,
        ),
        throwsA(isA<WorkspaceIndexFailure>()),
      );
      expect(files.ordinaryReads, ordinary);
    },
  );
}
