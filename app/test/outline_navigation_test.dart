import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/models/document_session.dart';
import 'package:linefold/src/widgets/floating_outline.dart';

void main() {
  testWidgets('desktop outline crosses a very tall code block in Live', (
    tester,
  ) async {
    final code = List.generate(
      1000,
      (index) => 'print("line $index");',
    ).join('\n');
    final tail = List.generate(
      90,
      (index) => 'Tail paragraph $index.',
    ).join('\n\n');
    final source = '# Start\n\n```dart\n$code\n```\n\n## Destination\n\n$tail';
    final offset = source.indexOf('## Destination');
    final document = DocumentSession(
      id: 'tall-code-outline',
      name: 'tall.md',
      text: source,
    );
    addTearDown(document.dispose);
    await _pumpOutline(tester, document);
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingOutline),
        matching: find.text('Destination'),
      ),
    );
    await tester.pumpAndSettle();
    _expectTargetVisible(
      tester,
      IanvsMarkdownEditorMode.livePreview,
      offset,
      'Destination',
    );
    expect(document.controller.text, source);
    expect(document.controller.isDirty, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final mode in IanvsMarkdownEditorMode.values) {
    testWidgets('desktop outline reveals the right heading in ${mode.name}', (
      tester,
    ) async {
      final middle = List.generate(
        150,
        (index) => 'Paragraph $index. A short line before the destination.',
      ).join('\n\n');
      final tail = List.generate(
        20,
        (index) => 'Long tail $index ${'x' * 400}',
      ).join('\n\n');
      final source =
          '''
---
title: Outline audit
---
# Repeated heading

$middle

Repeated heading
===============

Destination text.

$tail
''';
      final offset = source.indexOf('Repeated heading\n===');
      final document = DocumentSession(
        id: 'outline-audit',
        name: 'outline.md',
        text: source,
        mode: mode,
      );
      addTearDown(document.dispose);
      await _pumpOutline(tester, document);

      Future<void> clickTarget() async {
        await tester.tap(
          find
              .descendant(
                of: find.byType(FloatingOutline),
                matching: find.text('Repeated heading'),
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(document.controller.mode, mode);
        expect(document.controller.selection.extentOffset, offset);
        expect(document.controller.text, source);
        expect(document.controller.isDirty, isFalse);
        expect(document.controller.canUndo, isFalse);
        _expectTargetVisible(tester, mode, offset, 'Repeated heading');
      }

      await clickTarget();
      document.scrollController.jumpTo(0);
      await tester.pumpAndSettle();
      // Clicking the same selected heading after scrolling must navigate again.
      await clickTarget();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in [
    IanvsMarkdownEditorMode.livePreview,
    IanvsMarkdownEditorMode.preview,
  ]) {
    testWidgets('desktop outline expands folded ancestors in ${mode.name}', (
      tester,
    ) async {
      const source = '''
# Parent

Parent body.

## Child

Child body.

### Target

Target body.

# Outside

Outside body.
''';
      final document = DocumentSession(
        id: 'folded-outline',
        name: 'folded.md',
        text: source,
        mode: mode,
      );
      addTearDown(document.dispose);
      await _pumpOutline(tester, document, folding: true);
      final sections = IanvsMarkdownHeadingFoldModel.parse(source).sections;
      final prefix = mode == IanvsMarkdownEditorMode.livePreview
          ? 'ianvs-markdown-live-heading-fold'
          : 'ianvs-markdown-heading-fold';
      await tester.tap(find.byKey(ValueKey('$prefix-${sections[1].identity}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('$prefix-${sections[0].identity}')));
      await tester.pumpAndSettle();
      expect(find.text('Target body.'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(FloatingOutline),
          matching: find.text('Target'),
        ),
      );
      await tester.pumpAndSettle();
      expect(document.controller.mode, mode);
      expect(document.controller.text, source);
      expect(document.controller.isDirty, isFalse);
      expect(find.text('Target body.'), findsOneWidget);
      _expectTargetVisible(
        tester,
        mode,
        source.indexOf('### Target'),
        'Target',
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpOutline(
  WidgetTester tester,
  DocumentSession document, {
  bool folding = false,
}) async {
  tester.view.physicalSize = const Size(1080, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: desktopTheme(Brightness.light),
      home: Scaffold(
        body: Row(
          children: [
            Expanded(
              child: IanvsMarkdownLiveEditor(
                controller: document.controller,
                scrollController: document.scrollController,
                showToolbar: false,
                showOutlineInPreview: false,
                showFrontMatter: false,
                enableHeadingFolding: folding,
                contentMaxWidth: 720,
                padding: const EdgeInsets.fromLTRB(48, 32, 48, 56),
              ),
            ),
            FloatingOutline(document: document),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectTargetVisible(
  WidgetTester tester,
  IanvsMarkdownEditorMode mode,
  int offset,
  String text,
) {
  final viewport = tester.getRect(find.byType(IanvsMarkdownLiveEditor));
  final Rect target;
  switch (mode) {
    case IanvsMarkdownEditorMode.livePreview:
      final heading = find.byKey(
        ValueKey('ianvs-markdown-block-$offset-heading'),
      );
      expect(heading, findsOneWidget);
      target = tester.getRect(heading);
    case IanvsMarkdownEditorMode.source:
      final editable = tester
          .state<EditableTextState>(
            find.descendant(
              of: find.byType(IanvsMarkdownEditor),
              matching: find.byType(EditableText),
            ),
          )
          .renderEditable;
      final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
      target = editable.localToGlobal(caret.topLeft) & caret.size;
    case IanvsMarkdownEditorMode.preview:
      final heading = find
          .descendant(
            of: find.byType(IanvsMarkdownView),
            matching: find.text(text),
          )
          .last;
      expect(heading, findsOneWidget);
      target = tester.getRect(heading);
  }
  expect(target.top, greaterThanOrEqualTo(viewport.top));
  expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
}
