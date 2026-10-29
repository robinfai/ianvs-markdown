import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:linefold/src/widgets/note_collection_dialog.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'wiki_note_navigation_test.dart' show WikiFiles;
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/note_collections.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';

import 'support/fakes.dart';
import 'support/workflow_screenshot.dart';
import 'workspace_index_test.dart' show FakeIndexSource;

void main() {
  test(
    'long property edits use complete values and preserve unchanged YAML',
    () {
      final long = List.filled(1600, 'x').join();
      final source = '---\nsummary: "$long tail" # keep\n---\nBody';
      expect(collectionPropertyEditValue(source, 'summary'), '$long tail');
      expect(editCollectionProperty(source, 'summary', '$long tail'), source);
      final edited = editCollectionProperty(
        source,
        'summary',
        '$long tail edited',
      );
      expect(
        collectionPropertyEditValue(edited, 'summary'),
        '$long tail edited',
      );
      expect(edited, endsWith('---\nBody'));
      final block = '---\nsummary: |\n  $long\n  tail\n---\nBody';
      final full = collectionPropertyEditValue(block, 'summary');
      expect(full, '$long\ntail\n');
      expect(editCollectionProperty(block, 'summary', full), block);
    },
  );

  test(
    'adding properties preserves flow mappings and their original values',
    () {
      for (final raw in [
        '{}',
        '{title: Post}',
        '{title: Post, nested: {x: 1}}',
      ]) {
        final source = '---\n$raw # keep\n---\nBody';
        final edited = editCollectionProperty(source, 'status', 'draft');
        expect(parseMarkdownFrontMatter(edited).hasFrontMatter, isTrue);
        expect(collectionPropertyEditValue(edited, 'status'), 'draft');
        if (raw.contains('Post')) {
          expect(collectionPropertyEditValue(edited, 'title'), 'Post');
        }
        expect(edited, endsWith('# keep\n---\nBody'));
        if (raw.contains('nested')) expect(edited, contains('nested: {x: 1}'));
      }
    },
  );

  testWidgets('table property editing and board dragging persist Markdown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = WikiFiles();
    final longStatus = List.filled(1500, 'x').join();
    final initial = '---\ntitle: Post\nstatus: $longStatus\n---\nBody';
    files.files['/vault/Post.md'] = initial;
    files.directories['/vault'] = [
      const WorkspaceEntry(
        path: '/vault/Post.md',
        name: 'Post.md',
        isDirectory: false,
      ),
    ];
    files.selectedFolder = '/vault';
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          home: Scaffold(
            body: NoteCollectionDialog(
              workspace: workspace,
              onSave: workspace.saveDocument,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await captureWorkflowScreenshot(tester, boundary, 'collection-table');
    final displayedStatus = parseMarkdownFrontMatter(
      initial,
    ).entries.firstWhere((entry) => entry.key == 'status').value;
    await tester.tap(find.text(displayedStatus));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('collection-property-input')),
          )
          .controller!
          .text,
      longStatus,
    );
    await tester.tap(find.text('Save property'));
    await tester.pumpAndSettle();
    expect(files.files['/vault/Post.md'], initial);
    await tester.tap(find.text(displayedStatus));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('collection-property-input')),
      'draft',
    );
    await tester.tap(find.text('Save property'));
    await tester.pumpAndSettle();
    expect(files.files['/vault/Post.md'], contains('draft'));
    expect(files.files['/vault/Post.md'], endsWith('Body'));
    await tester.tap(find.text('board'));
    await tester.pumpAndSettle();
    await captureWorkflowScreenshot(tester, boundary, 'collection-board');
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Post')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.text('published')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(files.files['/vault/Post.md'], contains('published'));
    await tester.tap(find.text('Save view'));
    await tester.pumpAndSettle();
    expect(workspace.collectionViews.single['layout'], 'board');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

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
      final entries = source.directories['/vault/']!.entries;
      source.directories['/vault/'] = const WorkspaceDirectorySnapshot([
        WorkspaceMetadata(relativePath: 'blog', isDirectory: true, revision: 'v1'),
        WorkspaceMetadata(relativePath: 'reading', isDirectory: true, revision: 'v1'),
      ]);
      for (final folder in ['blog', 'reading']) {
        source.directories['/vault/$folder'] = WorkspaceDirectorySnapshot(
          entries.where((entry) => entry.relativePath.startsWith('$folder/')).toList(),
        );
      }
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
