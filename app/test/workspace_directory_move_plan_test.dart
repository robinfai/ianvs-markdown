import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/services/attachment_resolver.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_move_namespace.dart';
import 'package:linefold/src/services/workspace_move_tree.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';
import 'package:linefold/src/widgets/document_attachment_scope.dart';
import 'package:path/path.dart' as p;

import 'attachment_test_support.dart';
import 'workspace_note_move_plan_test.dart' show MovePlanSource;

WorkspaceMoveTreeSnapshot treeFor(
  MovePlanSource source,
  String path, {
  AttachmentIndex? images,
  List<WorkspaceMoveTreeMember> extra = const [],
  List<WorkspaceMoveTreeIssue> issues = const [],
}) {
  final paths = <String>{
    ...source.folders,
    ...source.files.keys,
    for (final a in images?.entries ?? <AttachmentMetadata>[]) a.relativePath,
  }.where((s) => WorkspaceMoveNamespace.contains(path, s)).toList()..sort();
  final members = <WorkspaceMoveTreeMember>[
    for (var i = 0; i < paths.length; i++)
      WorkspaceMoveTreeMember(
        path: paths[i],
        kind: source.folders.contains(paths[i])
            ? WorkspaceMoveTreeMemberKind.directory
            : source.files.containsKey(paths[i])
            ? WorkspaceMoveTreeMemberKind.note
            : WorkspaceMoveTreeMemberKind.image,
        revision: 'r:${paths[i]}',
        identity: '1:${i + 10}',
        local: !source.offline.contains(paths[i]),
        size:
            images?.entries
                .where((a) => a.relativePath == paths[i])
                .firstOrNull
                ?.size ??
            0,
      ),
    ...extra,
  ];
  return WorkspaceMoveTreeSnapshot(
    root: '/vault',
    sourcePath: path,
    requestId: 'fixture',
    sourceState: WorkspaceMoveTreeSourceState.directory,
    complete: true,
    rootIdentity: '1:1',
    sourceIdentity: members.where((m) => m.path == path).firstOrNull?.identity,
    members: members,
    issues: issues,
    observedEntryCount: members.length,
  );
}

AttachmentIndex images(Iterable<String> paths) => AttachmentIndex([
  for (final path in paths)
    AttachmentMetadata(
      relativePath: path,
      comparisonPath: path.toLowerCase(),
      size: tinyPng.length,
      modified: 1,
      revision: 'r:$path',
    ),
]);

void main() {
  late MovePlanSource source;
  late WorkspaceIndex index;
  late WorkspaceReferenceIndex references;
  setUp(() {
    source = MovePlanSource();
    index = WorkspaceIndex(source: source)..configure('/vault');
    references = WorkspaceReferenceIndex(
      index,
      normalize: (paths) async =>
          paths.map((s) => s.replaceAll('e\u0301', 'é').toLowerCase()).toList(),
    );
  });
  tearDown(() {
    references.dispose();
    index.dispose();
  });
  Future<WorkspaceNoteMovePlan> plan({
    String from = 'a',
    String to = 'dest/a',
    AttachmentIndex? attachments,
    WorkspaceMoveTreeSnapshot? tree,
    Set<String> dirty = const {},
    int maximumFiles = 128,
    int maximumBackupBytes = 32 * 1024 * 1024,
    bool Function()? isCancelled,
  }) async {
    final snapshot = await references.refresh();
    return WorkspaceNoteMovePlanner(
      references,
      maximumFiles: maximumFiles,
      maximumBackupBytes: maximumBackupBytes,
    ).buildDirectory(
      snapshot: snapshot,
      sourcePath: from,
      destinationPath: to,
      dirtySessionIds: dirty,
      tree: tree ?? treeFor(source, from, images: attachments),
      attachments: attachments,
      isCancelled: isCancelled,
    );
  }

  Set<String> codes(WorkspaceNoteMovePlan value) =>
      value.blockers.map((b) => b.code).toSet();
  void complete(WorkspaceNoteMovePlan value) {
    expect(
      value.complete,
      isTrue,
      reason: value.blockers
          .map((b) => '${b.code}:${b.path}:${b.message}')
          .join('\n'),
    );
    expect(value.kind, WorkspaceNoteMovePlanKind.directory);
    expect(value.executionSupported, isTrue);
  }

  test(
    'simultaneous component mapping preserves internal spelling and proves rebuilt graph',
    () async {
      source.note(
        'a/One.md',
        '\ufeff[internal](./nested/Two.md#H "title")\r\n[out](../Outside.md) [[./nested/Two]] [[#self]]',
      );
      source.note(
        'a/nested/Two.md',
        '---\naliases: [Stable]\n---\n[back](../One.md)',
      );
      source.note(
        'Outside.md',
        '[in](a/One.md) [[a/nested/Two#H|Alias]] [[Stable]]',
      );
      source.note('ab/Keep.md', '[sibling](../Outside.md)');
      source.folders.add('dest');
      final before = await references.refresh();
      final result = await plan();
      complete(result);
      expect(result.files, hasLength(3));
      expect(
        result.files.firstWhere((f) => f.path == 'a/One.md').contents,
        '\ufeff[internal](./nested/Two.md#H "title")\r\n[out](../../Outside.md) [[./nested/Two]] [[#self]]',
      );
      expect(
        result.files.firstWhere((f) => f.path == 'a/nested/Two.md').edits,
        isEmpty,
      );
      expect(result.namespace!.map('ab/Keep.md'), 'ab/Keep.md');
      // Independent oracle: build a fresh index against an independently
      // materialized synthetic after tree, not the planner's virtual resolver.
      final afterSource = MovePlanSource();
      final changed = {
        for (final file in result.files) file.path: file.contents,
      };
      for (final e in source.files.entries) {
        afterSource.note(
          result.namespace!.map(e.key),
          changed[e.key] ?? e.value,
        );
      }
      for (final folder in source.folders) {
        afterSource.folders.add(result.namespace!.map(folder));
      }
      final afterIndex = WorkspaceIndex(source: afterSource)
        ..configure('/vault');
      final afterReferences = WorkspaceReferenceIndex(afterIndex);
      addTearDown(afterReferences.dispose);
      addTearDown(afterIndex.dispose);
      final after = await afterReferences.refresh();
      expect(after.complete, isTrue);
      for (final e in before.notes.entries) {
        final relative = p.posix.relative(e.key, from: '/vault');
        final oldEdges = before.edges
            .where((edge) => identical(edge.note, e.value))
            .toList();
        final newNote =
            after.notes['/vault/${result.namespace!.map(relative)}'];
        final newEdges = after.edges
            .where((edge) => identical(edge.note, newNote))
            .toList();
        expect(newEdges.length, oldEdges.length);
        for (var i = 0; i < oldEdges.length; i++) {
          expect(newEdges[i].status, oldEdges[i].status);
          expect(
            newEdges[i].candidatePaths,
            oldEdges[i].candidatePaths.map(result.namespace!.map).toList(),
          );
        }
      }
    },
  );

  test(
    'shared definitions preserve first-wins BOM CRLF and relocated spans',
    () async {
      const input =
          '\ufeff😀 [x][r] [r]\r\n\r\n[r]: a/Note.md?x=%2520#Head "keep"\r\n[r]: Shadow.md\r\n';
      source.note('Origin.md', input);
      source.note('a/Note.md', '# Head');
      source.folders.add('dest');
      final result = await plan();
      complete(result);
      final origin = result.files.firstWhere((f) => f.path == 'Origin.md');
      expect(origin.edits, hasLength(1));
      expect(
        origin.contents,
        input.replaceFirst('a/Note.md', 'dest/a/Note.md'),
      );
    },
  );

  test(
    'empty and image-only directories are represented without dummy text files',
    () async {
      source.folders.addAll(['a', 'dest']);
      final empty = await plan();
      complete(empty);
      expect(empty.files, isEmpty);
      final imageOnly = await plan(attachments: images(['a/picture.png']));
      complete(imageOnly);
      expect(imageOnly.files, isEmpty);
      expect(imageOnly.attachmentRequirements, hasLength(1));
    },
  );

  test(
    'external moved image and internal images preserve real identities',
    () async {
      source.note(
        'a/Note.md',
        '![internal](./photo.png) ![[photo.png]] ![out](../other.png)',
      );
      source.note(
        'Outside.md',
        '![root](/a/photo.png) ![[/a/photo.png|label]]',
      );
      source.folders.add('dest');
      final result = await plan(
        attachments: images(['a/photo.png', 'other.png']),
      );
      complete(result);
      expect(
        result.files.firstWhere((f) => f.path == 'a/Note.md').contents,
        '![internal](./photo.png) ![[photo.png]] ![out](../../other.png)',
      );
      expect(
        result.files.firstWhere((f) => f.path == 'Outside.md').contents,
        '![root](./dest/a/photo.png) ![[/dest/a/photo.png|label]]',
      );
    },
  );

  test(
    'missing image newly resolved through root fallback blocks external unchanged note',
    () async {
      source.folders.addAll(['a', 'dest']);
      source.note('Outside.md', '![future](dest/a/photo.png)');
      final result = await plan(attachments: images(['a/photo.png']));
      expect(codes(result), contains('newResolution'));
      expect(result.complete, isFalse);
    },
  );

  test(
    'image relative preference change is explicitly rewritten to original identity',
    () async {
      source.note('a/Note.md', '![fallback](../photo.png)');
      source.folders.add('dest');
      final result = await plan(
        attachments: images(['photo.png', 'dest/photo.png']),
      );
      complete(result);
      expect(result.files.single.contents, '![fallback](../../photo.png)');
    },
  );

  test(
    'mixed image and link definition has one consistent destination edit',
    () async {
      source.folders.addAll(['a', 'dest']);
      source.note(
        'Outside.md',
        '![image][r] [link][r]\n\n[r]: a/photo.png "title"\n[r]: shadow.png\n',
      );
      final result = await plan(attachments: images(['a/photo.png']));
      complete(result);
      expect(result.files.single.edits, hasLength(1));
      expect(
        result.files.single.contents,
        '![image][r] [link][r]\n\n[r]: ./dest/a/photo.png "title"\n[r]: shadow.png\n',
      );
    },
  );

  test('note absolute paths differ from image vault-root paths', () async {
    source.note('a/Note.md', '# Note');
    source.folders.add('dest');
    source.note(
      'Outside.md',
      '[note](/vault/a/Note.md) ![image](/a/photo.png)',
    );
    final result = await plan(attachments: images(['a/photo.png']));
    complete(result);
    expect(
      result.files.firstWhere((f) => f.path == 'Outside.md').contents,
      '[note](/vault/dest/a/Note.md) ![image](./dest/a/photo.png)',
    );
  });

  test(
    'missing Wiki and Markdown becoming resolved are globally blocked',
    () async {
      source.note('a/Note.md', '# Note');
      source.folders.add('dest');
      source.note('Outside.md', '[[/dest/a/Note]] [future](dest/a/Note.md)');
      expect(codes(await plan()), contains('newResolution'));
    },
  );

  test('unchanged YAML alias dependency must be clean', () async {
    source.note('a/Note.md', '# Note');
    source.folders.add('dest');
    source.note('Alias.md', '---\naliases: [Stable]\n---\n');
    source.note('Outside.md', '[[Stable]]');
    index.updateBuffer(
      sessionId: 'alias',
      path: '/vault/Alias.md',
      name: 'Alias.md',
      text: source.files['Alias.md']!,
    );
    expect(codes(await plan(dirty: {'alias'})), contains('dirty'));
  });

  test('all moved zero-edit notes are dirty checked and budgeted', () async {
    source.note('a/Note.md', 'body');
    source.folders.add('dest');
    index.updateBuffer(
      sessionId: 'open',
      path: '/vault/a/Note.md',
      name: 'Note.md',
      text: 'body',
    );
    final dirty = await plan(dirty: {'open'});
    expect(codes(dirty), contains('dirty'));
    final limited = await plan(maximumFiles: 0);
    expect(codes(limited), contains('transactionBudget'));
    source.offline.add('a/Note.md');
    await references.refresh(refreshMetadata: true);
    expect(codes(await plan()), contains('offline'));
  });

  test(
    'source and destination subtree ghosts cannot authorize a move',
    () async {
      source.folders.addAll(['a', 'dest']);
      index.updateBuffer(
        sessionId: 'sourceGhost',
        path: '/vault/a/Ghost.md',
        name: 'Ghost.md',
        text: 'body',
      );
      index.updateBuffer(
        sessionId: 'destGhost',
        path: '/vault/dest/a/Ghost.md',
        name: 'Ghost.md',
        text: 'body',
      );
      final result = await plan();
      expect(
        codes(result),
        containsAll(['sourceGhost', 'destinationGhost', 'destinationExists']),
      );
    },
  );

  test('normalization collision and normalized overlap fail closed', () async {
    source.note('a/Café.md', 'body');
    source.note('a/Cafe\u0301.md', 'body');
    source.folders.add('dest');
    expect(codes(await plan()), contains('normalizationCollision'));
    expect(codes(await plan(to: 'A/child')), contains('sameIdentitySpelling'));
  });

  test(
    'PDF hidden artifacts and incomplete enumeration remain directory blockers, not missing',
    () async {
      source.folders.addAll(['a', 'dest']);
      final extras = [
        const WorkspaceMoveTreeMember(
          path: 'a/file.pdf',
          kind: WorkspaceMoveTreeMemberKind.unsupported,
          identity: '1:101',
          revision: 'pdf',
          local: true,
        ),
        const WorkspaceMoveTreeMember(
          path: 'a/.hidden',
          kind: WorkspaceMoveTreeMemberKind.unsupported,
          identity: '1:102',
          revision: 'hidden',
          local: true,
        ),
        const WorkspaceMoveTreeMember(
          path: 'a/.linefold-note-move-old',
          kind: WorkspaceMoveTreeMemberKind.unsupported,
          identity: '1:103',
          revision: 'old',
          local: true,
        ),
      ];
      final result = await plan(tree: treeFor(source, 'a', extra: extras));
      expect(
        codes(result),
        containsAll(['unsupportedMember', 'hiddenMember', 'retainedArtifacts']),
      );
      expect(codes(result), isNot(contains('sourceMissing')));
    },
  );

  test(
    'unknown and ambiguous references anywhere block even with no old directory spelling',
    () async {
      source.note('a/Note.md', 'body');
      source.note('one/Dup.md', 'one');
      source.note('two/Dup.md', 'two');
      source.note('Outside.md', '[[Dup]] [opaque](secret.pdf)');
      source.folders.add('dest');
      expect(codes(await plan()), contains('unresolved'));
    },
  );

  test(
    'unsupported image query and missing metadata block rather than guessing',
    () async {
      source.note('a/Note.md', '![x](photo.png?size=1)');
      source.folders.add('dest');
      expect(
        codes(await plan(attachments: images(['a/photo.png']))),
        contains('unresolved'),
      );
      expect(codes(await plan()), contains('unresolved'));
    },
  );

  test(
    'cancellation is cooperative and permanently marks partial proposal incomplete',
    () async {
      source.note('a/Note.md', 'body');
      source.folders.add('dest');
      var checks = 0;
      final result = await plan(isCancelled: () => ++checks > 2);
      expect(codes(result), contains('cancelled'));
      expect(result.complete, isFalse);
    },
  );

  test(
    'directory-only operation and cooperative deadline limits fail closed',
    () async {
      source.note('a/Note.md', '# Note');
      source.folders.add('dest');
      final snapshot = await references.refresh();
      for (final planner in [
        WorkspaceNoteMovePlanner(references, maximumDirectoryOperations: 0),
        WorkspaceNoteMovePlanner(
          references,
          directoryPreviewTimeout: Duration.zero,
        ),
      ]) {
        final result = await planner.buildDirectory(
          snapshot: snapshot,
          sourcePath: 'a',
          destinationPath: 'dest/a',
          dirtySessionIds: {},
          tree: treeFor(source, 'a'),
        );
        expect(result.complete, isFalse);
        expect(
          codes(result).intersection({'planningBudget', 'planningDeadline'}),
          isNotEmpty,
        );
      }
    },
  );

  test(
    'normalization async results are rejected after cancellation or root change',
    () async {
      source.note('a/Café.md', '# Note');
      source.folders.add('dest');
      final snapshot = await references.refresh();
      final tree = treeFor(source, 'a');
      references.dispose();
      var cancelled = false;
      references = WorkspaceReferenceIndex(
        index,
        normalize: (paths) async {
          await Future<void>.delayed(Duration.zero);
          cancelled = true;
          return paths.map((p) => p.toLowerCase()).toList();
        },
      );
      final cancelledPlan = await WorkspaceNoteMovePlanner(references)
          .buildDirectory(
            snapshot: snapshot,
            sourcePath: 'a',
            destinationPath: 'dest/a',
            dirtySessionIds: {},
            tree: tree,
            isCancelled: () => cancelled,
          );
      expect(codes(cancelledPlan), contains('cancelled'));
      references.dispose();
      references = WorkspaceReferenceIndex(
        index,
        normalize: (paths) async {
          await Future<void>.delayed(Duration.zero);
          index.configure('/other');
          return paths.map((p) => p.toLowerCase()).toList();
        },
      );
      final stalePlan = await WorkspaceNoteMovePlanner(references)
          .buildDirectory(
            snapshot: snapshot,
            sourcePath: 'a',
            destinationPath: 'dest/a',
            dirtySessionIds: {},
            tree: tree,
          );
      expect(codes(stalePlan), contains('stale'));
    },
  );

  testWidgets(
    'rewritten percent image targets traverse real renderer URI and repository pipeline',
    (tester) async {
      source.note(
        'Outside.md',
        '![percent](/a/literal%2520.png)\n\n![[/a/literal%20.png]]',
      );
      source.folders.addAll(['a', 'dest']);
      final result = await tester.runAsync(
        () => plan(attachments: images(['a/literal%20.png'])),
      );
      complete(result!);
      final data = result.files.single.contents;
      final rendererSource = FakeAttachmentSource()
        ..files.clear()
        ..files['dest/a/literal%20.png'] = tinyPng;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentAttachmentScope(
              root: '/vault',
              documentPath: '/vault/Outside.md',
              source: rendererSource,
              builder: (_, images) => IanvsMarkdownView(
                data: data,
                imageBuilder: images.image,
                wikiEmbedBuilder: images.wiki,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find.byType(RawImage).evaluate().length == 2) break;
      }
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNWidgets(2));
      expect(
        rendererSource.reads.where((path) => path.endsWith('.png')).toSet(),
        {'dest/a/literal%20.png'},
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
