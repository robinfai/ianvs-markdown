import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/widgets/workspace_sidebar.dart';
import 'package:path/path.dart' as p;

import 'support/fakes.dart';

void main() {
  late _ListedFiles files;
  late WorkspaceController workspace;

  setUp(() async {
    files = _ListedFiles()
      ..files['/vault/readme.md'] = '# Readme'
      ..files['/vault/notes/nested.md'] = '# Nested'
      ..selectedFolder = '/vault';
    workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
  });

  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });

  testWidgets('newly saved document appears without reopening the workspace', (
    tester,
  ) async {
    await _pumpSidebar(tester, workspace);
    expect(find.text('readme.md'), findsOneWidget);
    expect(find.text('File workflow.md'), findsNothing);

    final document = workspace.newDocument();
    document.controller.text = '# Saved from the app';
    files.savePath = '/vault/File workflow.md';
    expect(await workspace.saveDocument(document), isTrue);
    await tester.pumpAndSettle();

    expect(files.files[files.savePath], '# Saved from the app');
    expect(find.text('File workflow.md'), findsOneWidget);
    expect(find.text('readme.md'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('Save As refreshes an expanded folder without collapsing it', (
    tester,
  ) async {
    await _pumpSidebar(tester, workspace);
    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();
    expect(find.text('nested.md'), findsOneWidget);

    final document = (await workspace.openPath('/vault/notes/nested.md'))!;
    files.savePath = '/vault/notes/copy.md';
    expect(
      await tester.runAsync(
        () => workspace.saveDocument(document, saveAs: true),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();

    expect(find.text('copy.md'), findsOneWidget);
    expect(find.text('nested.md'), findsOneWidget);
    expect(files.files['/vault/notes/nested.md'], '# Nested');
    await _finish(tester);
  });

  testWidgets(
    'saved files refresh the current search and retain tree expansion',
    (tester) async {
      await _pumpSidebar(tester, workspace);
      await tester.tap(find.text('notes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workspace-search-field')),
        'draft',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('draft.md'), findsNothing);

      final document = workspace.newDocument();
      document.controller.text = '# Draft';
      files.savePath = '/vault/notes/draft.md';
      expect(await workspace.saveDocument(document), isTrue);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final search = tester.widget<TextField>(
        find.byKey(const ValueKey('workspace-search-field')),
      );
      expect(search.controller!.text, 'draft');
      expect(find.text('draft.md'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('nested.md'), findsOneWidget);
      expect(find.text('draft.md'), findsOneWidget);
      await _finish(tester);
    },
  );

  testWidgets('refresh preserves the file tree scroll offset', (tester) async {
    for (var i = 0; i < 40; i++) {
      files.files['/vault/note-${i.toString().padLeft(2, '0')}.md'] = '# Note';
    }
    await _pumpSidebar(tester, workspace);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    final scrolling = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    final offset = scrolling.position.pixels;
    expect(offset, greaterThan(0));

    final document = workspace.newDocument();
    files.savePath = '/vault/z-last.md';
    expect(await workspace.saveDocument(document), isTrue);
    await tester.pumpAndSettle();

    expect(scrolling.position.pixels, offset);
    await tester.scrollUntilVisible(
      find.text('z-last.md'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('z-last.md'), findsOneWidget);
    await _finish(tester);
  });
}

Future<void> _pumpSidebar(
  WidgetTester tester,
  WorkspaceController workspace,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: AnimatedBuilder(
            animation: workspace,
            builder: (context, _) => WorkspaceSidebar(
              workspace: workspace,
              onError: (error) => fail(error),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 700));
  expect(tester.takeException(), isNull);
}

class _ListedFiles extends MemoryMarkdownFileService {
  @override
  Future<List<WorkspaceEntry>> listDirectory(String path) async {
    final entries = <String, WorkspaceEntry>{};
    for (final file in files.keys) {
      if (!p.isWithin(path, file)) continue;
      final parts = p.split(p.relative(file, from: path));
      final name = parts.first;
      entries[name] = WorkspaceEntry(
        path: p.join(path, name),
        name: name,
        isDirectory: parts.length > 1,
      );
    }
    return entries.values.toList()..sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.name.compareTo(right.name);
    });
  }
}
