import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Future<void> exerciseLiveBlockIdentity(
  WidgetTester tester,
  IanvsMarkdownController controller,
) async {
  final handle = tester.ensureSemantics();
  try {
    const source = '# Heading\n\nUntouched paragraph.\n\nLast paragraph.';
    controller.mode = IanvsMarkdownEditorMode.source;
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      source,
    );
    controller.clearHistory();
    controller.markSaved();
    controller.selection = const TextSelection.collapsed(offset: 2);
    controller.mode = IanvsMarkdownEditorMode.livePreview;
    await tester.pumpAndSettle();
    final untouched = find.byWidgetPredicate(
      (w) => w is IanvsMarkdown && w.data == 'Untouched paragraph.',
    );
    final old = tester.element(untouched);
    final semantics = tester.getSemantics(untouched).id;
    final field = tester.widget<EditableText>(
      find.byWidgetPredicate(
        (w) => w is EditableText && !w.readOnly && w.focusNode.hasFocus,
      ),
    );
    expect(tester.testTextInput.hasAnyClients, isTrue);
    final value = field.controller.value;
    tester.testTextInput.updateEditingValue(
      value.replaced(value.selection, 'a'),
    );
    await tester.pumpAndSettle();
    controller.commitHistoryGroup();
    expect(controller.text, source.replaceRange(2, 2, 'a'));
    expect(controller.isDirty, isTrue);
    expect(tester.element(untouched), same(old));
    expect(tester.getSemantics(untouched).id, semantics);
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(tester.element(untouched), same(old));
    expect(tester.getSemantics(untouched).id, semantics);
    expect(tester.takeException(), isNull);
  } finally {
    handle.dispose();
  }
}
