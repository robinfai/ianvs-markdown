import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/editor/editor_diagnostics.dart';

class _BackgroundCanvas extends TestRecordingCanvas {
  @override
  Rect getLocalClipBounds() => const Rect.fromLTRB(0, 0, 800, 600);
}

Future<void> _mount(
  WidgetTester tester,
  IanvsMarkdownController controller,
  ScrollController scroll, {
  double width = 420,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  bool highlightSyntax = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        textTheme: const TextTheme(bodyLarge: TextStyle(letterSpacing: 2)),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: direction,
              child: SizedBox(
                width: width,
                height: 360,
                child: IanvsMarkdownEditor(
                  controller: controller,
                  scrollController: scroll,
                  showToolbar: false,
                  highlightSyntax: highlightSyntax,
                  padding: const EdgeInsetsDirectional.fromSTEB(31, 17, 19, 40),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectSurfaceTracksText(
  WidgetTester tester, {
  required String kind,
  required TextRange range,
  required double verticalOutset,
}) {
  final background = find.byKey(
    ValueKey('ianvs-markdown-source-$kind-backgrounds'),
  );
  final editable = tester
      .state<EditableTextState>(find.byType(EditableText))
      .renderEditable;
  final boxes = editable.getBoxesForSelection(
    TextSelection(baseOffset: range.start, extentOffset: range.end),
  );
  expect(boxes, isNotEmpty);
  final origin =
      editable.localToGlobal(Offset.zero) - tester.getTopLeft(background);
  final bounds = boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b))
      .shift(origin);
  final frames = _surfaceFrames(tester, kind);
  expect(frames, hasLength(1));
  expect(frames.single.top, closeTo(bounds.top - verticalOutset, .001));
  expect(frames.single.bottom, closeTo(bounds.bottom + verticalOutset, .001));
  expect(frames.single.left, closeTo(origin.dx - 6, .001));
  expect(
    frames.single.right,
    closeTo(origin.dx + editable.size.width + 6, .001),
  );
  expect(tester.takeException(), isNull);
}

List<Rect> _surfaceFrames(WidgetTester tester, String kind) {
  final background = find.byKey(
    ValueKey('ianvs-markdown-source-$kind-backgrounds'),
  );
  final canvas = _BackgroundCanvas();
  tester
      .widget<CustomPaint>(background)
      .painter!
      .paint(canvas, tester.getSize(background));
  return canvas.invocations
      .where((call) => call.invocation.memberName == #clipRRect)
      .map(
        (call) =>
            (call.invocation.positionalArguments.first as RRect).outerRect,
      )
      .toList();
}

void main() {
  testWidgets('growing fences and undo invalidate quote and code membership', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Plain\n');
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await _mount(tester, controller, scroll);
    const versions = [
      ('> Quote\n', 1, 0),
      ('```md\n> Inside\n', 0, 1),
      ('```md\n> Inside\n```\n\n> Outside\n', 1, 1),
    ];
    for (final (source, quotes, code) in versions) {
      controller.text = source;
      controller.commitHistoryGroup();
      await tester.pump();
      expect(_surfaceFrames(tester, 'quote'), hasLength(quotes));
      expect(_surfaceFrames(tester, 'code'), hasLength(code));
      expect(controller.text, source);
    }
    controller.undo();
    await tester.pump();
    expect(controller.text, versions[1].$1);
    expect(_surfaceFrames(tester, 'quote'), isEmpty);
    expect(_surfaceFrames(tester, 'code'), hasLength(1));
  });

  testWidgets(
    'disabled decoration does not parse and reenable uses current text',
    (tester) async {
      final controller = IanvsMarkdownController(text: '> Original\n');
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      final initial = IanvsMarkdownEditorDiagnostics.sourceBackgroundParses;
      await _mount(tester, controller, scroll, highlightSyntax: false);
      controller.text = '```md\n> Inside\n```\n';
      await tester.pump();
      expect(IanvsMarkdownEditorDiagnostics.sourceBackgroundParses, initial);
      expect(_surfaceFrames(tester, 'quote'), isEmpty);
      expect(_surfaceFrames(tester, 'code'), isEmpty);
      await _mount(tester, controller, scroll);
      expect(
        IanvsMarkdownEditorDiagnostics.sourceBackgroundParses,
        initial + 2,
      );
      expect(_surfaceFrames(tester, 'quote'), isEmpty);
      expect(_surfaceFrames(tester, 'code'), hasLength(1));
    },
  );

  testWidgets(
    'source ranges reuse selection and scroll updates, not text versions',
    (tester) async {
      const source = '> Quote **text**\n\n```dart\nfinal value = 1;\n```\n\n';
      final controller = IanvsMarkdownController(
        text: '$source${List.filled(30, 'After\n').join()}',
      )..selection = const TextSelection.collapsed(offset: 0);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await _mount(tester, controller, scroll);
      final initial = IanvsMarkdownEditorDiagnostics.sourceBackgroundParses;

      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 7),
        composing: const TextRange(start: 2, end: 7),
      );
      await tester.pump();
      scroll.jumpTo(40);
      await tester.pump();
      await _mount(tester, controller, scroll, width: 280, scale: 1.6);
      expect(IanvsMarkdownEditorDiagnostics.sourceBackgroundParses, initial);

      controller.text = '> Changed\n\n```dart\nnewCode();\n```\n';
      await tester.pump();
      expect(
        IanvsMarkdownEditorDiagnostics.sourceBackgroundParses,
        initial + 2,
      );
      _expectSurfaceTracksText(
        tester,
        kind: 'quote',
        range: const TextRange(start: 0, end: 10),
        verticalOutset: 8,
      );

      final replacement = IanvsMarkdownController(text: '> Replacement\n')
        ..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(replacement.dispose);
      await _mount(tester, replacement, scroll);
      expect(
        IanvsMarkdownEditorDiagnostics.sourceBackgroundParses,
        initial + 4,
      );
      _expectSurfaceTracksText(
        tester,
        kind: 'quote',
        range: TextRange(start: 0, end: replacement.text.length),
        verticalOutset: 8,
      );
      controller.text = '> Old controller must not repaint the new field\n';
      controller.commitHistoryGroup();
      await tester.pump();
      expect(
        IanvsMarkdownEditorDiagnostics.sourceBackgroundParses,
        initial + 4,
      );
    },
  );

  testWidgets(
    'budget rejection invalidates ranges before returning to Markdown',
    (tester) async {
      final controller = IanvsMarkdownController(text: '> Before\n')
        ..selection = const TextSelection.collapsed(offset: 0);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await _mount(tester, controller, scroll);
      final initial = IanvsMarkdownEditorDiagnostics.sourceBackgroundParses;
      controller.text = '> ${List.filled(5000, 'x').join()}';
      await tester.pump();
      expect(controller.parseDecision.useMarkdown, isFalse);
      expect(IanvsMarkdownEditorDiagnostics.sourceBackgroundParses, initial);
      for (final kind in ['quote', 'code']) {
        final background = find.byKey(
          ValueKey('ianvs-markdown-source-$kind-backgrounds'),
        );
        final canvas = _BackgroundCanvas();
        tester
            .widget<CustomPaint>(background)
            .painter!
            .paint(canvas, tester.getSize(background));
        expect(canvas.invocations, isEmpty);
      }
      controller.text = '> After\n';
      await tester.pump();
      expect(controller.parseDecision.useMarkdown, isTrue);
      expect(
        IanvsMarkdownEditorDiagnostics.sourceBackgroundParses,
        initial + 2,
      );
      _expectSurfaceTracksText(
        tester,
        kind: 'quote',
        range: TextRange(start: 0, end: controller.text.length),
        verticalOutset: 8,
      );
    },
  );

  for (final kind in ['quote', 'code']) {
    testWidgets(
      '$kind surface follows styled wraps, scaling, RTL and scrolling',
      (tester) async {
        const prefix = 'Before\n\n';
        final content = List.filled(
          7,
          '中文😀 **strong** and `inline` text',
        ).join(' ');
        final block = kind == 'quote'
            ? '> $content\n'
            : '```dart\n$content\n```\n';
        final controller = IanvsMarkdownController(
          text: '$prefix$block\n${List.filled(30, 'After\n').join()}',
        )..selection = const TextSelection.collapsed(offset: 0);
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        final range = TextRange(
          start: prefix.length,
          end: prefix.length + block.length,
        );
        await _mount(tester, controller, scroll);
        _expectSurfaceTracksText(
          tester,
          kind: kind,
          range: range,
          verticalOutset: kind == 'quote' ? 8 : 3,
        );

        await _mount(
          tester,
          controller,
          scroll,
          width: 280,
          scale: 1.6,
          direction: TextDirection.rtl,
        );
        _expectSurfaceTracksText(
          tester,
          kind: kind,
          range: range,
          verticalOutset: kind == 'quote' ? 8 : 3,
        );
        scroll.jumpTo(50);
        await tester.pump();
        _expectSurfaceTracksText(
          tester,
          kind: kind,
          range: range,
          verticalOutset: kind == 'quote' ? 8 : 3,
        );
      },
    );
  }
}
