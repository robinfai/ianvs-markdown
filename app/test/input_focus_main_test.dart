import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import '../../test/fixtures/input_focus_contract.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'app menu modes reconnect input after composition commit and cancel',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
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
      await tester.pumpAndSettle();
      await exerciseInputFocus(tester, document.controller, (mode) async {
        final label = switch (mode) {
          IanvsMarkdownEditorMode.livePreview => 'Live Preview',
          IanvsMarkdownEditorMode.source => 'Source',
          IanvsMarkdownEditorMode.preview => 'Read',
        };
        final menu = tester.widget<PlatformMenuBar>(
          find.byType(PlatformMenuBar),
        );
        final view = menu.menus.whereType<PlatformMenu>().singleWhere(
          (item) => item.label == 'View',
        );
        final modes = view.menus.whereType<PlatformMenuItemGroup>().first;
        modes.members.singleWhere((item) => item.label == label).onSelected!();
        await tester.pumpAndSettle();
        expect(document.controller.mode, mode);
      });
      expect(await workspace.saveActive(), isTrue);
      expect(files.files['/notes/input.md'], 'seed 你好嘛');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
