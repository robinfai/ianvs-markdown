import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_example/main.dart';

void main() {
  for (final mode in ['源码模式', '实时预览', '阅读模式']) {
    testWidgets(
      'main $mode copies complete source through the plain writer',
      (tester) async {
        const source =
            '---\r\ntitle: 中文😀\r\n---\r\n# Copy fixture\r\n\r\n**Bold** and [local](next.md)  \r\n\r\n![blocked](missing.png)\r\nNo final newline';
        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData')
              copied.add((call.arguments as Map)['text'] as String);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(const ExampleApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('源码模式'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('ianvs-markdown-source-field')),
          source,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(mode));
        await tester.pumpAndSettle();
        if (mode == '源码模式') {
          await tester.tap(
            find.byKey(const ValueKey('ianvs-markdown-source-field')),
          );
        } else if (mode == '阅读模式') {
          await tester.tap(
            find
                .descendant(
                  of: find.byType(SelectionArea),
                  matching: find.text('Copy fixture'),
                )
                .first,
          );
        } else {
          await tester.tap(find.text('Copy fixture').first);
        }
        await tester.pumpAndSettle();
        for (final key in [LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyC]) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pumpAndSettle();
        }
        expect(copied, isNotEmpty);
        expect(copied.last, source);
        final editor = tester.widget<IanvsMarkdownLiveEditor>(
          find.byType(IanvsMarkdownLiveEditor),
        );
        expect(editor.controller.text, source);
        expect(editor.imageBuilder, isNull);
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
