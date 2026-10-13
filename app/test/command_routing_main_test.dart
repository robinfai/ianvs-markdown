import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import '../../test/fixtures/native_menu_harness.dart';
import 'support/fakes.dart';

void main() {
  for (final command in ['Undo', 'Read']) {
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
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 600));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
