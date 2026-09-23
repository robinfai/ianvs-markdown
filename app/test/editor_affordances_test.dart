import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import 'support/fakes.dart';

void main() {
  Future<WorkspaceController> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 780);
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
    await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
    await tester.pumpAndSettle();
    return workspace;
  }

  testWidgets('assistive technology can identify and switch editor modes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final workspace = await openApp(tester);
    final document = workspace.activeDocument!;
    final source = document.controller.text;
    final live = tester.getSemantics(find.bySemanticsLabel('Live Preview'));
    expect(live.flagsCollection.isButton, isTrue);
    expect(live.flagsCollection.isSelected, Tristate.isTrue);
    expect(live.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(live.rect.height, greaterThanOrEqualTo(28));

    final read = tester.getSemantics(find.bySemanticsLabel('Read'));
    read.owner!.performAction(read.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(document.controller.mode, IanvsMarkdownEditorMode.preview);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Read'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(document.controller.text, source);
    expect(document.controller.isDirty, isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    semantics.dispose();
  });

  testWidgets('empty Source hint never becomes document content', (
    tester,
  ) async {
    final workspace = await openApp(tester);
    final draft = workspace.newDocument();
    await tester.pumpAndSettle();
    expect(find.text('Start writing Markdown…'), findsOneWidget);
    workspace.setMode(IanvsMarkdownEditorMode.source);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
    expect(
      tester.widget<TextField>(field).decoration!.hintText,
      'Start writing Markdown…',
    );
    expect(draft.controller.text, isEmpty);
    expect(draft.controller.isDirty, isFalse);
    await tester.enterText(field, '# My note');
    await tester.pumpAndSettle();
    expect(draft.controller.text, '# My note');
    await workspace.saveActive();
    expect(draft.persistedText, '# My note');
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    await workspace.saveActive();
    expect(draft.persistedText, isEmpty);
    workspace.setMode(IanvsMarkdownEditorMode.preview);
    await tester.pumpAndSettle();
    expect(find.text('Start writing Markdown…'), findsNothing);
    expect(draft.controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short mixed-language filenames fit their measured tabs', (
    tester,
  ) async {
    final workspace = await openApp(tester);
    final document = workspace.newDocument()..name = 'Markdown体验.md';
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(document.name),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getRect(find.text(document.name)).right, lessThan(1200));
    for (var i = 0; i < 8; i++) {
      workspace.newDocument();
    }
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(840, 560);
    await tester.pumpAndSettle();
    final selectedTab = tester.getRect(
      find.text(workspace.activeDocument!.name),
    );
    expect(selectedTab.left, greaterThanOrEqualTo(248));
    expect(selectedTab.right, lessThan(840));
    expect(tester.takeException(), isNull);
  });
}
