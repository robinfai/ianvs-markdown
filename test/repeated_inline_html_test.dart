import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  const cases = <({String tag, String? key, String attributes})>[
    (tag: 'kbd', key: 'kbd', attributes: ''),
    (tag: 'sup', key: 'sup', attributes: ''),
    (tag: 'sub', key: 'subscript', attributes: ''),
    (tag: 'strong', key: 'strong', attributes: ''),
    (tag: 'em', key: 'em', attributes: ''),
    (tag: 'u', key: null, attributes: ''),
    (tag: 's', key: 's', attributes: ''),
    (tag: 'small', key: 'small', attributes: ''),
    (tag: 'q', key: 'q', attributes: ''),
    (tag: 'abbr', key: 'abbr', attributes: ' title="Example"'),
    (tag: 'mark', key: 'mark', attributes: ''),
    (tag: 'span', key: 'span', attributes: ' style="color: red"'),
    (tag: 'code', key: 'code', attributes: ''),
  ];

  for (final entry in cases) {
    testWidgets('repeated ${entry.tag} elements stay usable in every mode', (
      tester,
    ) async {
      final element = '<${entry.tag}${entry.attributes}>Token</${entry.tag}>';
      final source = 'Before\n\nAlpha $element + $element omega.\n\nAfter';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              showToolbar: false,
              showOutlineInPreview: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectTwoTokens(tester);

      if (entry.key case final key?) {
        // Keep the diagnostic key available, scoped to each inline element.
        // Equal text must not be used as a supposedly unique occurrence key.
        final controls = find.byKey(ValueKey('ianvs-markdown-html-$key'));
        expect(controls, findsNWidgets(2));
        await tester.tap(controls.first);
        await tester.pumpAndSettle();
        await tester.tap(controls.last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('ianvs-markdown-active-block')),
          findsNothing,
        );
        _expectTwoTokens(tester);
      }

      controller.mode = IanvsMarkdownEditorMode.preview;
      await tester.pumpAndSettle();
      _expectTwoTokens(tester);

      controller.mode = IanvsMarkdownEditorMode.source;
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        source,
      );
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

void _expectTwoTokens(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.byType(ErrorWidget), findsNothing);
  final rendered = [
    ...tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? text.textSpan?.toPlainText() ?? ''),
    ...tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((text) => text.data ?? text.textSpan?.toPlainText() ?? ''),
  ].join('\n');
  expect(RegExp('Token').allMatches(rendered), hasLength(2));
}
