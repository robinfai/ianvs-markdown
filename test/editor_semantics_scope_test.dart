import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  testWidgets('editor keeps its text field semantics separate from its host', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    try {
      final source = '# 中文 👋\r\n${'**text**\n' * 4000}';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('Host status'),
                Expanded(
                  child: IanvsMarkdownLiveEditor(
                    controller: controller,
                    showToolbar: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.byType(IanvsMarkdownLiveEditor));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.scopesRoute, isFalse);
      final fields = <SemanticsNode>[];
      void collect(SemanticsNode current) {
        if (current.getSemanticsData().flagsCollection.isTextField) {
          fields.add(current);
        }
        current.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(node);
      expect(
        fields.where((field) => field.getSemanticsData().value == source),
        hasLength(1),
      );
      expect(data.label, isNot(contains('Host status')));
      expect(data.flagsCollection.isTextField, isFalse);
      for (final mode in [
        IanvsMarkdownEditorMode.source,
        IanvsMarkdownEditorMode.preview,
        IanvsMarkdownEditorMode.livePreview,
      ]) {
        controller.mode = mode;
        await tester.pumpAndSettle();
        final current = tester.getSemantics(
          find.byType(IanvsMarkdownLiveEditor),
        );
        expect(current.id, node.id);
        expect(controller.text, source);
        fields.clear();
        collect(current);
        if (mode != IanvsMarkdownEditorMode.preview) {
          expect(
            fields.where((field) => field.getSemanticsData().value == source),
            hasLength(1),
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
    } finally {
      semantics.dispose();
    }
  });
}
