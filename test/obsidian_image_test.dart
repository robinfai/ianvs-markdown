import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  Widget app(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 900, height: 700, child: child),
        ),
      ),
    );
  }

  test('parses Obsidian image dimensions without accepting near misses', () {
    final widthOnly = parseIanvsMarkdownImageDimensions('Diagram| 250 ');
    expect(widthOnly.alt, 'Diagram');
    expect(widthOnly.width, 250);
    expect(widthOnly.height, isNull);

    final fixed = parseIanvsMarkdownImageDimensions('Diagram| 100 x 145 ');
    expect(fixed.alt, 'Diagram');
    expect(fixed.width, 100);
    expect(fixed.height, 145);

    final dimensionOnly = parseIanvsMarkdownImageDimensions('250');
    expect(dimensionOnly.alt, isNull);
    expect(dimensionOnly.width, 250);

    for (final invalid in <String>[
      'Diagram|100X145',
      'Diagram|100.5x145',
      'Diagram|100x',
      'Diagram|wide',
    ]) {
      final parsed = parseIanvsMarkdownImageDimensions(invalid);
      expect(parsed.alt, invalid);
      expect(parsed.hasDimensions, isFalse);
    }
  });

  testWidgets('sizes standard images and cleans the host builder alt', (
    tester,
  ) async {
    String? receivedAlt;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '![Diagram|100x145](diagram.png)',
          imageBuilder: (uri, title, alt) {
            receivedAlt = alt;
            return const ColoredBox(
              key: ValueKey('host-standard-image'),
              color: Colors.blue,
            );
          },
        ),
      ),
    );

    expect(receivedAlt, 'Diagram');
    final sized = tester.widget<SizedBox>(
      find.byKey(const ValueKey('ianvs-markdown-image-size')),
    );
    expect(sized.width, 100);
    expect(sized.height, 145);
    expect(find.byKey(const ValueKey('host-standard-image')), findsOneWidget);
  });

  testWidgets('supports dimension-only external image syntax', (tester) async {
    String? receivedAlt = 'not-called';
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '![250](https://images.example.com/diagram.png)',
          imageBuilder: (uri, title, alt) {
            receivedAlt = alt;
            return const ColoredBox(color: Colors.blue);
          },
        ),
      ),
    );

    expect(receivedAlt, isNull);
    final sized = tester.widget<SizedBox>(
      find.byKey(const ValueKey('ianvs-markdown-image-size')),
    );
    expect(sized.width, 250);
    expect(sized.height, isNull);
  });

  testWidgets('keeps invalid image suffixes and does not size them', (
    tester,
  ) async {
    String? receivedAlt;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '![Diagram|100X145](diagram.png)',
          imageBuilder: (uri, title, alt) {
            receivedAlt = alt;
            return const ColoredBox(color: Colors.blue);
          },
        ),
      ),
    );

    expect(receivedAlt, 'Diagram|100X145');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-image-size')),
      findsNothing,
    );
  });

  testWidgets('cleans blocked image labels without performing image I/O', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '![Diagram|120](https://images.example.com/diagram.png)',
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-image-blocked')),
      findsOneWidget,
    );
    expect(find.textContaining('Diagram'), findsOneWidget);
    expect(find.textContaining('Diagram|120'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('passes Wiki image dimensions to the host and constrains it', (
    tester,
  ) async {
    IanvsMarkdownWikiEmbedReference? received;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '![[assets/diagram.PNG|Caption|100x145]]',
          wikiEmbedBuilder: (context, reference) {
            received = reference;
            return const ColoredBox(
              key: ValueKey('host-wiki-image'),
              color: Colors.green,
            );
          },
        ),
      ),
    );

    expect(received?.source, '![[assets/diagram.PNG|Caption|100x145]]');
    expect(received?.target, 'assets/diagram.PNG');
    expect(received?.alias, 'Caption');
    expect(received?.displayLabel, 'Caption');
    expect(received?.isImageEmbed, isTrue);
    expect(received?.width, 100);
    expect(received?.height, 145);
    final sized = tester.widget<SizedBox>(
      find.byKey(const ValueKey('ianvs-markdown-image-size')),
    );
    expect(sized.width, 100);
    expect(sized.height, 145);
    expect(find.byKey(const ValueKey('host-wiki-image')), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
  });

  testWidgets('does not mistake a numeric note alias for image dimensions', (
    tester,
  ) async {
    IanvsMarkdownWikiEmbedReference? received;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '![[Quarterly Note|100]]',
          wikiEmbedBuilder: (context, reference) {
            received = reference;
            return Text(reference.displayLabel);
          },
        ),
      ),
    );

    expect(received?.isImageEmbed, isFalse);
    expect(received?.alias, '100');
    expect(received?.width, isNull);
    expect(received?.height, isNull);
    expect(find.text('100'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-image-size')),
      findsNothing,
    );
  });

  testWidgets('Live Preview sizes inactive images and edits exact source', (
    tester,
  ) async {
    const source = '![Diagram|120x80](diagram.png)';
    final controller = IanvsMarkdownController(text: '$source\n\nTail');
    addTearDown(controller.dispose);
    String? receivedAlt;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              imageBuilder: (uri, title, alt) {
                receivedAlt = alt;
                return const ColoredBox(
                  key: ValueKey('host-live-image'),
                  color: Colors.orange,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(receivedAlt, 'Diagram');
    final sized = tester.widget<SizedBox>(
      find.byKey(const ValueKey('ianvs-markdown-image-size')),
    );
    expect(sized.width, 120);
    expect(sized.height, 80);

    await tester.tap(find.byKey(const ValueKey('host-live-image')));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(controller.text, '$source\n\nTail');
  });
}
