import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Widget _host(
  IanvsMarkdownController controller, {
  FocusNode? focus,
  ScrollController? scroll,
  bool autofocus = true,
  bool showFrontMatter = false,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 500,
      height: 360,
      child: IanvsMarkdownLiveEditor(
        controller: controller,
        focusNode: focus,
        scrollController: scroll,
        autofocus: autofocus,
        showToolbar: false,
        showFrontMatter: showFrontMatter,
      ),
    ),
  ),
);

Finder get _activeEditable => find.descendant(
  of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
  matching: find.byType(EditableText),
);

Future<void> _replaceFocusedSelection(
  WidgetTester tester,
  String inserted,
) async {
  // Send through the already-connected input client, without tap/showKeyboard
  // or tester.enterText, which would otherwise hide missing autofocus.
  expect(tester.testTextInput.hasAnyClients, isTrue);
  final editable = tester.widget<EditableText>(_activeEditable);
  expect(editable.focusNode.hasFocus, isTrue);
  final value = editable.controller.value;
  expect(value.selection.isValid, isTrue);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(
        value.selection.start,
        value.selection.end,
        inserted,
      ),
      selection: TextSelection.collapsed(
        offset: value.selection.start + inserted.length,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final selected in [false, true]) {
    for (final yaml in ['', '---\ntitle: Hidden\n---\n\n']) {
      testWidgets(
        'autofocus restores non-first ${selected ? 'selection' : 'caret'} with YAML=${yaml.isNotEmpty}',
        (tester) async {
          final text =
              '${yaml}First paragraph.\n\nSecond target paragraph.\n\nLast paragraph.';
          final start = text.indexOf('target');
          final selection = selected
              ? TextSelection(baseOffset: start + 6, extentOffset: start)
              : TextSelection.collapsed(offset: start + 2);
          final controller = IanvsMarkdownController(text: text)
            ..selection = selection;
          final focus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(focus.dispose);
          final history = controller.retainedHistoryEntries;
          await tester.pumpWidget(_host(controller, focus: focus));
          await tester.pumpAndSettle();
          expect(controller.selection, selection);
          expect(controller.text, text);
          expect(controller.retainedHistoryEntries, history);
          expect(controller.isDirty, isFalse);
          expect(_activeEditable, findsOneWidget);
          await _replaceFocusedSelection(tester, 'X');
          expect(
            controller.text,
            text.replaceRange(selection.start, selection.end, 'X'),
          );
          expect(controller.text, startsWith(yaml));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('autofocus preserves a cross-block source selection', (
    tester,
  ) async {
    const text = 'First.\n\nSecond paragraph.\n\nThird paragraph.\n\nLast.';
    final selection = TextSelection(
      baseOffset: text.indexOf('Second') + 2,
      extentOffset: text.indexOf('Third') + 5,
    );
    final controller = IanvsMarkdownController(text: text)
      ..selection = selection;
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    expect(controller.selection, selection);
    await _replaceFocusedSelection(tester, 'X');
    expect(
      controller.text,
      text.replaceRange(selection.start, selection.end, 'X'),
    );
    expect(tester.takeException(), isNull);
  });

  for (final selected in [false, true]) {
    testWidgets(
      'autofocus mounts a distant lazy ${selected ? 'selection' : 'caret'} and connects input',
      (tester) async {
        final text = List.generate(
          160,
          (i) => 'Paragraph $i has target text.',
        ).join('\n\n');
        final target = text.indexOf('target', text.indexOf('Paragraph 145 '));
        final selection = selected
            ? TextSelection(baseOffset: target, extentOffset: target + 6)
            : TextSelection.collapsed(offset: target + 2);
        final controller = IanvsMarkdownController(text: text)
          ..selection = selection;
        final focus = FocusNode();
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          _host(controller, focus: focus, scroll: scroll),
        );
        await tester.pumpAndSettle();
        expect(controller.selection, selection);
        expect(scroll.offset, greaterThan(1000));
        expect(_activeEditable, findsOneWidget);
        final bounds = tester.getRect(_activeEditable);
        expect(bounds.bottom, greaterThan(0));
        expect(bounds.top, lessThan(360));
        await _replaceFocusedSelection(tester, 'X');
        expect(
          controller.text,
          text.replaceRange(selection.start, selection.end, 'X'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final framesBeforeFocus in [0, 1]) {
    for (final selected in [false, true]) {
      testWidgets(
        'delayed autofocus yields to external focus after $framesBeforeFocus frames with selection=$selected',
        (tester) async {
          final text = List.generate(
            160,
            (i) => 'Paragraph $i has target text.',
          ).join('\n\n');
          final target = text.indexOf('target', text.indexOf('Paragraph 145 '));
          final selection = selected
              ? TextSelection(baseOffset: target, extentOffset: target + 6)
              : TextSelection.collapsed(offset: target);
          final controller = IanvsMarkdownController(text: text)
            ..selection = selection;
          final externalFocus = FocusNode();
          final sourceFocus = FocusNode();
          final externalText = TextEditingController();
          addTearDown(controller.dispose);
          addTearDown(externalFocus.dispose);
          addTearDown(sourceFocus.dispose);
          addTearDown(externalText.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 500,
                  height: 360,
                  child: Column(
                    children: [
                      TextField(
                        focusNode: externalFocus,
                        controller: externalText,
                      ),
                      Expanded(
                        child: IanvsMarkdownLiveEditor(
                          controller: controller,
                          focusNode: sourceFocus,
                          autofocus: true,
                          showToolbar: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          for (var frame = 0; frame < framesBeforeFocus; frame += 1) {
            await tester.pump();
          }
          externalFocus.requestFocus();
          await tester.pumpAndSettle();
          expect(externalFocus.hasFocus, isTrue);
          expect(sourceFocus.hasFocus, isFalse);
          expect(tester.testTextInput.hasAnyClients, isTrue);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'Outside',
              selection: TextSelection.collapsed(offset: 7),
            ),
          );
          await tester.pumpAndSettle();
          expect(externalText.text, 'Outside');
          expect(controller.text, text);
          expect(controller.selection, selection);
          expect(controller.isDirty, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('default offset zero autofocus still types in the first block', (
    tester,
  ) async {
    const text = 'First.\n\nSecond.';
    final controller = IanvsMarkdownController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    await _replaceFocusedSelection(tester, 'X');
    expect(controller.text, 'X$text');
  });

  testWidgets(
    'hidden YAML selection autofocus redirects input to visible body',
    (tester) async {
      const text = '---\ntitle: Hidden\n---\n\nBody paragraph.';
      final start = text.indexOf('Hidden');
      final controller = IanvsMarkdownController(text: text)
        ..selection = TextSelection(baseOffset: start, extentOffset: start + 6);
      addTearDown(controller.dispose);
      final history = controller.retainedHistoryEntries;
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();
      final bodyStart = text.indexOf('Body');
      expect(controller.selection, TextSelection.collapsed(offset: bodyStart));
      expect(controller.text, text);
      expect(controller.retainedHistoryEntries, history);
      expect(controller.isDirty, isFalse);
      await _replaceFocusedSelection(tester, 'X');
      expect(controller.text, text.replaceRange(bodyStart, bodyStart, 'X'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all-hidden YAML selection autofocus leaves no fake input focus',
    (tester) async {
      const text = '---\ntitle: Hidden\n---';
      final start = text.indexOf('Hidden');
      final selection = TextSelection(
        baseOffset: start,
        extentOffset: start + 6,
      );
      final controller = IanvsMarkdownController(text: text)
        ..selection = selection;
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      final history = controller.retainedHistoryEntries;
      await tester.pumpWidget(_host(controller, focus: focus));
      await tester.pumpAndSettle();
      expect(controller.selection, selection);
      expect(controller.text, text);
      expect(controller.retainedHistoryEntries, history);
      expect(controller.isDirty, isFalse);
      expect(_activeEditable, findsNothing);
      expect(focus.hasFocus, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('autofocus false leaves selection and inactive input untouched', (
    tester,
  ) async {
    const text = 'First.\n\nSecond.';
    final controller = IanvsMarkdownController(text: text)
      ..selection = const TextSelection.collapsed(offset: 10);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, autofocus: false));
    await tester.pumpAndSettle();
    expect(controller.selection, const TextSelection.collapsed(offset: 10));
    expect(_activeEditable, findsNothing);
    expect(tester.testTextInput.hasAnyClients, isFalse);
  });

  testWidgets(
    'controller swap before deferred autofocus does not activate stale text',
    (tester) async {
      const text = 'First.\n\nSecond.';
      final first = IanvsMarkdownController(text: text)
        ..selection = const TextSelection.collapsed(offset: 10);
      final second = IanvsMarkdownController(text: 'Different document.');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(_host(first));
      await tester.pumpWidget(_host(second, autofocus: false));
      await tester.pumpAndSettle();
      expect(first.text, text);
      expect(second.text, 'Different document.');
      expect(_activeEditable, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
