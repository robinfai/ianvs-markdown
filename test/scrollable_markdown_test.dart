import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  testWidgets('deferred table cells may read inherited text styles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IanvsMarkdown(
            data: '| Name | Value |\n| --- | --- |\n| item | **bold** |',
            scrollable: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('bold', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrollable renderer lays out visible blocks and retains references',
    (tester) async {
      final source =
          '[Shared reference][target]\n\n${List.generate(200, (i) => 'Paragraph $i').join('\n\n')}\n\n[target]: https://example.com';
      String? link;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdown(
              data: source,
              scrollable: true,
              scrollPadding: const EdgeInsets.all(24),
              onTapLink: (_, href, _) => link = href,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paragraph 199', findRichText: true), findsNothing);
      await tester.tap(find.text('Shared reference', findRichText: true));
      expect(link, 'https://example.com');
      await tester.scrollUntilVisible(
        find.text('Paragraph 199', findRichText: true),
        600,
      );
      await tester.pumpAndSettle();
      expect(find.text('Paragraph 199', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('offscreen image builders are deferred and revisiting is safe', (
    tester,
  ) async {
    final built = <String>[];
    final source = List.generate(
      100,
      (i) => '![Image $i](image-$i.png)\n\nParagraph $i',
    ).join('\n\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdown(
            data: source,
            scrollable: true,
            imageBuilder: (uri, title, alt) {
              built.add(uri.toString());
              return SizedBox(height: 120, child: Text(alt ?? ''));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built.length, lessThan(20));
    expect(built, isNot(contains('image-99.png')));
    await tester.scrollUntilVisible(find.text('Image 99'), 700, maxScrolls: 60);
    await tester.pumpAndSettle();
    expect(built, contains('image-99.png'));
    await tester.scrollUntilVisible(find.text('Image 0'), -700, maxScrolls: 60);
    await tester.pumpAndSettle();
    expect(find.text('Image 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
