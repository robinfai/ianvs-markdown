import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
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
}
