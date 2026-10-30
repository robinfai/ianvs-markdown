import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('five-column table keeps short words intact at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: const SingleChildScrollView(
              child: IanvsMarkdown(
                documentSelection: true,
                data:
                    '| Fruit | Color | Taste | Season | Origin |\n'
                    '| --- | --- | --- | --- | --- |\n'
                    '| Lemon | Yellow | Sour | Winter | Asia |\n'
                    '| Apple | Red | Sweet | Autumn | Europe |',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final word in ['Season', 'Lemon', 'Yellow', 'Winter', 'Autumn']) {
        final rich = find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == word,
        );
        expect(rich, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(rich);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: word.length),
        );
        expect(boxes, hasLength(1), reason: '$word must stay on one line');
      }
      expect(
        tester.getSize(find.byType(Table)).width,
        lessThan(560),
        reason: 'Short columns must not retain the old 800px total width',
      );
      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      expect(horizontal, findsOneWidget);
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(of: horizontal, matching: find.byType(Scrollable))
            .first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.drag(horizontal, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      expect(
        tester.getRect(find.byType(Table)).right,
        lessThanOrEqualTo(width + 1),
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 390.0, 1000.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final direction in TextDirection.values) {
        testWidgets(
          'bounded reading cells wrap prose and links at $width/$scale/${direction.name}',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 1200);
            addTearDown(tester.view.reset);
            final english = List.filled(8, 'Long readable prose').join(' ');
            final chinese = List.filled(8, '中文长段落需要正常换行').join();
            const label = 'Long link title with several words and 中文标题';
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                    textDirection: direction,
                    child: Scaffold(
                      body: SingleChildScrollView(
                        child: IanvsMarkdown(
                          data:
                              '| Season | Details | Link |\n| --- | --- | --- |\n| Winter | $english | [$label](docs/test.md) |\n| Autumn | $chinese | [External reference](https://example.com) |',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final table = tester.renderObject<RenderTable>(find.byType(Table));
            expect(table.size.width, lessThan(3 * (140 * scale + 20)));
            expect(table.size.width, greaterThan(2 * (140 * scale + 20)));
            final initialWidth = table.size.width;
            await tester.pump();
            expect(
              table.size.width,
              initialWidth,
              reason:
                  'Embedded links must keep the fallback width after layout',
            );
            final link = tester.renderObject<RenderBox>(find.text(label));
            final row = table.getRowBox(1);
            final origin = link.localToGlobal(Offset.zero, ancestor: table);
            expect(link.size.height, greaterThan(30 * scale));
            expect(
              origin.dy + link.size.height,
              lessThanOrEqualTo(row.bottom + .01),
            );
            // Paragraphs stay finite and wrap even on a wide desktop viewport.
            for (final text in [english, chinese]) {
              final finder = find.byWidgetPredicate(
                (w) => w is RichText && w.text.toPlainText() == text,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                finder.first,
              );
              expect(
                paragraph.size.width,
                lessThanOrEqualTo(140 * scale + .01),
              );
              expect(paragraph.size.height, greaterThan(30 * scale));
            }
            final horizontal = find.byWidgetPredicate(
              (w) =>
                  w is SingleChildScrollView &&
                  w.scrollDirection == Axis.horizontal,
            );
            final scrollable = tester.state<ScrollableState>(
              find
                  .descendant(of: horizontal, matching: find.byType(Scrollable))
                  .first,
            );
            if (table.size.width > width) {
              expect(scrollable.position.maxScrollExtent, greaterThan(0));
              // A direct jump verifies the far edge is laid out, including RTL.
              scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
              await tester.pumpAndSettle();
              expect(scrollable.position.extentAfter, closeTo(0, .01));
            } else {
              expect(scrollable.position.maxScrollExtent, 0);
            }
            final tableController = tester
                .widget<SingleChildScrollView>(horizontal)
                .controller;
            final bar = tester.widget<Scrollbar>(
              find.byWidgetPredicate(
                (w) => w is Scrollbar && w.controller == tableController,
              ),
            );
            expect(bar.thumbVisibility, isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('standard GFM tables use the same bounded reading policy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: IanvsMarkdown(
              syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
              data:
                  '| Fruit | Color | Taste | Season | Origin |\n| --- | --- | --- | --- | --- |\n| Lemon | Yellow | Sour | Winter | Asia |',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Table)).width, lessThan(560));
    final horizontal = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: horizontal, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    final controller = tester
        .widget<SingleChildScrollView>(horizontal)
        .controller;
    expect(
      tester
          .widget<Scrollbar>(
            find.byWidgetPredicate(
              (w) => w is Scrollbar && w.controller == controller,
            ),
          )
          .thumbVisibility,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reading table honors explicit host column and scrollbar styles',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => IanvsMarkdown(
                data: '| A | B |\n| --- | --- |\n| one | two |',
                styleSheet:
                    ianvsMarkdownStyleSheet(
                      context,
                      IanvsMarkdownThemeData.light,
                    ).copyWith(
                      tableColumnWidth: const FixedColumnWidth(110),
                      tableScrollbarThumbVisibility: false,
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Table)).width, 220);
      expect(
        tester
            .widgetList<Scrollbar>(find.byType(Scrollbar))
            .where((bar) => bar.controller != null)
            .single
            .thumbVisibility,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
