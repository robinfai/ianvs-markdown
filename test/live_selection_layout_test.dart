import 'package:flutter/material.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/editor/block_identity.dart';

void main() {
  testWidgets(
    'short drags never flash an editing rail and subsequent taps still edit',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: 'Alpha opening words\n\nSecond paragraph',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: false,
              showToolbar: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      final origin =
          tester.getTopLeft(find.text('Alpha opening words')) +
          const Offset(2, 10);
      for (var attempt = 0; attempt < 5; attempt++) {
        final lateTap = tester
            .widget<SelectableText>(find.byType(SelectableText).first)
            .onTap!;
        await gesture.down(origin);
        await gesture.moveTo(origin + const Offset(12, 0));
        await tester.pump();
        await tester.pump();
        await gesture.up();
        await tester.pump();
        // Exercise a queued tap delivered after the drag's pointer-up cleanup.
        lateTap();
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            find.byKey(const ValueKey('ianvs-markdown-active-line-rail')),
            findsNothing,
            reason:
                'attempt $attempt frame $frame: a completed drag is not a tap',
          );
        }
        expect(
          controller.selection.isCollapsed,
          false,
          reason: 'attempt $attempt selection ${controller.selection}',
        );
        expect(controller.text, 'Alpha opening words\n\nSecond paragraph');
      }
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.down(
        tester.getCenter(find.text('Second paragraph')),
        timeStamp: const Duration(seconds: 2),
      );
      await gesture.up(timeStamp: const Duration(seconds: 2, milliseconds: 40));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-line-rail')),
        findsOneWidget,
      );
      expect(controller.selection.isCollapsed, true);
      expect(tester.takeException(), isNull);
    },
  );

  for (final initiallyFocused in [false, true]) {
    for (final scrolled in [false, true]) {
      testWidgets(
        'drag preserves layout and scroll attachment on every move, focused=$initiallyFocused scrolled=$scrolled',
        (tester) async {
          final source =
              '${scrolled ? 'Padding paragraph\n\n' * 4 : ''}Opening paragraph words\n\n1. First list item\n2. Second list item\n3. Third list item\n\n# Heading\n\n> Quoted text\n\nClosing paragraph words';
          final controller = IanvsMarkdownController(text: source);
          final scroll = ScrollController();
          final focus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(scroll.dispose);
          addTearDown(focus.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: IanvsMarkdownLiveEditor(
                  controller: controller,
                  scrollController: scroll,
                  focusNode: focus,
                  preserveViewport: true,
                  autofocus: false,
                  showToolbar: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(focus.hasFocus, false);
          if (scrolled) {
            scroll.jumpTo(120);
            await tester.pumpAndSettle();
          }
          if (initiallyFocused) {
            await tester.tap(find.text('Opening paragraph words'));
            await tester.pumpAndSettle();
            expect(focus.hasFocus, true);
          }
          final initialOffset = scroll.offset;
          final before = <int, Rect>{
            for (final element in find.byType(MarkdownBlockRegion).evaluate())
              (element.widget as MarkdownBlockRegion).block.start: tester
                  .getRect(find.byWidget(element.widget)),
          };
          final origin = tester.getCenter(find.text('Opening paragraph words'));
          final end = tester.getCenter(find.text('Closing paragraph words'));
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await gesture.down(origin);
          for (var step = 1; step <= 12; step++) {
            await gesture.moveTo(Offset.lerp(origin, end, step / 12)!);
            await tester.pump();
            await tester.pump();
            expect(scroll.positions.length, 1);
            expect(scroll.offset, initialOffset);
            expect(tester.takeException(), isNull);
            for (final element in find.byType(MarkdownBlockRegion).evaluate()) {
              final block = (element.widget as MarkdownBlockRegion).block;
              expect(
                tester.getRect(find.byWidget(element.widget)),
                before[block.start],
                reason: 'move $step: ${block.type}',
              );
            }
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(controller.selection.isCollapsed, false);
          expect(
            controller.selection.textInside(source),
            contains('Second list item'),
          );
          expect(focus.hasFocus, true);
          expect(controller.text, source);
          await gesture.removePointer();
        },
      );
    }
  }
  final cases = <String, String>{
    'ordered and wrapped lists':
        '1. First item\n2. Second item with a long line that wraps across the available content width several times.\n3. Third item\n4. Fourth item',
    'nested and task lists':
        '- Parent\n  - Nested child\n  - Another child\n- [ ] Pending\n- [x] Complete',
    'heading quote and code':
        '# Heading\n\n> Quoted **strong** text\n> second line\n\n```dart\nfinal value = 42;\n```\n\n    indented code',
    'table and inline elements':
        '| Name | Value |\n| --- | --- |\n| Alpha | **Bold** |\n| Beta | `code` |\n\nText with **bold**, *italic*, [link](https://example.com) and ~~deleted~~.',
    'callout math and rule':
        '> [!NOTE] Note\n> Some details\n\n\$\$x^2\$\$\n\n---\n\nTail \$x\$ text.',
  };
  for (final entry in cases.entries) {
    for (final backwards in [false, true]) {
      testWidgets(
        '${entry.key}: selection preserves every block, backwards=$backwards',
        (tester) async {
          tester.view.physicalSize = const Size(1000, 1600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final source =
              'Opening paragraph\n\n${entry.value}\n\nClosing paragraph';
          final controller = IanvsMarkdownController(text: source);
          addTearDown(controller.dispose);
          Widget host(Key key, bool autofocus) => MaterialApp(
            home: Scaffold(
              body: IanvsMarkdownLiveEditor(
                key: key,
                controller: controller,
                autofocus: autofocus,
                showToolbar: false,
                contentMaxWidth: 450,
              ),
            ),
          );
          await tester.pumpWidget(host(const ValueKey('before'), false));
          await tester.pumpAndSettle();
          final regions = find.byType(MarkdownBlockRegion);
          final before = <int, Rect>{
            for (final element in regions.evaluate())
              (element.widget as MarkdownBlockRegion).block.start: tester
                  .getRect(find.byWidget(element.widget)),
          };
          final start = source.indexOf('Opening') + 3;
          final end = source.indexOf('Closing') + 4;
          controller.selection = TextSelection(
            baseOffset: backwards ? end : start,
            extentOffset: backwards ? start : end,
          );
          await tester.pumpWidget(host(const ValueKey('selected'), true));
          await tester.pumpAndSettle();
          expect(regions, findsNWidgets(before.length));
          for (final element in regions.evaluate()) {
            final block = (element.widget as MarkdownBlockRegion).block;
            expect(
              tester.getRect(find.byWidget(element.widget)),
              before[block.start],
              reason: '${block.type}: ${block.source}',
            );
          }
          expect(controller.text, source);
          expect(controller.isDirty, false);
          expect(tester.testTextInput.hasAnyClients, true);
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
                'replacement',
              ),
              selection: TextSelection.collapsed(
                offset: value.selection.start + 11,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            controller.text,
            source.replaceRange(start, end, 'replacement'),
          );
          controller.undo();
          await tester.pumpAndSettle();
          expect(controller.text, source);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
