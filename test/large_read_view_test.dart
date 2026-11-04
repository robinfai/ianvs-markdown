import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  testWidgets('large read view virtualizes and reveals an offscreen source', (
    tester,
  ) async {
    final source = List.generate(
      1000,
      (i) => '## Heading $i\n\nParagraph $i ${'ordinary text ' * 8}\n',
    ).join('\n');
    final controller = IanvsMarkdownController(text: source);
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: source,
            controller: scroll,
            showOutline: false,
            sourceNavigation: controller.sourceNavigation,
            headingNavigation: controller.headingNavigation,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Heading 999', findRichText: true), findsNothing);
    controller.revealSourceRange(
      TextRange.collapsed(source.indexOf('## Heading 999')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Heading 999', findRichText: true), findsOneWidget);
    expect(scroll.offset, greaterThan(1000));
    expect(tester.takeException(), isNull);
  });
}
