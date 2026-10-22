import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/controllers/workspace_search_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'package:linefold/src/widgets/workspace_search_dialog.dart';

import 'support/fakes.dart';

void main() {
  Future<WorkspaceController> open(
    WidgetTester tester, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = MemoryMarkdownFileService()
      ..files['/notes/a.md'] = 'first needle\nsecond needle';
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    await workspace.initialize();
    await workspace.openPath('/notes/a.md');
    workspace.setMode(IanvsMarkdownEditorMode.livePreview);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: EditorShell(
            workspace: workspace,
            dark: false,
            onToggleTheme: () {},
            enableFileDrop: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return workspace;
  }

  Future<void> search(WidgetTester tester, String value) async {
    await tester.tap(
      find.byKey(const ValueKey('workspace-source-search-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workspace-source-query')),
      value,
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets(
    'source search returns dirty buffers and opens exact match without changing mode',
    (tester) async {
      final workspace = await open(tester);
      final document = workspace.activeDocument!;
      document.controller.text = 'dirty needle\nsecond needle';
      await search(tester, 'needle');
      expect(
        find.byKey(const ValueKey('workspace-source-result-1')),
        findsOneWidget,
      );
      expect(
        find.text('Open buffers only. No folder is scanned.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-source-result-1')));
      await tester.pumpAndSettle();
      expect(workspace.activeDocument, same(document));
      expect(document.controller.isDirty, isTrue);
      expect(document.controller.mode, IanvsMarkdownEditorMode.livePreview);
      expect(
        document.controller.selection,
        const TextSelection(baseOffset: 20, extentOffset: 26),
      );
      expect(find.byKey(const ValueKey('document-find-bar')), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('stale hit never applies old offsets or discards newer text', (
    tester,
  ) async {
    final workspace = await open(tester);
    await search(tester, 'needle');
    final dialog = tester.widget<WorkspaceSearchDialog>(
      find.byType(WorkspaceSearchDialog),
    );
    final old = dialog.controller.results.first;
    workspace.activeDocument!.controller.text = 'newer dirty needle';
    Navigator.of(tester.element(find.byType(WorkspaceSearchDialog))).pop(old);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Source changed since this result. Search again to use current offsets.',
      ),
      findsOneWidget,
    );
    expect(workspace.activeDocument!.controller.text, 'newer dirty needle');
    expect(find.byKey(const ValueKey('document-find-bar')), findsNothing);
    await finish(tester);
  });

  testWidgets('Command Shift F is independent and Escape/reopen is safe', (
    tester,
  ) async {
    final workspace = await open(tester);
    workspace.toggleSidebar();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceSearchDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceSearchDialog), findsNothing);
    expect(find.byKey(const ValueKey('document-find-bar')), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'case toggle and no-result partial status remain visible at larger text',
    (tester) async {
      await open(tester, scale: 1.5);
      await search(tester, 'NEEDLE');
      expect(
        find.byKey(const ValueKey('workspace-source-result-0')),
        findsOneWidget,
      );
      await tester.tap(find.text('Match case'));
      await tester.pumpAndSettle();
      expect(find.text('No matches.'), findsOneWidget);
      final dialog = tester.widget<WorkspaceSearchDialog>(
        find.byType(WorkspaceSearchDialog),
      );
      dialog.controller.cancel();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('workspace-source-partial')),
        findsOneWidget,
      );
      expect(
        find.text('No matches in the source that could be searched.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'query IME blocks old-result navigation and dismissal until committed',
    (tester) async {
      final workspace = await open(tester);
      await search(tester, 'needle');
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('workspace-source-query')),
      );
      field.controller!.value = const TextEditingValue(
        text: 'needle',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 0, end: 6),
      );
      await tester.pump();
      expect(
        find.text('Finish composing to search or open a result.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('workspace-source-result-0')),
            )
            .onTap,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Close source search',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(WorkspaceSearchDialog), findsOneWidget);
      expect(
        workspace.activeDocument!.controller.text,
        'first needle\nsecond needle',
      );
      field.controller!.value = field.controller!.value.copyWith(
        composing: TextRange.empty,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('workspace-source-result-0')),
            )
            .onTap,
        isNotNull,
      );
      await finish(tester);
    },
  );

  testWidgets('offline no-results explicitly distinguish unread documents', (
    tester,
  ) async {
    final files = MemoryMarkdownFileService();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
      indexSource: _OfflineSource(),
    );
    await workspace.initialize();
    workspace.index.configure('/vault');
    final search = WorkspaceSearchController(workspace.index);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkspaceSearchDialog(controller: search)),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('workspace-source-query')),
      'needle',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-source-partial')),
      findsOneWidget,
    );
    expect(find.textContaining('cloud-only/offline'), findsOneWidget);
    expect(
      find.text('No matches in the source that could be searched.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    search.dispose();
    workspace.dispose();
    await files.dispose();
  });
}

class _OfflineSource implements WorkspaceIndexSource {
  @override
  Future<WorkspaceDirectorySnapshot> listWorkspaceDirectory(
    String root,
    String relativePath,
  ) async => const WorkspaceDirectorySnapshot([
    WorkspaceMetadata(
      relativePath: 'cloud.md',
      isDirectory: false,
      revision: '1',
      local: false,
    ),
  ]);
  @override
  Future<WorkspaceTextRead> readWorkspaceText(
    String root,
    String relativePath,
    int maximumBytes,
  ) => throw StateError('Must not read offline file');
}
