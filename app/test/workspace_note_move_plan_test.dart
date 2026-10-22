import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/attachment_resolver.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';
import 'package:path/path.dart' as p;

class MovePlanSource implements WorkspaceIndexSource {
  final files = <String, String>{};
  final folders = <String>{};
  final offline = <String>{};
  int reads = 0;
  void note(String path, String text) {
    files[path] = text;
    var parent = p.posix.dirname(path);
    while (parent != '.') {
      folders.add(parent);
      parent = p.posix.dirname(parent);
    }
  }

  @override
  Future<WorkspaceDirectorySnapshot> listWorkspaceDirectory(
    String root,
    String relativePath,
  ) async => WorkspaceDirectorySnapshot([
    for (final path in {...files.keys, ...folders})
      if (p.posix.dirname(path) == (relativePath.isEmpty ? '.' : relativePath))
        WorkspaceMetadata(
          relativePath: path,
          isDirectory: folders.contains(path),
          revision: 'r:$path',
          local: !offline.contains(path),
        ),
  ]);

  @override
  Future<WorkspaceTextRead> readWorkspaceText(
    String root,
    String relativePath,
    int maximumBytes,
  ) async {
    reads++;
    return WorkspaceTextRead(files[relativePath]!, 'r:$relativePath');
  }
}

void main() {
  late MovePlanSource source;
  late WorkspaceIndex index;
  late WorkspaceReferenceIndex references;
  setUp(() {
    source = MovePlanSource();
    index = WorkspaceIndex(source: source)..configure('/vault');
    references = WorkspaceReferenceIndex(index);
  });
  tearDown(() {
    references.dispose();
    index.dispose();
  });
  Future<WorkspaceNoteMovePlan> plan(
    String from,
    String to, {
    Set<String> dirty = const {},
    AttachmentIndex? attachments,
    int maximumFiles = 128,
    int maximumBackupBytes = 32 * 1024 * 1024,
  }) async =>
      WorkspaceNoteMovePlanner(
        references,
        maximumFiles: maximumFiles,
        maximumBackupBytes: maximumBackupBytes,
      ).build(
        snapshot: await references.refresh(),
        sourcePath: from,
        destinationPath: to,
        dirtySessionIds: dirty,
        attachments: attachments,
      );
  Set<String> codes(WorkspaceNoteMovePlan plan) =>
      plan.blockers.map((b) => b.code).toSet();

  test(
    'rename preserves BOM CRLF alias fragment title and untouched percent spelling',
    () async {
      const input =
          '\ufeff😀 [one](<Old%20Name.md?mode=%2520#Head%20one> "keep title")\r\n[[Old Name#Section|Alias]]\r\n';
      source.note('Origin.md', input);
      source.note('Old Name.md', '# Head');
      final result = await plan('Old Name.md', 'New (Name)%20.md');
      expect(result.complete, isTrue, reason: codes(result).toString());
      expect(result.files, hasLength(2));
      expect(result.editCount, 2);
      expect(
        result.files.firstWhere((f) => f.path == 'Origin.md').contents,
        '\ufeff😀 [one](<New%20%28Name%29%2520.md?mode=%2520#Head%20one> "keep title")\r\n[[/New (Name)%20#Section|Alias]]\r\n',
      );
      expect(source.files['Origin.md'], input);
      expect(source.files.containsKey('New (Name)%20.md'), isFalse);
    },
  );

  test(
    'shared first-wins definition is edited once and shadow definition is untouched',
    () async {
      const input =
          '[x][r] ![y][r] [r]\n\n[r]: Old.md#h "title"\n[r]: Shadow.md\n';
      source.note('Origin.md', input);
      source.note('Old.md', 'body');
      final result = await plan('Old.md', 'New.md');
      expect(result.complete, isTrue, reason: codes(result).toString());
      final origin = result.files.firstWhere((f) => f.path == 'Origin.md');
      expect(origin.edits, hasLength(1));
      expect(origin.contents, input.replaceFirst('Old.md', 'New.md'));
    },
  );

  test(
    'move rewrites incoming and the moved note own relative outgoing links',
    () async {
      source.note('a/Old.md', '[out](../Other.md#h) [[./Sibling]] [[#self]]');
      source.note('a/Sibling.md', 'body');
      source.note('Other.md', '[in](a/Old.md)');
      source.folders.add('b');
      final result = await plan('a/Old.md', 'b/New.md');
      expect(result.complete, isTrue, reason: codes(result).toString());
      expect(
        result.files.firstWhere((f) => f.path == 'a/Old.md').contents,
        '[out](../Other.md#h) [[/a/Sibling]] [[#self]]',
      );
      expect(
        result.files.firstWhere((f) => f.path == 'Other.md').contents,
        '[in](b/New.md)',
      );
    },
  );

  test(
    'a new bare Wiki ambiguity is disambiguated for the original other target',
    () async {
      source.note('Old.md', 'body');
      source.note('elsewhere/New.md', 'body');
      source.note('Origin.md', '[[New#h|label]] [[Old]]');
      final result = await plan('Old.md', 'New.md');
      expect(result.complete, isTrue, reason: codes(result).toString());
      expect(
        result.files.firstWhere((f) => f.path == 'Origin.md').contents,
        '[[/elsewhere/New#h|label]] [[/New]]',
      );
    },
  );

  test('unchanged alias target remains byte-for-byte unchanged', () async {
    source.note('Old.md', '---\naliases: [Stable]\n---\nbody');
    source.note('Origin.md', '[[Stable#h|label]]');
    final result = await plan('Old.md', 'New.md');
    expect(result.complete, isTrue, reason: codes(result).toString());
    expect(result.files, hasLength(1));
    expect(result.editCount, 0);
  });

  test(
    'previously missing Wiki newly resolving blocks instead of silent semantic change',
    () async {
      source.note('Old.md', 'body');
      source.note('Origin.md', '[[New]]');
      final result = await plan('Old.md', 'New.md');
      expect(codes(result), contains('newWikiResolution'));
    },
  );

  test('previously missing Markdown newly resolving blocks', () async {
    source.note('Old.md', 'body');
    source.note('Origin.md', '[future](New.md) [root](/vault/New.md)');
    final result = await plan('Old.md', 'New.md');
    expect(codes(result), contains('newMarkdownResolution'));
    expect(result.complete, isFalse);
  });

  test(
    'moving origin cannot make missing Markdown resolve elsewhere',
    () async {
      source.note('a/Old.md', '[missing](Target.md)');
      source.note('b/Target.md', 'body');
      final result = await plan('a/Old.md', 'b/Old.md');
      expect(codes(result), contains('newMarkdownResolution'));
    },
  );

  for (final offlinePath in ['Old.md', 'Origin.md']) {
    test('clean buffer cannot hide offline affected $offlinePath', () async {
      source.note('Old.md', 'body');
      source.note('Origin.md', '[[Old]]');
      source.offline.add(offlinePath);
      index.updateBuffer(
        sessionId: 'clean',
        path: '/vault/$offlinePath',
        name: offlinePath,
        text: source.files[offlinePath]!,
      );
      final result = await plan('Old.md', 'New.md');
      expect(codes(result), contains('offline'));
      expect(result.complete, isFalse);
    });
  }

  test(
    'open missing destination buffer reserves its canonical identity',
    () async {
      source.note('Old.md', 'body');
      source.note('Origin.md', '[[Old]]');
      index.updateBuffer(
        sessionId: 'deleted',
        path: '/vault/New.md',
        name: 'New.md',
        text: 'unsaved changes after deletion',
      );
      final result = await plan('Old.md', 'New.md', dirty: {'deleted'});
      expect(codes(result), contains('destinationExists'));
      expect(codes(result), contains('wikiResolution'));
      expect(result.complete, isFalse);
    },
  );

  test(
    'extension conversion cannot silently activate new Wiki aliases',
    () async {
      source.note('Old.txt', '---\naliases: [Stable]\n---\nbody');
      source.note('Origin.md', '[[Stable]]');
      final result = await plan('Old.txt', 'New.md');
      expect(codes(result), contains('extensionChange'));
      expect(result.complete, isFalse);
    },
  );

  test(
    'dirty affected buffer or clean conflicted buffer blocks but unrelated dirty buffer does not',
    () async {
      source.note('Old.md', 'body');
      source.note('Origin.md', '[[Old]]');
      index.updateBuffer(
        sessionId: 'affected',
        path: '/vault/Origin.md',
        name: 'Origin.md',
        text: '[[Old]]',
      );
      var result = await plan('Old.md', 'New.md', dirty: {'affected'});
      expect(codes(result), contains('dirty'));
      index.removeBuffer('affected');
      index.updateBuffer(
        sessionId: 'other',
        path: '/vault/Other.md',
        name: 'Other.md',
        text: 'plain',
      );
      result = await plan('Old.md', 'New.md', dirty: {'other'});
      expect(result.complete, isTrue, reason: codes(result).toString());
      index.updateBuffer(
        sessionId: 'moving',
        path: '/vault/Old.md',
        name: 'Old.md',
        text: 'body',
        externalConflict: true,
      );
      result = await plan('Old.md', 'New.md');
      expect(codes(result), contains('dirty'));
    },
  );

  test(
    'offline unsupported unknown and ambiguous coverage never authorizes maintenance',
    () async {
      source.note('Old.md', 'body');
      source.note('Cloud.md', '[[Old]]');
      source.offline.add('Cloud.md');
      var result = await plan('Old.md', 'New.md');
      expect(codes(result), contains('incomplete'));
      expect(source.reads, 1);
      source.offline.clear();
      source.note('Cloud.md', '<span>[[Old]]</span>');
      index.configure('/other');
      index.configure('/vault');
      result = await plan('Old.md', 'New.md');
      expect(codes(result), contains('incomplete'));
    },
  );

  test(
    'folder, case-only, occupied, hidden and missing-parent requests are blocked',
    () async {
      source.note('a/Old.md', 'body');
      source.note('New.md', 'body');
      expect(codes(await plan('a', 'b')), contains('singleNoteOnly'));
      expect(
        codes(await plan('a/Old.md', 'a/old.md')),
        contains('sameIdentitySpelling'),
      );
      expect(
        codes(await plan('a/Old.md', 'NEW.md')),
        contains('destinationExists'),
      );
      expect(
        codes(await plan('a/Old.md', '.private/New.md')),
        contains('scope'),
      );
      expect(
        codes(await plan('a/Old.md', 'missing/New.md')),
        contains('destinationParent'),
      );
    },
  );

  test(
    'move preserves attachment resolution, percent filenames and Wiki embed alias',
    () async {
      source.note(
        'a/Old.md',
        '![x](../assets/A%2520B.png#h) ![[./photo.png|200]]',
      );
      source.folders.add('b');
      final assets = AttachmentIndex([
        const AttachmentMetadata(
          relativePath: 'assets/A%20B.png',
          comparisonPath: 'assets/a%20b.png',
          size: 1,
          modified: 0,
          revision: 'image1',
        ),
        const AttachmentMetadata(
          relativePath: 'a/photo.png',
          comparisonPath: 'a/photo.png',
          size: 1,
          modified: 0,
          revision: 'image2',
        ),
      ]);
      final result = await plan('a/Old.md', 'b/New.md', attachments: assets);
      expect(result.complete, isTrue, reason: codes(result).toString());
      expect(
        result.files.single.contents,
        '![x](../assets/A%2520B.png#h) ![[/a/photo.png|200]]',
      );
      expect(result.attachmentRequirements, hasLength(2));
      expect(source.reads, 1);
    },
  );

  test(
    'moving unknown assets is incomplete; same-folder rename leaves them alone',
    () async {
      source.note('Old.md', '[manual](manual.pdf) ![photo](photo.png)');
      source.folders.add('b');
      expect(
        codes(await plan('Old.md', 'b/New.md')),
        contains('assetCoverage'),
      );
      final rename = await plan('Old.md', 'New.md');
      expect(rename.complete, isTrue, reason: codes(rename).toString());
      expect(rename.files.single.contents, source.files['Old.md']);
    },
  );

  test('bounded recovery planning retains explicit incomplete state', () async {
    source.note('Old.md', 'body');
    source.note('Origin.md', '[[Old]]');
    expect(
      codes(await plan('Old.md', 'New.md', maximumFiles: 1)),
      contains('transactionBudget'),
    );
    expect(
      codes(await plan('Old.md', 'New.md', maximumBackupBytes: 1)),
      contains('transactionBudget'),
    );
  });

  test('snapshot and plan become stale on content or scope changes', () async {
    source.note('Old.md', 'body');
    final result = await plan('Old.md', 'New.md');
    expect(result.isCurrent(index), isTrue);
    index.updateBuffer(
      sessionId: 'edit',
      path: '/vault/Old.md',
      name: 'Old.md',
      text: 'new',
    );
    expect(result.isCurrent(index), isFalse);
    final stale = await WorkspaceNoteMovePlanner(references).build(
      snapshot: result.snapshot,
      sourcePath: 'Old.md',
      destinationPath: 'New.md',
      dirtySessionIds: {},
    );
    expect(codes(stale), contains('stale'));
    index.configure('/other');
    expect(result.isCurrent(index), isFalse);
  });
  test(
    'table cell rewrites preserve escaped pipe aliases and code cells',
    () async {
      const input =
          '| [x](A\\|B.md#h) | [[A\\|B\\|Label]] | `[[A\\|B]]` |\n| --- | --- | --- |';
      source.note('Origin.md', input);
      source.note('A|B.md', 'body');
      source.note('A.md', 'body');
      final result = await plan('A|B.md', 'New.md');
      expect(result.complete, isTrue, reason: codes(result).toString());
      expect(
        result.files.firstWhere((f) => f.path == 'Origin.md').contents,
        '| [x](New.md#h) | [[A\\|B\\|Label]] | `[[A\\|B]]` |\n| --- | --- | --- |',
      );
    },
  );

  test(
    'Markdown new pipe and reserved characters are percent serialized once',
    () async {
      source.note('Origin.md', '[x](Old.md#keep%2520)');
      source.note('Old.md', 'body');
      final result = await plan('Old.md', 'A|B?#%.md');
      expect(result.complete, isTrue, reason: codes(result).toString());
      expect(
        result.files.firstWhere((f) => f.path == 'Origin.md').contents,
        '[x](A%7CB%3F%23%25.md#keep%2520)',
      );
    },
  );

  test(
    'unrepresentable new Wiki path blocks instead of corrupting syntax',
    () async {
      source.note('Origin.md', '[[Old#h|label]]');
      source.note('Old.md', 'body');
      final result = await plan('Old.md', 'New#part.md');
      expect(codes(result), contains('wikiSpelling'));
    },
  );

  test(
    'independent new basename collision cannot silently rewrite a dirty note',
    () async {
      source.note('Old.md', 'body');
      source.note('nested/New.md', 'body');
      source.note('Origin.md', '[[New]]');
      index.updateBuffer(
        sessionId: 'dirty',
        path: '/vault/Origin.md',
        name: 'Origin.md',
        text: '[[New]] changed',
      );
      final result = await plan('Old.md', 'New.md', dirty: {'dirty'});
      expect(codes(result), contains('dirty'));
    },
  );

  test(
    'missing attachment revision blocks native preflight eligibility',
    () async {
      source.note('Old.md', '![x](photo.png)');
      source.folders.add('nested');
      final result = await plan(
        'Old.md',
        'nested/New.md',
        attachments: AttachmentIndex([
          const AttachmentMetadata(
            relativePath: 'photo.png',
            comparisonPath: 'photo.png',
            size: 1,
            modified: 0,
          ),
        ]),
      );
      expect(codes(result), contains('assetRevision'));
    },
  );
}
