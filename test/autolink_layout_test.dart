import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

RenderEditable _editableWithin(WidgetTester tester, Finder finder) {
  RenderEditable? editable;
  void visit(RenderObject child) {
    if (editable != null) return;
    if (child is RenderEditable) {
      editable = child;
      return;
    }
    child.visitChildren(visit);
  }

  visit(tester.renderObject(finder));
  return editable!;
}

void main() {
  const url =
      'https://github.com/ABC_EDF_GHJ/bk_xxxxxxx/gateway/merge_requests/new'
      '?merge_request%5Bsource_branch%5D=wasm';

  for (final width in [320.0, 720.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
        'long quoted autolinks keep layout: width=$width, scale=$scale',
        (tester) async {
          const line = '2. echo "$url"';
          const source = 'Before\n\n$line\n\nAfter';
          final controller = IanvsMarkdownController(text: source);
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: IanvsMarkdownLiveEditor(
                  controller: controller,
                  showToolbar: false,
                  contentMaxWidth: width,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final block = find.byKey(
            const ValueKey('ianvs-markdown-block-8-orderedList'),
          );
          final blockRect = tester.getRect(block);
          final rendered = _editableWithin(
            tester,
            find.descendant(of: block, matching: find.byType(SelectableText)),
          );
          final renderedText = rendered.text!.toPlainText();
          expect(renderedText, 'echo "$url"');
          final start = renderedText.indexOf(url);
          final boxes = rendered.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + url.length),
          );
          final beforeOrigin = rendered.localToGlobal(Offset.zero);
          expect(boxes.length, greaterThan(1));
          for (final box in boxes) {
            final rect = box.toRect().shift(beforeOrigin);
            expect(rect.top, greaterThanOrEqualTo(blockRect.top));
            expect(rect.bottom, lessThanOrEqualTo(blockRect.bottom));
          }
          final beforeHeight = tester.getSize(block).height;
          final afterTop = tester.getTopLeft(find.text('After')).dy;

          await tester.tap(find.text('Before'));
          for (final caret in [
            source.indexOf('echo') + 1,
            source.indexOf('merge_requests') + 3,
          ]) {
            controller.selection = TextSelection.collapsed(offset: caret);
            await tester.pumpAndSettle();
            expect(tester.getSize(block).height, closeTo(beforeHeight, .01));
            expect(
              tester.getTopLeft(find.text('After')).dy,
              closeTo(afterTop, .01),
            );
            final editable = _editableWithin(tester, find.byType(TextField));
            expect(editable.text!.toPlainText(), contains(url));
            final activeStart = editable.text!.toPlainText().indexOf(url);
            final activeBoxes = editable.getBoxesForSelection(
              TextSelection(
                baseOffset: activeStart,
                extentOffset: activeStart + url.length,
              ),
            );
            expect(activeBoxes.length, boxes.length);
            for (var index = 0; index < boxes.length; index += 1) {
              final before = boxes[index].toRect().shift(beforeOrigin);
              final after = activeBoxes[index].toRect().shift(
                editable.localToGlobal(Offset.zero),
              );
              // Source marker spans can add a subpixel horizontal advance.
              expect(after.left, closeTo(before.left, .25));
              expect(after.top, closeTo(before.top, .1));
              expect(after.bottom, closeTo(before.bottom, .1));
            }
          }
          await tester.enterText(
            find.byType(TextField),
            line.replaceFirst('=wasm', '=native'),
          );
          await tester.pumpAndSettle();
          expect(controller.text, source.replaceFirst('=wasm', '=native'));
          controller.undo();
          await tester.pumpAndSettle();
          controller.selection = TextSelection.collapsed(
            offset: source.indexOf('After'),
          );
          await tester.pumpAndSettle();
          expect(tester.getSize(block).height, closeTo(beforeHeight, .01));
          expect(controller.text, source);
          expect(controller.isDirty, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
