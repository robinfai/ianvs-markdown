import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  for (final mode in [
    IanvsMarkdownEditorMode.livePreview,
    IanvsMarkdownEditorMode.preview,
  ]) {
    for (final fold in [false, true]) {
      testWidgets('$mode heading text aligns with body with folding=$fold', (
        tester,
      ) async {
        final controller = IanvsMarkdownController(
          text: '# Heading\n\nParagraph\n\n## Subheading\n\nAnother paragraph',
          mode: mode,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IanvsMarkdownLiveEditor(
                controller: controller,
                showToolbar: false,
                showNavigationPane: false,
                enableHeadingFolding: fold,
                padding: const EdgeInsets.all(40),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder headingText(String text, int level) =>
            mode == IanvsMarkdownEditorMode.preview
            ? find.descendant(
                of: find.byKey(ValueKey('ianvs-markdown-heading-rail-$level')),
                matching: find.text(text),
              )
            : find.text(text);
        final heading = tester.getTopLeft(headingText('Heading', 1)).dx;
        final body = tester
            .getTopLeft(find.text('Paragraph', findRichText: true))
            .dx;
        expect(heading, closeTo(body, .01));
        expect(
          tester.getTopLeft(headingText('Subheading', 2)).dx,
          closeTo(body, .01),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
