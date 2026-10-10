import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

const smallBudget = IanvsMarkdownRenderBudget(
  maxSourceCodeUnits: 64,
  maxLineCodeUnits: 16,
  maxSyntaxTokens: 8,
  maxFallbackBytes: 10,
);

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> copyAll(WidgetTester tester) async {
  for (final key in [LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyC]) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }
}

void main() {
  test('length boundaries use UTF-16 and ignore physical line separators', () {
    for (final separator in ['\n', '\r\n']) {
      final exact = scanMarkdownForRendering(
        '${'😀' * 8}$separator${'a' * 16}',
        budget: smallBudget,
      );
      expect(exact.useMarkdown, isTrue);
      final overflow = scanMarkdownForRendering(
        '${'a' * 16}$separator😀${'a' * 15}',
        budget: smallBudget,
      );
      expect(overflow.budgetExceeded, IanvsMarkdownBudgetExceeded.lineLength);
    }
    final exact = scanMarkdownForRendering('a\n' * 32, budget: smallBudget);
    final overflow = scanMarkdownForRendering('a\n' * 33, budget: smallBudget);
    expect(exact.useMarkdown, isTrue);
    expect(overflow.budgetExceeded, IanvsMarkdownBudgetExceeded.sourceLength);
    expect(
      scanMarkdownForRendering('a\r' * 16, budget: smallBudget).budgetExceeded,
      IanvsMarkdownBudgetExceeded.lineLength,
    );
  });

  test('reasons and UTF-8 fallback are observable without changing source', () {
    final fixtures = {
      'a\n' * 33: IanvsMarkdownBudgetExceeded.sourceLength,
      '[${'a' * 16}': IanvsMarkdownBudgetExceeded.lineLength,
      '**😀😀😀** __x__ *': IanvsMarkdownBudgetExceeded.syntaxTokens,
    };
    for (final fixture in fixtures.entries) {
      final budget = fixture.value == IanvsMarkdownBudgetExceeded.syntaxTokens
          ? const IanvsMarkdownRenderBudget(
              maxSyntaxTokens: 4,
              maxFallbackBytes: 10,
            )
          : smallBudget;
      final decision = scanMarkdownForRendering(fixture.key, budget: budget);
      expect(decision.budgetExceeded, fixture.value);
      expect(decision.useMarkdown, isFalse);
      expect(decision.truncated, isTrue);
      expect(utf8.encode(decision.text).length, lessThanOrEqualTo(10));
      expect(fixture.key, startsWith(decision.text));
      final disabled = scanMarkdownForRendering(fixture.key, budget: null);
      expect(disabled.useMarkdown, isTrue);
      expect(disabled.text, fixture.key);
    }
    final zero = scanMarkdownForRendering(
      'x',
      budget: const IanvsMarkdownRenderBudget(
        maxSourceCodeUnits: 0,
        maxFallbackBytes: 0,
      ),
    );
    expect(zero.text, isEmpty);
    expect(zero.truncated, isTrue);
  });

  test(
    'controller changes, undo and redo retain complete over-budget source',
    () {
      const initial = '[ref]\n\n[ref]: x';
      final oversized = '[${'a' * 80}\r\n😀';
      final controller = IanvsMarkdownController(
        text: initial,
        parseBudget: smallBudget,
      );
      addTearDown(controller.dispose);
      final observed = <IanvsMarkdownBudgetExceeded?>[];
      controller.addListener(
        () => observed.add(controller.parseDecision.budgetExceeded),
      );
      controller.text = oversized;
      final cached = controller.parseDecision;
      controller.selection = const TextSelection.collapsed(offset: 1);
      expect(controller.parseDecision, same(cached));
      expect(controller.text, oversized);
      expect(observed, everyElement(IanvsMarkdownBudgetExceeded.sourceLength));
      controller.markSaved();
      expect(controller.isDirty, isFalse);
      controller.undo();
      expect(controller.text, initial);
      expect(controller.parseDecision.useMarkdown, isTrue);
      expect(controller.isDirty, isTrue);
      controller.redo();
      expect(controller.text, oversized);
      expect(controller.parseDecision.useMarkdown, isFalse);
      expect(controller.isDirty, isFalse);
    },
  );

  test('document and fold models reject before YAML and heading parsing', () {
    final source = '---\ntitle: YAML\n---\n# ${'x' * 40}';
    final doc = IanvsMarkdownDocument.parse(source, budget: smallBudget);
    expect(doc.source, source);
    expect(doc.body, source);
    expect(
      doc.parseDecision!.budgetExceeded,
      IanvsMarkdownBudgetExceeded.lineLength,
    );
    expect(doc.metadata, isEmpty);
    expect(doc.headings, isEmpty);
    expect(doc.hasFrontMatter, isFalse);
    for (final preset in IanvsMarkdownSyntaxPreset.values) {
      final folds = IanvsMarkdownHeadingFoldModel.parse(
        source,
        budget: smallBudget,
        syntaxPreset: preset,
      );
      expect(folds.source, source);
      expect(folds.blocks, isEmpty);
      expect(folds.sections, isEmpty);
      expect(folds.budgetExceeded, IanvsMarkdownBudgetExceeded.lineLength);
      final controller = IanvsMarkdownHeadingFoldController();
      expect(folds.project(controller).source, source);
      controller.dispose();
    }
    final unrestricted = IanvsMarkdownDocument.parse(source, budget: null);
    expect(unrestricted.hasFrontMatter, isTrue);
    expect(unrestricted.headings, hasLength(1));
  });

  test(
    'whole and partial copies keep complete text and expose missing HTML',
    () {
      final source = '---\r\ntitle: 中文\r\n---\r\n[${'a' * 100}😀';
      final whole = ianvsMarkdownDocumentClipboardData(
        source,
        budget: smallBudget,
      );
      expect(whole.markdown, source);
      expect(whole.html, isEmpty);
      expect(whole.hasHtml, isFalse);
      expect(whole.budgetExceeded, IanvsMarkdownBudgetExceeded.sourceLength);
      const selected = '中文😀';
      final partial = ianvsMarkdownSelectionClipboardData(
        source,
        selected,
        budget: smallBudget,
      );
      expect(partial.markdown, selected);
      expect(partial.hasHtml, isFalse);
      expect(partial.budgetExceeded, whole.budgetExceeded);
      IanvsMarkdownBudgetExceeded? reason;
      expect(
        ianvsMarkdownClipboardHtml(
          source,
          budget: smallBudget,
          onBudgetExceeded: (value) => reason = value,
        ),
        isEmpty,
      );
      expect(reason, whole.budgetExceeded);
      final rich = ianvsMarkdownDocumentClipboardData('**ok**', budget: null);
      expect(rich.html, contains('<strong>ok</strong>'));
      expect(rich.budgetExceeded, isNull);
    },
  );

  test('copy projections and selected text cannot bypass input budget', () {
    final large = 'x' * 70;
    expect(
      ianvsMarkdownDocumentClipboardData(
        large,
        richMarkdown: 'small',
        budget: smallBudget,
      ).hasHtml,
      isFalse,
    );
    expect(
      ianvsMarkdownDocumentClipboardData(
        'small',
        richMarkdown: large,
        budget: smallBudget,
      ).hasHtml,
      isFalse,
    );
    final selected = ianvsMarkdownSelectionClipboardData(
      'small',
      large,
      budget: smallBudget,
    );
    expect(selected.markdown, large);
    expect(selected.hasHtml, isFalse);
  });

  test('over-budget input formatter passes through edits and composition', () {
    final source = 'x' * 70;
    final before = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: source.length),
    );
    final after = TextEditingValue(
      text: '$source[',
      selection: TextSelection.collapsed(offset: source.length + 1),
    );
    final formatter = IanvsMarkdownEditingFormatter(budget: smallBudget);
    expect(formatter.formatEditUpdate(before, after), after);
    final composing = after.copyWith(
      composing: TextRange(start: source.length, end: source.length + 1),
    );
    expect(formatter.formatEditUpdate(before, composing), composing);
    final shortened = const TextEditingValue(
      text: '**ok**',
      selection: TextSelection.collapsed(offset: 6),
    );
    expect(formatter.formatEditUpdate(before, shortened), shortened);
  });

  for (final surface in ['Body', 'View', 'Live Reading']) {
    testWidgets(
      '$surface full copy ignores display truncation',
      (tester) async {
        final source = '[${'a' * 80}\r\n😀';
        final controller = IanvsMarkdownController(
          text: source,
          mode: IanvsMarkdownEditorMode.preview,
          parseBudget: smallBudget,
        );
        addTearDown(controller.dispose);
        IanvsMarkdownClipboardData? copied;
        IanvsMarkdownRenderDecision? fallback;
        Widget builder(
          BuildContext context,
          IanvsMarkdownRenderDecision decision,
        ) {
          fallback = decision;
          return Text(decision.text);
        }

        await tester.pumpWidget(
          host(
            surface == 'Live Reading'
                ? IanvsMarkdownLiveEditor(
                    controller: controller,
                    renderBudget: smallBudget,
                    clipboardBudget: smallBudget,
                    onRenderDecision: (decision) => fallback = decision,
                    clipboardWriter: (data) async => copied = data,
                  )
                : surface == 'View'
                ? IanvsMarkdownView(
                    data: source,
                    renderBudget: smallBudget,
                    clipboardBudget: smallBudget,
                    enableHeadingFolding: true,
                    fallbackBuilder: builder,
                    clipboardWriter: (data) async => copied = data,
                  )
                : IanvsMarkdown(
                    data: source,
                    renderBudget: smallBudget,
                    clipboardBudget: smallBudget,
                    fallbackBuilder: builder,
                    clipboardWriter: (data) async => copied = data,
                  ),
          ),
        );
        expect(
          fallback!.budgetExceeded,
          IanvsMarkdownBudgetExceeded.sourceLength,
        );
        await tester.tap(find.text(fallback!.text));
        await tester.pump();
        await copyAll(tester);
        expect(copied!.markdown, source);
        expect(copied!.hasHtml, isFalse);
        expect(copied!.budgetExceeded, fallback!.budgetExceeded);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'disabling rendering budget does not disable clipboard guard',
    (tester) async {
      IanvsMarkdownClipboardData? copied;
      await tester.pumpWidget(
        host(
          IanvsMarkdownView(
            data: '**hello**',
            renderBudget: null,
            clipboardBudget: const IanvsMarkdownRenderBudget(
              maxSyntaxTokens: 0,
            ),
            clipboardWriter: (data) async => copied = data,
          ),
        ),
      );
      await tester.tap(find.text('hello'));
      await tester.pump();
      await copyAll(tester);
      expect(copied!.markdown, '**hello**');
      expect(copied!.hasHtml, isFalse);
      expect(copied!.budgetExceeded, IanvsMarkdownBudgetExceeded.syntaxTokens);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'zero-byte display still supports explicit full-source copy',
    (tester) async {
      const source = '**original**\r\n中文😀';
      const budget = IanvsMarkdownRenderBudget(
        maxSourceCodeUnits: 0,
        maxFallbackBytes: 0,
      );
      IanvsMarkdownClipboardData? copied;
      await tester.pumpWidget(
        host(
          IanvsMarkdownView(
            data: source,
            autofocus: true,
            renderBudget: budget,
            clipboardBudget: budget,
            clipboardWriter: (data) async => copied = data,
          ),
        ),
      );
      await tester.pump();
      await copyAll(tester);
      expect(copied!.markdown, source);
      expect(copied!.hasHtml, isFalse);
      expect(copied!.budgetExceeded, IanvsMarkdownBudgetExceeded.sourceLength);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Live input uses the host controller budget independently of rendering',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: 'abc',
        parseBudget: const IanvsMarkdownRenderBudget(maxSourceCodeUnits: 0),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          IanvsMarkdownLiveEditor(
            controller: controller,
            renderBudget: null,
            autofocus: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abc[',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pumpAndSettle();
      // Input limits preserve raw input instead of auto-pairing a closing ']'.
      expect(controller.text, 'abc[');
      expect(
        controller.parseDecision.budgetExceeded,
        IanvsMarkdownBudgetExceeded.sourceLength,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Live budget fallback preserves edits, selection, IME and undo', (
    tester,
  ) async {
    final source = '[${'a' * 80}';
    final controller = IanvsMarkdownController(
      text: source,
      parseBudget: smallBudget,
    );
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    final decisions = <IanvsMarkdownRenderDecision>[];
    await tester.pumpWidget(
      host(
        IanvsMarkdownLiveEditor(
          controller: controller,
          focusNode: focus,
          autofocus: true,
          renderBudget: smallBudget,
          onRenderDecision: decisions.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      findsOneWidget,
    );
    expect(controller.mode, IanvsMarkdownEditorMode.livePreview);
    expect(controller.text, source);
    expect(decisions.single.useMarkdown, isFalse);
    expect(focus.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), '$source中文');
    await tester.pump();
    controller.value = controller.value.copyWith(
      composing: TextRange(start: source.length, end: source.length + 2),
    );
    await tester.pump();
    expect(controller.text, '$source中文');
    expect(
      controller.value.composing,
      TextRange(start: source.length, end: source.length + 2),
    );
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    controller.commitHistoryGroup();
    controller.text = '# Short';
    await tester.pumpAndSettle();
    expect(decisions.last.useMarkdown, isTrue);
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, '$source中文');
    expect(decisions.last.useMarkdown, isFalse);
    controller.mode = IanvsMarkdownEditorMode.source;
    await tester.pumpAndSettle();
    expect(controller.text, '$source中文');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'budget-only update and controller replacement drop stale results',
    (tester) async {
      final controller = IanvsMarkdownController(text: '# Title');
      final other = IanvsMarkdownController(text: '# Replacement');
      addTearDown(controller.dispose);
      addTearDown(other.dispose);
      final decisions = <IanvsMarkdownRenderDecision>[];
      Widget live(
        IanvsMarkdownController value,
        IanvsMarkdownRenderBudget? budget,
      ) => host(
        IanvsMarkdownLiveEditor(
          controller: value,
          renderBudget: budget,
          onRenderDecision: decisions.add,
        ),
      );
      await tester.pumpWidget(
        live(controller, const IanvsMarkdownRenderBudget(maxSyntaxTokens: 0)),
      );
      expect(decisions.last.useMarkdown, isFalse);
      await tester.pumpWidget(live(controller, null));
      expect(decisions.last.useMarkdown, isTrue);
      controller.text = '[${'x' * 50}';
      await tester.pumpWidget(live(other, smallBudget));
      expect(decisions.last.text, '# Replacement');
      expect(
        decisions.where((decision) => decision.text.startsWith('[')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'crossing the budget keeps focus and defers Live until IME commits',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: 'start',
        parseBudget: smallBudget,
      );
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        host(
          IanvsMarkdownLiveEditor(
            controller: controller,
            focusNode: focus,
            autofocus: true,
            renderBudget: smallBudget,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final oversizedComposition = TextEditingValue(
        text: 'x' * 80,
        selection: const TextSelection.collapsed(offset: 80),
        composing: const TextRange(start: 70, end: 80),
      );
      tester.testTextInput.updateEditingValue(oversizedComposition);
      await tester.pumpAndSettle();
      expect(controller.value, oversizedComposition);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
        findsOneWidget,
      );
      expect(focus.hasFocus, isTrue);
      const composing = TextEditingValue(
        text: 'short',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
        composing: TextRange(start: 1, end: 4),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      expect(controller.value, composing);
      expect(controller.parseDecision.useMarkdown, isTrue);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
        findsOneWidget,
      );
      tester.testTextInput.updateEditingValue(
        composing.copyWith(composing: TextRange.empty),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
        findsNothing,
      );
      expect(controller.text, 'short');
      expect(controller.selection, composing.selection);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
