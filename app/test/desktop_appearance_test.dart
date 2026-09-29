import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_design/ianvs_design.dart' show IanvsTokens;
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/widgets/editor_shell.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'system appearance follows macOS and can be restored after an override',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
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
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
      await tester.pumpAndSettle();
      ThemeData theme() => Theme.of(tester.element(find.byType(EditorShell)));
      void command(String label) => tester
          .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
          .menus
          .whereType<PlatformMenu>()
          .singleWhere((menu) => menu.label == 'View')
          .descendants
          .singleWhere((item) => item.label == label)
          .onSelected!();
      expect(theme().brightness, Brightness.dark);
      expect(theme().extension<IanvsTokens>(), isNotNull);
      expect(theme().extension<IanvsMarkdownThemeData>(), isNotNull);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(theme().brightness, Brightness.light);
      command('Toggle Appearance');
      await tester.pumpAndSettle();
      expect(theme().brightness, Brightness.dark);
      command('Use System Appearance');
      await tester.pumpAndSettle();
      expect(theme().brightness, Brightness.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(theme().brightness, Brightness.dark);
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      await files.dispose();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
