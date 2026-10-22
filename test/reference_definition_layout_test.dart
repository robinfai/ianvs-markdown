import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  const path =
      '/Users/example/work/weekly-reports/'
      '2026-W40-W41_20260928-20261011/weekly-report-2026-10-12.md';
  const next = '/Users/example/work/supporting-info.md';
  const source = 'Before\n\n[S2]: $path\n[S2A]: $next\n\nAfter';
  for (final width in [320.0, 720.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('reference links reserve wrapped height $width / $scale', (
        tester,
      ) async {
        final controller = IanvsMarkdownController(text: source);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SizedBox(
                  width: width,
                  child: IanvsMarkdownLiveEditor(
                    controller: controller,
                    showToolbar: false,
                    showNavigationPane: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final definitions = find.byKey(
          const ValueKey('ianvs-markdown-reference-definitions'),
        );
        final rows = find.descendant(
          of: definitions,
          matching: find.byType(IanvsMarkdown),
        );
        expect(rows, findsNWidgets(2));
        void check() {
          final link = tester.getRect(find.text(path));
          final row = tester.getRect(rows.at(0));
          expect(link.height, greaterThan(30));
          expect(link.top, greaterThanOrEqualTo(row.top - .1));
          expect(link.bottom, lessThanOrEqualTo(row.bottom + .1));
          expect(
            link.bottom,
            lessThanOrEqualTo(tester.getTopLeft(rows.at(1)).dy),
          );
          expect(tester.takeException(), isNull);
        }

        check();
        await tester.tapAt(
          tester.getTopLeft(find.text(path)) + const Offset(5, 5),
        );
        await tester.pumpAndSettle();
        check();
        await tester.tap(find.text('Before'));
        await tester.pumpAndSettle();
        check();
        expect(controller.text, source);
        expect(controller.isDirty, isFalse);
      });
    }
  }
}
