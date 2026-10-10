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
