import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  test(
    'history identity survives rebasing and distinguishes capped new jumps',
    () {
      final controller = IanvsMarkdownController(text: 'x' * 100);
      addTearDown(controller.dispose);
      for (var i = 0; i < 64; i++) {
        controller.rememberViewport(
          IanvsMarkdownViewportAnchor(
            source: controller.text,
            sourceOffset: i,
            viewportOffset: 0,
          ),
        );
        controller.rememberNavigationPosition();
      }
      final boundary = controller.navigationHistoryToken;
      controller.text = 'prefix${controller.text}';
      expect(controller.navigationHistoryToken, same(boundary));
      controller.rememberViewport(
        IanvsMarkdownViewportAnchor(
          source: controller.text,
          sourceOffset: 80,
          viewportOffset: 0,
        ),
      );
      controller.rememberNavigationPosition();
      expect(controller.navigationHistoryToken, isNot(same(boundary)));
      controller.navigateBack();
      expect(controller.navigationHistoryToken, same(boundary));
    },
  );

  test(
    'explicit jumps return in order and source searches do not add history',
    () {
      final controller = IanvsMarkdownController(
        text: 'first\n\nsecond\n\nthird',
      );
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      controller.rememberViewport(
        IanvsMarkdownViewportAnchor(
          source: controller.text,
          sourceOffset: 0,
          viewportOffset: -8,
        ),
      );
      controller.revealHeading(7);
      controller.rememberViewport(
        IanvsMarkdownViewportAnchor(
          source: controller.text,
          sourceOffset: 7,
          viewportOffset: 3,
        ),
      );
      controller.revealHeading(15);
      controller.revealSourceRange(const TextRange.collapsed(2));
      expect(controller.navigateBack(), isTrue);
      expect(controller.sourceNavigation.value!.range.start, 7);
      expect(controller.sourceNavigation.value!.viewportOffset, 3);
      expect(controller.navigateBack(), isTrue);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(controller.sourceNavigation.value!.viewportOffset, -8);
      expect(controller.canNavigateBack.value, isFalse);
      expect(controller.navigateBack(), isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    },
  );

  test(
    'saved positions and selections follow edits and composition defers return',
    () {
      final controller = IanvsMarkdownController(
        text: 'intro\n\ntarget\n\nend',
      );
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(
        baseOffset: 7,
        extentOffset: 10,
      );
      controller.rememberViewport(
        IanvsMarkdownViewportAnchor(
          source: controller.text,
          sourceOffset: 7,
          viewportOffset: -2,
        ),
      );
      controller.revealHeading(15);
      controller.value = TextEditingValue(
        text: 'new\n${controller.text}',
        selection: const TextSelection.collapsed(offset: 0),
        composing: const TextRange(start: 0, end: 3),
      );
      expect(controller.navigateBack(), isFalse);
      expect(controller.canNavigateBack.value, isTrue);
      controller.clearComposing();
      final undo = controller.canUndo;
      expect(controller.navigateBack(), isTrue);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 11, extentOffset: 14),
      );
      expect(controller.sourceNavigation.value!.range.start, 11);
      expect(controller.canUndo, undo);
    },
  );

  test('duplicate origins coalesce and history has a fixed limit', () {
    final controller = IanvsMarkdownController(text: 'x' * 100);
    addTearDown(controller.dispose);
    for (var i = 0; i < 80; i++) {
      controller.rememberViewport(
        IanvsMarkdownViewportAnchor(
          source: controller.text,
          sourceOffset: i,
          viewportOffset: 0,
        ),
      );
      controller.rememberNavigationPosition();
      controller.rememberNavigationPosition();
    }
    var count = 0;
    while (controller.navigateBack()) {
      count++;
    }
    expect(count, 64);
    expect(controller.sourceNavigation.value!.range.start, 16);
  });

  for (final mode in IanvsMarkdownEditorMode.values) {
    testWidgets('$mode heading jump returns to visible paragraph', (
      tester,
    ) async {
      final source = List.generate(
        100,
        (i) => '# Heading $i\n\nParagraph $i\n\n',
      ).join();
      final controller = IanvsMarkdownController(text: source, mode: mode);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              scrollController: scroll,
              preserveViewport: true,
              showToolbar: false,
              showNavigationPane: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      final anchor = controller.viewportAnchor.value!;
      final selection = controller.selection;
      controller.revealHeading(source.indexOf('# Heading 80'));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(1000));
      expect(controller.navigateBack(), isTrue);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(500, 2));
      expect(
        controller.viewportAnchor.value!.sourceOffset,
        anchor.sourceOffset,
      );
      expect(controller.selection, selection);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
