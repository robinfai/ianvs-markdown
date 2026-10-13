import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

// Framework text-input protocol coverage; not evidence of a native IME session.
Future<void> exerciseInputFocus(
  WidgetTester tester,
  IanvsMarkdownController controller,
  Future<void> Function(IanvsMarkdownEditorMode) mode,
) async {
  await mode(IanvsMarkdownEditorMode.source);
  await tester.enterText(
    find.byKey(const ValueKey('ianvs-markdown-source-field')),
    'seed ',
  );
  await tester.pumpAndSettle();
  Future<void> input(
    String text, {
    TextRange composing = TextRange.empty,
  }) async {
    expect(
      tester.testTextInput.hasAnyClients,
      isTrue,
      reason: 'the active surface must own a text-input connection',
    );
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: composing,
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, text);
    expect(controller.value.composing, composing);
  }

  await input('seed ni', composing: const TextRange(start: 5, end: 7));
  await input('seed 你');
  await input('seed 你hao', composing: const TextRange(start: 6, end: 9));
  await input('seed 你'); // IME cancels the uncommitted candidate.
  controller.commitHistoryGroup();
  await mode(IanvsMarkdownEditorMode.preview);
  expect(tester.testTextInput.hasAnyClients, isFalse);
  await mode(IanvsMarkdownEditorMode.source);
  // No tap/showKeyboard: switching the focused surface must reconnect input.
  await input('seed 你好');
  await mode(IanvsMarkdownEditorMode.preview);
  await mode(IanvsMarkdownEditorMode.livePreview);
  controller.commitHistoryGroup();
  await input('seed 你好ma', composing: const TextRange(start: 7, end: 9));
  await input('seed 你好');
  await input('seed 你好嘛');
  controller.commitHistoryGroup();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
  expect(controller.text, 'seed 你好');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
  expect(controller.text, 'seed 你好嘛');
  expect(tester.takeException(), isNull);
}
