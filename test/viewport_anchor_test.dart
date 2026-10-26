import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  test(
    'anchors follow unchanged content and reject stale viewport updates',
    () {
      const source =
          'Introduction\n\nTarget paragraph with meaningful content.\n\nEnd';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      final anchor = IanvsMarkdownViewportAnchor(
        source: source,
        sourceOffset: source.indexOf('Target'),
        viewportOffset: -12,
      );
      var textNotifications = 0;
      controller.addListener(() => textNotifications++);
      controller.rememberViewport(anchor);
      expect(textNotifications, 0);
      expect(controller.canUndo, isFalse);
      controller.text = 'Inserted\n\n$source';
      expect(
        controller.viewportAnchor.value!.sourceOffset,
        anchor.sourceOffset + 10,
      );
      expect(controller.viewportAnchor.value!.viewportOffset, -12);
      controller.rememberViewport(anchor);
      expect(controller.viewportAnchor.value!.source, controller.text);
      controller.restoreViewport();
      expect(controller.sourceNavigation.value!.viewportOffset, -12);
      expect(
        controller.sourceNavigation.value!.range.start,
        source.indexOf('Target') + 10,
      );
    },
  );

  test('replaced or ambiguous content falls back without splitting emoji', () {
    const anchor = IanvsMarkdownViewportAnchor(
      source: '😀old text',
      sourceOffset: 4,
      viewportOffset: -99,
    );
    final replaced = anchor.rebase('😁replacement');
    expect(replaced.sourceOffset, 0);
    expect(replaced.viewportOffset, 0);
    const moved = IanvsMarkdownViewportAnchor(
      source: 'before\nunique paragraph\nafter',
      sourceOffset: 7,
      viewportOffset: 8,
    );
    final next = moved.rebase('new\nunique paragraph\nafter\nend');
    expect(next.sourceOffset, 4);
    expect(next.viewportOffset, 8);
  });

  final source = List.generate(
    100,
    (i) => 'Paragraph $i has enough text to identify its position.',
  ).join('\n\n');
  for (final (mode, fallback) in [
    for (final mode in IanvsMarkdownEditorMode.values) (mode, false),
    (IanvsMarkdownEditorMode.livePreview, true),
    (IanvsMarkdownEditorMode.preview, true),
  ]) {
    testWidgets(
      '$mode fallback=$fallback user scroll wins over delayed restoration',
      (tester) async {
        final controller = IanvsMarkdownController(text: source, mode: mode);
        final scroll = ScrollController(keepScrollOffset: false);
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        controller.rememberViewport(
          IanvsMarkdownViewportAnchor(
            source: source,
            sourceOffset: source.indexOf('Paragraph 70 '),
            viewportOffset: 0,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IanvsMarkdownLiveEditor(
                controller: controller,
                renderBudget: fallback
                    ? const IanvsMarkdownRenderBudget(maxSourceCodeUnits: 1)
                    : const IanvsMarkdownRenderBudget(),
                scrollController: scroll,
                preserveViewport: true,
                showToolbar: false,
                showNavigationPane: false,
              ),
            ),
          ),
        );
        // The initial restoration is still waiting for layout. User input must
        // supersede it instead of being pulled back to the recovered paragraph.
        await tester.drag(
          find.byType(IanvsMarkdownLiveEditor),
          const Offset(0, -100),
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, lessThan(700));
        expect(
          controller.viewportAnchor.value!.sourceOffset,
          lessThan(source.indexOf('Paragraph 70 ')),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final (mode, fallback) in [
    for (final mode in IanvsMarkdownEditorMode.values) (mode, false),
    (IanvsMarkdownEditorMode.livePreview, true),
    (IanvsMarkdownEditorMode.preview, true),
  ]) {
    testWidgets(
      '$mode fallback=$fallback viewport survives unmount and remount',
      (tester) async {
        final controller = IanvsMarkdownController(text: source, mode: mode);
        final scroll = ScrollController(keepScrollOffset: false);
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        Widget host() => MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              renderBudget: fallback
                  ? const IanvsMarkdownRenderBudget(maxSourceCodeUnits: 1)
                  : const IanvsMarkdownRenderBudget(),
              scrollController: scroll,
              preserveViewport: true,
              autofocus: true,
              showToolbar: false,
              showNavigationPane: false,
            ),
          ),
        );
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        scroll.jumpTo(1200);
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(1200, 1));
        final saved = controller.viewportAnchor.value!;
        expect(saved.sourceOffset, greaterThan(0));
        final selection = controller.selection;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        final restored = controller.viewportAnchor.value!;
        expect(restored.sourceOffset, saved.sourceOffset);
        expect(restored.viewportOffset, closeTo(saved.viewportOffset, 1));
        expect(scroll.offset, closeTo(1200, 1));
        expect(controller.selection, selection);
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Read Live Source cycle stays near the visible paragraph', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: source,
      mode: IanvsMarkdownEditorMode.preview,
    );
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            scrollController: scroll,
            preserveViewport: true,
            showToolbar: false,
            showNavigationPane: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(1200);
    await tester.pumpAndSettle();
    final saved = controller.viewportAnchor.value!;
    for (final mode in [
      IanvsMarkdownEditorMode.livePreview,
      IanvsMarkdownEditorMode.source,
      IanvsMarkdownEditorMode.preview,
    ]) {
      controller.mode = mode;
      await tester.pumpAndSettle();
      expect(
        controller.viewportAnchor.value!.sourceOffset,
        closeTo(saved.sourceOffset, 60),
      );
    }
    expect(controller.isDirty, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in [
    IanvsMarkdownEditorMode.preview,
    IanvsMarkdownEditorMode.livePreview,
  ]) {
    testWidgets(
      '$mode keeps its paragraph when an image loads or typography changes',
      (tester) async {
        final height = ValueNotifier<double>(40);
        final controller = IanvsMarkdownController(
          text: '![image](local.png)\n\n$source',
          mode: mode,
        );
        final scroll = ScrollController();
        addTearDown(height.dispose);
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        Widget host(double fontSize) => MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              scrollController: scroll,
              preserveViewport: true,
              showToolbar: false,
              showNavigationPane: false,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: fontSize, height: 1.5),
              ),
              imageBuilder: (_, _, _) => ValueListenableBuilder<double>(
                valueListenable: height,
                builder: (_, value, _) => SizedBox(height: value, width: 200),
              ),
            ),
          ),
        );
        await tester.pumpWidget(host(14));
        await tester.pumpAndSettle();
        scroll.jumpTo(180);
        await tester.pumpAndSettle();
        final saved = controller.viewportAnchor.value!;
        final before = controller.value;
        final paragraph = controller.text
            .substring(saved.sourceOffset)
            .split('\n')
            .first;
        final target = find.text(paragraph, findRichText: true);
        final originalTop = tester.getTopLeft(target).dy;
        height.value = 300;
        await tester.pumpAndSettle();
        expect(
          controller.viewportAnchor.value!.sourceOffset,
          saved.sourceOffset,
        );
        expect(
          controller.viewportAnchor.value!.viewportOffset,
          closeTo(saved.viewportOffset, 1),
        );
        expect(scroll.offset, closeTo(440, 1));
        expect(tester.getTopLeft(target).dy, closeTo(originalTop, 1));
        await tester.pumpWidget(host(22));
        await tester.pumpAndSettle();
        expect(
          controller.viewportAnchor.value!.sourceOffset,
          saved.sourceOffset,
        );
        expect(
          controller.viewportAnchor.value!.viewportOffset,
          closeTo(saved.viewportOffset, 1),
        );
        expect(tester.getTopLeft(target).dy, closeTo(originalTop, 1));
        expect(controller.value, before);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'standalone Read rebases the current viewport rather than the initial one',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final initial = IanvsMarkdownViewportAnchor(
        source: source,
        sourceOffset: source.indexOf('Paragraph 10 '),
        viewportOffset: 0,
      );
      IanvsMarkdownViewportAnchor? captured;
      Widget host(String text) => MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: text,
            controller: scroll,
            initialViewportAnchor: initial,
            onViewportChanged: (value) => captured = value,
            preserveScrollOnUpdate: true,
            showOutline: false,
          ),
        ),
      );
      await tester.pumpWidget(host(source));
      await tester.pumpAndSettle();
      scroll.jumpTo(1600);
      await tester.pumpAndSettle();
      final current = captured!;
      const prefix = 'Inserted paragraph\n\n';
      await tester.pumpWidget(host('$prefix$source'));
      await tester.pumpAndSettle();
      expect(captured!.sourceOffset, current.sourceOffset + prefix.length);
      expect(captured!.viewportOffset, closeTo(current.viewportOffset, 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
