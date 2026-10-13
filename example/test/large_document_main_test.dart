import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_example/main.dart';

import '../../test/fixtures/large_documents.dart';

void main() {
  for (final entry in largeDocuments.entries) {
    testWidgets(
      'main preserves default-budget ${entry.key} through modes and copy',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String;
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
        final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
        await tester.enterText(field, entry.value);
        await tester.pumpAndSettle();
        final controller = tester
            .widget<IanvsMarkdownLiveEditor>(
              find.byType(IanvsMarkdownLiveEditor),
            )
            .controller;
        expect(controller.parseDecision.budgetExceeded?.name, entry.key);
        await tester.tap(find.byTooltip('实时预览'));
        await tester.pumpAndSettle();
        expect(field, findsOneWidget);
        expect(
          tester
              .widget<IanvsMarkdownEditor>(find.byType(IanvsMarkdownEditor))
              .highlightSyntax,
          isFalse,
        );
        expect(
          find.byKey(const ValueKey('ianvs-markdown-budget-notice')),
          findsOneWidget,
        );
        final edited = '${entry.value} edited';
        await tester.enterText(field, edited);
        await tester.pumpAndSettle();
        controller.commitHistoryGroup();
        await tester.tap(find.byTooltip('阅读模式'));
        await tester.pumpAndSettle();
        final fallback = find.byKey(
          const ValueKey('ianvs-markdown-plain-fallback'),
        );
        expect(fallback, findsOneWidget);
        expect(
          find.byKey(const ValueKey('ianvs-markdown-budget-notice')),
          findsOneWidget,
        );
        final decision = scanMarkdownForRendering(
          edited,
          budget: const IanvsMarkdownRenderBudget(),
        );
        expect(tester.widget<Text>(fallback).data == decision.text, isTrue);
        expect(decision.truncated, entry.key == 'sourceLength');
        await tester.tapAt(tester.getTopLeft(fallback) + const Offset(8, 8));
        await tester.pumpAndSettle();
        for (final key in [LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyC]) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pumpAndSettle();
        }
        expect(
          copied == edited,
          isTrue,
          reason:
              'Copy contains full source, including its tail, without the notice',
        );
        await tester.tap(find.byTooltip('源码模式'));
        await tester.pumpAndSettle();
        expect(controller.text == edited, isTrue);
        await tester.tap(find.byTooltip('保存'));
        await tester.pumpAndSettle();
        expect(find.text('Host save callback invoked'), findsOneWidget);
        await tester.tap(find.byTooltip('Reset example'));
        await tester.pumpAndSettle();
        expect(controller.text, exampleMarkdown);
        expect(
          find.byKey(const ValueKey('ianvs-markdown-budget-notice')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
