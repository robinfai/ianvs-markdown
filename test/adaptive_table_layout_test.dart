import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/table_layout.dart';

const _wideTable =
    '| ID | When | Owner | State | Value | Notes |\n'
    '| :--- | :--- | :--- | :--- | ---: | :--- |\n'
    '| Identifier with readable context | Scheduled delivery window | '
    'Responsible person and team | Current progress and next step | '
    '12345678901234567890 | Final column with useful details |';

class _ScaleCounter {
  int calls = 0;
}

class _CountingTextScaler extends TextScaler {
  const _CountingTextScaler(this.counter);

  final _ScaleCounter counter;

  @override
  double scale(double fontSize) {
    counter.calls++;
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}

Widget _frame({
  required Widget child,
  double width = 520,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);

Future<void> _pumpReading(
  WidgetTester tester,
  String source, {
  double width = 520,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  MarkdownStyleSheet? styleSheet,
  bool enableFileLinkChips = false,
  IanvsMarkdownThemeData? markdownTheme,
}) async {
  await tester.pumpWidget(
    _frame(
      width: width,
      scale: scale,
      direction: direction,
      child: SingleChildScrollView(
        child: IanvsMarkdown(
          data: source,
          styleSheet: styleSheet,
          enableFileLinkChips: enableFileLinkChips,
          theme: markdownTheme,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpLive(
  WidgetTester tester,
  IanvsMarkdownController controller, {
  double width = 520,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  IanvsMarkdownThemeData? markdownTheme,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    _frame(
      width: width,
      scale: scale,
      direction: direction,
      theme: theme,
      child: IanvsMarkdownLiveEditor(
        controller: controller,
        showToolbar: false,
        showNavigationPane: false,
        contentMaxWidth: 1000,
        padding: padding,
        theme: markdownTheme,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _horizontalScroll() => find.byWidgetPredicate(
  (widget) =>
      widget is SingleChildScrollView &&
      widget.scrollDirection == Axis.horizontal,
);

Finder _paragraphWithText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
);

RenderTable _table(WidgetTester tester) =>
    tester.renderObject<RenderTable>(find.byType(Table));

List<double> _columnWidths(RenderTable table) => [
  for (final cell in table.row(0)) cell.size.width,
];

RenderEditable _editableWithin(WidgetTester tester, Finder field) {
  RenderEditable? editable;
  void visit(RenderObject object) {
    if (object is RenderEditable) {
      editable = object;
    } else {
      object.visitChildren(visit);
    }
  }

  visit(tester.renderObject(field));
  expect(editable, isNotNull);
  return editable!;
}

Rect _inTable(RenderBox box, RenderTable table) =>
    box.localToGlobal(Offset.zero, ancestor: table) & box.size;

void _expectCellsWithinTable(RenderTable table, int rows) {
  for (var row = 0; row < rows; row++) {
    final rowBounds = table.getRowBox(row);
    for (final cell in table.row(row)) {
      final rect = _inTable(cell, table);
      expect(rect.left, greaterThanOrEqualTo(-0.01));
      expect(rect.right, lessThanOrEqualTo(table.size.width + 0.01));
      expect(rect.top, greaterThanOrEqualTo(rowBounds.top - 0.01));
      expect(rect.bottom, lessThanOrEqualTo(rowBounds.bottom + 0.01));
    }
  }
}

void _expectParagraphWithinCell(
  WidgetTester tester,
  String text, {
  required int row,
  required int column,
}) {
  final table = _table(tester);
  final paragraph = tester.renderObject<RenderParagraph>(
    _paragraphWithText(text),
  );
  final rect = _inTable(paragraph, table);
  final cell = _inTable(table.row(row).elementAt(column), table);
  final rowBounds = table.getRowBox(row);
  expect(rect.left, greaterThanOrEqualTo(cell.left - 0.01));
  expect(rect.right, lessThanOrEqualTo(cell.right + 0.01));
  expect(rect.top, greaterThanOrEqualTo(rowBounds.top - 0.01));
  expect(rect.bottom, lessThanOrEqualTo(rowBounds.bottom + 0.01));
  expect(paragraph.didExceedMaxLines, isFalse);

  // A constrained render box alone is not proof that its glyphs fit inside it.
  // Full-line selections include trailing whitespace outside centered lines;
  // inspect visible tokens instead, allowing only subpixel glyph overhang.
  final boxes = [
    for (final token in RegExp(r'\S+').allMatches(text))
      ...paragraph.getBoxesForSelection(
        TextSelection(baseOffset: token.start, extentOffset: token.end),
      ),
  ];
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    expect(box.left, greaterThanOrEqualTo(-0.5));
    expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.5));
    expect(box.top, greaterThanOrEqualTo(-0.5));
    expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.5));
  }
}

void _expectHorizontallyVisible(Rect target, Rect viewport) {
  expect(target.left, greaterThanOrEqualTo(viewport.left - 0.5));
  expect(target.right, lessThanOrEqualTo(viewport.right + 0.5));
}

Future<void> _loadProportionalTestFont(WidgetTester tester) async {
  await tester.runAsync(() async {
    final bytes = await File(
      'test/fixtures/fonts/TableTestProportional.otf',
    ).readAsBytes();
    final loader = FontLoader('TableTestProportional')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('adaptive width allocation', () {
    test('keeps compact columns and allocates proportional spare space', () {
      const metrics = MarkdownTableMetrics([50, 120, 60], [50, 420, 80]);
      final widths = metrics.resolve(390);

      expect(widths, [50, 270, 70]);
      expect(widths.reduce((a, b) => a + b), 390);
      expect(metrics.resolve(100), [50, 100, 60]);
      expect(metrics.resolve(1000), [50, 420, 80]);
    });

    test('widths are finite, bounded and monotonic during resize', () {
      const metrics = MarkdownTableMetrics([55, 132, 80], [55, 524, 180]);
      var previous = metrics.resolve(0);
      for (final viewport in [100.0, 267.0, 320.0, 540.0, 720.0, 1000.0]) {
        final widths = metrics.resolve(viewport);
        for (var column = 0; column < widths.length; column++) {
          expect(widths[column].isFinite, isTrue);
          expect(widths[column], greaterThanOrEqualTo(previous[column]));
          expect(
            widths[column],
            greaterThanOrEqualTo(
              math.min(metrics.minimumWidths[column], math.max(44, viewport)),
            ),
          );
          expect(
            widths[column],
            lessThanOrEqualTo(metrics.preferredWidths[column]),
          );
        }
        previous = widths;
      }
      expect(metrics.resolve(double.infinity), metrics.preferredWidths);
      expect(metrics.resolve(double.nan), metrics.preferredWidths);
      expect(const MarkdownTableMetrics([], []).resolve(320), isEmpty);
      expect(const MarkdownTableMetrics([55], [55]).resolve(55), [55]);
    });

    test('measures headers and bounds very long cells at both text scales', () {
      for (final scale in [1.0, 2.0]) {
        final metrics = MarkdownTableMetrics.measure(
          rows: [
            ['ID', 'Header substantially longer than its body', 'Token'],
            ['A', 'x', List.filled(10000, 'W').join()],
          ],
          bodyStyle: const TextStyle(fontSize: 14),
          headerStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          textScaler: TextScaler.linear(scale),
          textDirection: TextDirection.ltr,
          horizontalPadding: 20,
        );
        final compact = 2.5 * 14 * scale + 20;
        final readable = 8 * 14 * scale + 20;
        final cap = 36 * 14 * scale + 20;

        expect(metrics.preferredWidths.first, closeTo(compact, 0.01));
        expect(metrics.preferredWidths[1], greaterThan(compact));
        expect(metrics.preferredWidths[2], cap);
        expect(metrics.minimumWidths[1], readable);
        expect(metrics.minimumWidths[2], readable);
      }
    });

    testWidgets(
      'resizing and equivalent new row lists reuse text measurements',
      (tester) async {
        final counter = _ScaleCounter();
        final scaler = _CountingTextScaler(counter);
        const originalRows = [
          ['ID', 'Description'],
          [
            'A',
            'Long descriptive content with enough words to require allocation',
          ],
        ];
        var allocatedWidths = <double>[];

        Future<void> pumpLayout({
          required double width,
          required List<List<String>> rows,
          TextStyle bodyStyle = const TextStyle(fontSize: 14),
        }) async {
          await tester.pumpWidget(
            _frame(
              width: width,
              child: MarkdownTableLayout(
                rows: rows,
                bodyStyle: bodyStyle,
                headerStyle: const TextStyle(fontSize: 14),
                textScaler: scaler,
                textDirection: TextDirection.ltr,
                horizontalPadding: 20,
                builder: (context, widths) {
                  allocatedWidths = List.of(widths);
                  // No text widgets: only measurement can invoke this scaler.
                  return SizedBox(
                    width: widths.fold<double>(
                      0.0,
                      (sum, value) => sum + value,
                    ),
                    height: 1,
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await pumpLayout(width: 720, rows: originalRows);
        final initialCalls = counter.calls;
        final wideWidths = List<double>.of(allocatedWidths);
        expect(initialCalls, greaterThan(0));

        for (final width in [320.0, 540.0, 720.0]) {
          await pumpLayout(
            width: width,
            rows: [for (final row in originalRows) List<String>.of(row)],
          );
          expect(counter.calls, initialCalls);
          if (width == 320) {
            expect(allocatedWidths[1], lessThan(wideWidths[1]));
          }
        }

        const changedRows = [
          ['ID', 'Description'],
          ['A', 'Updated content must invalidate the cached text measurements'],
        ];
        await pumpLayout(width: 720, rows: changedRows);
        expect(counter.calls, greaterThan(initialCalls));
        final changedContentCalls = counter.calls;

        await pumpLayout(
          width: 720,
          rows: changedRows,
          bodyStyle: const TextStyle(fontSize: 16),
        );
        expect(counter.calls, greaterThan(changedContentCalls));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('reading tables', () {
    testWidgets('short tables remain compact instead of filling the page', (
      tester,
    ) async {
      await _pumpReading(
        tester,
        '| A | B |\n| --- | --- |\n| x | y |',
        width: 720,
      );

      final table = _table(tester);
      expect(table.size.width, lessThan(240));
      expect(_columnWidths(table), everyElement(lessThan(120)));
      final scroll = tester.widget<SingleChildScrollView>(_horizontalScroll());
      expect(scroll.controller!.position.maxScrollExtent, 0);
      _expectCellsWithinTable(table, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'long descriptions receive room without widening ID and numbers',
      (tester) async {
        const description =
            'A long explanation of this item with enough detail to wrap across '
            'multiple lines while its identifier and numeric amount stay compact.';
        await _pumpReading(
          tester,
          '| ID | Description | Amount |\n'
          '| :--- | :--- | ---: |\n'
          '| A | $description | 123.45 |\n'
          '| B | Brief | 7 |',
        );

        final table = _table(tester);
        final widths = _columnWidths(table);
        expect(widths[1], greaterThan(widths[0] * 2));
        expect(widths[1], greaterThan(widths[2] * 2));
        expect(table.size.width, lessThanOrEqualTo(520.01));
        final amount = tester.renderObject<RenderParagraph>(
          _paragraphWithText('123.45'),
        );
        final shortAmount = tester.renderObject<RenderParagraph>(
          _paragraphWithText('7'),
        );
        expect(amount.textAlign, TextAlign.right);
        expect(shortAmount.textAlign, TextAlign.right);
        expect(
          _inTable(amount, table).right,
          closeTo(_inTable(shortAmount, table).right, 0.1),
          reason:
              'Different-length numeric values keep their right edge aligned.',
        );
        _expectParagraphWithinCell(tester, description, row: 1, column: 1);
        _expectCellsWithinTable(table, 3);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a long header participates in column sizing', (tester) async {
      const header = 'Expected completion date and delivery window';
      await _pumpReading(
        tester,
        '| $header | ID |\n| --- | --- |\n| x | A |',
        width: 360,
      );

      final widths = _columnWidths(_table(tester));
      expect(widths[0], greaterThan(widths[1] * 2));
      _expectParagraphWithinCell(tester, header, row: 0, column: 0);
      _expectCellsWithinTable(_table(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mixed Chinese and English wrap inside their own row', (
      tester,
    ) async {
      const description =
          '中文说明与 English mixed content：窄屏下应完整换行，保留短编号列，'
          '并确保下一行不会覆盖当前说明。';
      await _pumpReading(
        tester,
        '| 编号 | Description / 说明 |\n'
        '| --- | --- |\n'
        '| A1 | $description |\n'
        '| B2 | 下一行 |',
        width: 420,
      );

      final widths = _columnWidths(_table(tester));
      expect(widths[1], greaterThan(widths[0] * 2));
      final paragraph = tester.renderObject<RenderParagraph>(
        _paragraphWithText(description),
      );
      expect(paragraph.size.height, greaterThan(30));
      _expectParagraphWithinCell(tester, description, row: 1, column: 1);
      _expectParagraphWithinCell(tester, '下一行', row: 2, column: 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('link destinations do not inflate short visible labels', (
      tester,
    ) async {
      final destination =
          'https://example.com/${List.filled(300, 'path').join()}';
      await _pumpReading(
        tester,
        '| ID | Link |\n| --- | --- |\n| A | [Doc]($destination) |',
        width: 720,
      );

      expect(_table(tester).size.width, lessThan(240));
      _expectParagraphWithinCell(tester, 'Doc', row: 1, column: 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unbroken URLs and inline code wrap without clipped glyphs', (
      tester,
    ) async {
      final url = 'https://example.com/${List.filled(100, 'x').join()}';
      final code = 'veryLongIdentifier${List.filled(80, 'W').join()}';
      await _pumpReading(
        tester,
        '| Kind | Content |\n'
        '| --- | --- |\n'
        '| URL | <$url> |\n'
        '| Code | `$code` |\n'
        '| End | Last row |',
        width: 320,
      );

      for (final entry in [(url, 1), (code, 2)]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          _paragraphWithText(entry.$1),
        );
        expect(paragraph.size.height, greaterThan(30));
        _expectParagraphWithinCell(tester, entry.$1, row: entry.$2, column: 1);
      }
      _expectCellsWithinTable(_table(tester), 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('code is measured in its own font when the viewport has room', (
      tester,
    ) async {
      // Ahem alone cannot expose the difference between proportional i glyphs
      // and a monospace code span. Use the repository's bundled font for body
      // text, while explicitly keeping code in the test font's wider glyphs.
      await _loadProportionalTestFont(tester);
      final code = List.filled(40, 'i').join();
      await _pumpReading(
        tester,
        '| ID | Code |\n| --- | --- |\n| A | `$code` |',
        width: 720,
        styleSheet: MarkdownStyleSheet(
          tableColumnWidth: const AdaptiveMarkdownColumnWidth(),
          tableBody: const TextStyle(
            fontSize: 14,
            fontFamily: 'TableTestProportional',
          ),
          tableHead: const TextStyle(
            fontSize: 14,
            fontFamily: 'TableTestProportional',
          ),
        ),
        markdownTheme: IanvsMarkdownThemeData.light.copyWith(
          monoFontFamily: 'Ahem',
          monoFontFamilyFallback: const [],
        ),
      );

      final paragraph = tester.renderObject<RenderParagraph>(
        _paragraphWithText(code),
      );
      expect(
        paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: code.length),
        ),
        hasLength(1),
        reason:
            'Code should not wrap solely because body i glyphs are narrower.',
      );
      _expectParagraphWithinCell(tester, code, row: 1, column: 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'file chips reserve their icon and padding before ellipsizing',
      (tester) async {
        await _pumpReading(
          tester,
          '| ID | File |\n| --- | --- |\n| A | [report.pdf](report.pdf) |',
          width: 720,
          enableFileLinkChips: true,
        );

        expect(
          find.byKey(const ValueKey('ianvs-markdown-file-reference')),
          findsOneWidget,
        );
        final label = tester.renderObject<RenderParagraph>(
          _paragraphWithText('report.pdf'),
        );
        expect(label.didExceedMaxLines, isFalse);
        _expectParagraphWithinCell(tester, 'report.pdf', row: 1, column: 1);
        expect(tester.takeException(), isNull);
      },
    );

    for (final direction in TextDirection.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '320px many-column table scrolls to its end in ${direction.name} at ${scale}x',
          (tester) async {
            await _pumpReading(
              tester,
              _wideTable,
              width: 320,
              scale: scale,
              direction: direction,
            );

            final scrollFinder = _horizontalScroll();
            final scroll = tester.widget<SingleChildScrollView>(scrollFinder);
            final position = scroll.controller!.position;
            expect(position.maxScrollExtent, greaterThan(0));
            final table = _table(tester);
            expect(table.size.width, greaterThan(320));
            expect(
              _columnWidths(table),
              everyElement(greaterThan(100 * scale)),
            );
            _expectCellsWithinTable(table, 2);

            scroll.controller!.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            final lastCell = table.row(0).last;
            _expectHorizontallyVisible(
              lastCell.localToGlobal(Offset.zero) & lastCell.size,
              tester.getRect(scrollFinder),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final policy in <TableColumnWidth>[
      const FixedColumnWidth(88),
      const FlexColumnWidth(2),
      const IntrinsicColumnWidth(),
    ]) {
      testWidgets('explicit ${policy.runtimeType} remains host-controlled', (
        tester,
      ) async {
        await _pumpReading(
          tester,
          '| ID | Description |\n| --- | --- |\n| A | Several words |',
          width: 420,
          styleSheet: MarkdownStyleSheet(tableColumnWidth: policy),
        );

        final widget = tester.widget<Table>(find.byType(Table));
        expect(widget.defaultColumnWidth, same(policy));
        expect(widget.columnWidths ?? <int, TableColumnWidth>{}, isEmpty);
        final widths = _columnWidths(_table(tester));
        if (policy is FixedColumnWidth) {
          expect(widths, everyElement(closeTo(88, 0.01)));
        } else if (policy is FlexColumnWidth) {
          expect(widths[0], closeTo(widths[1], 0.01));
          expect(_table(tester).size.width, closeTo(420, 0.01));
        } else {
          expect(widths[1], greaterThan(widths[0]));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('live tables', () {
    for (final useMaterial3 in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('short words stay on one line with caret space in Material '
            '${useMaterial3 ? 3 : 2} at ${scale}x', (tester) async {
          const source =
              '| Name | Qty |\n| :--- | ---: |\n'
              '| Apples | 10 |\n| Pears | 2 |';
          final controller = IanvsMarkdownController(text: source);
          addTearDown(controller.dispose);
          await _pumpLive(
            tester,
            controller,
            width: 540,
            scale: scale,
            theme: ThemeData(useMaterial3: useMaterial3),
          );

          for (var row = 0; row < 3; row++) {
            for (var column = 0; column < 2; column++) {
              final field = find.byKey(
                ValueKey('ianvs-markdown-table-$row-$column'),
              );
              await tester.tap(field);
              await tester.pumpAndSettle();
              final text = tester.widget<TextField>(field).controller!.text;
              final editable = _editableWithin(tester, field);
              expect(
                editable.getBoxesForSelection(
                  TextSelection(baseOffset: 0, extentOffset: text.length),
                ),
                hasLength(1),
                reason: 'The caret must not force a short word onto two lines.',
              );
              expect(
                editable.getLineAtOffset(const TextPosition(offset: 0)).end,
                text.length,
              );
            }
          }
          expect(controller.text, source);
          _expectCellsWithinTable(_table(tester), 3);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('short fields stay compact and resizing never rewrites source', (
      tester,
    ) async {
      const source =
          '|ID|Description|N|\n'
          '|:---|:---|---:|\n'
          '|A|A longer description with enough words to use the spare width|7|';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      for (final width in [720.0, 320.0, 540.0]) {
        await _pumpLive(tester, controller, width: width);
        final widths = _columnWidths(_table(tester));
        expect(widths[1], greaterThan(widths[0] * 2));
        expect(widths[1], greaterThan(widths[2] * 2));
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('ianvs-markdown-table-1-2')),
              )
              .textAlign,
          TextAlign.right,
        );
        _expectCellsWithinTable(_table(tester), 2);
        expect(controller.text, source);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('cached metrics react to text scale and changed cell content', (
      tester,
    ) async {
      const shortSource = '| A | B |\n| --- | --- |\n| x | y |';
      final controller = IanvsMarkdownController(text: shortSource);
      addTearDown(controller.dispose);
      await _pumpLive(tester, controller, width: 720);
      final originalWidths = _columnWidths(_table(tester));

      await _pumpLive(tester, controller, width: 720, scale: 2);
      final scaledWidths = _columnWidths(_table(tester));
      expect(scaledWidths[0], greaterThan(originalWidths[0]));
      expect(scaledWidths[1], greaterThan(originalWidths[1]));
      expect(controller.text, shortSource);

      const changedSource =
          '| A | B |\n| --- | --- |\n'
          '| x | A newly expanded description requiring additional room |';
      controller.text = changedSource;
      await tester.pumpAndSettle();
      final changedWidths = _columnWidths(_table(tester));
      expect(changedWidths[1], greaterThan(scaledWidths[1] * 2));
      expect(controller.text, changedSource);
      _expectCellsWithinTable(_table(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cached metrics react to a changed inline-code font', (
      tester,
    ) async {
      await _loadProportionalTestFont(tester);
      final code = List.filled(40, 'i').join();
      final source = '| ID | Code |\n| --- | --- |\n| A | `$code` |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await _pumpLive(
        tester,
        controller,
        width: 720,
        markdownTheme: IanvsMarkdownThemeData.light.copyWith(
          monoFontFamily: 'TableTestProportional',
          monoFontFamilyFallback: const [],
        ),
      );
      final narrowFontWidths = _columnWidths(_table(tester));

      await _pumpLive(
        tester,
        controller,
        width: 720,
        markdownTheme: IanvsMarkdownThemeData.light.copyWith(
          monoFontFamily: 'Ahem',
          monoFontFamilyFallback: const [],
        ),
      );
      final wideFontWidths = _columnWidths(_table(tester));
      expect(wideFontWidths[1], greaterThan(narrowFontWidths[1] * 1.5));
      expect(controller.text, source);
      _expectCellsWithinTable(_table(tester), 2);
      expect(tester.takeException(), isNull);
    });

    for (final direction in TextDirection.values) {
      for (final scale in [1.0, 2.0, 4.0]) {
        for (final padded in [false, true]) {
          if (scale == 4 && !padded) continue;
          testWidgets(
            'Tab reveals the last column at 320px in ${direction.name} at ${scale}x '
            'with ${padded ? 'default' : 'zero'} editor padding',
            (tester) async {
              final controller = IanvsMarkdownController(text: _wideTable);
              addTearDown(controller.dispose);
              final padding = padded
                  ? const EdgeInsets.fromLTRB(28, 20, 32, 44)
                  : EdgeInsets.zero;
              await _pumpLive(
                tester,
                controller,
                width: 320,
                scale: scale,
                direction: direction,
                padding: padding,
              );

              final scrollFinder = find.byKey(
                const ValueKey('ianvs-markdown-table-horizontal-scroll'),
              );
              final scroll = tester.widget<SingleChildScrollView>(scrollFinder);
              expect(
                scroll.controller!.position.maxScrollExtent,
                greaterThan(0),
              );

              await tester.tap(
                find.byKey(const ValueKey('ianvs-markdown-table-0-0')),
              );
              await tester.pumpAndSettle();
              for (var column = 1; column < 6; column++) {
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pumpAndSettle();
                final fieldFinder = find.byKey(
                  ValueKey('ianvs-markdown-table-0-$column'),
                );
                expect(
                  tester.widget<TextField>(fieldFinder).focusNode!.hasFocus,
                  isTrue,
                );
                _expectHorizontallyVisible(
                  tester.getRect(fieldFinder),
                  tester.getRect(scrollFinder),
                );
              }
              expect(scroll.controller!.offset, greaterThan(0));
              expect(controller.text, _wideTable);
              _expectCellsWithinTable(_table(tester), 2);

              await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
              for (var column = 4; column >= 0; column--) {
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pumpAndSettle();
                final fieldFinder = find.byKey(
                  ValueKey('ianvs-markdown-table-0-$column'),
                );
                expect(
                  tester.widget<TextField>(fieldFinder).focusNode!.hasFocus,
                  isTrue,
                );
                _expectHorizontallyVisible(
                  tester.getRect(fieldFinder),
                  tester.getRect(scrollFinder),
                );
              }
              await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
              expect(controller.text, _wideTable);

              // Rebuild the existing editor rather than replacing its controller.
              await _pumpLive(
                tester,
                controller,
                width: 640,
                scale: scale,
                direction: direction,
                padding: padding,
              );
              expect(controller.text, _wideTable);
              expect(
                tester
                    .widget<TextField>(
                      find.byKey(const ValueKey('ianvs-markdown-table-0-0')),
                    )
                    .focusNode!
                    .hasFocus,
                isTrue,
              );
              _expectCellsWithinTable(_table(tester), 2);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    testWidgets(
      'touch column reordering does not simultaneously scroll the wide table',
      (tester) async {
        final controller = IanvsMarkdownController(text: _wideTable);
        addTearDown(controller.dispose);
        await _pumpLive(tester, controller, width: 320);

        final scrollFinder = find.byKey(
          const ValueKey('ianvs-markdown-table-horizontal-scroll'),
        );
        final scrollController = tester
            .widget<SingleChildScrollView>(scrollFinder)
            .controller!;
        expect(scrollController.position.maxScrollExtent, greaterThan(0));
        await tester.tap(
          find.byKey(const ValueKey('ianvs-markdown-table-0-1')),
        );
        await tester.pumpAndSettle();
        final sourceHandle = find.byKey(
          const ValueKey('ianvs-markdown-table-column-drag-1'),
        );
        final targetHandle = find.byKey(
          const ValueKey('ianvs-markdown-table-column-drag-0'),
        );
        final initialOffset = scrollController.offset;
        final target = tester.getCenter(targetHandle);
        final gesture = await tester.startGesture(
          tester.getCenter(sourceHandle),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        expect(
          tester.widget<SingleChildScrollView>(scrollFinder).physics,
          isA<NeverScrollableScrollPhysics>(),
        );
        await gesture.moveTo(target);
        await tester.pump();
        expect(scrollController.offset, closeTo(initialOffset, 0.01));
        await gesture.up();
        await tester.pumpAndSettle();

        String cellText(int row, int column) => tester
            .widget<TextField>(
              find.byKey(ValueKey('ianvs-markdown-table-$row-$column')),
            )
            .controller!
            .text;
        expect(cellText(0, 0), 'When');
        expect(cellText(0, 1), 'ID');
        expect(cellText(1, 0), 'Scheduled delivery window');
        expect(cellText(1, 1), 'Identifier with readable context');
        expect(scrollController.offset, closeTo(initialOffset, 0.01));
        expect(
          tester.widget<SingleChildScrollView>(scrollFinder).physics,
          isNot(isA<NeverScrollableScrollPhysics>()),
        );
        _expectCellsWithinTable(_table(tester), 2);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }),
    );
  });
}
