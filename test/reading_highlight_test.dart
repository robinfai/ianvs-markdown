import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/renderer/reading_highlight.dart';

void main() {
  for (final mode in [
    IanvsMarkdownEditorMode.preview,
    IanvsMarkdownEditorMode.livePreview,
  ]) {
    for (final wrap in [false, true]) {
      testWidgets('code search reveals distant text in $mode wrap=$wrap', (
        tester,
      ) async {
        final source =
            '```dart\n${List.filled(80, "padding").join(" ")} needle();\n```';
        final controller = IanvsMarkdownController(text: source, mode: mode);
        addTearDown(controller.dispose);
        final matches = IanvsMarkdownReadingSearch.parse(
          source,
        )!.find('needle');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: IanvsMarkdownCodeLayout(
                  softWrap: wrap,
                  child: IanvsMarkdownLiveEditor(
                    controller: controller,
                    showToolbar: false,
                    readingHighlights: IanvsMarkdownReadingHighlights(
                      source: source,
                      matches: matches,
                      activeIndex: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (mode == IanvsMarkdownEditorMode.livePreview) {
          await tester.tapAt(
            tester.getTopLeft(find.byType(SelectableText).first) +
                const Offset(10, 10),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('ianvs-markdown-active-block')),
            findsOneWidget,
          );
        }
        final before = controller.value;
        controller.revealSourceRange(matches.single.navigationRange);
        await tester.pumpAndSettle();
        final render = tester
            .renderObjectList<RenderMarkdownReadingHighlight>(
              find.byType(MarkdownReadingHighlightOverlay),
            )
            .singleWhere((r) => r.activeRect != null);
        final rect = render.activeRect!;
        final topLeft = render.localToGlobal(rect.topLeft);
        final bottomRight = render.localToGlobal(rect.bottomRight);
        expect(topLeft.dx, greaterThanOrEqualTo(0));
        expect(bottomRight.dx, lessThanOrEqualTo(400));
        expect(topLeft.dy, inInclusiveRange(0, 600));
        expect(controller.value, before);
        expect(controller.canUndo, isFalse);
        if (!wrap) {
          expect(
            tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .any(
                  (s) =>
                      s.axisDirection == AxisDirection.right &&
                      s.position.pixels > 300,
                ),
            isTrue,
          );
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final listSource in [
    '- same\n- same\n- other',
    '1. same\n2. same',
    '- [ ] same\n- [x] same',
    '- parent\n    - same\n    - same',
  ]) {
    testWidgets(
      'Live highlights and navigates the second repeated item in $listSource',
      (tester) async {
        final source = listSource;
        final controller = IanvsMarkdownController(
          text: source,
          mode: IanvsMarkdownEditorMode.livePreview,
        );
        addTearDown(controller.dispose);
        final matches = IanvsMarkdownReadingSearch.parse(source)!.find('same');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IanvsMarkdownLiveEditor(
                controller: controller,
                readingHighlights: IanvsMarkdownReadingHighlights(
                  source: source,
                  matches: matches,
                  activeIndex: 1,
                ),
              ),
            ),
          ),
        );
        final before = controller.value;
        controller.revealSourceRange(matches.last.navigationRange);
        await tester.pumpAndSettle();
        final overlays = tester
            .renderObjectList<RenderMarkdownReadingHighlight>(
              find.byType(MarkdownReadingHighlightOverlay),
            )
            .toList();
        expect(overlays.length, 2);
        expect(overlays.first.activeRect, isNull);
        expect(overlays.last.activeRect, isNotNull);
        expect(controller.value, before);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final activeSource in [
    'target phrase',
    'target **phrase**',
    'target [phrase](hidden)',
    'target `phrase`',
    '# target phrase',
    '## target phrase ##',
    '- target phrase',
    '1. target phrase',
    '- [ ] target phrase',
    '> target phrase',
    '> > target phrase',
    'target phrase\n===',
  ]) {
    for (final caretInside in [false, true]) {
      testWidgets(
        'Live active $activeSource caretInside=$caretInside retains its editing selection during search',
        (tester) async {
          final source = activeSource;
          final controller = IanvsMarkdownController(
            text: source,
            mode: IanvsMarkdownEditorMode.livePreview,
          );
          controller.selection = TextSelection.collapsed(
            offset: caretInside ? source.indexOf('phrase') + 1 : 3,
          );
          final queryFocus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(queryFocus.dispose);
          final matches = IanvsMarkdownReadingSearch.parse(
            source,
          )!.find('target phrase');
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    TextField(focusNode: queryFocus),
                    Expanded(
                      child: IanvsMarkdownLiveEditor(
                        controller: controller,
                        autofocus: true,
                        readingHighlights: IanvsMarkdownReadingHighlights(
                          source: source,
                          matches: matches,
                          activeIndex: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('ianvs-markdown-active-block')),
            findsOneWidget,
          );
          queryFocus.requestFocus();
          await tester.pumpAndSettle();
          final before = controller.value;
          controller.revealSourceRange(matches.single.sourceRange);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('ianvs-markdown-active-block')),
            findsOneWidget,
          );
          final render = tester.renderObject<RenderMarkdownReadingHighlight>(
            find.byType(MarkdownReadingHighlightOverlay),
          );
          expect(render.activeRect, isNotNull);
          expect(controller.value, before);
          expect(queryFocus.hasFocus, isTrue);
          expect(controller.canUndo, isFalse);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final body in ['target phrase', 'target **phrase**']) {
    testWidgets('Live preview highlights $body without stealing query focus', (
      tester,
    ) async {
      final source = 'first paragraph\n\n$body';
      final controller = IanvsMarkdownController(
        text: source,
        mode: IanvsMarkdownEditorMode.livePreview,
      );
      final queryFocus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(queryFocus.dispose);
      final matches = IanvsMarkdownReadingSearch.parse(
        source,
      )!.find('target phrase');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: queryFocus),
                Expanded(
                  child: IanvsMarkdownLiveEditor(
                    controller: controller,
                    readingHighlights: IanvsMarkdownReadingHighlights(
                      source: source,
                      matches: matches,
                      activeIndex: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      queryFocus.requestFocus();
      await tester.pump();
      final before = controller.value;
      controller.revealSourceRange(matches.single.sourceRange);
      await tester.pumpAndSettle();
      final render = tester.renderObject<RenderMarkdownReadingHighlight>(
        find.byType(MarkdownReadingHighlightOverlay),
      );
      expect(render.activeRect, isNotNull);
      expect(queryFocus.hasFocus, isTrue);
      expect(controller.value, before);
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('active text reveals through a horizontal code-like viewport', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final text = '${List.filled(120, "word").join(" ")} needle';
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: MarkdownReadingHighlightOverlay(
              flows: [
                MarkdownReadingHighlightFlow(
                  text: text,
                  ranges: [TextRange(start: text.length - 6, end: text.length)],
                  activeRange: TextRange(
                    start: text.length - 6,
                    end: text.length,
                  ),
                ),
              ],
              child: SingleChildScrollView(
                controller: scroll,
                scrollDirection: Axis.horizontal,
                child: Text(text, style: const TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderMarkdownReadingHighlight>(
      find.byType(MarkdownReadingHighlightOverlay),
    );
    render.revealActiveText();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(100));
    expect(render.activeRect!.right, lessThanOrEqualTo(201));
    expect(render.activeRect!.left, greaterThanOrEqualTo(-1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search decoration paints after an opaque text background', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: MarkdownReadingHighlightOverlay(
            flows: [
              MarkdownReadingHighlightFlow(
                text: 'needle',
                ranges: [TextRange(start: 0, end: 6)],
                activeRange: TextRange(start: 0, end: 6),
              ),
            ],
            child: ColoredBox(color: Color(0xff123456), child: Text('needle')),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderMarkdownReadingHighlight>(
      find.byType(MarkdownReadingHighlightOverlay),
    );
    expect(
      render,
      paints
        ..rect(color: const Color(0xff123456))
        ..rrect(color: const Color(0x99ff9800)),
    );
  });

  testWidgets('Read paints and reveals a hit inside collapsed selectable code', (
    tester,
  ) async {
    final source =
        '```dart\n${List.generate(90, (i) => "line $i;").join("\n")}\nneedle();\n```';
    final matches = IanvsMarkdownReadingSearch.parse(source)!.find('needle');
    final navigation = ValueNotifier<IanvsMarkdownSourceNavigation?>(null);
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: source,
            showOutline: false,
            sourceNavigation: navigation,
            readingHighlights: IanvsMarkdownReadingHighlights(
              source: source,
              matches: matches,
              activeIndex: 0,
            ),
          ),
        ),
      ),
    );
    navigation.value = IanvsMarkdownSourceNavigation(
      source: source,
      range: matches.single.sourceRange,
    );
    await tester.pumpAndSettle();
    final render = tester.renderObject<RenderMarkdownReadingHighlight>(
      find.byType(MarkdownReadingHighlightOverlay),
    );
    expect(render.activeRect, isNotNull);
    final position = render.localToGlobal(render.activeRect!.topLeft);
    expect(position.dy, greaterThanOrEqualTo(0));
    expect(position.dy, lessThan(600));
    expect(tester.takeException(), isNull);
    final scrolls = tester.stateList<ScrollableState>(find.byType(Scrollable));
    expect(scrolls.any((s) => s.position.pixels > 100), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tab-expanded fenced code still has matching text geometry', (
    tester,
  ) async {
    const source = '```dart\n\tneedle();\n```';
    final matches = IanvsMarkdownReadingSearch.parse(source)!.find('needle');
    await tester.pumpWidget(
      MaterialApp(
        home: IanvsMarkdownView(
          data: source,
          readingHighlights: IanvsMarkdownReadingHighlights(
            source: source,
            matches: matches,
            activeIndex: 0,
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderMarkdownReadingHighlight>(
      find.byType(MarkdownReadingHighlightOverlay),
    );
    expect(render.activeRect, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Read reveals the active occurrence inside a long paragraph', (
    tester,
  ) async {
    final source =
        'needle ${List.filled(300, "filler words").join(" ")} needle';
    final matches = IanvsMarkdownReadingSearch.parse(source)!.find('needle');
    final navigation = ValueNotifier<IanvsMarkdownSourceNavigation?>(null);
    final scroll = ScrollController();
    addTearDown(navigation.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: source,
            controller: scroll,
            showOutline: false,
            sourceNavigation: navigation,
            readingHighlights: IanvsMarkdownReadingHighlights(
              source: source,
              matches: matches,
              activeIndex: 1,
            ),
          ),
        ),
      ),
    );
    navigation.value = IanvsMarkdownSourceNavigation(
      source: source,
      range: matches.last.sourceRange,
    );
    await tester.pumpAndSettle();
    final render = tester.renderObject<RenderMarkdownReadingHighlight>(
      find.byType(MarkdownReadingHighlightOverlay),
    );
    final position = render.localToGlobal(render.activeRect!.topLeft);
    expect(scroll.offset, greaterThan(300));
    expect(position.dy, greaterThanOrEqualTo(0));
    expect(position.dy, lessThan(600));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'inline widget text remains searchable between surrounding spans',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: MarkdownReadingHighlightOverlay(
              flows: [
                MarkdownReadingHighlightFlow(
                  text: 'before code after',
                  ranges: [TextRange(start: 7, end: 11)],
                  activeRange: TextRange(start: 7, end: 11),
                ),
              ],
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'before '),
                    WidgetSpan(child: Text('code')),
                    TextSpan(text: ' after'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final render = tester.renderObject<RenderMarkdownReadingHighlight>(
        find.byType(MarkdownReadingHighlightOverlay),
      );
      expect(render.activeRect, isNotNull);
      expect(render.activeRect!.width, greaterThan(10));
      expect(render, paints..rrect(color: const Color(0x99ff9800)));
    },
  );

  testWidgets(
    'Read highlights the selected occurrence in repeated paragraphs',
    (tester) async {
      const source = 'same **phrase**\n\nsame phrase';
      final matches = IanvsMarkdownReadingSearch.parse(
        source,
      )!.find('same phrase');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownView(
              data: source,
              showOutline: false,
              readingHighlights: IanvsMarkdownReadingHighlights(
                source: source,
                matches: matches,
                activeIndex: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final overlays = tester
          .renderObjectList<RenderMarkdownReadingHighlight>(
            find.byType(MarkdownReadingHighlightOverlay),
          )
          .toList();
      expect(overlays.length, 2);
      expect(overlays.first.activeRect, isNull);
      expect(overlays.last.activeRect, isNotNull);
      expect(overlays.last.activeRect!.width, greaterThan(20));
      expect(overlays.last, paints..rrect(color: const Color(0x99ff9800)));
    },
  );

  testWidgets('stale highlights disappear after source changes', (
    tester,
  ) async {
    const source = 'needle';
    final highlights = IanvsMarkdownReadingHighlights(
      source: source,
      matches: IanvsMarkdownReadingSearch.parse(source)!.find('needle'),
      activeIndex: 0,
    );
    Widget view(String text) => MaterialApp(
      home: IanvsMarkdownView(data: text, readingHighlights: highlights),
    );
    await tester.pumpWidget(view(source));
    expect(find.byType(MarkdownReadingHighlightOverlay), findsOneWidget);
    await tester.pumpWidget(view('different text'));
    expect(find.byType(MarkdownReadingHighlightOverlay), findsNothing);
  });

  testWidgets('highlight geometry follows wrapping without editing text', (
    tester,
  ) async {
    const text = 'a phrase that wraps onto several lines';
    Widget view(double width) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: width,
          child: MarkdownReadingHighlightOverlay(
            flows: const [
              MarkdownReadingHighlightFlow(
                text: text,
                ranges: [TextRange(start: 0, end: text.length)],
                activeRange: TextRange(start: 0, end: text.length),
              ),
            ],
            child: const Text(text),
          ),
        ),
      ),
    );
    await tester.pumpWidget(view(600));
    final render = tester.renderObject<RenderMarkdownReadingHighlight>(
      find.byType(MarkdownReadingHighlightOverlay),
    );
    final before = render.activeRect!;
    await tester.pumpWidget(view(100));
    expect(render.activeRect!.height, greaterThan(before.height));
    expect(find.text(text), findsOneWidget);
  });
}
