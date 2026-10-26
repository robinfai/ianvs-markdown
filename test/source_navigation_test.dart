import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  test(
    'source navigation validates snapshots and leaves editing state intact',
    () {
      final controller = IanvsMarkdownController(text: 'hello 中文😀');
      addTearDown(controller.dispose);
      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 3, extentOffset: 1),
        composing: const TextRange(start: 0, end: 3),
      );
      final before = controller.value;
      expect(
        controller.revealSourceRange(const TextRange(start: 6, end: 8)),
        isTrue,
      );
      final first = controller.sourceNavigation.value;
      expect(controller.value, before);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(
        controller.revealSourceRange(const TextRange(start: 6, end: 8)),
        isTrue,
      );
      expect(identical(controller.sourceNavigation.value, first), isFalse);
      for (final range in [
        TextRange.empty,
        const TextRange(start: 3, end: 1),
        const TextRange(start: 0, end: 100),
      ]) {
        expect(controller.revealSourceRange(range), isFalse);
      }
      expect(
        controller.revealSourceRange(
          const TextRange.collapsed(0),
          source: 'stale',
        ),
        isFalse,
      );
      controller.text = 'changed';
      expect(controller.sourceNavigation.value, isNull);
      controller.undo();
      expect(controller.sourceNavigation.value, isNull);
    },
  );

  for (final (mode, fallback) in [
    (IanvsMarkdownEditorMode.source, false),
    (IanvsMarkdownEditorMode.livePreview, false),
    (IanvsMarkdownEditorMode.preview, false),
    (IanvsMarkdownEditorMode.livePreview, true),
  ]) {
    testWidgets(
      '$mode fallback=$fallback reveals distant content without moving selection or focus',
      (tester) async {
        final source = List.generate(
          100,
          (i) => 'Paragraph $i 中文 text.',
        ).join('\n\n');
        final controller = IanvsMarkdownController(text: source, mode: mode);
        final scroll = ScrollController();
        final queryFocus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        addTearDown(queryFocus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: queryFocus),
                  Expanded(
                    child: IanvsMarkdownLiveEditor(
                      controller: controller,
                      renderBudget: fallback
                          ? const IanvsMarkdownRenderBudget(
                              maxSourceCodeUnits: 1,
                            )
                          : const IanvsMarkdownRenderBudget(),
                      scrollController: scroll,
                      showToolbar: false,
                      showNavigationPane: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        queryFocus.requestFocus();
        await tester.pumpAndSettle();
        final before = controller.value;
        final offset = source.indexOf('Paragraph 90');
        controller.revealSourceRange(
          TextRange(start: offset, end: offset + 12),
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(500));
        if (mode != IanvsMarkdownEditorMode.source && !fallback) {
          expect(
            find
                .textContaining('Paragraph 90 中文 text.', findRichText: true)
                .hitTestable(),
            findsOneWidget,
          );
        } else {
          final editable = tester
              .state<EditableTextState>(
                find.descendant(
                  of: find.byKey(const ValueKey('ianvs-markdown-source-field')),
                  matching: find.byType(EditableText),
                ),
              )
              .renderEditable;
          final caret = editable.localToGlobal(
            editable.getLocalRectForCaret(TextPosition(offset: offset)).topLeft,
          );
          expect(caret.dy, inInclusiveRange(56, 600));
        }
        expect(controller.value, before);
        expect(queryFocus.hasFocus, isTrue);
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
        // Superseding a pending distant request with an edit invalidates it.
        scroll.jumpTo(0);
        controller.revealSourceRange(TextRange.collapsed(offset));
        controller.text = 'replacement';
        await tester.pumpAndSettle();
        expect(controller.sourceNavigation.value, isNull);
        expect(scroll.offset, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'pending navigation belongs to its controller, including before mount',
    (tester) async {
      final source = List.generate(100, (i) => 'Block $i').join('\n\n');
      final first = IanvsMarkdownController(text: source);
      final second = IanvsMarkdownController(text: 'replacement');
      final scroll = ScrollController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(scroll.dispose);
      Widget host(IanvsMarkdownController controller) => MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            scrollController: scroll,
            showToolbar: false,
            showNavigationPane: false,
          ),
        ),
      );
      first.revealSourceRange(TextRange.collapsed(source.indexOf('Block 90')));
      await tester.pumpWidget(host(first));
      await tester.pumpAndSettle();
      expect(
        find.text('Block 90', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      scroll.jumpTo(0);
      first.revealSourceRange(TextRange.collapsed(source.indexOf('Block 95')));
      await tester.pumpWidget(host(second));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(second.selection, const TextSelection.collapsed(offset: 0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
