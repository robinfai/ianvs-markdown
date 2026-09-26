import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/models/workspace_layout.dart';
import 'package:linefold/src/services/workspace_session_store.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'package:linefold/src/widgets/workspace_sidebar.dart';

import 'support/fakes.dart';

void main() {
  late MemoryMarkdownFileService files;
  late MemoryWorkspaceSessionStore sessions;
  late WorkspaceController workspace;

  setUp(() async {
    files = MemoryMarkdownFileService();
    sessions = MemoryWorkspaceSessionStore();
    workspace = WorkspaceController(fileService: files, sessionStore: sessions);
    await workspace.initialize();
  });

  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });

  testWidgets('dragging the edge resizes the sidebar and preserves the tree', (
    tester,
  ) async {
    files.files['/tmp/notes/draft.md'] = '# Draft';
    await workspace.openPath('/tmp/notes/draft.md');
    await _pumpShell(tester, workspace);
    expect(_sidebarWidth(tester), WorkspaceLayout.defaultSidebarWidth);
    await tester.tap(find.text('/tmp/notes'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(_handle));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(_sidebarWidth(tester), closeTo(308, .01));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(_sidebarWidth(tester), closeTo(348, .01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.sidebarWidth, closeTo(348, .01));
    expect(
      find.byKey(const ValueKey('workspace-file-/tmp/notes/draft.md')),
      findsNothing,
    );

    workspace.toggleSidebar();
    await tester.pumpAndSettle();
    expect(_handle, findsNothing);
    workspace.toggleSidebar();
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), closeTo(348, .01));
    expect(workspace.activeDocument?.path, '/tmp/notes/draft.md');
    await _finish(tester);
  });

  testWidgets('resize limits leave room for editor and adapt to the window', (
    tester,
  ) async {
    await _pumpShell(tester, workspace);
    await tester.drag(_handle, const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), WorkspaceLayout.maxSidebarWidth);

    tester.view.physicalSize = const Size(840, 560);
    await tester.pumpAndSettle();
    expect(
      _sidebarWidth(tester),
      840 - DesktopMetrics.inspectorWidth - WorkspaceLayout.minEditorWidth,
    );
    expect(
      tester.getSize(find.byType(IanvsMarkdownLiveEditor)).width,
      greaterThanOrEqualTo(WorkspaceLayout.minEditorWidth),
    );
    expect(workspace.sidebarWidth, WorkspaceLayout.maxSidebarWidth);
    expect(tester.takeException(), isNull);

    workspace.toggleOutline();
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), 840 - WorkspaceLayout.minContentWidth);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1400, 800);
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), WorkspaceLayout.maxSidebarWidth);
    await tester.drag(_handle, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(_sidebarWidth(tester), WorkspaceLayout.minSidebarWidth);
    await _finish(tester);
  });

  testWidgets('sidebar width survives serialization and session recovery', (
    tester,
  ) async {
    await _pumpShell(tester, workspace);
    await tester.drag(_handle, const Offset(120, 0));
    await tester.pumpAndSettle();
    await _finish(tester);
    final saved = WorkspaceSnapshot.fromJson(sessions.snapshot!.toJson());
    expect(saved.sidebarWidth, closeTo(368, .01));
    sessions.snapshot = saved;
    workspace.dispose();
    workspace = WorkspaceController(fileService: files, sessionStore: sessions);
    await workspace.initialize();
    await _pumpShell(tester, workspace);
    expect(_sidebarWidth(tester), closeTo(368, .01));
    await _finish(tester);
  });

  testWidgets('assistive technology can adjust sidebar width', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpShell(tester, workspace);
      final handle = tester.getSemantics(
        find.bySemanticsLabel('Resize sidebar'),
      );
      expect(
        handle.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      handle.owner!.performAction(handle.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), WorkspaceLayout.defaultSidebarWidth + 20);
      handle.owner!.performAction(handle.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), WorkspaceLayout.defaultSidebarWidth);
      await _finish(tester);
    } finally {
      semantics.dispose();
    }
  });

  test('old sessions and invalid widths use safe layout bounds', () {
    expect(
      WorkspaceSnapshot.fromJson({}).sidebarWidth,
      WorkspaceLayout.defaultSidebarWidth,
    );
    for (final value in ['wide', double.nan, double.infinity]) {
      expect(
        WorkspaceSnapshot.fromJson({'sidebarWidth': value}).sidebarWidth,
        WorkspaceLayout.defaultSidebarWidth,
      );
    }
    expect(
      WorkspaceSnapshot.fromJson({'sidebarWidth': -20}).sidebarWidth,
      WorkspaceLayout.minSidebarWidth,
    );
    expect(
      WorkspaceSnapshot.fromJson({'sidebarWidth': 9000}).sidebarWidth,
      WorkspaceLayout.maxSidebarWidth,
    );
    workspace.setSidebarWidth(320);
    workspace.setSidebarWidth(double.nan);
    expect(workspace.sidebarWidth, 320);
  });
}

final _handle = find.byKey(const ValueKey('sidebar-resize-handle'));

double _sidebarWidth(WidgetTester tester) =>
    tester.getSize(find.byType(WorkspaceSidebar)).width;

Future<void> _pumpShell(
  WidgetTester tester,
  WorkspaceController workspace,
) async {
  tester.view.physicalSize = const Size(1400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.menu,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.menu,
      null,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: desktopTheme(Brightness.light),
      home: EditorShell(
        workspace: workspace,
        dark: false,
        onToggleTheme: () {},
        enableFileDrop: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull);
}
