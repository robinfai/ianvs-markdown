import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  test(
    'external host observes parse and clipboard budgets without source loss',
    () {
      const budget = IanvsMarkdownRenderBudget(
        maxLineCodeUnits: 8,
        maxFallbackBytes: 4,
      );
      const source = '# preserved source\r\n中文😀';
      final controller = IanvsMarkdownController(
        text: source,
        parseBudget: budget,
      );
      addTearDown(controller.dispose);
      expect(controller.text, source);
      expect(
        controller.parseDecision.budgetExceeded,
        IanvsMarkdownBudgetExceeded.lineLength,
      );
      final document = IanvsMarkdownDocument.parse(source, budget: budget);
      expect(document.body, source);
      expect(document.headings, isEmpty);
      final copy = ianvsMarkdownDocumentClipboardData(source, budget: budget);
      expect(copy.markdown, source);
      expect(copy.hasHtml, isFalse);
      expect(copy.budgetExceeded, IanvsMarkdownBudgetExceeded.lineLength);
    },
  );

  testWidgets('migration keeps exact plain text with and without HTML', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final source = '---\r\ntitle: 中文😀\r\n---\r\n${'a' * 4097}';
    final data = ianvsMarkdownDocumentClipboardData(source);
    expect(data.hasHtml, isFalse);
    expect(data.budgetExceeded, IanvsMarkdownBudgetExceeded.lineLength);
    await writeIanvsMarkdownClipboard(data);
    // Existing hosts can still construct the original required payload fields.
    await writeIanvsMarkdownClipboard(
      const IanvsMarkdownClipboardData(
        markdown: '**legacy**',
        html: '<strong>legacy</strong>',
      ),
    );
    expect(calls.map((call) => call.method), [
      'Clipboard.setData',
      'Clipboard.setData',
    ]);
    expect(calls.map((call) => call.arguments), [
      {'text': source},
      {'text': '**legacy**'},
    ]);
  });

  test('migration budgets remain local to each operation', () {
    final source = 'a' * 4097;
    final controller = IanvsMarkdownController(text: source, parseBudget: null);
    addTearDown(controller.dispose);
    expect(controller.parseDecision.budgetExceeded, isNull);
    final copy = ianvsMarkdownDocumentClipboardData(source);
    expect(copy.budgetExceeded, IanvsMarkdownBudgetExceeded.lineLength);
    expect(copy.markdown, source);
    expect(copy.hasHtml, isFalse);
    final explicitlyUnbounded = ianvsMarkdownDocumentClipboardData(
      source,
      budget: null,
    );
    expect(explicitlyUnbounded.budgetExceeded, isNull);
    expect(explicitlyUnbounded.hasHtml, isTrue);
    expect(explicitlyUnbounded.markdown, source);
  });

  test('migration offers bounded history and explicit legacy retention', () {
    final bounded = IanvsMarkdownController(text: 'version 0');
    final legacy = IanvsMarkdownController(
      text: 'version 0',
      historyPolicy: null,
    );
    addTearDown(bounded.dispose);
    addTearDown(legacy.dispose);
    for (var version = 1; version <= 205; version++) {
      for (final controller in [bounded, legacy]) {
        controller.commitHistoryGroup();
        controller.value = TextEditingValue(
          text: 'version $version',
          selection: const TextSelection.collapsed(offset: 0),
        );
        controller.commitHistoryGroup();
      }
    }
    expect(bounded.retainedHistoryEntries, 200);
    expect(legacy.retainedHistoryEntries, 206);
    expect(bounded.text, legacy.text);
    for (final controller in [bounded, legacy]) {
      while (controller.canUndo) {
        controller.undo();
      }
    }
    expect(bounded.text, 'version 6');
    expect(bounded.isDirty, isTrue);
    expect(legacy.text, 'version 0');
    expect(legacy.isDirty, isFalse);
  });

  testWidgets('migration save captures source through fallback and retry', (
    tester,
  ) async {
    const budget = IanvsMarkdownRenderBudget(maxLineCodeUnits: 8);
    final controller = IanvsMarkdownController(
      text: '# Original document',
      mode: IanvsMarkdownEditorMode.source,
      parseBudget: budget,
      historyPolicy: const IanvsMarkdownHistoryPolicy(maxEntries: 3),
    );
    addTearDown(controller.dispose);
    final captured = <String>[];
    final pending = <Completer<void>>[];
    controller.text = '# Captured document\r\n中文😀';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            renderBudget: budget,
            onSaveRequested: (source) {
              captured.add(source);
              final gate = Completer<void>();
              pending.add(gate);
              return gate.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('保存'));
    await tester.pump();
    const newer = '# Newer document\r\n中文😀';
    controller.text = newer;
    pending[0].complete();
    await tester.pump();
    expect(captured, ['# Captured document\r\n中文😀']);
    expect(controller.text, newer);
    expect(controller.isDirty, isTrue);
    expect(
      controller.parseDecision.budgetExceeded,
      IanvsMarkdownBudgetExceeded.lineLength,
    );
    await tester.tap(find.byTooltip('保存'));
    await tester.pump();
    pending[1].completeError(const IanvsMarkdownSaveCancelledException());
    await tester.pump();
    expect(controller.isDirty, isTrue);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('保存'));
    await tester.pump();
    pending[2].complete();
    await tester.pump();
    expect(captured, ['# Captured document\r\n中文😀', newer, newer]);
    expect(controller.text, newer);
    expect(controller.isDirty, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external host renders, edits, saves and restores exact source', (
    tester,
  ) async {
    const source = '# 外部宿主\n\nHello **Markdown**.\n\n- [ ] Task';
    final controller = IanvsMarkdownController(text: source);
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLocalization(
            strings: const IanvsMarkdownStrings.english(
              overrides: {IanvsMarkdownMessage.save: 'Persist note'},
            ),
            child: IanvsMarkdownShortcuts(
              bindings: const {
                IanvsMarkdownCommand.source: [
                  SingleActivator(LogicalKeyboardKey.f2),
                ],
                IanvsMarkdownCommand.save: [
                  SingleActivator(LogicalKeyboardKey.f3),
                ],
              },
              child: IanvsMarkdownLiveEditor(
                controller: controller,
                focusNode: focus,
                onSaveRequested: (value) => saved = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('外部宿主'), findsWidgets);
    await tester.tap(find.text('外部宿主').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
    expect(field, findsOneWidget);
    expect(focus.hasFocus, isTrue);
    await tester.enterText(field, '$source\n\nNew paragraph.');
    await tester.pump();
    expect(find.byTooltip('Persist note'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    expect(saved, '$source\n\nNew paragraph.');
    controller.undo();
    await tester.pump();
    expect(controller.text, source);
    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    expect(find.text('外部宿主'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
