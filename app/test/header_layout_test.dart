import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'package:linefold/src/widgets/middle_ellipsis_text.dart';

import 'support/fakes.dart';

void main() {
  late MemoryMarkdownFileService files;
  late WorkspaceController workspace;
  const text =
      '# Centering\n\nA paragraph in the document.\n\n## Next\n\nMore text.';

  setUp(() async {
    files = MemoryMarkdownFileService()..selectedFolder = '/Projects/Project';
    files.files['/Projects/Project/notes/目标.md'] = text;
    workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    await workspace.initialize();
    await workspace.chooseWorkspaceFolder();
    await workspace.openPath('/Projects/Project/notes/目标.md');
  });

  tearDown(() async {
    workspace.dispose();
    await files.dispose();
  });

  Future<void> pumpShell(WidgetTester tester, {double textScale = 1}) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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

  testWidgets(
    'document stays centered in all modes as panels and window change',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      await pumpShell(tester);

      for (final size in [const Size(1600, 1000), const Size(840, 560)]) {
        tester.view.physicalSize = size;
        for (final panels in [
          (true, true),
          (false, true),
          (true, false),
          (false, false),
        ]) {
          if (workspace.sidebarVisible != panels.$1) workspace.toggleSidebar();
          if (workspace.outlineVisible != panels.$2) workspace.toggleOutline();
          for (final mode in IanvsMarkdownEditorMode.values) {
            workspace.setMode(mode);
            await tester.pumpAndSettle();
            final modeButton = find.byKey(const ValueKey('editor-mode-button'));
            final row = tester.getRect(
              find.byKey(const ValueKey('document-context-row')),
            );
            final button = tester.getRect(modeButton);
            expect(button.center.dy, closeTo(row.center.dy, 0.5));
            for (final part
                in find
                    .descendant(
                      of: modeButton,
                      matching: find.byWidgetPredicate(
                        (widget) => widget is Icon || widget is Text,
                      ),
                    )
                    .evaluate()) {
              expect(
                tester.getRect(find.byWidget(part.widget)).center.dy,
                closeTo(button.center.dy, 0.5),
              );
            }
            final editor = tester.getRect(find.byType(IanvsMarkdownLiveEditor));
            final Finder column;
            switch (mode) {
              case IanvsMarkdownEditorMode.livePreview:
                column = find.byKey(
                  const ValueKey('ianvs-markdown-block-13-paragraph'),
                );
              case IanvsMarkdownEditorMode.preview:
                column = find
                    .descendant(
                      of: find.byType(IanvsMarkdownView),
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is ConstrainedBox &&
                            widget.constraints.maxWidth == 720,
                      ),
                    )
                    .first;
              case IanvsMarkdownEditorMode.source:
                column = find.descendant(
                  of: find.byKey(const ValueKey('ianvs-markdown-source-field')),
                  matching: find.byType(EditableText),
                );
            }
            final bounds = tester.getRect(column);
            expect(
              bounds.center.dx,
              closeTo(editor.center.dx, 1),
              reason: '$size, panels $panels, $mode',
            );
            expect(bounds.width, lessThanOrEqualTo(721));
            if (size.width == 1600) expect(bounds.width, closeTo(720, 1));
            expect(tester.takeException(), isNull);
          }
        }
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('context follows document and save path beneath the tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(840, 560);
    await pumpShell(tester, textScale: 2);
    String location() => tester
        .widget<MiddleEllipsisText>(
          find.byKey(const ValueKey('document-location')),
        )
        .data;
    expect(location(), 'Project / notes/目标.md');
    expect(
      tester.getRect(find.byKey(const ValueKey('document-tabs-row'))).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('document-context-row'))).top,
      ),
    );
    expect(find.text('Workspace'), findsNothing);
    final modeButton = tester.getRect(
      find.byKey(const ValueKey('editor-mode-button')),
    );
    final contextRow = tester.getRect(
      find.byKey(const ValueKey('document-context-row')),
    );
    expect(modeButton.center.dy, closeTo(contextRow.center.dy, 0.5));
    expect(modeButton.top, greaterThan(contextRow.top));
    expect(modeButton.bottom, lessThan(contextRow.bottom));

    await tester.tap(find.byTooltip('New document (⌘N)'));
    await tester.pumpAndSettle();
    expect(location(), 'Unsaved / ${workspace.activeDocument!.name}');
    files.savePath = '/Projects/Project/saved.md';
    await workspace.saveActive();
    await tester.pumpAndSettle();
    expect(location(), 'Project / saved.md');

    await tester.tap(find.byTooltip('Hide sidebar'));
    await tester.pumpAndSettle();
    final title = tester.getRect(
      find.byKey(const ValueKey('window-app-title')),
    );
    expect(title.left, greaterThanOrEqualTo(80));
    for (final tooltip in [
      'All open documents',
      'New document (⌘N)',
      'Hide outline',
    ]) {
      final bounds = tester.getRect(find.byTooltip(tooltip));
      expect(bounds.right, lessThanOrEqualTo(840));
      expect(bounds.top, greaterThanOrEqualTo(0));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'new and selected tabs remain visible in a long variable-width strip',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(1200, 780);
        for (var i = 0; i < 30; i++) {
          final name = i < 15 ? '$i.md' : 'long-document-$i-with-notes.md';
          final path = '/Projects/Project/$name';
          files.files[path] = '# Document $i';
          await workspace.openPath(path);
        }
        workspace.selectDocument(0);
        await pumpShell(tester);

        void expectActiveTabVisible() {
          final viewport = tester.getRect(find.byType(ReorderableListView));
          final tab = find.descendant(
            of: find.byType(ReorderableListView),
            matching: find.byKey(ValueKey(workspace.activeDocument!.id)),
          );
          expect(tab, findsOneWidget);
          final bounds = tester.getRect(tab);
          expect(bounds.left, greaterThanOrEqualTo(viewport.left - 1));
          expect(bounds.right, lessThanOrEqualTo(viewport.right + 1));
          expect(tester.takeException(), isNull);
        }

        await tester.tap(find.byTooltip('New document (⌘N)'));
        await tester.pumpAndSettle();
        expectActiveTabVisible();
        final created = workspace.activeDocument!;
        final tab = find.descendant(
          of: find.byType(ReorderableListView),
          matching: find.byKey(ValueKey(created.id)),
        );
        final start = tester.getCenter(tab);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: start);
        await mouse.moveTo(start);
        await tester.pump(const Duration(seconds: 1));
        await mouse.down(start);
        await mouse.moveBy(const Offset(-400, 0));
        await tester.pump(const Duration(milliseconds: 500));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(workspace.activeDocument, same(created));
        expect(workspace.activeIndex, lessThan(workspace.documents.length - 1));
        await mouse.removePointer();
        for (final index in [0, 20, workspace.documents.length - 1]) {
          workspace.selectDocument(index);
          await tester.pumpAndSettle();
          expectActiveTabVisible();
        }
        workspace.selectDocument(workspace.documents.indexOf(created));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close ${created.name}'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('All open documents'));
        await tester.pumpAndSettle();
        final menuItem = find.widgetWithText(MenuItemButton, '目标.md');
        await tester.ensureVisible(menuItem);
        await tester.pumpAndSettle();
        await tester.tap(menuItem);
        await tester.pumpAndSettle();
        expect(workspace.activeDocument!.name, '目标.md');
        expectActiveTabVisible();
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );
}
