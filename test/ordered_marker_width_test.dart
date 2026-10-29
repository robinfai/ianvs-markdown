import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  for (final start in [99, 999, 9999, 1]) {
    testWidgets('ordered markers keep one line across $start at phone width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 667);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: IanvsMarkdown(
                data: start == 1
                    ? List.generate(
                        100,
                        (_) => '1. Apples remain useful.',
                      ).join('\n')
                    : '$start. Apples remain useful.\n${start + 1}. More apples.',
                syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
                selectable: true,
                fitContent: true,
              ),
            ),
          ),
        ),
      );
      final rightEdges = <double>[];
      for (final n in (start == 1 ? [99, 100] : [start, start + 1])) {
        final marker = find.text('$n.');
        final rich = find.descendant(
          of: marker,
          matching: find.byType(RichText),
        );
        final paragraph = tester.renderObject<RenderParagraph>(rich);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: '$n.'.length),
        );
        expect(boxes, hasLength(1), reason: 'The period must stay with $n');
        final row = tester.widget<Row>(
          find.ancestor(of: marker, matching: find.byType(Row)).first,
        );
        final contentLeft = tester
            .getRect(find.byWidget(row.children.last))
            .left;
        expect(
          tester.getRect(rich).left + boxes.single.right,
          lessThanOrEqualTo(contentLeft),
        );
        rightEdges.add(tester.getRect(marker).right);
      }
      expect(rightEdges.first, closeTo(rightEdges.last, .01));
      expect(tester.takeException(), isNull);
    });
  }
}
