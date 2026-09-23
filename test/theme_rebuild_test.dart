import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  testWidgets('theme changes preserve reading headings and task markers', (
    tester,
  ) async {
    var dark = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: const Scaffold(
              body: IanvsMarkdownView(
                data:
                    '# First\n\n## Repeated\n\n- [/] Working\n- [?] Question\n\n## Repeated\n\nLast',
                showOutline: false,
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      rebuild(() => dark = !dark);
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Repeated'), findsNWidgets(2));
      expect(
        tester
            .widgetList<IanvsMarkdownTaskCheckbox>(
              find.byType(IanvsMarkdownTaskCheckbox),
            )
            .map((checkbox) => checkbox.marker),
        ['/', '?'],
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('theme changes preserve image source indices', (tester) async {
    var dark = false;
    late StateSetter rebuild;
    final resized = <int>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: Scaffold(
              body: IanvsMarkdown(
                data: '![First|80](one.png)\n\n![Second|80](two.png)',
                imageBuilder: (_, _, _) =>
                    const SizedBox(width: 80, height: 50),
                onImageResize: (request) => resized.add(request.imageIndex),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    rebuild(() => dark = true);
    await tester.pumpAndSettle();
    for (final image in tester.widgetList<IanvsMarkdownSizedImage>(
      find.byType(IanvsMarkdownSizedImage),
    )) {
      image.onResize!(100);
    }
    expect(resized, [0, 1]);
  });
}
