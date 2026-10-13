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
      await menu.select('Redo');
      expect(tester.widget<TextField>(field).controller!.text, 'Changed again');
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Ianvs');
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(controller.text, exampleMarkdown);
      await tester.enterText(field, 'Saved author');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byTooltip('保存'));
      await tester.pumpAndSettle();
      expect(controller.text, contains('author: Saved author'));
      expect(controller.isDirty, isFalse);
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
      for (final label in [
        'Undo',
        'Redo',
        'Read',
        'Cut',
        'Paste',
        'Select All',
      ]) {
        await menu.select(label);
        expect(controller.value, composing);
      }
      for (final key in [
        LogicalKeyboardKey.keyZ,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.keyB,
      ]) {
        await commandKey(tester, key);
        expect(controller.value, composing);
      }
      await tester.tap(find.byTooltip('阅读模式'));
      await tester.pumpAndSettle();
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
      await menu.select('Source');
      final controller = tester
          .widget<IanvsMarkdownLiveEditor>(find.byType(IanvsMarkdownLiveEditor))
          .controller;
      final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
      await tester.enterText(field, 'Edited');
      controller.commitHistoryGroup();
      await commandKey(tester, LogicalKeyboardKey.keyZ);
      expect(controller.text, 'Edited');
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(controller.text, exampleMarkdown);
      await menu.select('Redo');
      expect(controller.text, 'Edited');
      await menu.select('Undo');
      expect(controller.text, exampleMarkdown);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    'main native table history and Read toolbar preserve scope',
    (tester) async {
      final menu = NativeMenuHarness(tester);
      await tester.pumpWidget(const ExampleApp());
      await tester.pumpAndSettle();
      final controller = tester
          .widget<IanvsMarkdownLiveEditor>(find.byType(IanvsMarkdownLiveEditor))
          .controller;
      await menu.select('Source');
      const table = '| Original | B |\n| --- | --- |\n| C | D |';
      await tester.enterText(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
        table,
      );
      controller.commitHistoryGroup();
      await tester.pumpAndSettle();
      await tester.tap(find.text('ianvs_markdown example'));
      await tester.pumpAndSettle();
      await menu.select('Live Preview');
      expect(controller.mode, IanvsMarkdownEditorMode.livePreview);
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-0-0'));
      await tester.tap(cell);
      await tester.pumpAndSettle();
      await tester.enterText(cell, 'Changed');
      controller.commitHistoryGroup();
      final edited = controller.text;
      await menu.select('Undo');
      expect(controller.text, table);
      await menu.select('Redo');
      expect(controller.text, edited);
      const pendingCell = TextEditingValue(
        text: 'Changedni',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 7, end: 9),
      );
      tester.testTextInput.updateEditingValue(pendingCell);
      await tester.pumpAndSettle();
      final pendingDocument = controller.value;
      for (final label in ['Undo', 'Read']) {
        await menu.select(label);
        expect(controller.value, pendingDocument);
        expect(tester.widget<TextField>(cell).controller!.value, pendingCell);
      }
      tester.testTextInput.updateEditingValue(
        pendingCell.copyWith(
          text: 'Changed',
          selection: const TextSelection.collapsed(offset: 7),
          composing: TextRange.empty,
        ),
      );
      await tester.pumpAndSettle();
      await menu.select('Read');
      await menu.select('Undo');
      expect(controller.text, edited);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.undo_rounded),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.redo_rounded),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    'main Live and property composing survive commands',
    (tester) async {
      final menu = NativeMenuHarness(tester);
      await tester.pumpWidget(const ExampleApp());
      await tester.pumpAndSettle();
      final controller = tester
          .widget<IanvsMarkdownLiveEditor>(find.byType(IanvsMarkdownLiveEditor))
          .controller;
      final author = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-author'),
      );
      await tester.tap(author);
      await tester.pumpAndSettle();
      const property = TextEditingValue(
        text: 'Ianvsni',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 7),
      );
      tester.testTextInput.updateEditingValue(property);
      await tester.pumpAndSettle();
      for (final label in ['Undo', 'Read', 'Source']) {
        await menu.select(label);
        expect(tester.widget<TextField>(author).controller!.value, property);
        expect(controller.text, exampleMarkdown);
      }
      tester.testTextInput.updateEditingValue(
        property.copyWith(
          text: 'Ianvs',
          selection: const TextSelection.collapsed(offset: 5),
          composing: TextRange.empty,
        ),
      );
      await tester.pumpAndSettle();
      await menu.select('Source');
      await tester.enterText(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
        'seed ',
      );
      await menu.select('Live Preview');
      const live = TextEditingValue(
        text: 'seed ni',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 7),
      );
      tester.testTextInput.updateEditingValue(live);
      await tester.pumpAndSettle();
      for (final label in ['Undo', 'Read', 'Source', 'Cut']) {
        await menu.select(label);
        expect(controller.value, live);
        expect(controller.mode, IanvsMarkdownEditorMode.livePreview);
      }
      await commandKey(tester, LogicalKeyboardKey.keyZ);
      expect(controller.value, live);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
