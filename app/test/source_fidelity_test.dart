import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'Linefold preserves exact source through modes, undo and reopen',
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
      const source =
          '---\r\ntitle: 中文 😀\r\n---\r\n# 标题\r\n\r\n'
          '**保真** [链接](notes/a.md)  \r\n\t缩进\r\n\r\n'
          '| A | B |\r\n| --- | --- |\r\n| a \\| b | 😀 |\r\n\r\n'
          '```dart\r\nfinal value = "中文";\r\n```\r\n无尾换行';
      final files = MemoryMarkdownFileService()
        ..files['/notes/source.md'] = source;
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
      await tester.pumpAndSettle();
      final document = (await workspace.openPath('/notes/source.md'))!;
      await tester.pumpAndSettle();
      Future<void> mode(String name) async {
        final value = {
          'Source': 'source',
          'Live Preview': 'livePreview',
          'Read': 'preview',
        }[name]!;
        await tester.tap(find.byTooltip('Editor mode'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('editor-mode-$value')));
        await tester.pumpAndSettle();
      }

      for (final name in ['Source', 'Live Preview', 'Read', 'Source']) {
        await mode(name);
        expect(document.controller.text, source, reason: 'after $name');
        expect(document.controller.isDirty, isFalse);
      }
      final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
      await tester.enterText(field, '$source\r\n追加😀');
      await tester.pumpAndSettle();
      document.controller.commitHistoryGroup();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(document.controller.text, source);
      expect(document.controller.isDirty, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(document.controller.text, '$source\r\n追加😀');
      expect(await workspace.saveActive(), isTrue);
      expect(files.files['/notes/source.md'], '$source\r\n追加😀');
      workspace.removeDocument(document);
      final reopened = (await workspace.openPath('/notes/source.md'))!;
      await tester.pumpAndSettle();
      expect(reopened.controller.text, '$source\r\n追加😀');
      expect(reopened.controller.isDirty, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
