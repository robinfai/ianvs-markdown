import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_example/main.dart';

import '../../test/fixtures/input_focus_contract.dart';
import '../../test/fixtures/live_block_contract.dart';

void main() {
  testWidgets(
    'main keyboard modes reconnect input after composition commit and cancel',
    (tester) async {
      await tester.pumpWidget(const ExampleApp());
      await tester.pumpAndSettle();
      final controller = tester
          .widget<IanvsMarkdownLiveEditor>(find.byType(IanvsMarkdownLiveEditor))
          .controller;
      await tester.tap(find.byTooltip('源码模式'));
      await tester.pumpAndSettle();
      await exerciseInputFocus(tester, controller, (mode) async {
        final key = switch (mode) {
          IanvsMarkdownEditorMode.livePreview => LogicalKeyboardKey.digit1,
          IanvsMarkdownEditorMode.source => LogicalKeyboardKey.digit2,
          IanvsMarkdownEditorMode.preview => LogicalKeyboardKey.digit3,
        };
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(controller.mode, mode);
      });
      await exerciseLiveBlockIdentity(tester, controller);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
