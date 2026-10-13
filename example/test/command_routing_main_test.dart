import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_example/main.dart';

import '../../test/fixtures/native_menu_harness.dart';

void main() {
  testWidgets(
    'native property undo matches local keyboard undo',
    (tester) async {
      final menu = NativeMenuHarness(tester);
      await tester.pumpWidget(const ExampleApp());
      await tester.pumpAndSettle();
      final controller = tester
          .widget<IanvsMarkdownLiveEditor>(find.byType(IanvsMarkdownLiveEditor))
          .controller;
      final field = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-author'),
      );
      await tester.tap(field);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(field, 'Changed author');
      await tester.pump(const Duration(milliseconds: 600));
      await commandKey(tester, LogicalKeyboardKey.keyZ);
      expect(tester.widget<TextField>(field).controller!.text, 'Ianvs');
      await tester.enterText(field, 'Changed again');
      await tester.pump(const Duration(milliseconds: 600));
      await menu.select('Undo');
      expect(tester.widget<TextField>(field).controller!.text, 'Ianvs');
      expect(controller.text, exampleMarkdown);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'native modes preserve active source composition',
    (tester) async {
      final menu = NativeMenuHarness(tester);
      await tester.pumpWidget(const ExampleApp());
      await tester.pumpAndSettle();
      final controller = tester
          .widget<IanvsMarkdownLiveEditor>(find.byType(IanvsMarkdownLiveEditor))
          .controller;
      await menu.select('Source');
      final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
      await tester.enterText(field, 'seed ');
      const composing = TextEditingValue(
        text: 'seed ni',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 7),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      await menu.select('Read');
      expect(controller.mode, IanvsMarkdownEditorMode.source);
      expect(controller.value, composing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'native editor menus do not steal remapped accelerators',
    (tester) async {
      final menu = NativeMenuHarness(tester);
      await tester.pumpWidget(
        const IanvsMarkdownShortcuts(
          bindings: {
            IanvsMarkdownCommand.undo: [SingleActivator(LogicalKeyboardKey.f3)],
          },
          child: ExampleApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(menu.items['Undo']!['shortcutCharacter'], isNull);
      expect(menu.items['Undo']!['shortcutTrigger'], isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
