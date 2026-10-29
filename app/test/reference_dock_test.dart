import 'dart:ui' show PointerDeviceKind;
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/widgets/note_link_preview.dart';
import 'wiki_note_navigation_test.dart' show WikiFiles, wikiWorkspace;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/widgets/reference_dock.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('reading link hover previews local note without navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = WikiFiles();
    files.files['/vault/Origin.md'] = 'Read [[Target]]';
    files.files['/vault/Target.md'] = 'Preview target content';
    final workspace = await wikiWorkspace(files);
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    final origin = workspace.activeDocument!;
    origin.controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(NoteLinkPreview).first));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Preview target content'), findsOneWidget);
    expect(workspace.activeDocument, same(origin));
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'pinned open note follows edits without changing active document',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
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
      await workspace.initialize();
      final reference = workspace.newDocument(name: 'Reference.md');
      reference.controller.text = 'Reference content';
      final draft = workspace.newDocument(name: 'Draft.md');
      String? inserted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: ReferenceDock(
                workspace: workspace,
                onClose: () {},
                onInsert: (value, path) => inserted = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reference.md'));
      await tester.pumpAndSettle();
      expect(workspace.activeDocument, same(draft));
      reference.controller.text = 'Updated reference';
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Insert reference at cursor'));
      expect(inserted, 'Updated reference');
      expect(workspace.activeDocument, same(draft));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}
