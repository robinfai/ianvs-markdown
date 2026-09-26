import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/widgets/middle_ellipsis_text.dart';
import 'package:linefold/src/widgets/workspace_sidebar.dart';

import 'support/fakes.dart';

void main() {
  late _TrackedFiles files;
  late MemoryWorkspaceSessionStore sessions;
  late WorkspaceController workspace;

  setUp(() async {
    files = _TrackedFiles();
    sessions = MemoryWorkspaceSessionStore();
    workspace = WorkspaceController(fileService: files, sessionStore: sessions);
    await workspace.initialize();
  });

  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });

  testWidgets('a standalone file appears under its full directory path', (
    tester,
  ) async {
    files.files['/tmp/notes/draft.md'] = '# Draft';
    await _pumpSidebar(tester, workspace);
    expect(find.text('No folder open'), findsOneWidget);

    final document = (await workspace.openPath('/tmp/notes/draft.md'))!;
    await tester.pumpAndSettle();

    expect(find.text('Temporary Files'), findsOneWidget);
    expect(find.text('/tmp/notes'), findsOneWidget);
    expect(find.text('draft.md'), findsOneWidget);
    expect(find.text('No folder open'), findsNothing);
    expect(find.byTooltip('/tmp/notes/draft.md'), findsOneWidget);
    expect(workspace.workspaceRoot, isNull);
    expect(files.listedDirectories, isEmpty);

    document.controller.text = '# Local edit';
    workspace.selectDocument(0);
    await tester.pumpAndSettle();
    await tester.tap(_fileRow('/tmp/notes/draft.md'));
    await tester.pumpAndSettle();

    expect(workspace.activeDocument, same(document));
    expect(workspace.documents.length, 2);
    expect(document.controller.text, '# Local edit');
    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'draft.md',
      ),
    );
    expect(semantics.properties.selected, isTrue);
    expect(semantics.properties.hint, '/tmp/notes/draft.md');
    await _finish(tester);
  });

  testWidgets('multiple files share folders and distinguish identical names', (
    tester,
  ) async {
    files.files.addAll({
      '/tmp/one/readme.md': '# One',
      '/tmp/one/design.md': '# Design',
      '/tmp/two/readme.md': '# Two',
      '/tmp/one/later.md': '# Later',
    });
    files.selectedFiles = [
      '/tmp/one/readme.md',
      '/tmp/one/design.md',
      '/tmp/two/readme.md',
      '/tmp/one/./readme.md',
    ];
    await workspace.chooseAndOpenFiles();
    await _pumpSidebar(tester, workspace);

    expect(find.text('/tmp'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('/tmp/one'), findsNothing);
    expect(find.text('/tmp/two'), findsNothing);
    expect(
      find.descendant(
        of: _directory('/tmp/one'),
        matching: _fileRow('/tmp/one/readme.md'),
      ),
      findsOneWidget,
    );
    expect(find.text('readme.md'), findsNWidgets(2));
    expect(find.text('design.md'), findsOneWidget);
    expect(find.text('later.md'), findsNothing);
    expect(workspace.documents.length, 4);

    await tester.tap(find.text('one'));
    await tester.pumpAndSettle();
    expect(_fileRow('/tmp/one/readme.md'), findsNothing);
    expect(_fileRow('/tmp/two/readme.md'), findsOneWidget);
    await workspace.openPath('/tmp/one/later.md');
    await tester.pumpAndSettle();
    expect(find.text('later.md'), findsNothing);
    await tester.tap(find.text('one'));
    await tester.pumpAndSettle();
    expect(find.text('later.md'), findsOneWidget);

    await tester.tap(_fileRow('/tmp/two/readme.md'));
    await tester.pumpAndSettle();
    expect(workspace.activeDocument?.path, '/tmp/two/readme.md');
    expect(files.listedDirectories, isEmpty);
    await _finish(tester);
  });

  testWidgets('shared ancestors contain files and nested expanded branches', (
    tester,
  ) async {
    files.files.addAll({
      '/tmp/project/readme.md': '# Root',
      '/tmp/project/notes/summary.md': '# Summary',
      '/tmp/project/notes/daily/readme.md': '# Daily',
      '/tmp/project/reference/api.md': '# API',
    });
    await workspace.openPaths(files.files.keys);
    await _pumpSidebar(tester, workspace);

    expect(find.text('/tmp/project'), findsOneWidget);
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('daily'), findsOneWidget);
    expect(find.text('reference'), findsOneWidget);
    expect(find.text('readme.md'), findsNWidgets(2));
    expect(
      find.descendant(
        of: _directory('/tmp/project/notes'),
        matching: _directory('/tmp/project/notes/daily'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _directory('/tmp/project/notes/daily'),
        matching: _fileRow('/tmp/project/notes/daily/readme.md'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _directory('/tmp/project/notes'),
        matching: _fileRow('/tmp/project/readme.md'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();
    expect(find.text('daily'), findsNothing);
    expect(find.text('summary.md'), findsNothing);
    expect(_fileRow('/tmp/project/readme.md'), findsOneWidget);
    expect(find.text('api.md'), findsOneWidget);

    await tester.tap(find.text('/tmp/project'));
    await tester.pumpAndSettle();
    expect(find.text('api.md'), findsNothing);
    await tester.tap(find.text('/tmp/project'));
    await tester.pumpAndSettle();
    expect(find.text('api.md'), findsOneWidget);
    expect(find.text('summary.md'), findsNothing);
    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();
    expect(find.text('summary.md'), findsOneWidget);
    expect(find.text('readme.md'), findsNWidgets(2));
    expect(files.listedDirectories, isEmpty);
    await _finish(tester);
  });

  testWidgets('reparenting and Save As retain directory expansion choices', (
    tester,
  ) async {
    files.files.addAll({'/tmp/one/a.md': '# A', '/tmp/two/b.md': '# B'});
    await workspace.openPath('/tmp/one/a.md');
    await _pumpSidebar(tester, workspace);
    await tester.tap(find.text('/tmp/one'));
    await tester.pumpAndSettle();
    expect(find.text('a.md'), findsNothing);

    final two = (await workspace.openPath('/tmp/two/b.md'))!;
    await tester.pumpAndSettle();
    expect(find.text('/tmp'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('a.md'), findsNothing);
    expect(find.text('b.md'), findsOneWidget);

    files.savePath = '/tmp/one/copy.md';
    expect(
      await tester.runAsync(() => workspace.saveDocument(two, saveAs: true)),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.text('/tmp/one'), findsOneWidget);
    expect(_directory('/tmp/two'), findsNothing);
    expect(find.text('copy.md'), findsNothing);
    await tester.tap(find.text('/tmp/one'));
    await tester.pumpAndSettle();
    expect(find.text('a.md'), findsOneWidget);
    expect(find.text('copy.md'), findsOneWidget);
    expect(find.text('b.md'), findsNothing);
    expect(files.listedDirectories, isEmpty);
    await _finish(tester);
  });

  testWidgets('path merging respects segments and compacts unbranched paths', (
    tester,
  ) async {
    files.files.addAll({
      '/tmp/notes/a.md': '# A',
      '/tmp/notes-old/b.md': '# B',
      '/other/deep/folder/c.md': '# C',
    });
    await workspace.openPaths(files.files.keys);
    await _pumpSidebar(tester, workspace);

    expect(find.text('/'), findsOneWidget);
    expect(find.text('tmp'), findsOneWidget);
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('notes-old'), findsOneWidget);
    expect(_pathLabel('other/deep/folder'), findsOneWidget);
    expect(find.byTooltip('/other/deep/folder'), findsOneWidget);
    expect(
      find.descendant(
        of: _directory('/tmp'),
        matching: _directory('/tmp/notes'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _directory('/tmp/notes'),
        matching: _fileRow('/tmp/notes-old/b.md'),
      ),
      findsNothing,
    );
    expect(find.text('a.md'), findsOneWidget);
    expect(find.text('b.md'), findsOneWidget);
    expect(find.text('c.md'), findsOneWidget);
    expect(files.listedDirectories, isEmpty);
    await _finish(tester);
  });

  testWidgets('closing files removes empty temporary folders', (tester) async {
    files.files.addAll({'/tmp/one/a.md': '# A', '/tmp/two/b.md': '# B'});
    final one = (await workspace.openPath('/tmp/one/a.md'))!;
    final two = (await workspace.openPath('/tmp/two/b.md'))!;
    await _pumpSidebar(tester, workspace);

    workspace.removeDocument(one);
    await tester.pumpAndSettle();
    expect(find.text('/tmp/one'), findsNothing);
    expect(find.text('/tmp/two'), findsOneWidget);
    expect(find.text('b.md'), findsOneWidget);

    workspace.removeDocument(two);
    await tester.pumpAndSettle();
    expect(find.text('Temporary Files'), findsNothing);
    expect(find.text('/tmp/two'), findsNothing);
    expect(find.text('No folder open'), findsOneWidget);
    expect(find.text('Welcome.md'), findsNothing);
    await _finish(tester);
  });

  testWidgets('saving and Save As update the temporary path and filename', (
    tester,
  ) async {
    await _pumpSidebar(tester, workspace);
    final draft = workspace.newDocument();
    draft.controller.text = '# Draft';
    files.savePath = '/tmp/original/draft.md';
    expect(await workspace.saveDocument(draft), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('/tmp/original'), findsOneWidget);
    expect(find.text('draft.md'), findsOneWidget);

    files.savePath = '/tmp/renamed/copy.md';
    expect(
      await tester.runAsync(() => workspace.saveDocument(draft, saveAs: true)),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.text('/tmp/original'), findsNothing);
    expect(find.text('draft.md'), findsNothing);
    expect(find.text('/tmp/renamed'), findsOneWidget);
    expect(find.text('copy.md'), findsOneWidget);
    expect(files.files['/tmp/original/draft.md'], '# Draft');
    expect(files.listedDirectories, isEmpty);
    await _finish(tester);
  });

  testWidgets('workspace files and external files appear once across roots', (
    tester,
  ) async {
    files.files.addAll({
      '/vault/readme.md': '# Workspace',
      '/vault-other/readme.md': '# External',
    });
    files.directories['/vault'] = [
      const WorkspaceEntry(
        path: '/vault/readme.md',
        name: 'readme.md',
        isDirectory: false,
      ),
    ];
    files.directories['/vault-other'] = [
      const WorkspaceEntry(
        path: '/vault-other/readme.md',
        name: 'readme.md',
        isDirectory: false,
      ),
    ];
    await workspace.openPaths(files.files.keys);
    await _pumpSidebar(tester, workspace);
    expect(find.text('/'), findsOneWidget);
    expect(find.text('vault'), findsOneWidget);
    expect(find.text('vault-other'), findsOneWidget);

    files.selectedFolder = '/vault';
    await workspace.chooseWorkspaceFolder();
    await tester.pumpAndSettle();
    expect(find.text('vault'), findsOneWidget);
    expect(find.text('/vault'), findsNothing);
    expect(find.text('/vault-other'), findsOneWidget);
    expect(_fileRow('/vault/readme.md'), findsOneWidget);
    expect(_fileRow('/vault-other/readme.md'), findsOneWidget);
    expect(files.listedDirectories, ['/vault']);

    await _search(tester, 'readme');
    expect(find.text('readme.md'), findsNWidgets(2));
    expect(find.text('/vault-other'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    files.selectedFolder = '/vault-other';
    await workspace.chooseWorkspaceFolder();
    await tester.pumpAndSettle();
    expect(find.text('/vault'), findsOneWidget);
    expect(find.text('/vault-other'), findsNothing);
    expect(_fileRow('/vault/readme.md'), findsOneWidget);
    expect(_fileRow('/vault-other/readme.md'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('temporary search follows opens, Save As and closes', (
    tester,
  ) async {
    files.files.addAll({
      '/tmp/one/note.md': '# One',
      '/tmp/two/note.md': '# Two',
      '/else/other.md': '# Other',
    });
    final one = (await workspace.openPath('/tmp/one/note.md'))!;
    await workspace.openPath('/else/other.md');
    await _pumpSidebar(tester, workspace);
    await _search(tester, 'note');
    expect(find.text('note.md'), findsOneWidget);
    expect(find.text('other.md'), findsNothing);

    final two = (await workspace.openPath('/tmp/two/note.md'))!;
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('note.md'), findsNWidgets(2));

    files.savePath = '/else/renamed.md';
    expect(
      await tester.runAsync(() async {
        final saved = await workspace.saveDocument(two, saveAs: true);
        // The watcher cancellation and resulting search debounce run in this
        // real async zone, outside the widget test's simulated clock.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return saved;
      }),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('note.md'), findsOneWidget);
    workspace.removeDocument(one);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('No matching files'), findsOneWidget);

    await _search(tester, '/else');
    expect(find.text('renamed.md'), findsOneWidget);
    expect(find.text('other.md'), findsOneWidget);
    expect(files.listedDirectories, isEmpty);
    await _finish(tester);
  });

  testWidgets('restored open sessions rebuild temporary folders', (
    tester,
  ) async {
    files.files.addAll({
      '/tmp/one/restored.md': '# Saved',
      '/tmp/two/another.md': '# Another',
    });
    await workspace.openPaths(files.files.keys);
    workspace.activeDocument!.controller.text = '# Recovered edit';
    await tester.pump(const Duration(milliseconds: 400));
    workspace.dispose();
    workspace = WorkspaceController(fileService: files, sessionStore: sessions);
    await workspace.initialize();
    await _pumpSidebar(tester, workspace);

    expect(find.text('/tmp'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('restored.md'), findsOneWidget);
    expect(find.text('another.md'), findsOneWidget);
    expect(workspace.activeDocument?.controller.text, '# Recovered edit');
    expect(workspace.activeDocument?.controller.isDirty, isTrue);
    expect(files.listedDirectories, isEmpty);
    await _finish(tester);
  });

  testWidgets('long directory paths stay on one line with middle ellipsis', (
    tester,
  ) async {
    const directory =
        '/Users/someone/Documents/项目资料/long directory name/another long folder';
    const path = '$directory/notes with spaces.md';
    files.files[path] = '# Long path';
    await workspace.openPath(path);
    await _pumpSidebar(tester, workspace);

    final label = _pathLabel(directory);
    final text = tester.widget<Text>(
      find.descendant(of: label, matching: find.byType(Text)),
    );
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    expect(text.data, contains('...'));
    expect(text.data!.startsWith('/'), isTrue);
    final suffix = text.data!.split('...').last;
    expect(suffix, isNotEmpty);
    expect(directory.endsWith(suffix), isTrue);
    expect(tester.getSize(label).height, lessThanOrEqualTo(26));
    expect(find.text('notes with spaces.md'), findsOneWidget);
    expect(find.byTooltip(path), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _finish(tester);
  });

  testWidgets('an unreadable workspace does not hide temporary files', (
    tester,
  ) async {
    files.files['/tmp/available.md'] = '# Available';
    files.selectedFolder = '/unreadable';
    files.unreadableDirectory = '/unreadable';
    await workspace.chooseWorkspaceFolder();
    await workspace.openPath('/tmp/available.md');
    await _pumpSidebar(tester, workspace);

    expect(find.textContaining('Unable to read folder'), findsOneWidget);
    expect(find.text('/tmp'), findsOneWidget);
    expect(find.text('available.md'), findsOneWidget);
    expect(files.listedDirectories, ['/unreadable']);
    await _finish(tester);
  });
}

Finder _fileRow(String path) => find.byKey(ValueKey('workspace-file-$path'));

Finder _directory(String path) =>
    find.byKey(ValueKey('temporary-directory-$path'));

Finder _pathLabel(String path) => find.byWidgetPredicate(
  (widget) => widget is MiddleEllipsisText && widget.data == path,
);

Future<void> _pumpSidebar(
  WidgetTester tester,
  WorkspaceController workspace,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: WorkspaceSidebar(
            workspace: workspace,
            onError: (error) => fail(error),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.byKey(const ValueKey('workspace-search-field')),
    query,
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull);
}

class _TrackedFiles extends MemoryMarkdownFileService {
  final listedDirectories = <String>[];
  String? unreadableDirectory;

  @override
  Future<List<WorkspaceEntry>> listDirectory(String path) async {
    listedDirectories.add(path);
    if (path == unreadableDirectory) throw StateError('Folder unavailable');
    return super.listDirectory(path);
  }
}
