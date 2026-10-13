import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  testWidgets('explicit commands respect controller ownership and disposal', (
    tester,
  ) async {
    final first = IanvsMarkdownController(text: 'first');
    final second = IanvsMarkdownController(text: 'second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget page(IanvsMarkdownController controller) => MaterialApp(
      home: Scaffold(body: IanvsMarkdownEditor(controller: controller)),
    );
    await tester.pumpWidget(page(first));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      'changed',
    );
    first.commitHistoryGroup();
    expect(
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.undo,
        controller: second,
      ),
      isFalse,
    );
    expect(first.text, 'changed');
    expect(
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.undo,
        controller: first,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(first.text, 'first');
    await tester.pumpWidget(page(second));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      'next',
    );
    second.commitHistoryGroup();
    expect(
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.undo,
        controller: first,
      ),
      isFalse,
    );
    expect(second.text, 'next');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(IanvsMarkdownShortcuts.invoke(IanvsMarkdownCommand.undo), isFalse);
  });

  testWidgets('explicit invocation delegates unrelated input to its host', (
    tester,
  ) async {
    final input = TextEditingController(text: 'outside');
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: input)),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(IanvsMarkdownShortcuts.invoke(IanvsMarkdownCommand.cut), isFalse);
    expect(input.text, 'outside');
  });
}
