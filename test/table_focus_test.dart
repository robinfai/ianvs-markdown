import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  for (final pressDuration in [
    Duration.zero,
    const Duration(milliseconds: 150),
  ]) {
    testWidgets(
      'table cell clicks keep input connected after ${pressDuration.inMilliseconds} ms',
      (tester) async {
        const source = '| Left | Right |\n| --- | --- |\n| alpha | bravo |';
        final controller = IanvsMarkdownController(text: source);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IanvsMarkdownLiveEditor(
                controller: controller,
                showToolbar: false,
                showNavigationPane: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final column in [0, 1, 0, 1]) {
          final cell = find.byKey(ValueKey('ianvs-markdown-table-1-$column'));
          final editableFinder = find.descendant(
            of: cell,
            matching: find.byType(EditableText),
          );
          final editable = tester.state<EditableTextState>(editableFinder);
          final render = editable.renderEditable;
          final caret = render.getLocalRectForCaret(
            const TextPosition(offset: 2),
          );
          final gesture = await tester.startGesture(
            render.localToGlobal(Offset(caret.left, caret.center.dy)),
            kind: PointerDeviceKind.mouse,
          );
          if (pressDuration != Duration.zero) {
            await tester.pump(pressDuration);
            await tester.pump();
          }
          await gesture.up();
          await tester.pumpAndSettle();

          final field = tester.widget<TextField>(cell);
          expect(field.focusNode!.hasPrimaryFocus, isTrue);
          expect(field.controller!.selection.isCollapsed, isTrue);
          expect(field.controller!.selection.extentOffset, 2);
          expect(
            tester.testTextInput.hasAnyClients,
            isTrue,
            reason: 'cell 1-$column must accept input without another click',
          );
          // enterText would request focus again and hide a broken connection.
          final editedText = column == 0 ? 'alXpha' : 'brXavo';
          tester.testTextInput.updateEditingValue(
            field.controller!.value.copyWith(
              text: editedText,
              selection: const TextSelection.collapsed(offset: 3),
            ),
          );
          await tester.pump();
          expect(field.controller!.text, editedText);
          expect(controller.text, contains(editedText));
          expect(
            controller.selection.extentOffset,
            controller.text.indexOf(editedText) + 3,
          );
          tester.testTextInput.updateEditingValue(
            field.controller!.value.copyWith(
              text: column == 0 ? 'alpha' : 'bravo',
              selection: const TextSelection.collapsed(offset: 2),
            ),
          );
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.desktop(),
    );
  }

  testWidgets(
    'switching table cells preserves mouse drag selection',
    (tester) async {
      const source = '| Left | Right |\n| --- | --- |\n| alpha | bravo delta |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              showToolbar: false,
              showNavigationPane: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final first = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(first, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(first).focusNode!.hasPrimaryFocus,
        isTrue,
      );

      final second = find.byKey(const ValueKey('ianvs-markdown-table-1-1'));
      final render = tester
          .state<EditableTextState>(
            find.descendant(of: second, matching: find.byType(EditableText)),
          )
          .renderEditable;
      Offset caretAt(int offset) {
        final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
        return render.localToGlobal(Offset(caret.left, caret.center.dy));
      }

      final gesture = await tester.startGesture(
        caretAt(1),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      await gesture.moveTo(caretAt(7));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(second);
      expect(field.focusNode!.hasPrimaryFocus, isTrue);
      expect(field.controller!.selection.baseOffset, 1);
      expect(field.controller!.selection.extentOffset, 7);
      expect(controller.selection.textInside(controller.text), 'ravo d');
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
