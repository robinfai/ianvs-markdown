import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/services/workspace_session_store.dart';
import 'package:linefold/src/widgets/floating_outline.dart';
import 'package:linefold/src/widgets/workspace_sidebar.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'Command digits select tabs without changing editor modes',
    (tester) async {
      tester.view.physicalSize = const Size(840, 560);
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
      final files = MemoryMarkdownFileService()..selectedFolder = '/vault';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await tester.pumpWidget(
        LinefoldApp(workspaceController: workspace),
      );
      await tester.pumpAndSettle();
      await workspace.chooseWorkspaceFolder();
      final first = workspace.activeDocument!;
      first.controller.text = 'First document';
      first.controller.mode = IanvsMarkdownEditorMode.source;
      final second = workspace.newDocument();
      second.controller.text = 'Second document';
      second.controller.mode = IanvsMarkdownEditorMode.livePreview;
      workspace.selectDocument(0);
      await tester.pumpAndSettle();

      Future<void> command(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
      }

      Future<void> focusEditor() async {
        await tester.tap(
          find
              .descendant(
                of: find.byType(IanvsMarkdownLiveEditor),
                matching: find.byType(EditableText),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }

      await focusEditor();
      await command(LogicalKeyboardKey.digit2);
      expect(workspace.activeDocument, same(second));
      expect(first.controller.mode, IanvsMarkdownEditorMode.source);
      expect(second.controller.mode, IanvsMarkdownEditorMode.livePreview);
      await focusEditor();
      await command(LogicalKeyboardKey.digit9);
      expect(
        workspace.activeDocument,
        same(second),
        reason: 'Missing tab is a no-op',
      );
      await command(LogicalKeyboardKey.digit1);
      expect(workspace.activeDocument, same(first));

      for (var i = 2; i < 9; i++) {
        workspace.newDocument();
      }
      final ninth = workspace.activeDocument!;
      workspace.selectDocument(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-search-field')));
      await command(LogicalKeyboardKey.digit9);
      expect(workspace.activeDocument, same(ninth));
      final tabRect = tester.getRect(find.text(ninth.name));
      expect(tabRect.left, greaterThanOrEqualTo(248));
      expect(tabRect.right, lessThan(840));

      workspace.reorderDocument(8, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-search-field')));
      await command(LogicalKeyboardKey.digit2);
      expect(
        workspace.activeDocument,
        same(first),
        reason: 'Shortcuts follow the new visual order',
      );
      final menus = tester.widget<PlatformMenuBar>(
        find.byType(PlatformMenuBar),
      );
      final window = menus.menus.whereType<PlatformMenu>().singleWhere(
        (menu) => menu.label == 'Window',
      );
      final firstTabMenu = window.menus
          .whereType<PlatformMenuItemGroup>()
          .single
          .members
          .singleWhere((item) => item.label == ninth.name);
      expect(
        (firstTabMenu.shortcut as SingleActivator).trigger,
        LogicalKeyboardKey.digit1,
      );
      firstTabMenu.onSelected!();
      await tester.pumpAndSettle();
      expect(workspace.activeDocument, same(ninth));
      final view = menus.menus.whereType<PlatformMenu>().singleWhere(
        (menu) => menu.label == 'View',
      );
      expect(
        view.menus
            .whereType<PlatformMenuItemGroup>()
            .single
            .members
            .singleWhere((item) => item.label == 'Source')
            .shortcut,
        isNull,
      );
      expect(first.controller.text, 'First document');
      expect(second.controller.text, 'Second document');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'desktop menus and save dialog work at minimum window size',
    (tester) async {
      tester.view.physicalSize = const Size(840, 560);
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
      final files = MemoryMarkdownFileService();
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await tester.pumpWidget(
        LinefoldApp(workspaceController: workspace),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlatformMenuBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      final menuBar = tester.widget<PlatformMenuBar>(
        find.byType(PlatformMenuBar),
      );
      final fileMenu = menuBar.menus.whereType<PlatformMenu>().singleWhere(
        (menu) => menu.label == 'File',
      );
      fileMenu.descendants
          .singleWhere((item) => item.label == 'New Document')
          .onSelected!();
      await tester.pumpAndSettle();
      final draft = workspace.activeDocument!;
      draft.controller.text = '# Draft\n\nUnsaved changes';
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close ${draft.name}'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(workspace.activeDocument, same(draft));
      expect(draft.controller.isDirty, isTrue);
      await tester.tap(find.byTooltip('Close ${draft.name}'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(files.files[files.savePath], '# Draft\n\nUnsaved changes');
      expect(workspace.documents.contains(draft), isFalse);
      tester
          .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
          .menus
          .whereType<PlatformMenu>()
          .singleWhere((menu) => menu.label == 'View')
          .descendants
          .singleWhere((item) => item.label == 'Toggle Appearance')
          .onSelected!();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('renders a consolidated desktop shell', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final files = MemoryMarkdownFileService();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);

    await tester.pumpWidget(
      LinefoldApp(workspaceController: workspace),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome.md'), findsOneWidget);
    final sidebar = find.byType(WorkspaceSidebar);
    expect(sidebar, findsOneWidget);
    expect(tester.getSize(sidebar).width, 248);
    expect(
      tester
          .widget<Material>(
            find.descendant(of: sidebar, matching: find.byType(Material)).first,
          )
          .color,
      const Color(0xff17191a),
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('Workspace')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('Welcome.md')),
      findsNothing,
    );
    expect(find.byType(FloatingOutline), findsOneWidget);
    expect(find.text('Outline'), findsWidgets);
    expect(find.text('Notes'), findsNothing);
    expect(find.byTooltip('More actions'), findsNothing);
    expect(find.byTooltip('Toggle theme'), findsNothing);
    expect(find.byTooltip('New document (⌘N)'), findsOneWidget);
    expect(find.byTooltip('Hide outline'), findsOneWidget);

    await tester.tap(find.byTooltip('Source'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.byTooltip('Source'),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .selected,
      isTrue,
    );
    await tester.tap(find.byTooltip('Live Preview'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hide outline'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingOutline), findsNothing);

    await tester.tap(find.byTooltip('Show outline'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingOutline), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new-document-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Untitled-'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('shows the directory tree directly below workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final files = MemoryMarkdownFileService()
      ..directories['/vault'] = const <WorkspaceEntry>[
        WorkspaceEntry(path: '/vault/notes', name: 'notes', isDirectory: true),
        WorkspaceEntry(
          path: '/vault/readme.md',
          name: 'readme.md',
          isDirectory: false,
        ),
      ]
      ..directories['/vault/notes'] = const <WorkspaceEntry>[
        WorkspaceEntry(
          path: '/vault/notes/nested.md',
          name: 'nested.md',
          isDirectory: false,
        ),
      ];
    final store = MemoryWorkspaceSessionStore()
      ..snapshot = const WorkspaceSnapshot(
        documents: <Map<String, Object?>>[],
        activeDocumentId: null,
        workspaceRoot: '/vault',
        workspaceAccessToken: 'access:/vault',
        sidebarVisible: true,
        outlineVisible: true,
      );
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: store,
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);

    await tester.pumpWidget(
        LinefoldApp(workspaceController: workspace),
    );
    await tester.pumpAndSettle();

    final sidebar = find.byType(WorkspaceSidebar);
    expect(
      find.descendant(of: sidebar, matching: find.text('vault')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('notes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('readme.md')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('nested.md')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: sidebar, matching: find.text('notes')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: sidebar, matching: find.text('nested.md')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('Welcome.md')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('workspace-search-field')),
      'nested',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sidebar, matching: find.text('nested.md')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('readme.md')),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sidebar, matching: find.text('readme.md')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
