import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  testWidgets('external host renders, edits, saves and restores exact source', (
    tester,
  ) async {
    const source = '# 外部宿主\n\nHello **Markdown**.\n\n- [ ] Task';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLocalization(
            strings: const IanvsMarkdownStrings.english(
              overrides: {IanvsMarkdownMessage.save: 'Persist note'},
            ),
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              onSaveRequested: (value) => saved = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('外部宿主'), findsWidgets);
    await tester.tap(find.byTooltip('Source mode'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
    expect(field, findsOneWidget);
    await tester.enterText(field, '$source\n\nNew paragraph.');
    await tester.pump();
    await tester.tap(find.byTooltip('Persist note'));
    await tester.pump();
    expect(saved, '$source\n\nNew paragraph.');
    controller.undo();
    await tester.pump();
    expect(controller.text, source);
    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    expect(find.text('外部宿主'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
