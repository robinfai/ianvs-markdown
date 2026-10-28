import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  final longLine = List.filled(30, 'long_code_token').join(' ');
  for (final indented in [false, true]) {
    for (final brightness in Brightness.values) {
      for (final direction in TextDirection.values) {
        testWidgets(
          'Live code background fills its frame across focus ($indented, $brightness, $direction)',
          (tester) async {
            final source = indented
                ? '    $longLine\n    tail'
                : '```text\n$longLine\ntail\n```';
            final controller = IanvsMarkdownController(text: source);
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: Directionality(
                  textDirection: direction,
                  child: Scaffold(
                    body: SizedBox(
                      width: 360,
                      child: IanvsMarkdownLiveEditor(
                        controller: controller,
                        showToolbar: false,
                        showNavigationPane: false,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final inactivePattern = find.byKey(
              ValueKey(
                indented
                    ? 'ianvs-markdown-live-indented-code-pattern'
                    : 'ianvs-markdown-code-pattern',
              ),
            );
            final before = tester.getRect(inactivePattern);
            await tester.tap(find.byType(SelectableText).first);
            await tester.pumpAndSettle();

            final active = find.byKey(
              const ValueKey('ianvs-markdown-active-block'),
            );
            final pattern = find.byKey(
              const ValueKey('ianvs-markdown-active-code-pattern'),
            );
            final container = tester.widget<Container>(active);
            final frame = container.margin!
                .resolve(direction)
                .deflateRect(tester.getRect(active));
            expect(tester.getRect(pattern), frame);
            expect(tester.getRect(pattern).left, closeTo(before.left, .01));
            expect(tester.getRect(pattern).right, closeTo(before.right, .01));
            for (final key in [
              'ianvs-markdown-active-line-rail',
              'ianvs-markdown-active-indented-code-line-rail',
              'ianvs-markdown-active-indented-code-line-marker',
            ]) {
              expect(find.byKey(ValueKey(key)), findsNothing);
            }
            final rail = find.byKey(
              const ValueKey('ianvs-markdown-active-code-line-rail'),
            );
            expect(rail, findsOneWidget);
            if (direction == TextDirection.ltr) {
              expect(tester.getRect(rail).right, lessThan(frame.left));
            } else {
              expect(tester.getRect(rail).left, greaterThan(frame.right));
            }
            final field = tester.widget<TextField>(
              find.descendant(of: active, matching: find.byType(TextField)),
            );
            expect(field.focusNode!.hasFocus, isTrue);
            expect(field.controller!.text, source);
            expect(controller.isDirty, isFalse);
            expect(tester.takeException(), isNull);
          },
          variant: TargetPlatformVariant.only(TargetPlatform.macOS),
        );
      }
    }

    testWidgets(
      'code wrap toggles visual lines, preserving selection ($indented)',
      (tester) async {
        var wrap = true;
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return SizedBox(
                    width: 300,
                    child: IanvsMarkdownCodeLayout(
                      softWrap: wrap,
                      child: IanvsMarkdown(
                        data: indented
                            ? '    $longLine'
                            : '```dart\n$longLine\n```',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final editable = find.byType(EditableText);
        final initialState = tester.state(editable);
        final text = tester.widget<EditableText>(editable).controller;
        text.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
        final wrappedHeight = tester.getSize(editable).height;
        rebuild(() => wrap = false);
        await tester.pumpAndSettle();
        expect(tester.state(editable), same(initialState));
        expect(tester.getSize(editable).height, lessThan(wrappedHeight));
        expect(text.text, longLine);
        expect(
          text.selection,
          const TextSelection(baseOffset: 0, extentOffset: 8),
        );
        final horizontal = tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .where((state) => state.axisDirection == AxisDirection.right)
            .single;
        expect(horizontal.position.maxScrollExtent, greaterThan(300));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getTopLeft(editable) + const Offset(80, 10),
            scrollDelta: const Offset(500, 0),
          ),
        );
        await tester.pump();
        expect(horizontal.position.pixels, greaterThan(0));
        horizontal.position.jumpTo(horizontal.position.maxScrollExtent);
        await tester.pump();
        rebuild(() => wrap = true);
        await tester.pumpAndSettle();
        expect(horizontal.position.maxScrollExtent, 0);
        expect(horizontal.position.pixels, 0);
        expect(tester.getSize(editable).height, wrappedHeight);
        expect(text.text, longLine);
      },
    );
  }

  testWidgets(
    'Live active code keeps focus and editing history across wrap changes',
    (tester) async {
      final source = '```dart\n$longLine\n```';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      var wrap = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SizedBox(
                  width: 400,
                  child: IanvsMarkdownCodeLayout(
                    softWrap: wrap,
                    child: IanvsMarkdownLiveEditor(
                      controller: controller,
                      showToolbar: false,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SelectableText).first);
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget);
      final state = tester.state(field);
      final focus = FocusManager.instance.primaryFocus;
      final before = controller.value;
      final undo = controller.canUndo;
      rebuild(() => wrap = false);
      await tester.pumpAndSettle();
      expect(tester.state(field), same(state));
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(controller.value, before);
      expect(controller.canUndo, undo);
      expect(controller.isDirty, isFalse);
      final horizontal = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .where((state) => state.axisDirection == AxisDirection.right)
          .single;
      expect(horizontal.position.maxScrollExtent, greaterThan(300));
      rebuild(() => wrap = true);
      await tester.pumpAndSettle();
      expect(controller.value, before);
      expect(horizontal.position.maxScrollExtent, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
