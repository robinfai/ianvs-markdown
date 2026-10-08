import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Future<void> requestSave(WidgetTester tester, {required bool toolbar}) async {
  if (toolbar) {
    await tester.tap(find.byTooltip('保存'));
  } else {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  }
  await tester.pump();
}

Widget editorHost(
  IanvsMarkdownController controller,
  IanvsMarkdownSaveCallback save,
) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: IanvsMarkdownLiveEditor(
      controller: controller,
      autofocus: true,
      onSaveRequested: save,
    ),
  ),
);

void main() {
  test('late save acknowledgment is harmless after controller disposal', () {
    final controller = IanvsMarkdownController(text: 'initial');
    controller.text = 'persisted';
    final captured = controller.text;
    controller.dispose();
    expect(() => controller.markSaved(savedText: captured), returnsNormally);
  });

  for (final toolbar in [true, false]) {
    final path = toolbar ? 'toolbar' : 'keyboard';
    testWidgets(
      '$path save preserves edits made while persistence is pending',
      (tester) async {
        final controller = IanvsMarkdownController(
          text: '# Initial',
          mode: IanvsMarkdownEditorMode.source,
        );
        addTearDown(controller.dispose);
        controller.text = '# Captured';
        final gate = Completer<void>();
        String? persisted;
        await tester.pumpWidget(
          editorHost(controller, (source) {
            persisted = source;
            return gate.future;
          }),
        );
        await tester.pumpAndSettle();
        await requestSave(tester, toolbar: toolbar);
        expect(persisted, '# Captured');
        controller.text = '# Newer edit';
        gate.complete();
        await tester.pump();
        expect(controller.isDirty, isTrue);
        expect(controller.text, '# Newer edit');
        controller.undo();
        await tester.pump();
        expect(controller.text, '# Captured');
        expect(controller.isDirty, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$path save may complete after the document has been closed', (
      tester,
    ) async {
      final controller = IanvsMarkdownController(
        text: '# Initial',
        mode: IanvsMarkdownEditorMode.source,
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) controller.dispose();
      });
      controller.text = '# Persisted';
      final gate = Completer<void>();
      await tester.pumpWidget(editorHost(controller, (_) => gate.future));
      await tester.pumpAndSettle();
      await requestSave(tester, toolbar: toolbar);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      disposed = true;
      gate.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
