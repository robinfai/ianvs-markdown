import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import '../../test/fixtures/native_menu_harness.dart';
import 'support/fakes.dart';

void main() {
  for (final command in ['Undo', 'Read', 'Save', 'Save As…']) {
    testWidgets(
      'app native $command preserves active source composition',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final menu = NativeMenuHarness(tester);
        final files = MemoryMarkdownFileService()
          ..files['/notes/input.md'] = 'seed ';
        final workspace = WorkspaceController(
          fileService: files,
          sessionStore: MemoryWorkspaceSessionStore(),
        );
        addTearDown(workspace.dispose);
        addTearDown(files.dispose);
        await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
        await tester.pumpAndSettle();
        final document = (await workspace.openPath('/notes/input.md'))!;
        document.controller.mode = IanvsMarkdownEditorMode.source;
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
        await tester.enterText(field, 'seed new ');
        document.controller.commitHistoryGroup();
        const composing = TextEditingValue(
          text: 'seed new ni',
          selection: TextSelection.collapsed(offset: 11),
          composing: TextRange(start: 9, end: 11),
        );
        tester.testTextInput.updateEditingValue(composing);
        await tester.pump();
        await menu.select(command);
        expect(document.controller.mode, IanvsMarkdownEditorMode.source);
        expect(document.controller.value, composing);
        await tester.tap(find.byKey(const ValueKey('editor-mode-button')));
        await tester.pumpAndSettle();
        expect(document.controller.value, composing);
        expect(find.byKey(const ValueKey('editor-mode-preview')), findsNothing);
        expect(files.files['/notes/input.md'], 'seed ');
        await commandKey(tester, LogicalKeyboardKey.keyZ);
        expect(document.controller.value, composing);
        await commandKey(tester, LogicalKeyboardKey.keyS);
        expect(files.files['/notes/input.md'], 'seed ');
        tester.testTextInput.updateEditingValue(
          composing.copyWith(
            text: 'seed new 你',
            selection: const TextSelection.collapsed(offset: 10),
            composing: TextRange.empty,
          ),
        );
        await tester.pumpAndSettle();
        await menu.select('Save');
        expect(files.files['/notes/input.md'], 'seed new 你');
        expect(document.controller.isDirty, isFalse);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 600));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
  testWidgets(
    'main native undo belongs to Search Files and disabled keys still allow menus',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final menu = NativeMenuHarness(tester);
      final files = MemoryMarkdownFileService()
        ..files['/notes/input.md'] = 'seed ';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await tester.pumpWidget(
        IanvsMarkdownShortcuts(
          bindings: const {
            IanvsMarkdownCommand.undo: [],
            IanvsMarkdownCommand.save: [],
          },
          child: LinefoldApp(workspaceController: workspace),
        ),
      );
      await tester.pumpAndSettle();
      final document = (await workspace.openPath('/notes/input.md'))!;
      await tester.pumpAndSettle();
      await menu.select(
        'Source',
      ); // Explicit modes work with enableModeShortcuts:false.
      final source = find.byKey(const ValueKey('ianvs-markdown-source-field'));
      await tester.enterText(source, 'edited');
      document.controller.commitHistoryGroup();
      await commandKey(tester, LogicalKeyboardKey.keyZ);
      expect(document.controller.text, 'edited');
      await commandKey(tester, LogicalKeyboardKey.keyS);
      expect(files.files['/notes/input.md'], 'seed ');
      expect(menu.items['Save']!['shortcutCharacter'], isNull);
      await menu.select('Save');
      expect(files.files['/notes/input.md'], 'edited');
      await menu.select('Undo');
      expect(document.controller.text, 'seed ');
      await menu.select('Redo');
      expect(document.controller.text, 'edited');
      final search = find.descendant(
        of: find.byKey(const ValueKey('workspace-search-field')),
        matching: find.byType(TextField),
      );
      await tester.tap(search);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(search, 'find');
      await tester.pump(const Duration(milliseconds: 600));
      await menu.select('Undo');
      expect(tester.widget<TextField>(search).controller!.text, '');
      expect(document.controller.text, 'edited');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
