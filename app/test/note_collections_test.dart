import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/note_collections.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';

import 'support/fakes.dart';
import 'workspace_index_test.dart' show FakeIndexSource;

void main() {
  test(
    'collection filters and numeric sort operate over indexed Markdown',
    () async {
      final source = FakeIndexSource();
      source.note(
        'blog/a.md',
        '---\nstatus: draft\nrank: 10\n---\n# A\n#writing',
      );
      source.note(
        'blog/b.md',
        '---\nstatus: draft\nrank: 2\n---\n# B\n#writing',
      );
      source.note('reading/c.md', '---\nstatus: done\n---\n# C');
      final index = WorkspaceIndex(source: source)..configure('/vault');
      final references = WorkspaceReferenceIndex(index);
      addTearDown(references.dispose);
      addTearDown(index.dispose);
      final snapshot = await references.refresh();
      final rows = collectionNotes(
        snapshot,
        '/vault',
        folder: 'blog',
        tag: 'writing',
        property: 'status',
        equals: 'draft',
        sort: 'rank',
      );
      expect(rows.map((r) => r.relativePath), ['blog/b.md', 'blog/a.md']);
    },
  );

  test('typed property edits preserve body and round-trip metadata types', () {
    const source =
        '---\nstatus: draft\nrank: 2\ndone: false\n---\n# Body\nUnchanged';
    final status = editCollectionProperty(source, 'status', 'published');
    expect(status, endsWith('# Body\nUnchanged'));
    final number = editCollectionProperty(status, 'rank', '10');
    final done = editCollectionProperty(number, 'done', 'true');
    final entries = parseMarkdownFrontMatter(done).entries;
    expect(
      entries.firstWhere((e) => e.key == 'rank').type,
      MarkdownMetadataValueType.number,
    );
    expect(entries.firstWhere((e) => e.key == 'done').value, 'true');
    expect(
      () => editCollectionProperty(source, 'done', 'yes'),
      throwsFormatException,
    );
    expect(
      editCollectionProperty('# Body', 'status', 'idea'),
      '---\nstatus: "idea"\n---\n# Body',
    );
  });

  test(
    'saved collection views survive restart and remain workspace scoped',
    () async {
      final files = MemoryMarkdownFileService();
      final store = MemoryWorkspaceSessionStore();
      final first = WorkspaceController(
        fileService: files,
        sessionStore: store,
      );
      await first.initialize();
      await first.saveCollectionView({
        'name': 'Blog',
        'property': 'status',
        'equals': 'draft',
      });
      first.dispose();
      final restored = WorkspaceController(
        fileService: files,
        sessionStore: store,
      );
      await restored.initialize();
      expect(restored.collectionViews.single['name'], 'Blog');
      await restored.deleteCollectionView('Blog');
      expect(restored.collectionViews, isEmpty);
      restored.dispose();
      files.dispose();
    },
  );
}
