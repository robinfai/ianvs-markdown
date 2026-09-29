import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'long table content fits and stays editable in ${direction.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source =
            '| ID | Name | Result | Evidence |\n'
            '| --- | --- | --- | --- |\n'
            '| A01 | New file | ${List.filled(60, 'W').join()} | U/T |';
        final controller = IanvsMarkdownController(text: source);
        addTearDown(controller.dispose);

        for (final width in [1000.0, 480.0]) {
          for (final scale in [1.0, 2.0]) {
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                    textDirection: direction,
                    child: Scaffold(
                      body: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: width,
                          child: IanvsMarkdownLiveEditor(
                            controller: controller,
                            showToolbar: false,
                            showNavigationPane: false,
                            contentMaxWidth: 720,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final table = tester.renderObject<RenderTable>(find.byType(Table));
            for (var row = 0; row < 2; row++) {
              for (final cell in table.row(row)) {
                final rect =
                    cell.localToGlobal(Offset.zero, ancestor: table) &
                    cell.size;
                expect(rect.left, greaterThanOrEqualTo(-.01));
                expect(
                  rect.right,
                  lessThanOrEqualTo(table.size.width + .01),
                  reason: 'width $width, text scale $scale: no column overflow',
                );
              }
            }
            expect(controller.text, source);
            // The far edge must be reachable, not merely painted outside the box.
            final header = find.byKey(
              const ValueKey('ianvs-markdown-table-0-3'),
            );
            await tester.tap(header);
            await tester.pumpAndSettle();
            expect(
              tester.widget<TextField>(header).focusNode!.hasFocus,
              isTrue,
            );
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  }
}
