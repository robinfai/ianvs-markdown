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
  testWidgets('drag can collapse back to its anchor', (tester) async {
    final controller = IanvsMarkdownController(
      text: 'Opening words\n\nClosing words',
    );
    addTearDown(controller.dispose);
    await mount(tester, controller);
    final origin =
        tester.getTopLeft(find.text('Opening words')) + const Offset(2, 10);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.down(origin);
    await gesture.moveTo(origin + const Offset(60, 0));
    await tester.pump();
    await tester.pump();
    final anchor = controller.selection.baseOffset;
    expect(controller.selection.isCollapsed, false);
    await gesture.moveTo(origin);
    await tester.pump();
    await tester.pump();
    expect(controller.selection.extentOffset, anchor);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.selection.isCollapsed, true);
  });

  for (final target in ['link', 'after']) {
    for (final backwards in [false, true]) {
      testWidgets(
        'drag hits exact inline $target source on every frame backwards=$backwards',
        (tester) async {
          const source =
              'Opening words\n\nBefore [link](https://example.com/after) after text\n\nClosing words';
          final controller = IanvsMarkdownController(text: source);
          addTearDown(controller.dispose);
          await mount(tester, controller);
          final boxes = <RenderBox>[];
          void visit(RenderObject object) {
            if (object is RenderEditable || object is RenderParagraph) {
              boxes.add(object as RenderBox);
            }
            object.visitChildren(visit);
          }

          visit(
            tester.renderObject(
              find.byKey(
                const ValueKey('ianvs-markdown-document-drag-selection'),
              ),
            ),
          );
          String textOf(RenderBox box) => switch (box) {
            RenderEditable e => e.text?.toPlainText() ?? '',
            RenderParagraph p => p.text.toPlainText(),
            _ => '',
          };
          final box = boxes.firstWhere((box) => textOf(box).contains(target));
          final offset = textOf(box).indexOf(target) + 2;
          final caret = switch (box) {
            RenderEditable e => e.getLocalRectForCaret(
              TextPosition(offset: offset),
            ),
            RenderParagraph p =>
              p
                  .getBoxesForSelection(
                    TextSelection(baseOffset: offset, extentOffset: offset + 1),
                  )
                  .first
                  .toRect(),
            _ => Rect.zero,
          };
          final end = box.localToGlobal(Offset(caret.left, caret.center.dy));
          final origin =
              tester.getTopLeft(
                find.text(backwards ? 'Closing words' : 'Opening words'),
              ) +
              const Offset(2, 10);
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(gesture.removePointer);
          await gesture.down(origin);
          await gesture.moveTo(end);
          final expected =
              (target == 'link'
                  ? source.indexOf('[link') + 1
                  : source.lastIndexOf('after')) +
              2;
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump();
            expect(
              controller.selection.extentOffset,
              expected,
              reason: 'frame $frame',
            );
          }
          expect(controller.selection.extentOffset, expected);
          await gesture.moveTo(end + const Offset(0.1, 0));
          await tester.pump();
          await tester.pump();
          expect(controller.selection.extentOffset, expected);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(controller.selection.extentOffset, expected);
          // Inspect partial highlights too: matching against the hidden URL can
          // accidentally highlight an entire word or omit its selected prefix.
          final surface = tester.renderObject<RenderBox>(
            find
                .byWidgetPredicate(
                  (widget) =>
                      widget.runtimeType.toString() ==
                      '_RenderedSelectionSurface',
                )
                .at(1),
          );
          final canvas = TestRecordingCanvas();
          surface.paint(TestRecordingPaintingContext(canvas), Offset.zero);
          final rects = canvas.invocations
              .where((call) => call.invocation.memberName == #drawRect)
              .map((call) => call.invocation.positionalArguments.first as Rect)
              .toList();
          boxes.clear();
          visit(surface);
          final paintedBox = boxes.firstWhere(
            (box) => textOf(box).contains(target),
          );
          final textStart = textOf(paintedBox).indexOf(target);
          for (var character = 0; character < target.length; character++) {
            final selection = TextSelection(
              baseOffset: textStart + character,
              extentOffset: textStart + character + 1,
            );
            final characterBoxes = switch (paintedBox) {
              RenderEditable e => e.getBoxesForSelection(selection),
              RenderParagraph p => p.getBoxesForSelection(selection),
              _ => <TextBox>[],
            };
            for (final textBox in characterBoxes) {
              final bounds = MatrixUtils.transformRect(
                paintedBox.getTransformTo(surface),
                textBox.toRect(),
              );
              expect(
                rects.any((rect) => rect.contains(bounds.center)),
                backwards ? character >= 2 : character < 2,
                reason: '$target character $character',
              );
            }
          }
          await verifyEdits(tester, controller);
        },
      );
    }
  }

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
