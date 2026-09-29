import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/desktop_typography.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/widgets/editor_shell.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'render desktop design acceptance in light, dark and narrow views',
    (tester) async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final font = File('/System/Library/Fonts/SFNS.ttf');
      if (font.existsSync()) {
        await tester.runAsync(() async {
          final loader = FontLoader(DesktopTypography.fontFamily)
            ..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            );
          await loader.load();
        });
      }
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

      final files = MemoryMarkdownFileService()
        ..selectedFolder = '/Projects/Linefold';
      WorkspaceEntry entry(String path, {bool folder = false}) =>
          WorkspaceEntry(
            path: path,
            name: path.split('/').last,
            isDirectory: folder,
          );
      files.files.addAll({
        '/Projects/Linefold/README.md':
            '# Linefold\n\nA quiet space for your ideas.',
        '/Projects/Linefold/docs/product-brief.md': '# Product brief',
        '/Projects/Linefold/docs/sidebar-design.md': '''# A place for every idea

Keep your notes close and your writing in focus.

## Your workspace

Files stay in ordinary folders. Open a project, find a note, and keep writing.

- Browse folders with the keyboard
- Search file names and paths
- Drag a note back to the workspace root

## Made for the Mac

A familiar sidebar, quiet controls, and a comfortable reading surface.

> Good tools make space for the work.

## Next steps

- [x] Bring the design system together
- [ ] Review the next draft
''',
        '/Projects/Linefold/notes/week-2.md': '# Week 2',
        '/Projects/Linefold/notes/week-10.md': '# Week 10',
        '/Downloads/meeting-notes.md': '# Meeting notes',
      });
      files.directories.addAll({
        '/Projects/Linefold': [
          entry('/Projects/Linefold/docs', folder: true),
          entry('/Projects/Linefold/notes', folder: true),
          entry('/Projects/Linefold/README.md'),
        ],
        '/Projects/Linefold/docs': [
          entry('/Projects/Linefold/docs/product-brief.md'),
          entry('/Projects/Linefold/docs/sidebar-design.md'),
        ],
        '/Projects/Linefold/notes': [
          entry('/Projects/Linefold/notes/week-2.md'),
          entry('/Projects/Linefold/notes/week-10.md'),
        ],
      });
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      await workspace.initialize();
      await workspace.chooseWorkspaceFolder();
      await workspace.openPath('/Downloads/meeting-notes.md');
      await workspace.openPath('/Projects/Linefold/README.md');
      await workspace.openPath('/Projects/Linefold/docs/sidebar-design.md');
      await workspace.browser.reveal(workspace.activeDocument!.path!);
      workspace.browser.toggle('/Projects/Linefold/notes');
      await workspace.browser.load('/Projects/Linefold/notes');
      workspace.browser.toggleFavorite(entry('/Projects/Linefold/README.md'));
      workspace.setMode(IanvsMarkdownEditorMode.preview);
      final boundary = GlobalKey();

      Future<void> saveFrame(String name) async {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/desktop-design-acceptance');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/$name.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> capture(
        String name,
        Brightness brightness,
        Size size, {
        double textScale = 1,
      }) async {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: desktopTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: RepaintBoundary(key: boundary, child: child!),
            ),
            home: EditorShell(
              workspace: workspace,
              dark: brightness == Brightness.dark,
              onToggleTheme: () {},
              enableFileDrop: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveFrame(name);
      }

      await capture('desktop-light', Brightness.light, const Size(1200, 780));
      await capture('desktop-dark', Brightness.dark, const Size(1200, 780));
      await capture('desktop-narrow', Brightness.light, const Size(840, 560));
      await capture(
        'desktop-large-text',
        Brightness.light,
        const Size(1200, 780),
        textScale: 2,
      );
      await capture(
        'desktop-narrow-large-text',
        Brightness.light,
        const Size(840, 560),
        textScale: 2,
      );
      await capture('desktop-light', Brightness.light, const Size(1200, 780));
      final activeRow = find.byKey(
        const ValueKey(
          'workspace-file-/Projects/Linefold/docs/sidebar-design.md',
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.tapAt(tester.getCenter(activeRow));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Move to Trash'), findsOneWidget);
      await saveFrame('desktop-context-menu');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(activeRow),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(
        tester.getTopLeft(
              find.byKey(const ValueKey('workspace-root-drop-space')),
            ) +
            const Offset(100, 30),
      );
      await tester.pumpAndSettle();
      expect(find.text('Move to Linefold'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('workspace-drag-label')))
            .dx,
        greaterThan(0),
      );
      await saveFrame('desktop-root-drop');
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      await files.dispose();
    },
  );
}
