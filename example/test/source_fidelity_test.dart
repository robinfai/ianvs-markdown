import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_example/main.dart';

const _source =
    '---\ntitle: 中文 😀\n---\n# 标题\n\n'
    '保留 **强调**、[链接](notes/a.md "标题") 和 `代码`。  \n'
    '\t缩进\n\n| A | B |\n| --- | --- |\n| a \\| b | 中文 |\n\n'
    '```dart\nfinal value = "😀";\n```\n\n末尾没有换行';

void main() {
  for (final ending in ['LF', 'CRLF']) {
    testWidgets('main playground preserves $ending source and edit history', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ExampleApp());
      await tester.pumpAndSettle();
      final controller = tester
          .widget<IanvsMarkdownLiveEditor>(find.byType(IanvsMarkdownLiveEditor))
          .controller;
      final source = ending == 'LF'
          ? _source
          : _source.replaceAll('\n', '\r\n');
      final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
      await tester.tap(find.byTooltip('源码模式'));
      await tester.pumpAndSettle();
      await tester.enterText(field, source);
      await tester.pumpAndSettle();
      controller.commitHistoryGroup();
      for (final mode in ['实时预览', '阅读模式', '源码模式']) {
        await tester.tap(find.byTooltip(mode));
        await tester.pumpAndSettle();
        expect(controller.text, source, reason: '$ending after $mode');
      }

      // Exercise the source field and real toolbar, not a detached controller.
      await tester.tap(field);
      final start = source.indexOf('强调');
      final selection = TextSelection(
        baseOffset: start,
        extentOffset: start + 2,
      );
      tester.testTextInput.updateEditingValue(
        TextEditingValue(text: source, selection: selection),
      );
      await tester.pump();
      expect(controller.selection, selection);
      final edited = source.replaceRange(start, start + 2, '替换😀');
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: edited,
          selection: TextSelection.collapsed(offset: start + '替换😀'.length),
        ),
      );
      await tester.pump();
      controller.commitHistoryGroup();
      expect(controller.text, edited);
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(controller.text, source);
      expect(controller.selection, selection);
      await tester.tap(find.byTooltip('重做'));
      await tester.pumpAndSettle();
      expect(controller.text, edited);
      await tester.tap(find.byTooltip('保存'));
      await tester.pumpAndSettle();
      expect(find.text('Host save callback invoked'), findsOneWidget);
      expect(controller.text, edited);
      await tester.tap(find.byTooltip('Reset example'));
      await tester.pumpAndSettle();
      expect(controller.text, exampleMarkdown);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
