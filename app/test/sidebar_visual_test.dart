import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_typography.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/widgets/workspace_sidebar.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'render normal, narrow, and search sidebar acceptance artifacts',
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
      final files = MemoryMarkdownFileService()
        ..selectedFolder = '/Projects/Linefold';
      WorkspaceEntry entry(String path, {bool folder = false}) =>
          WorkspaceEntry(
            path: path,
            name: path.split('/').last,
            isDirectory: folder,
          );
      files.files.addAll({
        '/Projects/Linefold/README.md': '# Linefold',
        '/Projects/Linefold/docs/product-brief.md': '# Brief',
        '/Projects/Linefold/docs/sidebar-design.md': '# Design',
        '/Projects/Linefold/notes/week-2.md': '# Week 2',
        '/Projects/Linefold/notes/week-10.md': '# Week 10',
        '/Downloads/meeting-notes.md': '# Meeting',
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
          entry('/Projects/Linefold/notes/week-10.md'),
          entry('/Projects/Linefold/notes/week-2.md'),
        ],
      });
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      await workspace.initialize();
      await workspace.chooseWorkspaceFolder();
      await workspace.openPath('/Downloads/meeting-notes.md');
      await workspace.openPath('/Projects/Linefold/docs/sidebar-design.md');
      workspace.activeDocument!.controller.text = '# Draft design';
      await workspace.browser.reveal(workspace.activeDocument!.path!);
      workspace.browser.toggle('/Projects/Linefold/notes');
      await workspace.browser.load('/Projects/Linefold/notes');
      workspace.browser.toggleFavorite(entry('/Projects/Linefold/README.md'));
      final boundary = GlobalKey();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Future<void> capture(String name, double width) async {
        tester.view.physicalSize = Size(width, 660);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: WorkspaceSidebar(
                  workspace: workspace,
                  width: width,
                  onError: (error) => fail(error),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/sidebar-acceptance');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/$name.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('sidebar-normal', 248);
      await capture('sidebar-narrow', 180);
      await tester.enterText(
        find.byKey(const ValueKey('workspace-search-field')),
        'design',
      );
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      expect(
        find.text('sidebar-design.md', findRichText: true),
        findsOneWidget,
      );
      expect(workspace.browser.query, 'design');
      await capture('sidebar-search', 248);
      expect(workspace.browser.query, 'design');
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      await files.dispose();
    },
  );
}
