import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Future<void> mount(
  WidgetTester tester,
  IanvsMarkdownController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: IanvsMarkdownLiveEditor(
          controller: controller,
          autofocus: false,
          showToolbar: false,
          showNavigationPane: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> verifyEdits(
  WidgetTester tester,
  IanvsMarkdownController controller,
) async {
  final source = controller.text;
  final selection = controller.selection;
  for (final replacement in ['X', '']) {
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
        matching: find.byType(TextField),
      ),
    );
    final value = field.controller!.value;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(
          value.selection.start,
          value.selection.end,
          replacement,
        ),
        selection: TextSelection.collapsed(
          offset: value.selection.start + replacement.length,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller.text,
      source.replaceRange(selection.start, selection.end, replacement),
    );
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
    expect(controller.selection, selection);
  }
}

void main() {
  for (final column in [0, 1, 2]) {
    for (final backwards in [false, true]) {
      testWidgets('drag into table column $column backwards=$backwards', (
        tester,
      ) async {
        const source =
            'Opening words\n\n| Left | Middle | Right |\n| --- | --- | --- |\n| same | same | same |\n\nClosing words';
        final controller = IanvsMarkdownController(text: source);
        addTearDown(controller.dispose);
        await mount(tester, controller);
        final cell = find.byKey(ValueKey('ianvs-markdown-table-1-$column'));
        final editable = tester
            .state<EditableTextState>(
              find.descendant(of: cell, matching: find.byType(EditableText)),
            )
            .renderEditable;
        final caret = editable.getLocalRectForCaret(
          const TextPosition(offset: 2),
        );
        final end = editable.localToGlobal(Offset(caret.left, caret.center.dy));
        final start =
            tester.getTopLeft(
              find.text(backwards ? 'Closing words' : 'Opening words'),
            ) +
            const Offset(2, 10);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.down(start);
        for (var step = 1; step <= 10; step++) {
          await gesture.moveTo(Offset.lerp(start, end, step / 10)!);
          await tester.pump();
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
        await gesture.removePointer();
        final actualEnd = controller.selection.extentOffset;
        await verifyEdits(tester, controller);
        expect(actualEnd, source.indexOf('| same |') + 2 + column * 7 + 2);
      });
    }
  }

  testWidgets('selected text after inline link is painted', (tester) async {
    const source =
        'Opening words\n\nBefore [link](https://example.com) after\n\nClosing words';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await mount(tester, controller);
    controller.selection = TextSelection(
      baseOffset: 2,
      extentOffset: source.indexOf('Closing') + 3,
    );
    // Remount with focus to activate the source-backed cross-block input.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            key: const ValueKey('selected'),
            controller: controller,
            autofocus: true,
            showToolbar: false,
            showNavigationPane: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_RenderedSelectionSurface',
    );
    final render = tester.renderObject<RenderBox>(surface.at(1));
    final canvas = TestRecordingCanvas();
    render.paint(TestRecordingPaintingContext(canvas), Offset.zero);
    final rects = canvas.invocations
        .where((c) => c.invocation.memberName == #drawRect)
        .map((c) => c.invocation.positionalArguments.first as Rect)
        .toList();
    final texts = <RenderBox>[];
    void visit(RenderObject obj) {
      if (obj is RenderEditable || obj is RenderParagraph) {
        texts.add(obj as RenderBox);
      }
      obj.visitChildren(visit);
    }

    visit(render);
    for (final target in ['Before ', 'link', 'after']) {
      String textOf(RenderBox box) => switch (box) {
        RenderEditable e => e.text?.toPlainText() ?? '',
        RenderParagraph p => p.text.toPlainText(),
        _ => '',
      };
      final paragraph = texts.firstWhere((e) => textOf(e).contains(target));
      final visible = textOf(paragraph);
      final selection = TextSelection(
        baseOffset: visible.indexOf(target),
        extentOffset: visible.indexOf(target) + target.length,
      );
      final boxes = switch (paragraph) {
        RenderEditable e => e.getBoxesForSelection(selection),
        RenderParagraph p => p.getBoxesForSelection(selection),
        _ => <TextBox>[],
      };
      expect(boxes, isNotEmpty);
      for (final box in boxes) {
        final bounds = MatrixUtils.transformRect(
          paragraph.getTransformTo(render),
          box.toRect(),
        );
        expect(
          rects.any((rect) => rect.contains(bounds.center)),
          isTrue,
          reason: 'selected $target must have a painted highlight',
        );
      }
    }
    await verifyEdits(tester, controller);
  });
}
