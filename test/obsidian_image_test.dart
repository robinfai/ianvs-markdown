import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  const desktopPlatform = TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.macOS,
  });

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

  test('rewrites only rendered standard image size segments', () {
    const source =
        r'`![code](code.png)` %% ![hidden](hidden.png) %% '
        r'\![escaped](escaped.png) '
        '![First|100x50](image_(1).png "Caption") '
        '![Second][diagram-ref] ![Missing][missing-ref]';

    expect(
      rewriteIanvsMarkdownImageWidth(
        source,
        imageIndex: 0,
        width: 240,
        linkReferenceLabels: const <String>{'diagram-ref'},
      ),
      source.replaceFirst('First|100x50', 'First|240'),
    );
    expect(
      rewriteIanvsMarkdownImageWidth(
        source,
        imageIndex: 1,
        width: 90,
        linkReferenceLabels: const <String>{'diagram-ref'},
      ),
      source.replaceFirst('Second', 'Second|90'),
    );
    expect(
      rewriteIanvsMarkdownImageWidth(
        source,
        imageIndex: 2,
        width: 90,
        linkReferenceLabels: const <String>{'diagram-ref'},
      ),
      source,
    );
    expect(
      rewriteIanvsMarkdownImageWidth(
        '![250](image.png)',
        imageIndex: 0,
        width: null,
      ),
      '![](image.png)',
    );
    expect(
      rewriteIanvsMarkdownImageWidth(
        '![Alt|wide](image.png)',
        imageIndex: 0,
        width: 160,
      ),
      '![Alt|wide|160](image.png)',
    );
  });

  test('finds exact editable ranges for rendered standard images', () {
    const source =
        r'`![code](code.png)` %% ![hidden](hidden.png) %% '
        r'\![escaped](escaped.png) '
        '![First](image_(1).png "Caption") '
        '![Second][diagram-ref] ![Missing][missing-ref]';
    const references = <String>{'diagram-ref'};

    final inline = findIanvsMarkdownStandardImageSource(
      source,
      imageIndex: 0,
      linkReferenceLabels: references,
    );
    expect(inline, isNotNull);
    expect(
      source.substring(inline!.sourceRange.start, inline.sourceRange.end),
      '![First](image_(1).png "Caption")',
    );
    expect(
      source.substring(inline.editableRange.start, inline.editableRange.end),
      'image_(1).png "Caption"',
    );

    final reference = findIanvsMarkdownStandardImageSource(
      source,
      imageIndex: 1,
      linkReferenceLabels: references,
    );
    expect(reference, isNotNull);
    expect(
      source.substring(
        reference!.editableRange.start,
        reference.editableRange.end,
      ),
      'diagram-ref',
    );
    expect(
      findIanvsMarkdownStandardImageSource(
        source,
        imageIndex: 2,
        linkReferenceLabels: references,
      ),
      isNull,
    );
  });

  test('rewrites and resets Wiki image sizes without normalizing source', () {
    expect(
      rewriteIanvsMarkdownWikiImageWidth(
        '  ![[assets/image.png|Caption|100x50]]  ',
        width: 220,
      ),
      '  ![[assets/image.png|Caption|220]]  ',
    );
    expect(
      rewriteIanvsMarkdownWikiImageWidth(
        '![[assets/image.png|Caption|100x50]]',
        width: null,
      ),
      '![[assets/image.png|Caption]]',
    );
    expect(
      rewriteIanvsMarkdownWikiImageWidth(
        '![[assets/image.png|100]]',
        width: null,
      ),
      '![[assets/image.png]]',
    );
    expect(
      rewriteIanvsMarkdownWikiImageWidth('![[assets/image.png]]', width: 180),
      '![[assets/image.png|180]]',
    );
  });

  testWidgets(
    'desktop resize handle follows aspect ratio and resets',
    (tester) async {
      final widths = <int?>[];
      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: Align(
                alignment: Alignment.topLeft,
                child: IanvsMarkdownSizedImage(
                  dimensions: const IanvsMarkdownImageDimensions(
                    alt: 'Diagram',
                    width: 100,
                    height: 50,
                  ),
                  onResize: widths.add,
                  child: const ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
        ),
      );

      final opacityFinder = find.byKey(
        const ValueKey('ianvs-markdown-image-resize-handle-opacity'),
      );
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      final imageFinder = find.byKey(
        const ValueKey('ianvs-markdown-image-size'),
      );
      await mouse.moveTo(tester.getCenter(imageFinder));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1);

      final imageRect = tester.getRect(imageFinder);
      final handleRect = tester.getRect(
        find.byKey(const ValueKey('ianvs-markdown-image-resize-handle')),
      );
      expect(handleRect.bottomRight, imageRect.bottomRight);
      final start = handleRect.bottomRight - const Offset(1, 1);
      final target = imageRect.topLeft + const Offset(180, 90);
      await mouse.moveTo(start);
      await tester.pump();
      await mouse.down(start);
      await tester.pump();
      await mouse.moveTo(Offset.lerp(start, target, .5)!);
      await tester.pump();
      await mouse.moveTo(target);
      await tester.pump();
      await mouse.up();
      await tester.pump();

      expect(widths, <int?>[180]);
      expect(tester.getSize(imageFinder), const Size(180, 90));

      await tester.pump(const Duration(milliseconds: 500));
      final resetHandle = find.byKey(
        const ValueKey('ianvs-markdown-image-resize-handle'),
      );
      await tester.tap(resetHandle);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(resetHandle);
      await tester.pump();
      expect(widths, <int?>[180, null]);
      expect(tester.getSize(imageFinder), const Size(100, 50));
      await tester.pump(const Duration(milliseconds: 500));

      var resizedRect = tester.getRect(imageFinder);
      var resizedHandleRect = tester.getRect(
        find.byKey(const ValueKey('ianvs-markdown-image-resize-handle')),
      );
      var resizeStart = resizedHandleRect.bottomRight - const Offset(1, 1);
      await mouse.moveTo(resizeStart);
      await tester.pump();
      await mouse.down(resizeStart);
      await tester.pump();
      await mouse.moveTo(resizedRect.topLeft + const Offset(500, 250));
      await tester.pump();
      await mouse.up();
      await tester.pump();
      expect(widths, <int?>[180, null, 300]);
      expect(tester.getSize(imageFinder), const Size(300, 150));

      resizedRect = tester.getRect(imageFinder);
      resizedHandleRect = tester.getRect(
        find.byKey(const ValueKey('ianvs-markdown-image-resize-handle')),
      );
      resizeStart = resizedHandleRect.bottomRight - const Offset(1, 1);
      await mouse.moveTo(resizeStart);
      await tester.pump();
      await mouse.down(resizeStart);
      await tester.pump();
      await mouse.moveTo(resizedRect.topLeft + const Offset(5, 2.5));
      await tester.pump();
      await mouse.up();
      await tester.pump();
      expect(widths, <int?>[180, null, 300, 20]);
      expect(tester.getSize(imageFinder), const Size(20, 10));
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: desktopPlatform,
  );

  testWidgets(
    'mobile platforms do not expose the desktop resize handle',
    (tester) async {
      await tester.pumpWidget(
        app(
          IanvsMarkdownSizedImage(
            dimensions: const IanvsMarkdownImageDimensions(
              alt: 'Diagram',
              width: 100,
              height: 50,
            ),
            onResize: (_) {},
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('ianvs-markdown-image-resize-handle')),
        findsNothing,
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
    }),
  );

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

  testWidgets(
    'standard image resize callback reports its rendered index',
    (tester) async {
      final requests = <IanvsMarkdownImageResizeRequest>[];
      await tester.pumpWidget(
        app(
          IanvsMarkdown(
            data: '![Diagram|100x50](diagram.png)',
            imageBuilder: (uri, title, alt) => const AspectRatio(
              aspectRatio: 2,
              child: ColoredBox(color: Colors.blue),
            ),
            onImageResize: requests.add,
          ),
        ),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      final imageFinder = find.byKey(
        const ValueKey('ianvs-markdown-image-size'),
      );
      await mouse.moveTo(tester.getCenter(imageFinder));
      await tester.pump(const Duration(milliseconds: 150));
      final imageRect = tester.getRect(imageFinder);
      final handleRect = tester.getRect(
        find.byKey(const ValueKey('ianvs-markdown-image-resize-handle')),
      );
      final start = handleRect.bottomRight - const Offset(1, 1);
      final target = imageRect.topLeft + const Offset(180, 90);
      await mouse.moveTo(start);
      await tester.pump();
      await mouse.down(start);
      await tester.pump();
      await mouse.moveTo(Offset.lerp(start, target, .5)!);
      await tester.pump();
      await mouse.moveTo(target);
      await tester.pump();
      await mouse.up();
      await tester.pump();

      expect(requests, hasLength(1));
      expect(requests.single.syntax, IanvsMarkdownImageSourceSyntax.standard);
      expect(requests.single.imageIndex, 0);
      expect(requests.single.width, 180);
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: desktopPlatform,
  );

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

  testWidgets(
    'Live Preview drag rewrites width and double click resets it',
    (tester) async {
      const original = '![Diagram|100x50](diagram.png)';
      final controller = IanvsMarkdownController(text: '$original\n\nTail');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: IanvsMarkdownLiveEditor(
                controller: controller,
                showToolbar: false,
                imageBuilder: (uri, title, alt) => const AspectRatio(
                  aspectRatio: 2,
                  child: ColoredBox(color: Colors.orange),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      final imageFinder = find.byKey(
        const ValueKey('ianvs-markdown-image-size'),
      );
      await mouse.moveTo(tester.getCenter(imageFinder));
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(
                const ValueKey('ianvs-markdown-image-resize-handle-opacity'),
              ),
            )
            .opacity,
        1,
      );
      final imageRect = tester.getRect(imageFinder);
      final handleRect = tester.getRect(
        find.byKey(const ValueKey('ianvs-markdown-image-resize-handle')),
      );
      expect(handleRect.bottomRight, imageRect.bottomRight);
      final start = handleRect.bottomRight - const Offset(1, 1);
      final target = imageRect.topLeft + const Offset(180, 90);
      await mouse.moveTo(start);
      await tester.pump();
      await mouse.down(start);
      await tester.pump();
      await mouse.moveTo(Offset.lerp(start, target, .5)!);
      await tester.pump();
      await mouse.moveTo(target);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();

      expect(controller.text, '![Diagram|180](diagram.png)\n\nTail');
      expect(tester.getSize(imageFinder), const Size(180, 90));
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-block')),
        findsNothing,
      );

      await mouse.moveTo(tester.getCenter(imageFinder));
      await tester.pump(const Duration(milliseconds: 150));
      final handle = find.byKey(
        const ValueKey('ianvs-markdown-image-resize-handle'),
      );
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(handle);
      await tester.pumpAndSettle();

      expect(controller.text, '![Diagram](diagram.png)\n\nTail');
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-block')),
        findsNothing,
      );

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, '![Diagram|180](diagram.png)\n\nTail');
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, '$original\n\nTail');
    },
    variant: desktopPlatform,
  );

  testWidgets('Live Preview drag rewrites Wiki image width only', (
    tester,
  ) async {
    const original = '![[assets/diagram.png|Caption|100x50]]';
    final controller = IanvsMarkdownController(text: '$original\n\nTail');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              showToolbar: false,
              wikiEmbedBuilder: (context, reference) => const AspectRatio(
                aspectRatio: 2,
                child: ColoredBox(color: Colors.green),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final imageFinder = find.byKey(const ValueKey('ianvs-markdown-image-size'));
    await mouse.moveTo(tester.getCenter(imageFinder));
    await tester.pump(const Duration(milliseconds: 150));
    final imageRect = tester.getRect(imageFinder);
    final handleRect = tester.getRect(
      find.byKey(const ValueKey('ianvs-markdown-image-resize-handle')),
    );
    expect(handleRect.bottomRight, imageRect.bottomRight);
    final start = handleRect.bottomRight - const Offset(1, 1);
    final target = imageRect.topLeft + const Offset(180, 90);
    await mouse.moveTo(start);
    await tester.pump();
    await mouse.down(start);
    await tester.pump();
    await mouse.moveTo(Offset.lerp(start, target, .5)!);
    await tester.pump();
    await mouse.moveTo(target);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    expect(controller.text, '![[assets/diagram.png|Caption|180]]\n\nTail');
    expect(tester.getSize(imageFinder), const Size(180, 90));
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
  }, variant: desktopPlatform);

  testWidgets(
    'Live Preview sizes images and edits source through its control',
    (tester) async {
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

      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-block')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ianvs-markdown-image-controls')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('ianvs-markdown-image-edit')));
      await tester.pump();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      expect(active, findsOneWidget);
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, source);
      expect(
        field.controller?.selection,
        const TextSelection(baseOffset: 18, extentOffset: 29),
      );
      expect(find.byKey(const ValueKey('host-live-image')), findsOneWidget);
      expect(controller.text, '$source\n\nTail');
    },
  );
}
