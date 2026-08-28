import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/code_surface.dart';
import 'package:ianvs_markdown/src/list_guide.dart';

void main() {
  Widget app(IanvsMarkdownController controller) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 720,
          child: IanvsMarkdownLiveEditor(controller: controller),
        ),
      ),
    );
  }

  RenderEditable editableWithin(WidgetTester tester, Finder finder) {
    final root = tester.renderObject(finder);
    RenderEditable? editable;
    void visit(RenderObject child) {
      if (editable != null) return;
      if (child is RenderEditable) {
        editable = child;
        return;
      }
      child.visitChildren(visit);
    }

    if (root is RenderEditable) {
      editable = root;
    } else {
      root.visitChildren(visit);
    }
    expect(editable, isNotNull);
    return editable!;
  }

  Finder selectableTextWithPlainText(String text) => find.byWidgetPredicate(
    (widget) =>
        widget is SelectableText &&
        (widget.data ?? widget.textSpan?.toPlainText()) == text,
  );

  Finder selectableTextContainingPlainText(String text) =>
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data ?? widget.textSpan?.toPlainText() ?? '').contains(
              text,
            ),
      );

  testWidgets('clicking a rendered block edits its exact source in place', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '# Title\n\nParagraph with **formatting**.\n\n## Tail',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.text('Title'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );

    await tester.tap(find.text('Title'));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    final field = find.descendant(of: active, matching: find.byType(TextField));
    final headingField = tester.widget<TextField>(field);
    expect(headingField.controller?.text, '# Title');
    expect(headingField.style?.fontSize, 26);
    expect(headingField.style?.fontFamily, isNull);
    expect(find.text('HEADING'), findsNothing);
    expect(find.text('Edit Markdown'), findsNothing);

    final activeContainer = tester.widget<Container>(active);
    expect(activeContainer.decoration, isNull);

    await tester.enterText(field, '# Edited title');
    await tester.pump();
    expect(
      controller.text,
      '# Edited title\n\nParagraph with **formatting**.\n\n## Tail',
    );

    await tester.tap(find.textContaining('Paragraph with'));
    await tester.pump();
    expect(find.text('Edited title'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: active, matching: find.byType(TextField)),
          )
          .controller
          ?.text,
      'Paragraph with **formatting**.',
    );
  });

  testWidgets('HTML comments and inline tags keep exact block boundaries', (
    tester,
  ) async {
    final commentController = IanvsMarkdownController(
      text: '<!--\nhidden\n-->\nAfter',
    );
    addTearDown(commentController.dispose);
    await tester.pumpWidget(app(commentController));
    await tester.pumpAndSettle();

    await tester.tap(find.text('After'));
    await tester.pumpAndSettle();
    var active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'After');
    expect(field.style?.fontFamily, isNull);

    final inlineController = IanvsMarkdownController(
      text: '<em>inline</em> continuation\nnext',
    );
    addTearDown(inlineController.dispose);
    await tester.pumpWidget(app(inlineController));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('continuation'));
    await tester.pumpAndSettle();
    active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '<em>inline</em> continuation\nnext');
    expect(field.style?.fontFamily, isNull);
  });

  testWidgets('rendered text click places the caret at its visual character', (
    tester,
  ) async {
    const source = 'Alpha bravo charlie';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final renderedRect = tester.getRect(find.text(source));
    final target = Offset(
      renderedRect.left + 55,
      renderedRect.top + renderedRect.height / 2,
    );
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, inInclusiveRange(3, 6));
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.selection, controller.selection);
    expect(field.controller?.text, source);
  });

  testWidgets('live ordinary links enter source without navigating', (
    tester,
  ) async {
    const source = 'Before [Label](https://example.com/path) after.';
    final controller = IanvsMarkdownController(text: source);
    String? openedHref;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              onTapLink: (text, href, title) => openedHref = href,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Label'));
    await tester.pumpAndSettle();
    expect(openedHref, isNull);
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    final spans = field.controller!
        .buildTextSpan(
          context: tester.element(
            find.descendant(of: active, matching: find.byType(TextField)),
          ),
          style: field.style,
          withComposing: false,
        )
        .children!
        .cast<TextSpan>();
    expect(
      spans.singleWhere((span) => span.text == '[').style?.fontSize,
      greaterThan(1),
    );
    expect(
      spans
          .singleWhere((span) => span.text == '](https://example.com/path)')
          .style
          ?.fontSize,
      greaterThan(1),
    );
    expect(controller.text, source);

    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Label'));
    await tester.pump();
    expect(openedHref, 'https://example.com/path');
  });

  testWidgets('live preview renders tag pills and reveals their exact source', (
    tester,
  ) async {
    const block = 'Before #中文/子项 and #one#two, then ：#after-colon.';
    const source = '$block\n\nTail.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ianvs-markdown-tag')), findsNWidgets(4));
    for (final tag in <String>['#中文/子项', '#one', '#two', '#after-colon']) {
      expect(find.text(tag), findsOneWidget);
    }

    await tester.tap(find.textContaining('Before'));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, block);
    expect(controller.text, source);
  });

  testWidgets('live preview hides surplus highlight runs until activation', (
    tester,
  ) async {
    const source = 'L====x===R';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-highlight')),
      findsOneWidget,
    );
    expect(find.textContaining('='), findsNothing);

    await tester.tap(find.text('x'));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(controller.text, source);
  });

  testWidgets(
    'live preview keeps a cross-paragraph attempted highlight literal',
    (tester) async {
      const source = 'L==before\n\nafter==R';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ianvs-markdown-highlight')),
        findsNothing,
      );
      expect(find.textContaining('L==before'), findsOneWidget);
      expect(find.textContaining('after==R'), findsOneWidget);
      expect(controller.text, source);

      await tester.tap(find.textContaining('L==before'));
      await tester.pumpAndSettle();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, 'L==before');
      final sourceLeaves = _textSpanLeaves(
        field.controller!.buildTextSpan(
          context: tester.element(
            find.descendant(of: active, matching: find.byType(TextField)),
          ),
          style: field.style,
          withComposing: false,
        ),
      );
      expect(
        sourceLeaves
            .where((leaf) => leaf.text?.contains('before') ?? false)
            .every(
              (leaf) => leaf.style?.backgroundColor != const Color(0x66ffd54f),
            ),
        isTrue,
      );
      expect(controller.text, source);

      await tester.tap(find.textContaining('after==R'));
      await tester.pumpAndSettle();

      final secondField = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(secondField.controller?.text, 'after==R');
      expect(controller.text, source);
    },
  );

  testWidgets('live Wiki links navigate through the host callback', (
    tester,
  ) async {
    const source = 'Before [[Target note|Wiki alias]] after.';
    final controller = IanvsMarkdownController(text: source);
    String? openedHref;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              onTapLink: (text, href, title) => openedHref = href,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wiki alias'));
    await tester.pump();

    expect(openedHref, 'Target note');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
    expect(controller.text, source);
  });

  testWidgets('live leading-pipe Wiki links keep the pipe as their target', (
    tester,
  ) async {
    const source = 'Before [[|Leading Pipe]] and [[]] after.';
    final controller = IanvsMarkdownController(text: source);
    String? openedText;
    String? openedHref;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              onTapLink: (text, href, title) {
                openedText = text;
                openedHref = href;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('|Leading Pipe'), findsOneWidget);
    expect(find.textContaining('[[]]'), findsOneWidget);
    await tester.tap(find.text('|Leading Pipe'));
    await tester.pump();

    expect(openedText, '|Leading Pipe');
    expect(openedHref, '|Leading Pipe');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
    expect(controller.text, source);
  });

  testWidgets('live preview resolves document-wide reference links', (
    tester,
  ) async {
    const source =
        'Full [Reference label][guide-ref] tail.\n\n'
        'Collapsed [Collapsed][] and [shortcut].\n\n'
        '[guide-ref]: docs/guide.md "Reference title"\n'
        '[Collapsed]: docs/collapsed.md\n'
        '[shortcut]: docs/shortcut.md';
    final controller = IanvsMarkdownController(text: source);
    String? openedHref;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              onTapLink: (text, href, title) => openedHref = href,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reference label'), findsOneWidget);
    expect(find.text('Collapsed'), findsOneWidget);
    expect(find.text('shortcut'), findsOneWidget);
    expect(find.textContaining('[guide-ref]:'), findsNothing);

    await tester.tap(find.text('Reference label'));
    await tester.pumpAndSettle();
    expect(openedHref, isNull);
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'Full [Reference label][guide-ref] tail.');
    expect(controller.text, source);

    TextSpan markerSpan() {
      final spans = field.controller!
          .buildTextSpan(
            context: tester.element(fieldFinder),
            style: field.style,
            withComposing: false,
          )
          .children!
          .cast<TextSpan>();
      return spans.firstWhere((span) => span.text == '[');
    }

    field.controller!.selection = TextSelection.collapsed(
      offset: field.controller!.text.length,
    );
    await tester.pump();
    expect(markerSpan().style?.fontSize, .01);
    field.controller!.selection = const TextSelection.collapsed(offset: 8);
    await tester.pump();
    expect(markerSpan().style?.fontSize, greaterThan(1));

    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reference label'));
    await tester.pump();
    expect(openedHref, 'docs/guide.md');
  });

  testWidgets('live preview keeps extra-whitespace reference labels literal', (
    tester,
  ) async {
    const source =
        'Literal [Whitespace   Ref][  Ref   A  ].\n\n'
        '[Ref A]: docs/ref.md';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-ordinary-link')),
      findsNothing,
    );
    expect(
      find.textContaining(
        '[Whitespace   Ref][  Ref   A  ]',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(controller.text, source);
  });

  testWidgets(
    'live preview projects odd link targets but activates exact source',
    (tester) async {
      const source = r'Odd [Odd](https://example.com/a\\\(b\)) tail.';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 720,
              child: IanvsMarkdownLiveEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip(r'https://example.com/a%5C(b)'), findsOneWidget);
      await tester.tap(find.text('Odd'));
      await tester.pumpAndSettle();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, source);
      expect(controller.text, source);
    },
  );

  testWidgets('live preview preserves exact angle www fallback source', (
    tester,
  ) async {
    const source = '<www.example.com> tail.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('<', findRichText: true), findsOneWidget);
    expect(find.text('www.example.com>'), findsOneWidget);
    expect(controller.text, source);

    await tester.tap(find.text('www.example.com>'));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(controller.text, source);
  });

  testWidgets('live preview autolinks keep rendered controls on normal click', (
    tester,
  ) async {
    const url = 'https://example.com/path?x=1#frag';
    const source =
        'Before\n\n'
        'Bare $url omega\n\n'
        'Angle <$url> omega\n\n'
        'After';
    final controller = IanvsMarkdownController(text: source);
    String? openedHref;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              onTapLink: (text, href, title) => openedHref = href,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final links = find.text(url);
    expect(links, findsNWidgets(2));
    expect(find.text('<$url>'), findsNothing);

    for (final link in <Finder>[links.first, links.last]) {
      for (var tapCount = 1; tapCount <= 3; tapCount += 1) {
        await tester.tap(link);
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byKey(const ValueKey('ianvs-markdown-active-block')),
          findsNothing,
          reason: 'tap $tapCount on ${link == links.first ? 'bare' : 'angle'}',
        );
        expect(openedHref, isNull);
      }
      await tester.pumpAndSettle();
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('ordinary active rail follows only the caret line', (
    tester,
  ) async {
    const source = 'first line\nsecond line';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text(source));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final rail = find.byKey(const ValueKey('ianvs-markdown-active-line-rail'));
    expect(rail, findsOneWidget);
    expect(
      tester.getSize(rail).height,
      lessThan(tester.getSize(active).height),
    );
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 1);
    await tester.pumpAndSettle();
    final firstTop = tester.getTopLeft(rail).dy;

    field.controller?.selection = const TextSelection.collapsed(
      offset: source.length,
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(rail).dy, greaterThan(firstTop));
    expect(controller.text, source);
  });

  testWidgets('direct double click selects a word across block activation', (
    tester,
  ) async {
    const source = 'Alpha beta gamma';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final renderedRect = tester.getRect(find.text(source));
    final target = Offset(
      renderedRect.left + 90,
      renderedRect.top + renderedRect.height / 2,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(controller.text), 'beta');
    expect(controller.text, source);
  });

  testWidgets('double click selects the complete inline source range', (
    tester,
  ) async {
    const source = 'Left **formattedword** right';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final renderedRect = tester.getRect(find.textContaining('Left'));
    final target = Offset(
      renderedRect.left + 85,
      renderedRect.top + renderedRect.height / 2,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(
      controller.selection.textInside(controller.text),
      '**formattedword**',
    );
    expect(controller.text, source);
  });

  testWidgets('inline code clicks preserve Obsidian source selections', (
    tester,
  ) async {
    const line = 'Alpha `bravo charlie` omega';
    const source = 'Before\n\n$line\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Finder paragraphFinder() => selectableTextWithPlainText(line);
    expect(paragraphFinder(), findsOneWidget);
    final paragraph = editableWithin(tester, paragraphFinder());
    final caret = paragraph.getLocalRectForCaret(
      const TextPosition(offset: 11),
    );
    final target = paragraph.localToGlobal(caret.center);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, 19);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'bravo');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), line);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('double click selects a complete triple emphasis run', (
    tester,
  ) async {
    const source = 'Left ***formattedword*** right';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final renderedRect = tester.getRect(find.textContaining('Left'));
    final target = Offset(
      renderedRect.left + 85,
      renderedRect.top + renderedRect.height / 2,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(
      controller.selection.textInside(controller.text),
      '***formattedword***',
    );
    expect(controller.text, source);
  });

  testWidgets('double click selects complete Obsidian highlight source', (
    tester,
  ) async {
    const source = 'Left ==highlightword== right';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final renderedRect = tester.getRect(find.textContaining('Left'));
    final target = Offset(
      renderedRect.left + 95,
      renderedRect.top + renderedRect.height / 2,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(
      controller.selection.textInside(controller.text),
      '==highlightword==',
    );
    expect(controller.text, source);
  });

  testWidgets('double click selects complete Obsidian strikethrough source', (
    tester,
  ) async {
    const source = 'Left ~~strikeword~~ right';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final renderedRect = tester.getRect(find.textContaining('Left'));
    final target = Offset(
      renderedRect.left + 90,
      renderedRect.top + renderedRect.height / 2,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(controller.text), '~~strikeword~~');
    expect(controller.text, source);
  });

  testWidgets('direct triple click selects the complete source line', (
    tester,
  ) async {
    const source =
        '## Long heading with enough words to wrap across visual lines lambda.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 720,
            child: IanvsMarkdownLiveEditor(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final renderedRect = tester.getRect(find.textContaining('Long heading'));
    final target = Offset(renderedRect.left + 85, renderedRect.top + 12);
    for (var tap = 0; tap < 3; tap += 1) {
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(controller.text), source);
    expect(controller.selection.start, 0);
    expect(controller.selection.end, source.length);
    expect(controller.text, source);
  });

  testWidgets('Backspace at a block start removes document separators', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Alpha\n\nBeta');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beta'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(controller.text, 'Alpha\nBeta');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'Alpha\nBeta');
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(controller.text, 'AlphaBeta');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(controller.text, 'Alpha\nBeta');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, 'Alpha\n\nBeta');
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
  });

  testWidgets('live list prefixes degrade one source character at a time', (
    tester,
  ) async {
    const cases =
        <
          ({
            String source,
            String label,
            int caret,
            String after,
            int afterCaret,
          })
        >[
          (
            source: '- root item',
            label: 'root item',
            caret: 2,
            after: '-root item',
            afterCaret: 1,
          ),
          (
            source: '- [ ] task item',
            label: 'task item',
            caret: 6,
            after: '- [ ]task item',
            afterCaret: 5,
          ),
          (
            source: '12. ordered item',
            label: 'ordered item',
            caret: 4,
            after: '12.ordered item',
            afterCaret: 3,
          ),
          (
            source: '  - nested item',
            label: 'nested item',
            caret: 4,
            after: '  -nested item',
            afterCaret: 3,
          ),
        ];

    for (final testCase in cases) {
      final controller = IanvsMarkdownController(text: testCase.source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text(testCase.label));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = TextSelection.collapsed(
        offset: testCase.caret,
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(controller.text, testCase.after);
      expect(
        controller.selection,
        TextSelection.collapsed(offset: testCase.afterCaret),
      );
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, testCase.after);
      expect(field.focusNode?.hasFocus, isTrue);

      if (testCase.source == '- root item') {
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        expect(controller.text, 'root item');
        expect(controller.selection, const TextSelection.collapsed(offset: 0));
      }
    }
  });

  testWidgets('Backspace before a nested list marker outdents one level', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '- parent\n  - nested item',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('nested item'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(controller.text, '- parent\n- nested item');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Delete at a block end removes document separators', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Alpha\n\nBeta');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = TextSelection.collapsed(
      offset: field.controller!.text.length,
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    expect(controller.text, 'Alpha\nBeta');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'Alpha\nBeta');
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    expect(controller.text, 'AlphaBeta');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    expect(field.focusNode?.hasFocus, isTrue);

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, 'Alpha\nBeta');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, 'Alpha\n\nBeta');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
  });

  testWidgets('vertical arrows traverse blank source lines between blocks', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'aa\n\nbbbbbb\n\ncc');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('aa'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(controller.text, 'aa\n\nbbbbbb\n\ncc');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'aa\n');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 3),
    );
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'bbbbbb');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 2),
    );
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'aa\n');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'aa');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 2),
    );
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('ArrowUp enters a leading blank line before the first block', (
    tester,
  ) async {
    const source = '\nAlpha';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('vertical arrows skip descendants of a collapsed heading', (
    tester,
  ) async {
    const source = '# Heading\nBody\n# Tail';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('折叠标题内容'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
    expect(find.text('Tail'), findsOneWidget);

    await tester.tap(find.text('Heading'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = TextSelection.collapsed(
      offset: field.controller!.text.length,
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(active, findsOneWidget);
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '# Tail');
    expect(field.focusNode?.hasFocus, isTrue);

    field.controller?.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '# Heading');
    expect(field.focusNode?.hasFocus, isTrue);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('ArrowDown stays at a collapsed heading at document end', (
    tester,
  ) async {
    const source = '# Heading\nBody';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('折叠标题内容'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);

    await tester.tap(find.text('Heading'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = TextSelection.collapsed(
      offset: field.controller!.text.length,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(active, findsOneWidget);
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '# Heading');
    expect(field.controller?.selection.extentOffset, '# Heading'.length);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('a folded heading gap skips hidden descendants', (tester) async {
    const source = '# Heading\n\nBody\n\n# Tail';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('折叠标题内容'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-gap-9')));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '# Heading\n');
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(active, findsOneWidget);
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '# Tail');
    expect(field.focusNode?.hasFocus, isTrue);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets(
    'shift right crosses a folded heading without selecting hidden source',
    (tester) async {
      const source = '# Heading\nBody one two\n# Tail';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('折叠标题内容'));
      await tester.pumpAndSettle();
      expect(find.text('Body one two'), findsNothing);

      await tester.tap(find.text('Heading'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = TextSelection.collapsed(
        offset: field.controller!.text.length,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, '# Tail');
      expect(
        field.controller?.selection,
        const TextSelection.collapsed(offset: 0),
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 23));
      expect(find.text('Body one two'), findsNothing);

      field.controller?.value = const TextEditingValue(
        text: 'X# Tail',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pumpAndSettle();

      expect(controller.text, '# Heading\nBody one two\nX# Tail');
    },
  );

  testWidgets(
    'folded shift selection copies visible text and replaces only its source',
    (tester) async {
      const source = '# Heading\nBody one two\n# Tail';
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copied =
                (methodCall.arguments as Map<Object?, Object?>)['text']
                    as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('折叠标题内容'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heading'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = TextSelection.collapsed(
        offset: field.controller!.text.length,
      );

      Future<void> shiftRight() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
      }

      await shiftRight();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(copied, '\n');

      await shiftRight();
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(
        field.controller?.selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
      expect(
        controller.selection,
        const TextSelection(baseOffset: 23, extentOffset: 24),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(copied, '\n#');

      field.controller?.value = const TextEditingValue(
        text: 'X Tail',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pumpAndSettle();

      expect(controller.text, '# Heading\nBody one two\nX Tail');
    },
  );

  testWidgets(
    'reverse folded shift selection preserves its virtual first step',
    (tester) async {
      const source = '# Heading\nBody one two\n# Tail';
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copied =
                (methodCall.arguments as Map<Object?, Object?>)['text']
                    as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('折叠标题内容'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tail'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 0);

      Future<void> shiftLeft() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
      }

      await shiftLeft();
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, '# Tail');
      expect(
        field.controller?.selection,
        const TextSelection.collapsed(offset: 0),
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 23));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(copied, '\n');

      await shiftLeft();
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, '# Heading\nBody one two\n');
      expect(
        controller.selection,
        const TextSelection(
          baseOffset: 23,
          extentOffset: 9,
          isDirectional: true,
        ),
      );
      expect(
        controller.selection.textInside(controller.text),
        '\nBody one two\n',
      );

      field.controller?.value = const TextEditingValue(
        text: '# HeadingX',
        selection: TextSelection.collapsed(offset: 10),
      );
      await tester.pumpAndSettle();

      expect(controller.text, '# HeadingX# Tail');
    },
  );

  testWidgets(
    'forward Shift Option skips folded source and selects visible punctuation',
    (tester) async {
      const source = '# Heading\nBody one two\n# Tail';
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copied =
                (methodCall.arguments as Map<Object?, Object?>)['text']
                    as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('折叠标题内容'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heading'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = TextSelection.collapsed(
        offset: field.controller!.text.length,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, '# Tail');
      expect(
        field.controller?.selection,
        const TextSelection(
          baseOffset: 0,
          extentOffset: 1,
          isDirectional: true,
        ),
      );
      expect(
        controller.selection,
        const TextSelection(
          baseOffset: 23,
          extentOffset: 24,
          isDirectional: true,
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(copied, '\n#');

      field.controller?.value = const TextEditingValue(
        text: 'X Tail',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pumpAndSettle();
      expect(controller.text, '# Heading\nBody one two\nX Tail');
    },
  );

  testWidgets(
    'Shift Left first shrinks native selection after a folded bridge',
    (tester) async {
      const source = '# Heading\nBody one two\n# Tail';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('折叠标题内容'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heading'));
      await tester.pump();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      var field = tester.widget<TextField>(fieldFinder);
      field.controller?.selection = TextSelection.collapsed(
        offset: field.controller!.text.length,
      );

      Future<void> shift(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
      }

      await shift(LogicalKeyboardKey.arrowRight);
      await shift(LogicalKeyboardKey.arrowRight);
      await shift(LogicalKeyboardKey.arrowLeft);

      field = tester.widget<TextField>(fieldFinder);
      expect(field.controller?.text, '# Tail');
      expect(
        field.controller?.selection,
        const TextSelection.collapsed(offset: 0),
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 23));
      expect(field.focusNode?.hasFocus, isTrue);
    },
  );

  testWidgets('reverse Shift Option selects the folded source range', (
    tester,
  ) async {
    const source = '# Heading\nBody one two\n# Tail';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('折叠标题内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tail'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '# Heading\nBody one two\n');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 23, extentOffset: 9, isDirectional: true),
    );
    expect(
      controller.selection.textInside(controller.text),
      '\nBody one two\n',
    );

    field.controller?.value = const TextEditingValue(
      text: '# HeadingX',
      selection: TextSelection.collapsed(offset: 10),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '# HeadingX# Tail');
  });

  testWidgets(
    'shift vertical arrows select across blocks at the visual column',
    (tester) async {
      const source = 'abc\n\n123456\n\nxy';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      Future<void> shiftArrow(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('abc'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      var field = tester.widget<TextField>(fieldFinder);
      field.controller?.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      await shiftArrow(LogicalKeyboardKey.arrowDown);

      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
      expect(controller.selection.baseOffset, 3);
      expect(controller.selection.extentOffset, 4);
      expect(controller.selection.textInside(controller.text), '\n');
      field = tester.widget<TextField>(fieldFinder);
      expect(field.controller?.text, 'abc\n');

      await shiftArrow(LogicalKeyboardKey.arrowDown);

      expect(controller.selection.baseOffset, 3);
      expect(controller.selection.extentOffset, 8);
      expect(controller.selection.textInside(controller.text), '\n\n123');
      field = tester.widget<TextField>(fieldFinder);
      expect(field.controller?.text, 'abc\n\n123456');

      await shiftArrow(LogicalKeyboardKey.arrowDown);

      expect(controller.selection.baseOffset, 3);
      expect(controller.selection.extentOffset, 12);
      expect(controller.selection.textInside(controller.text), '\n\n123456\n');

      await shiftArrow(LogicalKeyboardKey.arrowDown);

      expect(controller.selection.baseOffset, 3);
      expect(controller.selection.extentOffset, 15);
      expect(
        controller.selection.textInside(controller.text),
        '\n\n123456\n\nxy',
      );

      await shiftArrow(LogicalKeyboardKey.arrowUp);

      expect(controller.selection.baseOffset, 3);
      expect(controller.selection.extentOffset, 12);
      expect(controller.selection.textInside(controller.text), '\n\n123456\n');

      field = tester.widget<TextField>(fieldFinder);
      field.controller?.value = const TextEditingValue(
        text: 'abcZ',
        selection: TextSelection.collapsed(offset: 4),
      );
      await tester.pumpAndSettle();

      expect(controller.text, 'abcZ\nxy');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
      expect(controller.isDirty, isTrue);

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, source);
      expect(field.focusNode?.hasFocus, isTrue);
    },
  );

  testWidgets('reverse shift vertical selection stays directional', (
    tester,
  ) async {
    const source = 'abc\n\n123456\n\nxy';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Future<void> shiftArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('123456'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();

    await shiftArrow(LogicalKeyboardKey.arrowUp);

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection.baseOffset, 11);
    expect(controller.selection.extentOffset, 4);
    expect(controller.selection.isDirectional, isTrue);
    expect(controller.selection.textInside(controller.text), '\n123456');
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'abc\n\n123456');

    await shiftArrow(LogicalKeyboardKey.arrowUp);

    expect(controller.selection.baseOffset, 11);
    expect(controller.selection.extentOffset, 3);
    expect(controller.selection.textInside(controller.text), '\n\n123456');

    await shiftArrow(LogicalKeyboardKey.arrowDown);

    expect(controller.selection.baseOffset, 11);
    expect(controller.selection.extentOffset, 4);
    expect(controller.selection.textInside(controller.text), '\n123456');
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('shift vertical selection stays inside wrapped visual lines', (
    tester,
  ) async {
    const first = 'alpha beta gamma delta epsilon zeta eta theta';
    final controller = IanvsMarkdownController(text: '$first\n\nnext');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 400,
            child: IanvsMarkdownLiveEditor(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(first));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(controller.text, '$first\n\nnext');
    expect(controller.isDirty, isFalse);
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, greaterThan(0));
    expect(controller.selection.extentOffset, lessThan(first.length));
    expect(field.controller?.text, first);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Command+A selects the entire Markdown document', (tester) async {
    const source = 'aa\n\nbbbbbb\n\ncc';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('bbbbbb'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, source.length);
    expect(controller.selection.textInside(controller.text), source);
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, source);
    expect(field.focusNode?.hasFocus, isTrue);

    field.controller?.value = const TextEditingValue(
      text: 'Z',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'Z');

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
  });

  testWidgets('Command+A keeps leading blank lines in the active selection', (
    tester,
  ) async {
    const source = '\nAlpha\n\nBeta';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, source.length);
    expect(controller.selection.isDirectional, isTrue);
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(field.focusNode?.hasFocus, isTrue);

    field.controller?.value = const TextEditingValue(
      text: 'Z',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'Z');

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
  });

  testWidgets(
    'mouse drag selects forward and backward across Markdown blocks',
    (tester) async {
      const source =
          'Alpha opening words\n\n'
          'Bravo middle words\n\n'
          'Charlie closing words';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final alpha = find.text('Alpha opening words');
      final charlie = find.text('Charlie closing words');
      final alphaRect = tester.getRect(alpha);
      final charlieRect = tester.getRect(charlie);
      final alphaPoint = Offset(
        alphaRect.left + alphaRect.width * .35,
        alphaRect.center.dy,
      );
      final charliePoint = Offset(
        charlieRect.left + charlieRect.width * .7,
        charlieRect.center.dy,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.down(alphaPoint);
      await mouse.moveTo(charliePoint);
      await tester.pumpAndSettle();
      await mouse.up();
      await tester.pumpAndSettle();

      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
      expect(
        controller.selection.baseOffset,
        lessThan(controller.selection.extentOffset),
      );
      expect(
        controller.selection.textInside(source),
        contains('\n\nBravo middle words\n\n'),
      );
      var active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, source);
      expect(field.focusNode?.hasFocus, isTrue);

      final selectionEditable = editableWithin(tester, active);
      final bravoCaret = selectionEditable.getLocalRectForCaret(
        TextPosition(offset: source.indexOf('Bravo') + 3),
      );
      await mouse.down(selectionEditable.localToGlobal(bravoCaret.center));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(controller.selection.isCollapsed, isTrue);

      await mouse.down(charliePoint);
      await mouse.moveTo(alphaPoint);
      await tester.pumpAndSettle();
      await mouse.up();
      await tester.pumpAndSettle();

      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
      expect(
        controller.selection.baseOffset,
        greaterThan(controller.selection.extentOffset),
      );
      expect(controller.selection.isDirectional, isTrue);
      expect(
        controller.selection.textInside(source),
        contains('\n\nBravo middle words\n\n'),
      );
      active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, source);
      expect(field.focusNode?.hasFocus, isTrue);

      final replacementStart = controller.selection.start;
      final replacementEnd = controller.selection.end;
      final replaced = source.replaceRange(
        replacementStart,
        replacementEnd,
        'Z',
      );
      field.controller?.value = TextEditingValue(
        text: replaced,
        selection: TextSelection.collapsed(offset: replacementStart + 1),
      );
      await tester.pumpAndSettle();
      expect(controller.text, replaced);
      expect(
        controller.selection,
        TextSelection.collapsed(offset: replacementStart + 1),
      );

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, source);
    },
  );

  testWidgets('mouse cross-block selection retains exact Markdown source', (
    tester,
  ) async {
    const source =
        'Alpha opening words\n\n'
        '- Bravo list item\n\n'
        '> Quoted middle words\n\n'
        '```js\n'
        'const value = 1;\n'
        '```\n\n'
        'Charlie closing words';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final alphaRect = tester.getRect(find.text('Alpha opening words'));
    final charlieRect = tester.getRect(find.text('Charlie closing words'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.down(
      Offset(alphaRect.left + alphaRect.width * .4, alphaRect.center.dy),
    );
    await mouse.moveTo(
      Offset(charlieRect.left + charlieRect.width * .6, charlieRect.center.dy),
    );
    await tester.pumpAndSettle();
    await mouse.up();
    await tester.pumpAndSettle();

    final selectedSource = controller.selection.textInside(source);
    expect(selectedSource, contains('- Bravo list item'));
    expect(selectedSource, contains('> Quoted middle words'));
    expect(selectedSource, contains('```js\nconst value = 1;\n```'));
    expect(controller.isDirty, isFalse);
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
  });

  testWidgets('Command vertical arrows move to document boundaries', (
    tester,
  ) async {
    const source = 'aa\n\nbbbbbb\n\ncc';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Future<void> commandArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('bbbbbb'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 3);

    await commandArrow(LogicalKeyboardKey.arrowUp);

    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'aa');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 0),
    );

    await commandArrow(LogicalKeyboardKey.arrowDown);

    expect(
      controller.selection,
      const TextSelection.collapsed(offset: source.length),
    );
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'cc');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 2),
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Shift Command vertical arrows select to document boundaries', (
    tester,
  ) async {
    const source = 'aa\n\nbbbbbb\n\ncc';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Future<void> shiftCommandArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('bbbbbb'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 3);

    await shiftCommandArrow(LogicalKeyboardKey.arrowUp);

    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 0);
    expect(controller.selection.isDirectional, isTrue);
    expect(controller.selection.textInside(controller.text), 'aa\n\nbbb');
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'aa\n\nbbbbbb');

    field.controller?.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    expect(controller.selection, const TextSelection.collapsed(offset: 7));

    await shiftCommandArrow(LogicalKeyboardKey.arrowDown);

    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, source.length);
    expect(controller.selection.isDirectional, isTrue);
    expect(controller.selection.textInside(controller.text), 'bbb\n\ncc');
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'bbbbbb\n\ncc');
    expect(field.controller?.selection.baseOffset, 3);
    expect(field.controller?.selection.extentOffset, 10);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Command horizontal arrows move to source line boundaries', (
    tester,
  ) async {
    const source = 'abc def\nghij klm';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Future<void> commandArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.textContaining('abc def'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 10);

    await commandArrow(LogicalKeyboardKey.arrowLeft);
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 8),
    );

    // A repeated shortcut at the same boundary must stay in this block rather
    // than leaking to the document-level EditableText action.
    await commandArrow(LogicalKeyboardKey.arrowLeft);
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
    expect(field.controller?.text, source);

    await commandArrow(LogicalKeyboardKey.arrowRight);
    expect(controller.selection, const TextSelection.collapsed(offset: 16));
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 16),
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Shift Command horizontal arrows preserve the line anchor', (
    tester,
  ) async {
    const source = 'abc def\nghij klm';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Future<void> shiftCommandArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.textContaining('abc def'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 10);

    await shiftCommandArrow(LogicalKeyboardKey.arrowLeft);
    expect(controller.selection.baseOffset, 10);
    expect(controller.selection.extentOffset, 8);
    expect(controller.selection.isDirectional, isTrue);
    expect(controller.selection.textInside(source), 'gh');

    await shiftCommandArrow(LogicalKeyboardKey.arrowRight);
    expect(controller.selection.baseOffset, 10);
    expect(controller.selection.extentOffset, 16);
    expect(controller.selection.isDirectional, isTrue);
    expect(controller.selection.textInside(source), 'ij klm');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Command Left enters hidden list prefixes in two stages', (
    tester,
  ) async {
    const cases =
        <({String source, String label, int visibleStart, bool task})>[
          (
            source: '- alpha beta',
            label: 'alpha beta',
            visibleStart: 2,
            task: false,
          ),
          (
            source: '- [ ] task item',
            label: 'task item',
            visibleStart: 6,
            task: true,
          ),
          (
            source: '12. ordered item',
            label: 'ordered item',
            visibleStart: 4,
            task: false,
          ),
          (
            source: '  - nested item',
            label: 'nested item',
            visibleStart: 4,
            task: false,
          ),
        ];

    Future<void> commandLeft() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    for (final testCase in cases) {
      final controller = IanvsMarkdownController(text: testCase.source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text(testCase.label));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = TextSelection.collapsed(
        offset: testCase.source.length,
      );
      await tester.pump();

      await commandLeft();
      expect(
        controller.selection,
        TextSelection.collapsed(offset: testCase.visibleStart),
      );
      if (testCase.task) {
        expect(
          find.descendant(
            of: active,
            matching: find.byType(IanvsMarkdownTaskCheckbox),
          ),
          findsOneWidget,
        );
      } else {
        expect(
          find.byKey(const ValueKey('ianvs-markdown-active-list-marker')),
          findsOneWidget,
        );
      }

      await commandLeft();
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-list-marker')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: active,
          matching: find.byType(IanvsMarkdownTaskCheckbox),
        ),
        findsNothing,
      );
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, testCase.source);
      expect(field.focusNode?.hasFocus, isTrue);
      expect(controller.isDirty, isFalse);
    }
  });

  testWidgets('Shift Command Left selects visible list content first', (
    tester,
  ) async {
    const source = '- alpha beta';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('alpha beta'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(
      offset: source.length,
    );
    await tester.pump();

    Future<void> shiftCommandLeft() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    await shiftCommandLeft();
    expect(controller.selection.baseOffset, source.length);
    expect(controller.selection.extentOffset, 2);
    expect(controller.selection.textInside(source), 'alpha beta');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-list-marker')),
      findsOneWidget,
    );

    await shiftCommandLeft();
    expect(controller.selection.baseOffset, source.length);
    expect(controller.selection.extentOffset, 0);
    expect(controller.selection.textInside(source), source);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-list-marker')),
      findsNothing,
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('macOS Control+A and E navigate physical lines in live mode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const source = 'alpha beta\nsecond line';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('alpha beta'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );

      Future<void> controlBoundary(
        LogicalKeyboardKey key, {
        bool shift = false,
      }) async {
        if (shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        if (shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pumpAndSettle();
      }

      field.controller?.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      await controlBoundary(LogicalKeyboardKey.keyA);
      expect(controller.selection, const TextSelection.collapsed(offset: 0));

      field.controller?.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      await controlBoundary(LogicalKeyboardKey.keyE);
      expect(controller.selection, const TextSelection.collapsed(offset: 10));

      field.controller?.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      await controlBoundary(LogicalKeyboardKey.keyA, shift: true);
      expect(controller.selection.baseOffset, 5);
      expect(controller.selection.extentOffset, 0);
      expect(controller.selection.textInside(source), 'alpha');

      field.controller?.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      await controlBoundary(LogicalKeyboardKey.keyE, shift: true);
      expect(controller.selection.baseOffset, 5);
      expect(controller.selection.extentOffset, 10);
      expect(controller.selection.textInside(source), ' beta');
      expect(controller.mode, IanvsMarkdownEditorMode.livePreview);
      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'macOS Control+K deletes through physical line ends in live mode',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const source = 'alpha beta\ngamma delta';
        final controller = IanvsMarkdownController(text: source);
        addTearDown(controller.dispose);
        await tester.pumpWidget(app(controller));
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('alpha beta'));
        await tester.pump();
        final active = find.byKey(
          const ValueKey('ianvs-markdown-active-block'),
        );
        final field = tester.widget<TextField>(
          find.descendant(of: active, matching: find.byType(TextField)),
        );
        field.controller?.selection = const TextSelection.collapsed(offset: 5);
        await tester.pump();

        Future<void> controlK() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
        }

        await controlK();
        expect(controller.text, 'alpha\ngamma delta');
        expect(controller.selection, const TextSelection.collapsed(offset: 5));

        await controlK();
        expect(controller.text, 'alphagamma delta');
        expect(controller.selection, const TextSelection.collapsed(offset: 5));

        controller.undo();
        await tester.pumpAndSettle();
        expect(controller.text, 'alpha\ngamma delta');
        controller.undo();
        await tester.pumpAndSettle();
        expect(controller.text, source);
        expect(field.focusNode?.hasFocus, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('macOS Control+K can delete a live block boundary newline', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'alpha\n\nlast');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, 'alpha\nlast');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+K deletes only a live selection', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'alpha beta\nsecond');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('alpha beta'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, ' beta\nsecond');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+K keeps native line deletion in source mode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(
        text: 'alpha beta\ngamma',
        mode: IanvsMarkdownEditorMode.source,
      )..selection = const TextSelection.collapsed(offset: 5);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );
      controller.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      Future<void> controlK() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await controlK();
      expect(controller.text, 'alpha\ngamma');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));

      await controlK();
      expect(controller.text, 'alphagamma');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+H deletes one grapheme in live mode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'A😀B');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A😀B'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, 'AB');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+H deletes a live block boundary newline', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'alpha\n\nlast');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('last'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, 'alpha\nlast');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+H deletes only a live selection', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'alpha beta\nsecond');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('alpha beta'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, ' beta\nsecond');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+H keeps grapheme deletion in source mode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(
        text: 'A😀B\nnext',
        mode: IanvsMarkdownEditorMode.source,
      )..selection = const TextSelection.collapsed(offset: 3);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );

      Future<void> controlH() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      controller.selection = const TextSelection.collapsed(offset: 3);
      await controlH();
      expect(controller.text, 'AB\nnext');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));

      controller.value = const TextEditingValue(
        text: 'alpha\nbeta',
        selection: TextSelection.collapsed(offset: 6),
      );
      await tester.pump();
      await controlH();
      expect(controller.text, 'alphabeta');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));

      controller.value = const TextEditingValue(
        text: 'alpha beta',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tester.pump();
      await controlH();
      expect(controller.text, ' beta');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+U stays unbound in live and source modes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'alpha beta');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha beta'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      Future<void> controlU() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await controlU();
      expect(controller.text, 'alpha beta');
      expect(controller.selection.textInside(controller.text), 'alpha');

      controller.mode = IanvsMarkdownEditorMode.source;
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();
      await controlU();
      expect(controller.text, 'alpha beta');
      expect(controller.selection.textInside(controller.text), 'alpha');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+A reveals and enters a hidden list prefix', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const source = '- alpha beta\n- second';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha beta'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 7);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-list-marker')),
        findsNothing,
      );
      expect(field.controller?.text, '- alpha beta');
      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Command horizontal arrows use wrapped visual line boundaries', (
    tester,
  ) async {
    final source = List.generate(
      40,
      (index) => 'w${index.toString().padLeft(2, '0')}',
    ).join(' ');
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 720,
            child: IanvsMarkdownLiveEditor(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> commandArrow(
      LogicalKeyboardKey key, {
      bool shift = false,
    }) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.textContaining('w00'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    const offset = 100;
    field.controller?.selection = const TextSelection.collapsed(offset: offset);
    await tester.pump();

    final editable = editableWithin(tester, active);
    final line = editable.getLineAtOffset(const TextPosition(offset: offset));
    expect(line.start, greaterThan(0));
    expect(line.end, lessThan(source.length));

    await commandArrow(LogicalKeyboardKey.arrowLeft);
    expect(controller.selection, TextSelection.collapsed(offset: line.start));

    field.controller?.selection = const TextSelection.collapsed(offset: offset);
    await tester.pump();
    await commandArrow(LogicalKeyboardKey.arrowRight);
    expect(controller.selection, TextSelection.collapsed(offset: line.end));

    field.controller?.selection = const TextSelection.collapsed(offset: offset);
    await tester.pump();
    await commandArrow(LogicalKeyboardKey.arrowLeft, shift: true);
    expect(controller.selection.baseOffset, offset);
    expect(controller.selection.extentOffset, line.start);
    expect(
      controller.selection.textInside(source),
      source.substring(line.start, offset),
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Command+D deletes the active physical source line', (
    tester,
  ) async {
    const source = 'alpha\nbeta\ngamma';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('alpha'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 8);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.text, 'alpha\ngamma');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'alpha\ngamma');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 8),
    );
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(controller.text, source);
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('live Command+D preserves the visual horizontal position', (
    tester,
  ) async {
    const source = '😀😀\nabcdefgh\nlast';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('😀😀'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();

    final editable = editableWithin(tester, active);
    final headRect = editable.getLocalRectForCaret(
      const TextPosition(offset: 4),
    );
    final nextLineRect = editable.getLocalRectForCaret(
      const TextPosition(offset: 5),
    );
    final targetBeforeDelete = editable
        .getPositionForPoint(
          editable.localToGlobal(Offset(headRect.left, nextLineRect.center.dy)),
        )
        .offset
        .clamp(5, 13);
    final expectedCaret = targetBeforeDelete - 5;
    expect(expectedCaret, isNot(4));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.text, 'abcdefgh\nlast');
    expect(
      controller.selection,
      TextSelection.collapsed(offset: expectedCaret),
    );
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Command+D advances from a deleted list item', (tester) async {
    const source = 'intro\n\n- first\n- second\n- third';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('first'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.text, 'intro\n\n- second\n- third');
    expect(controller.selection, const TextSelection.collapsed(offset: 10));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '- second');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 3),
    );
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('live Command+D renumbers ordered siblings', (tester) async {
    final controller = IanvsMarkdownController(text: '1. A\n2. B\n3. C');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 9);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.text, '1. A\n2. C');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));
  });

  testWidgets('macOS Control+D deletes one grapheme in live mode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'A😀B');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A😀B'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, 'AB');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+D deletes a live block boundary newline', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'alpha\n\nlast');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, 'alpha\nlast');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+D deletes only a live selection', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'alpha beta\nsecond');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('alpha beta'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, ' beta\nsecond');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'macOS Control+B and F collapse live selections to directional edges',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final controller = IanvsMarkdownController(text: 'abcd');
        addTearDown(controller.dispose);
        await tester.pumpWidget(app(controller));
        await tester.pumpAndSettle();

        await tester.tap(find.text('abcd'));
        await tester.pump();
        final active = find.byKey(
          const ValueKey('ianvs-markdown-active-block'),
        );

        Future<void> control(LogicalKeyboardKey key) async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
        }

        var field = tester.widget<TextField>(
          find.descendant(of: active, matching: find.byType(TextField)),
        );
        field.controller?.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 3,
        );
        await tester.pump();
        await control(LogicalKeyboardKey.keyB);
        expect(controller.text, 'abcd');
        expect(controller.selection, const TextSelection.collapsed(offset: 1));

        field = tester.widget<TextField>(
          find.descendant(of: active, matching: find.byType(TextField)),
        );
        field.controller?.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 3,
        );
        await tester.pump();
        await control(LogicalKeyboardKey.keyF);
        expect(controller.text, 'abcd');
        expect(controller.selection, const TextSelection.collapsed(offset: 3));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('macOS Control+B and F traverse live graphemes and gaps', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'A😀B\n\nnext');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A😀B'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));

      Future<void> control(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      await control(LogicalKeyboardKey.keyF);
      expect(controller.selection, const TextSelection.collapsed(offset: 3));

      await control(LogicalKeyboardKey.keyB);
      expect(controller.selection, const TextSelection.collapsed(offset: 1));

      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await control(LogicalKeyboardKey.keyF);
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      await control(LogicalKeyboardKey.keyF);
      expect(controller.selection, const TextSelection.collapsed(offset: 6));

      await control(LogicalKeyboardKey.keyB);
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      await control(LogicalKeyboardKey.keyB);
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
      expect(controller.text, 'A😀B\n\nnext');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+P and N traverse live visual rows and gaps', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'abcd\n\nwxyz');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('abcd'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));

      Future<void> control(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();

      await control(LogicalKeyboardKey.keyN);
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      await control(LogicalKeyboardKey.keyN);
      expect(controller.selection, const TextSelection.collapsed(offset: 8));

      await control(LogicalKeyboardKey.keyP);
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      await control(LogicalKeyboardKey.keyP);
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
      expect(controller.text, 'abcd\n\nwxyz');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+P and N collapse live selections directionally', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'abcd');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('abcd'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));

      Future<void> control(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      await tester.pump();
      await control(LogicalKeyboardKey.keyN);
      expect(controller.selection, const TextSelection.collapsed(offset: 3));

      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      await tester.pump();
      await control(LogicalKeyboardKey.keyP);
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      expect(controller.text, 'abcd');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+N stays inside a wrapped live visual row', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const first = 'alpha beta gamma delta epsilon zeta eta theta';
      final controller = IanvsMarkdownController(text: '$first\n\nnext');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              height: 400,
              child: IanvsMarkdownLiveEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(first));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, '$first\n\nnext');
      expect(controller.selection.extentOffset, greaterThan(0));
      expect(controller.selection.extentOffset, lessThan(first.length));
      expect(field.controller?.text, first);
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Option vertical arrows traverse physical lines and blank gaps', (
    tester,
  ) async {
    const source = 'alpha\nbeta\n\ngamma';
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection.collapsed(offset: 8);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> optionArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
    }

    await optionArrow(LogicalKeyboardKey.arrowDown);
    expect(controller.selection, const TextSelection.collapsed(offset: 10));

    await optionArrow(LogicalKeyboardKey.arrowDown);
    expect(controller.selection, const TextSelection.collapsed(offset: 11));

    await optionArrow(LogicalKeyboardKey.arrowDown);
    expect(controller.selection, const TextSelection.collapsed(offset: 17));

    await optionArrow(LogicalKeyboardKey.arrowUp);
    expect(controller.selection, const TextSelection.collapsed(offset: 12));

    await optionArrow(LogicalKeyboardKey.arrowUp);
    expect(controller.selection, const TextSelection.collapsed(offset: 11));

    await optionArrow(LogicalKeyboardKey.arrowUp);
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    expect(controller.text, source);
  });

  testWidgets('Option arrows traverse words across block gaps', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const source = 'alpha\n\nbravo';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      Future<void> optionArrow(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('bravo'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 0);

      await optionArrow(LogicalKeyboardKey.arrowLeft);

      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, 'alpha');
      expect(
        field.controller?.selection,
        const TextSelection.collapsed(offset: 0),
      );

      field.controller?.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      await optionArrow(LogicalKeyboardKey.arrowRight);

      expect(
        controller.selection,
        const TextSelection.collapsed(offset: source.length),
      );
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, 'bravo');
      expect(
        field.controller?.selection,
        const TextSelection.collapsed(offset: 5),
      );
      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Option arrows skip descendants of a collapsed heading', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const source = '# Heading\nBody\n# Tail';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      Future<void> optionArrow(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byTooltip('折叠标题内容'));
      await tester.pumpAndSettle();
      expect(find.text('Body'), findsNothing);

      await tester.tap(find.text('Heading'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = TextSelection.collapsed(
        offset: field.controller!.text.length,
      );

      await optionArrow(LogicalKeyboardKey.arrowRight);

      expect(active, findsOneWidget);
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, '# Tail');
      expect(field.controller?.selection.extentOffset, 0);

      await optionArrow(LogicalKeyboardKey.arrowLeft);

      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, '# Heading');
      expect(field.controller?.selection.extentOffset, '# Heading'.length);
      expect(field.focusNode?.hasFocus, isTrue);
      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Shift Option arrows select and replace across block gaps', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const source = 'alpha\n\nbravo';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('bravo'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      var field = tester.widget<TextField>(fieldFinder);
      field.controller?.selection = const TextSelection.collapsed(offset: 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(controller.selection.baseOffset, 7);
      expect(controller.selection.extentOffset, 0);
      expect(controller.selection.isDirectional, isTrue);
      expect(controller.selection.textInside(controller.text), 'alpha\n\n');
      field = tester.widget<TextField>(fieldFinder);
      expect(field.controller?.text, 'alpha\n\n');

      field.controller?.value = const TextEditingValue(
        text: 'Z',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pumpAndSettle();
      expect(controller.text, 'Zbravo');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(controller.text, source);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.text, 'Zbravo');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(controller.text, source);
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Shift Option selection contracts and crosses its word anchor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const source = 'alpha\n\nbravo';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      Future<void> shiftOptionArrow(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('bravo'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      var field = tester.widget<TextField>(fieldFinder);
      field.controller?.selection = const TextSelection.collapsed(offset: 0);

      await shiftOptionArrow(LogicalKeyboardKey.arrowLeft);
      await shiftOptionArrow(LogicalKeyboardKey.arrowRight);

      expect(controller.selection.baseOffset, 7);
      expect(controller.selection.extentOffset, 5);
      expect(controller.selection.textInside(controller.text), '\n\n');

      await shiftOptionArrow(LogicalKeyboardKey.arrowRight);

      expect(controller.selection.baseOffset, 7);
      expect(controller.selection.extentOffset, source.length);
      expect(controller.selection.textInside(controller.text), 'bravo');
      field = tester.widget<TextField>(fieldFinder);
      expect(field.controller?.text, 'bravo');
      expect(field.controller?.selection.baseOffset, 0);
      expect(field.controller?.selection.extentOffset, 5);
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Option word selection keeps Markdown punctuation separate', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const source = '**bold**\n\nnext';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('next'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      var field = tester.widget<TextField>(fieldFinder);
      field.controller?.selection = const TextSelection.collapsed(offset: 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(controller.selection.baseOffset, 10);
      expect(controller.selection.extentOffset, 8);
      expect(controller.selection.textInside(controller.text), '\n\n');
      field = tester.widget<TextField>(fieldFinder);
      expect(field.controller?.text, '**bold**\n\n');
      expect(field.focusNode?.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('horizontal arrows traverse blank source lines between blocks', (
    tester,
  ) async {
    const source = 'aa\n\nbbbbbb\n\ncc';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('aa'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'aa\n');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 3),
    );
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'bbbbbb');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 0),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'aa\n');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'aa\n');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 2),
    );
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('ArrowLeft enters a leading blank line before the first block', (
    tester,
  ) async {
    const source = '\nAlpha';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(controller.isDirty, isFalse);

    field.controller?.value = const TextEditingValue(
      text: 'X\nAlpha',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'X\nAlpha');

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
  });

  testWidgets(
    'inserting a leading line keeps the gap editor and caret active',
    (tester) async {
      const source = '\nAlpha';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha'));
      await tester.pump();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      var field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      field.controller?.value = const TextEditingValue(
        text: '\n\nAlpha',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pumpAndSettle();

      expect(controller.text, '\n\nAlpha');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, '\n\nAlpha');
      expect(
        field.controller?.selection,
        const TextSelection.collapsed(offset: 1),
      );
      expect(field.focusNode?.hasFocus, isTrue);

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, source);
    },
  );

  testWidgets('deleting the first character restores the leading gap caret', (
    tester,
  ) async {
    const source = '\nAlpha';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    field = tester.widget<TextField>(fieldFinder);
    field.controller?.value = const TextEditingValue(
      text: 'X\nAlpha',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pumpAndSettle();

    field = tester.widget<TextField>(fieldFinder);
    field.controller?.value = const TextEditingValue(
      text: '\nAlpha',
      selection: TextSelection.collapsed(offset: 0),
    );
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, source);
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 0),
    );
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('horizontal arrows cross adjacent structural blocks', (
    tester,
  ) async {
    const source = '# H\nParagraph';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('H'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'Paragraph');
    expect(field.controller?.selection.extentOffset, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '# H');
    expect(field.controller?.selection.extentOffset, 3);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('horizontal arrows skip descendants of a collapsed heading', (
    tester,
  ) async {
    const source = '# Heading\nBody\n# Tail';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('折叠标题内容'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);

    await tester.tap(find.text('Heading'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = TextSelection.collapsed(
      offset: field.controller!.text.length,
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(active, findsOneWidget);
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '# Tail');
    expect(field.controller?.selection.extentOffset, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '# Heading');
    expect(field.controller?.selection.extentOffset, '# Heading'.length);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('shift horizontal arrows select and replace block separators', (
    tester,
  ) async {
    const source = 'aa\n\nbbbbbb\n\ncc';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Future<void> shiftArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('aa'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await shiftArrow(LogicalKeyboardKey.arrowRight);

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 2, extentOffset: 3, isDirectional: true),
    );
    expect(controller.selection.textInside(controller.text), '\n');
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'aa\n');
    expect(field.controller?.selection.baseOffset, 2);
    expect(field.controller?.selection.extentOffset, 3);

    await shiftArrow(LogicalKeyboardKey.arrowRight);

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection.baseOffset, 2);
    expect(controller.selection.extentOffset, 4);
    expect(controller.selection.textInside(controller.text), '\n\n');
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'aa\n\n');

    await shiftArrow(LogicalKeyboardKey.arrowLeft);

    expect(controller.selection.baseOffset, 2);
    expect(controller.selection.extentOffset, 3);
    expect(controller.selection.textInside(controller.text), '\n');

    field.controller?.value = const TextEditingValue(
      text: 'aaX\n',
      selection: TextSelection.collapsed(offset: 3),
    );
    await tester.pumpAndSettle();

    expect(controller.text, 'aaX\nbbbbbb\n\ncc');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(controller.isDirty, isTrue);

    controller.undo();
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(controller.selection.baseOffset, 2);
    expect(controller.selection.extentOffset, 3);
    expect(controller.selection.textInside(controller.text), '\n');
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'aa\n');
    expect(field.controller?.selection.baseOffset, 2);
    expect(field.controller?.selection.extentOffset, 3);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('reverse shift selection stays directional across blank lines', (
    tester,
  ) async {
    const source = 'aa\n\nbbbbbb\n\ncc';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Future<void> shiftArrow(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('bbbbbb'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await shiftArrow(LogicalKeyboardKey.arrowLeft);

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection.baseOffset, 4);
    expect(controller.selection.extentOffset, 3);
    expect(controller.selection.isDirectional, isTrue);
    expect(controller.selection.textInside(controller.text), '\n');
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'aa\n\n');
    expect(field.controller?.selection.baseOffset, 4);
    expect(field.controller?.selection.extentOffset, 3);

    await shiftArrow(LogicalKeyboardKey.arrowLeft);

    expect(controller.selection.baseOffset, 4);
    expect(controller.selection.extentOffset, 2);
    expect(controller.selection.textInside(controller.text), '\n\n');

    await shiftArrow(LogicalKeyboardKey.arrowRight);

    expect(controller.selection.baseOffset, 4);
    expect(controller.selection.extentOffset, 3);
    expect(controller.selection.textInside(controller.text), '\n');
    expect(controller.text, source);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('shift selection enters an adjacent structural block', (
    tester,
  ) async {
    const source = '# H\nParagraph';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Future<void> shiftRight() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('H'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await shiftRight();

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection.baseOffset, 3);
    expect(controller.selection.extentOffset, 4);
    expect(controller.selection.textInside(controller.text), '\n');
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, '# H\n');
    expect(find.text('Paragraph'), findsOneWidget);

    await shiftRight();

    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    expect(controller.selection.baseOffset, 3);
    expect(controller.selection.extentOffset, 5);
    expect(controller.selection.textInside(controller.text), '\nP');
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, source);
    expect(field.controller?.selection.baseOffset, 3);
    expect(field.controller?.selection.extentOffset, 5);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('typing on a navigated blank line creates its paragraph', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'aa\n\nbbbbbb');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('aa'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    field.controller?.selection = const TextSelection.collapsed(offset: 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    fieldFinder = find.descendant(of: active, matching: find.byType(TextField));
    await tester.enterText(fieldFinder, 'aa\nX');
    await tester.pumpAndSettle();

    expect(controller.text, 'aa\nX\nbbbbbb');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'aa\nX\nbbbbbb');
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('clicking a rendered block gap activates its blank source line', (
    tester,
  ) async {
    const source = 'aa\n\nbbb';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-gap-2')));
    await tester.pump();

    expect(controller.text, source);
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'aa\n');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 3),
    );
    expect(find.text('bbb'), findsOneWidget);
  });

  testWidgets('a focused gap keeps the preceding quote rendered', (
    tester,
  ) async {
    const source = '> Quote alpha\n>\n> Quote beta\n\nTail';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final quoteEnd = source.indexOf('\n\nTail');
    await tester.tap(find.byKey(ValueKey('ianvs-markdown-gap-$quoteEnd')));
    await tester.pump();

    expect(controller.selection, TextSelection.collapsed(offset: quoteEnd + 1));
    expect(find.text('Quote alpha'), findsOneWidget);
    expect(find.text('Quote beta'), findsOneWidget);
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.maxLines, isNull);
    expect(field.controller?.text, '> Quote alpha\n>\n> Quote beta\n');
    expect(field.focusNode?.hasFocus, isTrue);
    final editable = editableWithin(tester, active);
    final paintedText = editable.text?.toPlainText() ?? '';
    expect(paintedText, isNot(contains('Quote alpha')));
    expect(paintedText, isNot(contains('\n')));
    expect(find.text('Tail'), findsOneWidget);

    await tester.enterText(
      find.descendant(of: active, matching: find.byType(TextField)),
      '> Quote alpha\n>\n> Quote beta\nx',
    );
    await tester.pumpAndSettle();

    expect(controller.text, '> Quote alpha\n>\n> Quote beta\nx\nTail');
  });

  testWidgets('vertical arrows stay inside wrapped lines before a block gap', (
    tester,
  ) async {
    const first = 'alpha beta gamma delta epsilon zeta eta theta';
    final controller = IanvsMarkdownController(text: '$first\n\nnext');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 400,
            child: IanvsMarkdownLiveEditor(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(first));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection.collapsed(offset: 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(controller.text, '$first\n\nnext');
    expect(controller.selection.extentOffset, greaterThan(0));
    expect(controller.selection.extentOffset, lessThan(first.length));
    expect(field.controller?.text, first);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('toolbar switches live, source, and reading modes', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '# Modes');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));

    await tester.tap(find.byTooltip('源码模式'));
    await tester.pumpAndSettle();
    expect(controller.mode, IanvsMarkdownEditorMode.source);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      findsOneWidget,
    );

    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.tap(find.byTooltip('粗体'));
    await tester.pump();
    expect(controller.text, '# Modes****');

    await tester.tap(find.byTooltip('阅读模式'));
    await tester.pumpAndSettle();
    expect(controller.mode, IanvsMarkdownEditorMode.preview);
    expect(find.byKey(const ValueKey('ianvs-markdown-view')), findsOneWidget);

    await tester.tap(find.byTooltip('实时预览'));
    await tester.pumpAndSettle();
    expect(controller.mode, IanvsMarkdownEditorMode.livePreview);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-live-blocks')),
      findsOneWidget,
    );
  });

  testWidgets('toolbar uses selection-aware italic and empty-link commands', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'alpha');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));

    await tester.tap(find.byTooltip('源码模式'));
    await tester.pumpAndSettle();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.tap(find.byTooltip('斜体'));
    await tester.pump();
    expect(controller.text, '*alpha*');
    expect(controller.selection.textInside(controller.text), 'alpha');

    controller.value = const TextEditingValue(
      text: 'alpha',
      selection: TextSelection.collapsed(offset: 0),
    );
    await tester.tap(find.byTooltip('链接'));
    await tester.pump();
    expect(controller.text, '[]()alpha');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
  });

  testWidgets('keyboard shortcuts match selection-aware toolbar commands', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'alpha');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));

    await tester.tap(find.byTooltip('源码模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-source-field')));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(controller.text, '*alpha*');

    controller.value = const TextEditingValue(
      text: 'alpha',
      selection: TextSelection.collapsed(offset: 0),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(controller.text, '[]()alpha');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
  });

  testWidgets(
    'live inline shortcuts wrap the current word and preserve the caret',
    (tester) async {
      final controller = IanvsMarkdownController(text: 'PAIR_TARGET');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PAIR_TARGET'));
      await tester.pump();
      controller.selection = const TextSelection.collapsed(offset: 4);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, '**PAIR_TARGET**');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.focusNode?.hasFocus, isTrue);
    },
  );

  testWidgets('Control+K remains a link shortcut on non-Apple platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final controller = IanvsMarkdownController(
        text: 'alpha',
        mode: IanvsMarkdownEditorMode.source,
      )..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, '[]()alpha');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Control+B remains a bold shortcut on non-Apple platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final controller = IanvsMarkdownController(
        text: 'alpha',
        mode: IanvsMarkdownEditorMode.source,
      )..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, '****alpha');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('source paste turns a selected URL into a Markdown link', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const url = 'https://example.com';
      final controller = IanvsMarkdownController(
        text: url,
        mode: IanvsMarkdownEditorMode.source,
      );
      addTearDown(controller.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async => methodCall.method == 'Clipboard.getData'
            ? const <String, dynamic>{'text': url}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: url.length,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, '[$url]($url)');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('live paste turns selected text into a Markdown link', (
    tester,
  ) async {
    const url = 'https://example.com';
    final controller = IanvsMarkdownController(text: 'Label');
    addTearDown(controller.dispose);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async => methodCall.method == 'Clipboard.getData'
          ? const <String, dynamic>{'text': url}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Label'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(controller.text, '[Label]($url)');
  });

  testWidgets('smart paste preserves native collapsed and plain-text paste', (
    tester,
  ) async {
    const url = 'https://example.com';
    var clipboardText = url;
    final controller = IanvsMarkdownController(
      text: 'Label',
      mode: IanvsMarkdownEditorMode.source,
    );
    addTearDown(controller.dispose);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async => methodCall.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': clipboardText}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-source-field')));
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.text, 'Label$url');

    clipboardText = 'plain text';
    controller.value = const TextEditingValue(
      text: 'Label',
      selection: TextSelection(baseOffset: 0, extentOffset: 5),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.text, 'plain text');
  });

  testWidgets('smart paste ignores an unavailable platform clipboard', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Label');
    addTearDown(controller.dispose);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          throw PlatformException(code: 'clipboard-unavailable');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Label'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(controller.text, 'Label');
    expect(tester.takeException(), isNull);
  });

  testWidgets('word deletion keeps Markdown punctuation in separate segments', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(
        text: '**bold**',
        mode: IanvsMarkdownEditorMode.source,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final sourceField = find.byKey(
        const ValueKey('ianvs-markdown-source-field'),
      );
      await tester.tap(sourceField);
      controller.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(controller.text, '**bold');

      controller.value = const TextEditingValue(
        text: 'foo-bar_baz',
        selection: TextSelection.collapsed(offset: 11),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(controller.text, 'foo-');

      controller.value = const TextEditingValue(
        text: '[label](url)',
        selection: TextSelection.collapsed(offset: 0),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(controller.text, 'label](url)');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('word movement stops at Markdown punctuation boundaries', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(
        text: '**bold**',
        mode: IanvsMarkdownEditorMode.source,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final sourceField = find.byKey(
        const ValueKey('ianvs-markdown-source-field'),
      );
      await tester.tap(sourceField);
      controller.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(offset: 6));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(offset: 2));

      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(offset: 2));

      controller.selection = const TextSelection.collapsed(offset: 8);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(controller.selection.baseOffset, 8);
      expect(controller.selection.extentOffset, 6);
      expect(controller.selection.textInside(controller.text), '**');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('live preview shares Markdown punctuation deletion behavior', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: '**bold**');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('bold'));
      await tester.pump();
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
          matching: find.byType(TextField),
        ),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(controller.text, '**bold');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('live preview shares Markdown punctuation movement behavior', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: '**bold**');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('bold'));
      await tester.pump();
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
          matching: find.byType(TextField),
        ),
      );
      field.controller?.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
      expect(field.controller?.selection.extentOffset, 6);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('soft breaks match in live and reading modes', (tester) async {
    const source =
        'Soft alpha\nsoft beta\n\nHard alpha  \nhard beta\n\nEscaped \\*literal\\*.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.text('Soft alpha\nsoft beta'), findsOneWidget);

    await tester.tap(find.text('Soft alpha\nsoft beta'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'Soft alpha\nsoft beta');

    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    expect(find.textContaining('Soft alpha\nsoft beta'), findsOneWidget);
  });

  testWidgets('backslash hard breaks keep native Enter and Backspace flow', (
    tester,
  ) async {
    const source = 'Backslash alpha\\';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Backslash alpha'));
    await tester.pump();
    controller.selection = TextSelection.collapsed(offset: source.length);

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$source\n',
        selection: TextSelection.collapsed(offset: source.length + 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '$source\n');
    expect(
      controller.selection,
      TextSelection.collapsed(offset: source.length + 1),
    );

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, source);
    expect(
      controller.selection,
      TextSelection.collapsed(offset: source.length),
    );

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Backslash alpha',
        selection: TextSelection.collapsed(offset: 15),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'Backslash alpha');
    expect(controller.selection, const TextSelection.collapsed(offset: 15));
  });

  testWidgets('soft breaks can still follow standard Markdown collapsing', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Soft alpha\nsoft beta');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            softLineBreak: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Soft alpha soft beta'), findsOneWidget);

    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    expect(find.textContaining('Soft alpha soft beta'), findsOneWidget);
  });

  testWidgets('inactive whitespace collapses while active source stays exact', (
    tester,
  ) async {
    const source = 'Alpha   beta\tgamma';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.text('Alpha beta gamma'), findsOneWidget);
    await tester.tap(find.text('Alpha beta gamma'));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(controller.text, source);
  });

  testWidgets('whitespace-only documents activate their exact source', (
    tester,
  ) async {
    const source = ' \t \n\n';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final editTarget = find.bySemanticsLabel('Edit Markdown block');
    expect(tester.getSize(editTarget).width, greaterThan(100));
    await tester.tap(editTarget);
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(field.focusNode?.hasFocus, isTrue);

    field.controller?.value = const TextEditingValue(
      text: 'X',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'X');

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
  });

  testWidgets('extra source blank lines share one Obsidian paragraph gap', (
    tester,
  ) async {
    const source = 'One\n\nTwo\n\n\nThree\n\n\n\nFour';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    final blocks = parseMarkdownBlocks(source);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final heights = <double>[
      for (final block in blocks.take(3))
        tester
            .getSize(find.byKey(ValueKey('ianvs-markdown-gap-${block.end}')))
            .height,
    ];
    expect(heights, everyElement(14));
    expect(controller.text, source);
  });

  testWidgets(
    'renders H1-H6 rails and preserves Setext source in live preview',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: '###### Sixth\n\nSetext level two\n----------------',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ianvs-markdown-live-heading-rail-6')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ianvs-markdown-setext-underline-source')),
        findsOneWidget,
      );
      expect(find.text('----------------'), findsNothing);

      await tester.tap(find.text('Setext level two'));
      await tester.pump();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, 'Setext level two\n----------------');
      expect(field.style?.fontSize, 21);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-heading-rail')),
        findsOneWidget,
      );
      final badge = find.byKey(
        const ValueKey('ianvs-markdown-active-heading-level-badge'),
      );
      expect(badge, findsOneWidget);
      expect(tester.getSize(badge), const Size(17, 15));
      expect(find.text('H2'), findsOneWidget);
      expect(find.text('----------------'), findsNothing);
      final span = field.controller!.buildTextSpan(
        context: tester.element(
          find.descendant(of: active, matching: find.byType(TextField)),
        ),
        style: field.style,
        withComposing: false,
      );
      final hiddenUnderline = _textSpanLeaves(
        span,
      ).where((leaf) => leaf.text?.contains('----------------') ?? false);
      expect(hiddenUnderline, isNotEmpty);
      expect(
        hiddenUnderline.every((leaf) => leaf.style?.fontSize == 0),
        isTrue,
      );
    },
  );

  testWidgets('multiline Setext headings activate as one exact source block', (
    tester,
  ) async {
    const heading = 'First title line\nsecond title line\n---';
    final controller = IanvsMarkdownController(text: '$heading\n\nAfter');
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-setext-underline-source')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-live-heading-rail-2')),
      findsOneWidget,
    );
    await tester.tap(find.textContaining('second title line'));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, heading);
    expect(field.style?.fontSize, 21);
    expect(find.text('H2'), findsOneWidget);
    expect(controller.text, '$heading\n\nAfter');
  });

  testWidgets('ATX heading clicks map visible text to exact source offsets', (
    tester,
  ) async {
    const source = 'Before\n\n## Alpha bravo\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final editable = editableWithin(tester, find.text('Alpha bravo'));
    const visibleOffset = 6;
    final target = editable.localToGlobal(
      editable
          .getLocalRectForCaret(const TextPosition(offset: visibleOffset))
          .center,
    );
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(
      controller.selection,
      TextSelection.collapsed(
        offset: source.indexOf('Alpha bravo') + visibleOffset,
      ),
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('heading multi-click selections preserve physical source lines', (
    tester,
  ) async {
    const source =
        'Before\n\n## Alpha bravo\n\nSetext bravo\n------------\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Future<Offset> targetWithin(Finder finder, int offset) async {
      final editable = editableWithin(tester, finder);
      return editable.localToGlobal(
        editable.getLocalRectForCaret(TextPosition(offset: offset)).center,
      );
    }

    var target = await targetWithin(find.text('Alpha bravo'), 8);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.selection.textInside(source), 'bravo');

    await tester.tapAt(target);
    await tester.pumpAndSettle();
    expect(controller.selection.textInside(source), '## Alpha bravo');

    await tester.tap(find.text('After'));
    await tester.pumpAndSettle();
    target = await targetWithin(find.text('Setext bravo'), 9);
    for (var tap = 0; tap < 3; tap += 1) {
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), 'Setext bravo');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('active ATX headings expose compact H1-H6 badges', (
    tester,
  ) async {
    const labels = <String>['One', 'Two', 'Three', 'Four', 'Five', 'Six'];
    final source = <String>[
      for (var index = 0; index < labels.length; index += 1)
        '${List<String>.filled(index + 1, '#').join()} ${labels[index]}',
    ].join('\n\n');
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    for (var index = 0; index < labels.length; index += 1) {
      await tester.tap(find.text(labels[index]));
      await tester.pumpAndSettle();
      final badge = find.byKey(
        const ValueKey('ianvs-markdown-active-heading-level-badge'),
      );
      expect(badge, findsOneWidget);
      expect(tester.getSize(badge), const Size(17, 15));
      expect(find.text('H${index + 1}'), findsOneWidget);
      expect(controller.text, source);
    }
  });

  testWidgets('thematic break clicks select the marker only near its source', (
    tester,
  ) async {
    const source = 'Paragraph before.\n\n- - -\n\nParagraph after.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final start = source.indexOf('- - -');
    final renderedRule = find.byKey(
      ValueKey('ianvs-markdown-block-$start-thematicBreak'),
    );
    final ruleRect = tester.getRect(renderedRule);
    await tester.tapAt(Offset(ruleRect.left + 16, ruleRect.center.dy));
    await tester.pump();

    expect(controller.text, source);
    expect(
      controller.selection,
      TextSelection(baseOffset: start, extentOffset: start + 5),
    );
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '- - -');
    expect(
      field.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );

    await tester.tap(find.text('Paragraph before.'));
    await tester.pumpAndSettle();
    await tester.tapAt(Offset(ruleRect.center.dx, ruleRect.center.dy));
    await tester.pump();

    expect(controller.selection, TextSelection.collapsed(offset: start + 5));
    final collapsedField = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(collapsedField.controller?.text, '- - -');
    expect(
      collapsedField.controller?.selection,
      const TextSelection.collapsed(offset: 5),
    );
  });

  testWidgets('marker-only ATX prefixes stay literal and use paragraph UI', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '# \n\n###### \n\nBody');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-heading-rail')),
      findsNothing,
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '# ');
    expect(field.style?.fontSize, lessThan(20));

    await tester.tap(find.text('Body'));
    await tester.pumpAndSettle();

    expect(find.text('#'), findsOneWidget);
    expect(find.text('######'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-live-heading-rail-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-live-heading-rail-6')),
      findsNothing,
    );
    expect(controller.text, '# \n\n###### \n\nBody');
  });

  testWidgets('ATX markers enter heading UI only after title text', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '#\n\nBody');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    expect(field.controller!.text, '#');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-heading-rail')),
      findsNothing,
    );
    expect(field.style?.fontSize, lessThan(20));

    await tester.enterText(fieldFinder, '# ');
    await tester.pumpAndSettle();

    active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    fieldFinder = find.descendant(of: active, matching: find.byType(TextField));
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller!.text, '# ');
    expect(controller.text, '# \n\nBody');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-heading-rail')),
      findsNothing,
    );
    expect(field.style?.fontSize, lessThan(20));

    await tester.enterText(fieldFinder, '# Title');
    await tester.pumpAndSettle();

    active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    fieldFinder = find.descendant(of: active, matching: find.byType(TextField));
    field = tester.widget<TextField>(fieldFinder);
    expect(field.controller!.text, '# Title');
    expect(controller.text, '# Title\n\nBody');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-heading-rail')),
      findsOneWidget,
    );
    expect(field.style?.fontSize, greaterThanOrEqualTo(20));

    await tester.tap(find.text('Body'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-live-heading-rail-1')),
      findsOneWidget,
    );
  });

  testWidgets('heading folds preserve hierarchy across live and read modes', (
    tester,
  ) async {
    const source = '''
# Alpha

Alpha body.

## Beta

Beta body.

### Gamma

Gamma body.

## Delta

Delta body.

# Omega

Omega body.
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    final model = IanvsMarkdownHeadingFoldModel.parse(
      source,
      splitListItems: true,
    );
    final alpha = model.sections.firstWhere(
      (section) => section.text == 'Alpha',
    );
    final beta = model.sections.firstWhere((section) => section.text == 'Beta');

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('ianvs-markdown-live-heading-fold-${beta.identity}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Beta body.'), findsNothing);
    expect(find.text('Gamma'), findsNothing);
    expect(find.text('Delta'), findsOneWidget);

    await tester.tap(
      find.byKey(
        ValueKey('ianvs-markdown-live-heading-fold-${alpha.identity}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Delta'), findsNothing);
    expect(find.text('Omega'), findsOneWidget);

    await tester.tap(
      find.byKey(
        ValueKey('ianvs-markdown-live-heading-fold-${alpha.identity}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Beta body.'), findsNothing);
    expect(find.text('Delta'), findsOneWidget);

    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNWidgets(2));
    expect(find.text('Beta body.'), findsNothing);
    expect(find.text('Delta'), findsNWidgets(2));

    await tester.tap(
      find.byKey(ValueKey('ianvs-markdown-heading-fold-${beta.identity}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beta body.'), findsOneWidget);
    expect(find.text('Gamma'), findsNWidgets(2));
  });

  testWidgets('outline navigation reaches lazily built distant headings', (
    tester,
  ) async {
    final middle = List<String>.generate(
      80,
      (index) => 'Paragraph $index with enough content to occupy a row.',
    ).join('\n\n');
    final controller = IanvsMarkdownController(
      text: '# Start\n\n$middle\n\n## Far heading\n\nDestination.',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              showNavigationPane: true,
              navigationBreakpoint: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Far heading'), findsOneWidget);

    await tester.tap(find.text('Far heading'));
    await tester.pumpAndSettle();

    expect(find.text('Far heading'), findsNWidgets(2));
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('ianvs-markdown-live-blocks')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets(
    'empty front matter stays invisible without changing exact source',
    (tester) async {
      const source = '---\n---\nBody';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      bool isHorizontalRule(Widget widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) return false;
        final border = decoration.border;
        return border is Border &&
            border.top.width == 2 &&
            border.top.color == IanvsMarkdownThemeData.light.borderSoft;
      }

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final frontMatterBlock = find.byKey(
        const ValueKey('ianvs-markdown-block-0-frontMatter'),
      );
      expect(frontMatterBlock, findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
      expect(find.text('笔记属性'), findsNothing);
      expect(
        find.descendant(
          of: frontMatterBlock,
          matching: find.byWidgetPredicate(isHorizontalRule),
        ),
        findsNothing,
      );
      expect(controller.text, source);

      controller.mode = IanvsMarkdownEditorMode.preview;
      await tester.pumpAndSettle();

      expect(find.text('Body'), findsOneWidget);
      expect(find.text('笔记属性'), findsNothing);
      expect(find.byWidgetPredicate(isHorizontalRule), findsNothing);
      expect(controller.text, source);
    },
  );

  testWidgets(
    'compact properties default expanded and activate exact YAML source',
    (tester) async {
      const source = '''
---
title: Properties probe
status: draft
tags: [probe, properties]
empty:
---
# Body
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      expect(find.text('Properties probe'), findsOneWidget);
      expect(find.text('笔记属性'), findsOneWidget);
      expect(find.text('title'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-front-matter-row-status')),
        findsOneWidget,
      );
      expect(find.text('没有值'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-front-matter-toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text('status'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-front-matter-toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.text('status'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-front-matter-type-status')),
      );
      await tester.pump();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      expect(active, findsOneWidget);
      final field = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(field).controller?.text,
        '''
---
title: Properties probe
status: draft
tags: [probe, properties]
empty:
---
'''
            .trim(),
      );
    },
  );

  testWidgets(
    'compact properties edit text and boolean values without opening YAML',
    (tester) async {
      const source = '''
---
title: Alpha
enabled: true
tags: [one, two]
cssclasses: [wide]
---
# Body
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final titleInput = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-title'),
      );
      expect(titleInput, findsOneWidget);
      await tester.tap(titleInput);
      await tester.enterText(titleInput, 'Beta');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.text, '''
---
title: Beta
enabled: true
tags:
  - one
  - two
cssclasses:
  - wide
---
# Body
''');
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-block')),
        findsNothing,
      );

      final boolean = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-boolean-enabled'),
      );
      expect(boolean, findsOneWidget);
      await tester.tap(boolean);
      await tester.pumpAndSettle();
      expect(controller.text, contains('enabled: false'));

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, contains('enabled: true'));
    },
  );

  testWidgets('dragging inside a property value stays local', (tester) async {
    const source = '''
---
title: Alpha
---
Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-input-title'),
    );
    final rect = tester.getRect(input);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);

    await mouse.down(Offset(rect.left + 4, rect.center.dy));
    await mouse.moveTo(Offset(rect.left + 32, rect.center.dy));
    await tester.pumpAndSettle();

    expect(input, findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(input).controller?.selection.isCollapsed,
      isFalse,
    );
    expect(controller.text, source);

    await mouse.up();
    await tester.pumpAndSettle();
  });

  testWidgets('property text Escape cancels and focus loss commits', (
    tester,
  ) async {
    const source = '''
---
title: Alpha
---
# Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-input-title'),
    );
    await tester.tap(input);
    await tester.enterText(input, 'Pending');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, source);
    expect(tester.widget<TextField>(input).controller?.text, 'Alpha');

    await tester.tap(input);
    await tester.enterText(input, 'Committed');
    await tester.tap(find.text('Body'));
    await tester.pumpAndSettle();
    expect(controller.text, contains('title: Committed'));
  });

  testWidgets(
    'property inputs contain outer Markdown formatting shortcuts',
    (tester) async {
      const source = '''
---
title: Alpha
---
# Body
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final input = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-title'),
      );
      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.keyI,
        LogicalKeyboardKey.keyK,
      ]) {
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.tap(input);
        tester.widget<TextField>(input).controller?.selection =
            const TextSelection(baseOffset: 0, extentOffset: 5);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(controller.text, source, reason: 'shortcut: ${key.keyLabel}');
        expect(
          tester.widget<TextField>(input).controller?.text,
          'Alpha',
          reason: 'shortcut: ${key.keyLabel}',
        );
      }
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'macOS Control+B keeps native property-field navigation',
    (tester) async {
      const source = '''
---
title: Alpha
---
# Body
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final input = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-title'),
      );
      await tester.tap(input);
      final field = tester.widget<TextField>(input);
      field.controller?.selection = const TextSelection.collapsed(offset: 3);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(field.controller?.selection.extentOffset, 2);
      expect(controller.text, source);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'property Command+D cannot delete a stale document line',
    (tester) async {
      const source = '''
---
title: Alpha
---
first
second
''';
      final controller = IanvsMarkdownController(text: source)
        ..selection = TextSelection.collapsed(
          offset: source.indexOf('second') + 2,
        );
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final input = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-title'),
      );
      await tester.tap(input);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, source);
      expect(tester.widget<TextField>(input).controller?.text, 'Alpha');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'property Command+Z cannot undo stale document history',
    (tester) async {
      const source = '''
---
title: Alpha
---
first
''';
      const updated = '''
---
title: Alpha
---
second
''';
      final controller = IanvsMarkdownController(text: source)
        ..value = const TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(offset: 0),
        );
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final input = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-title'),
      );
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(input, 'Pending');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, updated);
      expect(tester.widget<TextField>(input).controller?.text, 'Alpha');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(controller.text, updated);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.text, updated);
      expect(tester.widget<TextField>(input).controller?.text, 'Pending');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'property list input isolates chip edits from document undo',
    (tester) async {
      const source = '''
---
tags: [one, two]
---
# Body
''';
      const afterRemoval = '''
---
tags:
  - one
---
# Body
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey('ianvs-markdown-front-matter-chip-remove-tags-1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.text, afterRemoval);

      final input = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-list-input-tags'),
      );
      await tester.tap(input);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(controller.text, afterRemoval);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.text, afterRemoval);

      await tester.tap(find.text('Body'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(controller.text, source);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'property Command+S commits pending input before saving',
    (tester) async {
      const source = '''
---
title: Alpha
---
# Body
''';
      const expected = '''
---
title: Beta
---
# Body
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      final saved = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 720,
              child: IanvsMarkdownLiveEditor(
                controller: controller,
                onSaveRequested: saved.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final input = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-title'),
      );
      await tester.tap(input);
      await tester.enterText(input, 'Beta');
      expect(controller.text, source);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, expected);
      expect(saved, <String>[expected]);
      expect(controller.isDirty, isFalse);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'date property Command+S commits pending input before saving',
    (tester) async {
      const source = '''
---
due: 2026-08-28
---
# Body
''';
      const expected = '''
---
due: 2026-08-27
---
# Body
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      final saved = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 720,
              child: IanvsMarkdownLiveEditor(
                controller: controller,
                onSaveRequested: saved.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final day = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-date-day-due'),
      );
      await tester.tap(day);
      await tester.enterText(day, '27');
      expect(controller.text, source);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, expected);
      expect(saved, <String>[expected]);
      expect(controller.isDirty, isFalse);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'date pending value survives Command+E mode switch',
    (tester) async {
      const source = '''
---
due: 2026-08-28
---
# Body
''';
      const expected = '''
---
due: 2026-08-27
---
# Body
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 720,
              child: IanvsMarkdownLiveEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final day = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-date-day-due'),
      );
      await tester.tap(day);
      await tester.enterText(day, '27');
      expect(controller.text, source);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.mode, IanvsMarkdownEditorMode.preview);
      expect(controller.text, expected);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'date pending value survives Command+3 mode switch',
    (tester) async {
      const source = '''
---
due: 2026-08-28
---
# Body
''';
      const expected = '''
---
due: 2026-08-27
---
# Body
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 720,
              child: IanvsMarkdownLiveEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final day = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-date-day-due'),
      );
      await tester.tap(day);
      await tester.enterText(day, '27');
      expect(controller.text, source);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.mode, IanvsMarkdownEditorMode.preview);
      expect(controller.text, expected);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'property paste cannot replace a stale document selection',
    (tester) async {
      const url = 'https://example.com';
      const source = '''
---
title: Alpha
---
Label
''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async => methodCall.method == 'Clipboard.getData'
            ? const <String, dynamic>{'text': url}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 720,
              child: IanvsMarkdownLiveEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final input = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-title'),
      );
      controller.selection = TextSelection(
        baseOffset: source.indexOf('Label'),
        extentOffset: source.indexOf('Label') + 'Label'.length,
      );
      await tester.tap(input);
      final field = tester.widget<TextField>(input);
      field.controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 'Alpha'.length,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, source);
      expect(field.controller!.text, url);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'property Option+Backspace cannot delete stale Markdown punctuation',
    (tester) async {
      const source = '''
---
title: Alpha
---
**bold**''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 720,
              child: IanvsMarkdownLiveEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final input = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-title'),
      );
      controller.selection = const TextSelection.collapsed(
        offset: source.length,
      );
      await tester.tap(input);
      final field = tester.widget<TextField>(input);
      field.controller!.selection = const TextSelection.collapsed(
        offset: 'Alpha'.length,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(controller.text, source);
      expect(field.controller!.text, isEmpty);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'property Option+Left cannot move a stale document selection',
    (tester) async {
      const source = '''
---
title: Alpha
---
**bold**''';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 720,
              child: IanvsMarkdownLiveEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final input = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-title'),
      );
      controller.selection = const TextSelection.collapsed(
        offset: source.length,
      );
      await tester.tap(input);
      final field = tester.widget<TextField>(input);
      field.controller!.selection = const TextSelection.collapsed(
        offset: 'Alpha'.length,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(
        controller.selection,
        const TextSelection.collapsed(offset: source.length),
      );
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 0),
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'property Tab traversal never indents a stale document selection',
    (tester) async {
      const source = '''
---
title: Alpha
---
- one
    - two
''';
      const expected = '''
---
title: Beta
---
- one
    - two
''';

      for (final backwards in <bool>[false, true]) {
        final controller = IanvsMarkdownController(text: source);
        addTearDown(controller.dispose);
        await tester.pumpWidget(app(controller));
        await tester.pumpAndSettle();

        final input = find.byKey(
          const ValueKey('ianvs-markdown-front-matter-input-title'),
        );
        await tester.tap(input);
        await tester.enterText(input, 'Beta');
        controller.selection = TextSelection.collapsed(
          offset: source.indexOf('two') + 1,
        );

        if (backwards) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        if (backwards) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pumpAndSettle();

        expect(controller.text, expected, reason: 'backwards: $backwards');
        expect(controller.text, isNot(contains('        - two')));
        expect(controller.text, isNot(contains('\n- two')));
      }
    },
  );

  testWidgets('date property Tab stays local to its segmented input', (
    tester,
  ) async {
    const source = '''
---
due: 2026-08-28
---
- one
    - two
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final dayInput = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-date-day-due'),
    );
    await tester.tap(dayInput);
    await tester.enterText(dayInput, '27');
    controller.selection = TextSelection.collapsed(
      offset: source.indexOf('two') + 1,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(tester.widget<TextField>(dayInput).controller?.text, '27');
  });

  testWidgets('property keys rename in place and reject empty or duplicate', (
    tester,
  ) async {
    const source = '''
---
title: Alpha
count: 42
tags:
  - one
---
# Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final countInput = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-key-input-count'),
    );
    expect(countInput, findsOneWidget);
    await tester.tap(countInput);
    await tester.enterText(countInput, 'weight');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, '''
---
title: Alpha
weight: 42
tags:
  - one
---
# Body
''');
    final renamedEntry = parseMarkdownFrontMatter(
      controller.text,
    ).entries.firstWhere((entry) => entry.key == 'weight');
    expect(renamedEntry.type, MarkdownMetadataValueType.number);

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
    controller.redo();
    await tester.pumpAndSettle();

    final weightInput = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-key-input-weight'),
    );
    await tester.tap(weightInput);
    await tester.enterText(weightInput, 'pending');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, contains('weight: 42'));
    expect(tester.widget<TextField>(weightInput).controller?.text, 'weight');

    await tester.tap(weightInput);
    await tester.enterText(weightInput, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, contains('weight: 42'));
    expect(tester.widget<TextField>(weightInput).controller?.text, 'weight');

    await tester.tap(weightInput);
    await tester.enterText(weightInput, 'title');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, contains('weight: 42'));
    expect(tester.widget<TextField>(weightInput).controller?.text, 'weight');

    await tester.tap(weightInput);
    await tester.enterText(weightInput, 'Weight');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, contains('weight: 42'));
    expect(tester.widget<TextField>(weightInput).controller?.text, 'weight');

    await tester.tap(weightInput);
    await tester.enterText(weightInput, 'TITLE');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, contains('weight: 42'));
    expect(tester.widget<TextField>(weightInput).controller?.text, 'weight');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
  });

  testWidgets('date properties commit on Return while Tab keeps pending', (
    tester,
  ) async {
    const source = '''
---
title: Alpha
due: 2026-08-28
tags: [one, two]
---
# Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final dayInput = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-date-day-due'),
    );
    final pickerButton = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-date-picker-due'),
    );
    expect(dayInput, findsOneWidget);
    expect(pickerButton, findsOneWidget);

    await tester.tap(pickerButton);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(controller.text, source);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);

    await tester.tap(dayInput);
    await tester.enterText(dayInput, '27');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.text, source);
    expect(tester.widget<TextField>(dayInput).controller?.text, '27');

    await tester.tap(dayInput);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.text, '''
---
title: Alpha
due: 2026-08-27
tags:
  - one
  - two
---
# Body
''');
    final due = parseMarkdownFrontMatter(
      controller.text,
    ).entries.firstWhere((entry) => entry.key == 'due');
    expect(due.type, MarkdownMetadataValueType.date);

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
    controller.redo();
    await tester.pumpAndSettle();
    expect(controller.text, contains('due: 2026-08-27'));
  });

  testWidgets('number properties commit finite values and stay numeric', (
    tester,
  ) async {
    const source = '''
---
count: 42
tags: [one, two]
---
# Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-number-input-count'),
    );
    expect(input, findsOneWidget);
    await tester.tap(input);
    await tester.enterText(input, '43');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, '''
---
count: 43
tags:
  - one
  - two
---
# Body
''');
    expect(
      parseMarkdownFrontMatter(
        controller.text,
      ).entries.firstWhere((entry) => entry.key == 'count').type,
      MarkdownMetadataValueType.number,
    );

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
    controller.redo();
    await tester.pumpAndSettle();
    expect(controller.text, contains('count: 43'));

    await tester.tap(input);
    await tester.enterText(input, 'not-a-number');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, contains('count: 43'));
    expect(tester.widget<TextField>(input).controller?.text, '43');

    await tester.tap(input);
    await tester.enterText(input, '99');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, contains('count: 43'));
    expect(tester.widget<TextField>(input).controller?.text, '43');
  });

  testWidgets('tag properties remove to an empty key and add from empty', (
    tester,
  ) async {
    const source = '''
---
tags: [one, two]
aliases: [Alias One]
---
# Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('ianvs-markdown-front-matter-chip-remove-tags-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '''
---
tags:
  - one
aliases:
  - Alias One
---
# Body
''');

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
    controller.redo();
    await tester.pumpAndSettle();
    expect(controller.text, contains('  - one'));

    await tester.tap(
      find.byKey(
        const ValueKey('ianvs-markdown-front-matter-chip-remove-tags-0'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '''
---
tags:
aliases:
  - Alias One
---
# Body
''');

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-list-input-tags'),
    );
    expect(input, findsOneWidget);
    await tester.tap(input);
    await tester.enterText(input, 'three');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, '''
---
tags:
  - three
aliases:
  - Alias One
---
# Body
''');

    await tester.tap(input);
    await tester.enterText(input, 'pending');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, contains('  - three'));
    expect(tester.widget<TextField>(input).controller?.text, isEmpty);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
  });

  testWidgets('alias properties match Obsidian commits', (tester) async {
    const source = '''
---
title: Alpha
aliases: [Alias One, Alias Two]
tags: [one, two]
---
# Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('ianvs-markdown-front-matter-chip-remove-aliases-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '''
---
title: Alpha
aliases:
  - Alias One
tags:
  - one
  - two
---
# Body
''');

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, source);
    controller.redo();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('ianvs-markdown-front-matter-chip-remove-aliases-0'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '''
---
title: Alpha
aliases:
tags:
  - one
  - two
---
# Body
''');

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-list-input-aliases'),
    );
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).decoration?.hintText, '添加别名');
    await tester.tap(input);
    await tester.enterText(input, 'Alias Three');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, '''
---
title: Alpha
aliases:
  - Alias Three
tags:
  - one
  - two
---
# Body
''');

    await tester.tap(input);
    await tester.enterText(input, 'Alias Four');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, '''
---
title: Alpha
aliases:
  - Alias Three
  - Alias Four
tags:
  - one
  - two
---
# Body
''');

    final afterReturn = controller.text;
    await tester.tap(input);
    await tester.enterText(input, 'Alias Four');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, afterReturn);
    expect(tester.widget<TextField>(input).controller?.text, 'Alias Four');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, afterReturn);
    expect(tester.widget<TextField>(input).controller?.text, 'Alias Four');

    await tester.tap(input);
    await tester.enterText(input, '    ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, afterReturn);

    await tester.tap(input);
    await tester.enterText(input, '  Alias Escape  ');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, '''
---
title: Alpha
aliases:
  - Alias Three
  - Alias Four
  - Alias Escape
tags:
  - one
  - two
---
# Body
''');

    await tester.tap(input);
    await tester.enterText(input, 'Alias Blur');
    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-input-title')),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '''
---
title: Alpha
aliases:
  - Alias Three
  - Alias Four
  - Alias Escape
  - Alias Blur
tags:
  - one
  - two
---
# Body
''');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
  });

  testWidgets('pending aliases rebase onto an external front matter update', (
    tester,
  ) async {
    const source = '''
---
title: A
aliases:
---
Body
''';
    const updated = '''
---
title: Longer
aliases:
---
Body
''';
    const expected = '''
---
title: Longer
aliases:
  - Alias
---
Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-list-input-aliases'),
    );
    await tester.tap(input);
    await tester.enterText(input, 'Alias');
    controller.text = updated;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, expected);
  });

  testWidgets('pending aliases merge with an external alias update', (
    tester,
  ) async {
    const source = '''
---
aliases:
---
Body
''';
    const updated = '''
---
aliases:
  - External
---
Body
''';
    const expected = '''
---
aliases:
  - External
  - Pending
---
Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-list-input-aliases'),
    );
    await tester.tap(input);
    await tester.enterText(input, 'Pending');
    controller.text = updated;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, expected);
  });

  testWidgets('pending tags do not overwrite a recreated tags property', (
    tester,
  ) async {
    const source = '''
---
tags: [old]
---
Body
''';
    const updated = '''
---
other: x
tags: [fresh]
---
Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-list-input-tags'),
    );
    await tester.tap(input);
    await tester.enterText(input, 'pending');
    controller.text = updated;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, updated);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-chip-tags-0')),
      findsOneWidget,
    );
  });

  testWidgets('stale alias removal preserves an external alias addition', (
    tester,
  ) async {
    const source = '''
---
aliases: [A, B]
---
Body
''';
    const updated = '''
---
aliases: [A, B, C]
---
Body
''';
    const expected = '''
---
aliases:
  - B
  - C
---
Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final remove = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-chip-remove-aliases-0'),
    );
    controller.text = updated;
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(controller.text, expected);
  });

  testWidgets('pending text does not overwrite the same external property', (
    tester,
  ) async {
    const source = '''
---
title: A
---
Body
''';
    const updated = '''
---
title: External
---
Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-input-title'),
    );
    await tester.tap(input);
    await tester.enterText(input, 'Local');
    controller.text = updated;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, updated);
    expect(tester.widget<TextField>(input).controller?.text, 'External');
  });

  testWidgets('pending text preserves an unrelated external property', (
    tester,
  ) async {
    const source = '''
---
title: A
---
Body
''';
    const updated = '''
---
title: A
other: x
---
Body
''';
    const expected = '''
---
title: Local
other: x
---
Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final input = find.byKey(
      const ValueKey('ianvs-markdown-front-matter-input-title'),
    );
    await tester.tap(input);
    await tester.enterText(input, 'Local');
    controller.text = updated;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, expected);
  });

  testWidgets('lossy typed tag lists remain presentation-only', (tester) async {
    const source = '''
---
tags: [one, 2]
---
# Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-list-input-tags')),
      findsNothing,
    );
    expect(controller.text, source);
  });

  testWidgets('editable properties retain Wiki and URL link callbacks', (
    tester,
  ) async {
    const source = '''
---
title: Alpha
wiki: "[[Target Note]]"
url: https://example.com/path
---
# Body
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    final taps = <(String, String?)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              onTapLink: (text, href, title) => taps.add((text, href)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-input-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-input-wiki')),
      findsNothing,
    );
    await tester.tap(find.text('Target Note'));
    await tester.tap(find.text('https://example.com/path'));
    await tester.pumpAndSettle();

    expect(taps, <(String, String?)>[
      ('Target Note', 'Target Note'),
      ('https://example.com/path', 'https://example.com/path'),
    ]);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
  });

  testWidgets('live preview edits one list item without flattening neighbors', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '- [x] Done\n- [ ] Open\n  - Nested',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = find.descendant(of: active, matching: find.byType(TextField));
    expect(tester.widget<TextField>(field).controller?.text, '- [ ] Open');
    expect(
      find.descendant(
        of: active,
        matching: find.byType(IanvsMarkdownTaskCheckbox),
      ),
      findsOneWidget,
    );
    final activeField = tester.widget<TextField>(field);
    final activeSpan = activeField.controller!.buildTextSpan(
      context: tester.element(field),
      style: activeField.style,
      withComposing: false,
    );
    expect(activeSpan.toPlainText(), '- [ ] Open');
    final hiddenPrefix = activeSpan.children!.first as TextSpan;
    expect(hiddenPrefix.text, '- [ ] ');
    expect(hiddenPrefix.style?.fontSize, 4);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Nested'), findsOneWidget);
  });

  testWidgets('loose list child blocks stay inside their editable item', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '- Parent\n\n  continuation\n\n- Sibling',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('continuation'));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = find.descendant(of: active, matching: find.byType(TextField));
    expect(
      tester.widget<TextField>(field).controller?.text,
      '- Parent\n\n  continuation',
    );
    expect(find.text('Sibling'), findsOneWidget);
  });

  testWidgets('blank-separated nested list items retain their depth', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '- [ ] Parent\n\n  - [ ] Child',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final checkboxes = find.byType(IanvsMarkdownTaskCheckbox);
    expect(checkboxes, findsNWidgets(2));
    final parent = tester.getCenter(checkboxes.at(0));
    final child = tester.getCenter(checkboxes.at(1));
    expect(child.dx - parent.dx, closeTo(28, .01));
  });

  testWidgets(
    'nested Live Preview lists keep 28px steps and connected guides',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: '- [!] Parent\n  - [b] Nested\n- [ ] Sibling',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      List<Offset> checkboxCenters() => tester
          .widgetList<IanvsMarkdownTaskCheckbox>(
            find.byType(IanvsMarkdownTaskCheckbox),
          )
          .map((checkbox) => tester.getCenter(find.byWidget(checkbox)))
          .toList();

      var centers = checkboxCenters();
      expect(centers, hasLength(3));
      expect(centers[1].dx - centers[0].dx, closeTo(28, .01));
      expect(centers[2].dx, closeTo(centers[0].dx, .01));

      final surface = tester.renderObject<IanvsMarkdownListGuideRenderBox>(
        find.byKey(const ValueKey('ianvs-markdown-live-list-guides')),
      );
      var segments = surface.debugGuideSegments();
      expect(segments, isNotEmpty);
      expect(
        segments.every((segment) => segment.end.dy < centers[2].dy),
        isTrue,
      );

      await tester.tap(find.text('Parent'));
      await tester.pump();

      final rail = find.byKey(
        const ValueKey('ianvs-markdown-active-line-rail'),
      );
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      expect(rail, findsOneWidget);
      expect(tester.getSize(rail).width, 2);
      expect(
        tester.getSize(rail).height,
        lessThan(tester.getSize(active).height),
      );
      final railDecoration = tester
          .widget<Container>(
            find.descendant(of: rail, matching: find.byType(Container)).first,
          )
          .decoration;
      expect(
        (railDecoration as BoxDecoration).color,
        IanvsMarkdownThemeData.light.accent,
      );
      final parentRailX = tester.getTopLeft(rail).dx;

      centers = checkboxCenters();
      expect(centers[1].dx - centers[0].dx, closeTo(28, .01));
      segments = surface.debugGuideSegments();
      expect(segments, isNotEmpty);

      await tester.tap(find.text('Nested'));
      await tester.pump();

      expect(tester.getTopLeft(rail).dx, closeTo(parentRailX, .01));
      expect(tester.getTopLeft(rail).dx, lessThan(checkboxCenters().first.dx));
      expect(controller.text, '- [!] Parent\n  - [b] Nested\n- [ ] Sibling');
    },
  );

  testWidgets('active list rail follows the caret across visual wraps', (
    tester,
  ) async {
    const source =
        '- [ ] Parent\n'
        '  - [ ] Alpha bravo charlie delta echo foxtrot golf hotel india';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 480,
            child: IanvsMarkdownLiveEditor(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Alpha bravo'));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    final blockSource = field.controller!.text;
    field.controller!.selection = TextSelection.collapsed(
      offset: blockSource.length,
    );
    await tester.pumpAndSettle();

    final rail = find.byKey(const ValueKey('ianvs-markdown-active-line-rail'));
    final editable = editableWithin(tester, fieldFinder);
    final caretRect = editable.getLocalRectForCaret(
      TextPosition(offset: blockSource.length),
    );
    final caretTop = editable.localToGlobal(caretRect.topLeft).dy;
    expect(tester.getTopLeft(rail).dy, closeTo(caretTop, 1));
    expect(
      tester.getTopLeft(rail).dy,
      greaterThan(tester.getTopLeft(active).dy + 20),
    );
    expect(controller.text, source);
  });

  testWidgets('active list rail stays at the logical page start in RTL', (
    tester,
  ) async {
    const source = '- [ ] Parent\n  - [ ] Nested';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 600,
              height: 480,
              child: IanvsMarkdownLiveEditor(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialCenters = tester
        .widgetList<IanvsMarkdownTaskCheckbox>(
          find.byType(IanvsMarkdownTaskCheckbox),
        )
        .map((checkbox) => tester.getCenter(find.byWidget(checkbox)))
        .toList();
    expect(initialCenters[0].dx - initialCenters[1].dx, closeTo(28, .01));

    await tester.tap(find.text('Parent'));
    await tester.pump();
    final rail = find.byKey(const ValueKey('ianvs-markdown-active-line-rail'));
    final parentRailRight = tester.getTopRight(rail).dx;

    await tester.tap(find.text('Nested'));
    await tester.pump();
    expect(tester.getTopRight(rail).dx, closeTo(parentRailRight, .01));
    expect(tester.getTopRight(rail).dx, greaterThan(initialCenters.first.dx));
    expect(controller.text, source);
  });

  testWidgets('active lists stay visual and quotes collapse outer prefixes', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text:
          '- Alpha\n- Beta\n\n1. First\n2. Second\n\n> Quote line\n> Continued',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    TextSpan activeSpan() {
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      final field = tester.widget<TextField>(fieldFinder);
      return field.controller!.buildTextSpan(
        context: tester.element(fieldFinder),
        style: field.style,
        withComposing: false,
      );
    }

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    var prefix = activeSpan().children!.first as TextSpan;
    expect(prefix.text, '- ');
    expect(prefix.style?.color, Colors.transparent);
    expect(
      tester
          .widget<IanvsMarkdownUnorderedListMarker>(
            find.descendant(
              of: find.byKey(
                const ValueKey('ianvs-markdown-active-list-marker'),
              ),
              matching: find.byType(IanvsMarkdownUnorderedListMarker),
            ),
          )
          .shape,
      IanvsMarkdownUnorderedListMarkerShape.circle,
    );

    await tester.tap(find.text('First'));
    await tester.pump();
    prefix = activeSpan().children!.first as TextSpan;
    expect(prefix.text, '1. ');
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(
                const ValueKey('ianvs-markdown-active-list-marker'),
              ),
              matching: find.byType(Text),
            ),
          )
          .data,
      '1.',
    );

    final renderedQuote = find.ancestor(
      of: find.textContaining('Quote line'),
      matching: find.bySemanticsLabel('Edit Markdown block'),
    );
    expect(renderedQuote, findsOneWidget);
    final quoteRect = tester.getRect(renderedQuote);
    await tester.tapAt(Offset(quoteRect.left + 20, quoteRect.top + 4));
    await tester.pump();
    final quoteSpan = activeSpan();
    expect(quoteSpan.toPlainText(), '> Quote line\n> Continued');
    final collapsedQuotePrefixes = quoteSpan.children!
        .whereType<TextSpan>()
        .where(
          (span) =>
              span.text == '> ' && span.style?.color == Colors.transparent,
        )
        .toList();
    expect(collapsedQuotePrefixes, hasLength(1));
    expect(
      collapsedQuotePrefixes.every((span) => span.style?.fontSize == 0),
      isTrue,
    );
    expect(
      controller.selection.extentOffset,
      lessThanOrEqualTo(
        controller.text.indexOf('\n', controller.text.indexOf('> Quote')),
      ),
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-quote-rail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-quote-rails')),
      findsOneWidget,
    );
    final quoteRail = tester.widget<Container>(
      find.byKey(const ValueKey('ianvs-markdown-active-quote-rail')),
    );
    expect(
      (quoteRail.decoration! as BoxDecoration).color,
      IanvsMarkdownThemeData.light.accent,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('ianvs-markdown-active-quote-rail')),
          )
          .width,
      3,
    );
    final quotePattern = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('ianvs-markdown-active-quote-pattern')),
    );
    final quotePatternPainter =
        quotePattern.painter! as IanvsMarkdownCodePatternPainter;
    expect(quotePatternPainter.color, Colors.black.withValues(alpha: .12));
    final active = tester.widget<Container>(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
    );
    expect(
      (active.decoration! as BoxDecoration).color,
      IanvsMarkdownThemeData.light.surface,
    );
    expect(
      (active.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(4),
    );
    expect(active.clipBehavior, Clip.antiAlias);
  });

  testWidgets(
    'nested quote focus keeps inactive markers hidden and paints rails',
    (tester) async {
      const source = '> Outer\n> > Nested\n> Outer tail';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final renderedQuote = find.bySemanticsLabel('Edit Markdown block');
      expect(renderedQuote, findsOneWidget);
      await tester.tapAt(tester.getRect(renderedQuote).center);
      await tester.pump();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      final field = tester.widget<TextField>(fieldFinder);
      final span = field.controller!.buildTextSpan(
        context: tester.element(fieldFinder),
        style: field.style,
        withComposing: false,
      );
      final leaves = _textSpanLeaves(span).toList();
      final hiddenPrefixes = leaves
          .where((child) => child.text == '> ' && child.style?.color?.a == 0)
          .toList();
      expect(hiddenPrefixes, hasLength(2));
      expect(
        hiddenPrefixes.every((child) => child.style?.fontSize == 0),
        isTrue,
      );
      final visibleNestedMarkerCharacters = leaves
          .where(
            (child) => child.style?.fontSize != 0 && child.style?.color?.a != 0,
          )
          .fold<int>(
            0,
            (count, child) => count + '>'.allMatches(child.text ?? '').length,
          );
      expect(visibleNestedMarkerCharacters, 2);
      final firstBreak = source.indexOf('\n');
      final nestedLineEnd = source.indexOf('\n', firstBreak + 1);
      expect(controller.selection.extentOffset, nestedLineEnd);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-quote-rails')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('ianvs-markdown-active-quote-rails')),
            )
            .painter,
        isNotNull,
      );
    },
  );

  testWidgets(
    'spaced nested quote markers stay hidden away from the active line',
    (tester) async {
      const source = '> Outer\n>   > Nested\n> Outer tail';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final renderedQuote = find.bySemanticsLabel('Edit Markdown block');
      final quoteRect = tester.getRect(renderedQuote);
      await tester.tapAt(Offset(quoteRect.center.dx, quoteRect.bottom - 15));
      await tester.pump();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      final field = tester.widget<TextField>(fieldFinder);
      final span = field.controller!.buildTextSpan(
        context: tester.element(fieldFinder),
        style: field.style,
        withComposing: false,
      );
      final visibleMarkerCharacters = _textSpanLeaves(span)
          .where(
            (child) => child.style?.fontSize != 0 && child.style?.color?.a != 0,
          )
          .fold<int>(
            0,
            (count, child) => count + '>'.allMatches(child.text ?? '').length,
          );

      expect(
        controller.selection.extentOffset,
        greaterThan(source.lastIndexOf('> Outer tail')),
      );
      expect(visibleMarkerCharacters, 1);
    },
  );

  testWidgets('quote activation follows the rendered horizontal tap', (
    tester,
  ) async {
    const source = '> Alpha bravo charlie';

    Future<int> activateAt(double horizontalOffset) async {
      final controller = IanvsMarkdownController(text: source);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final quote = find.bySemanticsLabel('Edit Markdown block');
      final rect = tester.getRect(quote);
      await tester.tapAt(Offset(rect.left + horizontalOffset, rect.center.dy));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-block')),
        findsOneWidget,
      );
      final offset = controller.selection.extentOffset;
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      return offset;
    }

    final leftOffset = await activateAt(64);
    final rightOffset = await activateAt(190);

    expect(leftOffset, greaterThanOrEqualTo(2));
    expect(rightOffset, greaterThan(leftOffset));
    expect(rightOffset, lessThanOrEqualTo(source.length));
  });

  testWidgets('quote clicks map visible text to the exact source offset', (
    tester,
  ) async {
    const source = 'Before\n\n> Alpha bravo\n> Charlie delta\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final preview = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data ?? widget.textSpan?.toPlainText() ?? '').contains(
            'Alpha bravo',
          ),
    );
    final editable = editableWithin(tester, preview);
    const visibleOffset = 8;
    final target = editable.localToGlobal(
      editable
          .getLocalRectForCaret(const TextPosition(offset: visibleOffset))
          .center,
    );
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(
      controller.selection,
      TextSelection.collapsed(
        offset: source.indexOf('Alpha bravo') + visibleOffset,
      ),
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('quote multi-click restores its raw marker line', (tester) async {
    const source = 'Before\n\n> Alpha bravo\n> Charlie delta\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final preview = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data ?? widget.textSpan?.toPlainText() ?? '').contains(
            'Alpha bravo',
          ),
    );
    final editable = editableWithin(tester, preview);
    final target = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 8)).center,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'bravo');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), '> Alpha bravo');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('lazy quote continuations edit as one Obsidian block', (
    tester,
  ) async {
    const quote =
        '> Quoted first line\n'
        'Lazy continuation without a marker\n'
        '> Explicit quoted tail';
    final controller = IanvsMarkdownController(text: '$quote\n\nAfter quote.');
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Lazy continuation without a marker'));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-quote-rail')),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, quote);
    expect(controller.text, '$quote\n\nAfter quote.');
    expect(find.text('After quote.'), findsOneWidget);
  });

  testWidgets('code-indented lazy quote lines edit as paragraph source', (
    tester,
  ) async {
    const quote =
        '> Paragraph before indentation\n'
        '    lazy code-looking continuation\n'
        '> Explicit quoted tail';
    final controller = IanvsMarkdownController(text: '$quote\n\nOutside.');
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('lazy code-looking continuation'),
      findsOneWidget,
    );
    await tester.tap(find.textContaining('lazy code-looking continuation'));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, quote);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-quote-rail')),
      findsOneWidget,
    );
    expect(controller.text, '$quote\n\nOutside.');
  });

  testWidgets('live preview continues compact block quotes', (tester) async {
    final controller = IanvsMarkdownController(text: '>quote')
      ..selection = const TextSelection.collapsed(offset: 6);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '>quote\n',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '>quote\n> ');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));
  });

  testWidgets('live preview exits nested quotes one layer at a time', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '> > child')
      ..selection = const TextSelection.collapsed(offset: 9);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '> > child\n',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '> > child\n> > ');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '> > child\n> > \n',
        selection: TextSelection.collapsed(offset: 15),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '> > child\n> ');
    expect(controller.selection, const TextSelection.collapsed(offset: 12));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '> > child\n> \n',
        selection: TextSelection.collapsed(offset: 13),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '> > child\n\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 11));
  });

  testWidgets('callouts render, expand, and enter exact block source editing', (
    tester,
  ) async {
    const source =
        '> [!warning]- Folded warning\n'
        '> Hidden ==highlighted== body.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-callout-warning')),
      findsOneWidget,
    );
    final warning = find.byKey(
      const ValueKey('ianvs-markdown-callout-warning'),
    );
    final warningToggle = find.byKey(
      const ValueKey('ianvs-markdown-callout-toggle-warning'),
    );
    expect(tester.getSize(warning).height, 42);
    expect(tester.getSize(warningToggle).height, 42);
    final collapsedDecoration =
        tester.widget<AnimatedContainer>(warning).decoration! as BoxDecoration;
    expect(collapsedDecoration.border, isNull);
    expect(
      collapsedDecoration.borderRadius,
      BorderRadius.circular(IanvsMarkdownThemeData.light.smallRadius / 2),
    );
    expect(
      collapsedDecoration.color,
      IanvsMarkdownThemeData.light.taskStatusOrange.withValues(alpha: .09),
    );
    expect(
      find.descendant(
        of: warning,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints == const BoxConstraints.tightFor(width: 3),
        ),
      ),
      findsNothing,
    );
    expect(find.textContaining('Hidden'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-callout-toggle-warning')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Hidden'), findsOneWidget);
    final warningBody = find.byKey(
      const ValueKey('ianvs-markdown-callout-body-warning'),
    );
    expect(tester.getSize(warning).height, 90);
    expect(tester.getSize(warningToggle).height, 35);
    expect(tester.getSize(warningBody).height, 55);
    expect(
      tester.widget<Padding>(warningBody).padding,
      const EdgeInsets.fromLTRB(20, 12, 20, 20),
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );

    await tester.tap(find.textContaining('Hidden'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-quote-rail')),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(controller.text, source);
    final span = field.controller!.buildTextSpan(
      context: tester.element(
        find.descendant(of: active, matching: find.byType(TextField)),
      ),
      style: field.style,
      withComposing: false,
    );
    final visibleMarkers = span.children!
        .whereType<TextSpan>()
        .where(
          (child) =>
              child.text == '> ' &&
              child.style?.fontSize != 0 &&
              child.style?.color != Colors.transparent,
        )
        .toList();
    expect(visibleMarkers, hasLength(2));
  });

  testWidgets('Unicode callout types keep every marker visible when active', (
    tester,
  ) async {
    const source = '> [!注意] Unicode callout\n> Exact body';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-callout-注意')),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('Exact body'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    final span = field.controller!.buildTextSpan(
      context: tester.element(fieldFinder),
      style: field.style,
      withComposing: false,
    );
    final visibleMarkerCharacters = _textSpanLeaves(span)
        .where(
          (child) => child.style?.fontSize != 0 && child.style?.color?.a != 0,
        )
        .fold<int>(
          0,
          (count, child) => count + '>'.allMatches(child.text ?? '').length,
        );

    expect(field.controller?.text, source);
    expect(visibleMarkerCharacters, 2);
  });

  testWidgets(
    'lazy callout continuation stays rendered and edits exact source',
    (tester) async {
      const source =
          '> [!note] **Lazy callout**\n'
          '> Quoted body\n'
          'Unmarked lazy body\n'
          '> Quoted tail';
      final controller = IanvsMarkdownController(text: '$source\n\nOutside.');
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final callout = find.byKey(const ValueKey('ianvs-markdown-callout-note'));
      expect(callout, findsOneWidget);
      expect(
        find.descendant(
          of: callout,
          matching: find.textContaining('Unmarked lazy body'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.textContaining('Unmarked lazy body'));
      await tester.pump();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      final field = tester.widget<TextField>(fieldFinder);
      expect(field.controller?.text, source);
      final span = field.controller!.buildTextSpan(
        context: tester.element(fieldFinder),
        style: field.style,
        withComposing: false,
      );
      final visibleMarkers = span.children!
          .whereType<TextSpan>()
          .where(
            (child) =>
                child.text == '> ' &&
                child.style?.fontSize != 0 &&
                child.style?.color != Colors.transparent,
          )
          .toList();
      expect(visibleMarkers, hasLength(3));
      expect(find.text('Outside.'), findsOneWidget);
      expect(controller.text, '$source\n\nOutside.');
    },
  );

  testWidgets('callouts keep four-space lazy continuations in one card', (
    tester,
  ) async {
    const source =
        '> [!note] Four-space boundary\n'
        '> before\n'
        '    lazy code-looking\n'
        '> after';
    final controller = IanvsMarkdownController(text: '$source\n\nOutside.');
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final callout = find.byKey(const ValueKey('ianvs-markdown-callout-note'));
    expect(callout, findsOneWidget);
    expect(
      find.descendant(
        of: callout,
        matching: find.textContaining('lazy code-looking'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('lazy code-looking'));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(find.text('Outside.'), findsOneWidget);
    expect(controller.text, '$source\n\nOutside.');
  });

  testWidgets('callout lazy paragraphs ignore non-interrupting list markers', (
    tester,
  ) async {
    const source =
        '> [!note] List interruption\n'
        '> paragraph\n'
        '2. item\n'
        '> tail';
    final controller = IanvsMarkdownController(text: '$source\n\nOutside.');
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final callout = find.byKey(const ValueKey('ianvs-markdown-callout-note'));
    expect(callout, findsOneWidget);
    expect(
      find.descendant(of: callout, matching: find.textContaining('2. item')),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('2. item'));
    await tester.pumpAndSettle();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(find.text('Outside.'), findsOneWidget);
  });

  testWidgets('Wiki embeds render and enter exact block source editing', (
    tester,
  ) async {
    const source = '![[Target Note#Section A|Section alias]]';
    final controller = IanvsMarkdownController(text: source);
    String? openedHref;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              wikiEmbedBuilder: (context, reference) => IanvsMarkdown(
                data: '## Embedded ${reference.note}: ${reference.subpath}',
              ),
              onTapLink: (text, href, title) => openedHref = href,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IanvsMarkdownWikiEmbed), findsOneWidget);
    expect(find.text('Embedded Target Note: Section A'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-standalone-heading-rail-2')),
      findsOneWidget,
    );
    expect(find.textContaining('![['), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-wiki-embed-open')),
    );
    await tester.pump();
    expect(openedHref, 'Target Note#Section A');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-wiki-embed-tap-target')),
    );
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    expect(find.byType(IanvsMarkdownWikiEmbed), findsOneWidget);
    expect(find.text('Embedded Target Note: Section A'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(controller.text, source);
  });

  testWidgets('Wiki links preserve live labels and format reading labels', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '[[Target Note#Section A]] and [[Missing Note]].',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              wikiLinkExists: (target) => !target.startsWith('Missing Note'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Target Note#Section A'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-wiki-link-unresolved')),
      findsOneWidget,
    );

    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();

    expect(find.text('Target Note > Section A'), findsOneWidget);
    expect(find.text('Target Note#Section A'), findsNothing);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-wiki-link-unresolved')),
      findsOneWidget,
    );
  });

  testWidgets('display math preserves its preview while editing exact source', (
    tester,
  ) async {
    const source = r'''
Inline $E = mc^2$ after.

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              mathBuilder: (context, expression, {required displayMode}) =>
                  Text('${displayMode ? 'display' : 'inline'}:$expression'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final formula = find.text(r'display:\int_0^1 x^2\,dx = \frac{1}{3}');
    expect(formula, findsOneWidget);
    await tester.tap(formula);
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    expect(formula, findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)).first,
    );
    expect(field.controller?.text, r'''$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$''');
    expect(controller.text, source);
  });

  testWidgets(
    'active inline code keeps compact mono styling and visible markers',
    (tester) async {
      const source = 'Before `inline code` after.';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Before').first);
      await tester.pump();
      final fieldFinder = find.descendant(
        of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
        matching: find.byType(TextField),
      );
      final field = tester.widget<TextField>(fieldFinder);

      TextSpan span() => field.controller!.buildTextSpan(
        context: tester.element(fieldFinder),
        style: field.style,
        withComposing: false,
      );

      field.controller!.selection = TextSelection.collapsed(
        offset: source.length,
      );
      await tester.pump();
      var leaves = _textSpanLeaves(span()).toList();
      var code = leaves.singleWhere((leaf) => leaf.text == 'inline code');
      expect(
        code.style?.fontFamily,
        IanvsMarkdownThemeData.light.monoFontFamily,
      );
      expect(code.style?.fontSize, 12);
      expect(code.style?.height, 1.35);
      expect(
        code.style?.color,
        IanvsMarkdownThemeData.light.inlineCodeForeground,
      );
      expect(
        code.style?.backgroundColor,
        IanvsMarkdownThemeData.light.surfaceHover,
      );
      var markers = leaves.where((leaf) => leaf.text == '`').toList();
      expect(markers, hasLength(2));
      expect(markers.every((leaf) => leaf.style?.fontSize != .01), isTrue);
      expect(
        markers.every(
          (leaf) =>
              leaf.style?.color ==
              IanvsMarkdownThemeData.light.inlineCodeForeground,
        ),
        isTrue,
      );

      field.controller!.selection = TextSelection.collapsed(
        offset: source.indexOf('code'),
      );
      await tester.pump();
      leaves = _textSpanLeaves(span()).toList();
      code = leaves.singleWhere((leaf) => leaf.text == 'inline code');
      expect(
        code.style?.fontFamily,
        IanvsMarkdownThemeData.light.monoFontFamily,
      );
      markers = leaves.where((leaf) => leaf.text == '`').toList();
      expect(markers.every((leaf) => leaf.style?.fontSize != .01), isTrue);
      expect(
        markers.every(
          (leaf) =>
              leaf.style?.color ==
              IanvsMarkdownThemeData.light.inlineCodeForeground,
        ),
        isTrue,
      );
      expect(controller.text, source);
    },
  );

  testWidgets('multiline emphasis keeps theme colors and line-local markers', (
    tester,
  ) async {
    const source =
        'Strong **strong one\nstrong two** tail and '
        'italic *italic one\nitalic two*.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    bool renderedHasColor(String text, Color color) =>
        tester
            .widgetList<RichText>(find.byType(RichText))
            .any(
              (widget) =>
                  _spanContainsColor(widget.text, text: text, color: color),
            ) ||
        tester
            .widgetList<Text>(find.byType(Text))
            .any(
              (widget) =>
                  widget.textSpan != null &&
                  _spanContainsColor(
                    widget.textSpan!,
                    text: text,
                    color: color,
                  ),
            ) ||
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .any(
              (widget) =>
                  widget.textSpan != null &&
                  _spanContainsColor(
                    widget.textSpan!,
                    text: text,
                    color: color,
                  ),
            );
    expect(
      renderedHasColor(
        'strong one\nstrong two',
        IanvsMarkdownThemeData.light.strongForeground,
      ),
      isTrue,
    );
    expect(
      renderedHasColor(
        'italic one\nitalic two',
        IanvsMarkdownThemeData.light.emphasisForeground,
      ),
      isTrue,
    );

    await tester.tap(find.textContaining('Strong').first);
    await tester.pump();
    final fieldFinder = find.descendant(
      of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);

    List<TextSpan> leaves() => _textSpanLeaves(
      field.controller!.buildTextSpan(
        context: tester.element(fieldFinder),
        style: field.style,
        withComposing: false,
      ),
    ).toList();

    field.controller!.selection = TextSelection.collapsed(
      offset: source.indexOf('strong one'),
    );
    await tester.pump();
    var spans = leaves();
    final strongContent = spans.singleWhere(
      (span) => span.text == 'strong one\nstrong two',
    );
    expect(strongContent.style?.fontWeight, FontWeight.w600);
    expect(
      strongContent.style?.color,
      IanvsMarkdownThemeData.light.strongForeground,
    );
    var strongMarkers = spans.where((span) => span.text == '**').toList();
    expect(strongMarkers, hasLength(2));
    expect(strongMarkers.first.style?.fontSize, isNot(.01));
    expect(strongMarkers.last.style?.fontSize, .01);
    expect(
      strongMarkers.first.style?.color,
      IanvsMarkdownThemeData.light.strongForeground,
    );

    field.controller!.selection = TextSelection.collapsed(
      offset: source.indexOf('strong two'),
    );
    await tester.pump();
    spans = leaves();
    strongMarkers = spans.where((span) => span.text == '**').toList();
    expect(strongMarkers.first.style?.fontSize, .01);
    expect(strongMarkers.last.style?.fontSize, isNot(.01));

    field.controller!.selection = TextSelection.collapsed(
      offset: source.indexOf('italic one'),
    );
    await tester.pump();
    spans = leaves();
    final italicContent = spans.singleWhere(
      (span) => span.text == 'italic one\nitalic two',
    );
    expect(italicContent.style?.fontStyle, FontStyle.italic);
    expect(
      italicContent.style?.color,
      IanvsMarkdownThemeData.light.emphasisForeground,
    );
    var italicMarkers = spans.where((span) => span.text == '*').toList();
    expect(italicMarkers, hasLength(2));
    expect(italicMarkers.first.style?.fontSize, isNot(.01));
    expect(italicMarkers.last.style?.fontSize, .01);
    expect(
      italicMarkers.first.style?.color,
      IanvsMarkdownThemeData.light.emphasisForeground,
    );

    field.controller!.selection = TextSelection.collapsed(
      offset: source.indexOf('italic two'),
    );
    await tester.pump();
    italicMarkers = leaves().where((span) => span.text == '*').toList();
    expect(italicMarkers.first.style?.fontSize, .01);
    expect(italicMarkers.last.style?.fontSize, isNot(.01));
    expect(controller.text, source);
  });

  testWidgets('inline math reveals delimiters only when the caret enters it', (
    tester,
  ) async {
    const source = r'Inline $E = mc^2$ after.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              mathBuilder: (context, expression, {required displayMode}) =>
                  Text('formula:$expression'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Inline').first);
    await tester.pump();
    expect(find.text('formula:E = mc^2'), findsOneWidget);
    final fieldFinder = find.descendant(
      of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);

    TextSpan span() => field.controller!.buildTextSpan(
      context: tester.element(fieldFinder),
      style: field.style,
      withComposing: false,
    );

    field.controller!.selection = TextSelection.collapsed(
      offset: source.length,
    );
    await tester.pump();
    var delimiters = _textSpanLeaves(
      span(),
    ).where((leaf) => leaf.text == r'$').toList();
    expect(delimiters, hasLength(2));
    expect(delimiters.every((leaf) => leaf.style?.fontSize == 0), isTrue);
    expect(find.text('formula:E = mc^2'), findsOneWidget);

    field.controller!.selection = TextSelection.collapsed(
      offset: source.indexOf('mc'),
    );
    await tester.pump();
    expect(find.text('formula:E = mc^2'), findsNothing);
    delimiters = _textSpanLeaves(
      span(),
    ).where((leaf) => leaf.text == r'$').toList();
    expect(delimiters.every((leaf) => leaf.style?.fontSize != .01), isTrue);
    expect(controller.text, source);
  });

  testWidgets('inline math clicks preserve Obsidian source selections', (
    tester,
  ) async {
    const line = r'Alpha $bravo + charlie$ omega';
    const source = 'Before\n\n$line\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              mathBuilder: (context, expression, {required displayMode}) =>
                  Text(
                    expression,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14.5,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Alpha').first);
    await tester.pumpAndSettle();
    final formula = find.text('bravo + charlie');
    expect(formula, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(formula);
    final caret = paragraph.getOffsetForCaret(
      const TextPosition(offset: 2),
      Rect.zero,
    );
    final target = paragraph.localToGlobal(
      caret + Offset(.1, paragraph.size.height / 2),
    );

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, 17);
    expect(formula, findsNothing);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'bravo');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), line);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('inline HTML clicks preserve Obsidian source selections', (
    tester,
  ) async {
    const line = 'Alpha <u>bravo charlie</u> omega';
    const source = 'Before\n\n$line\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final paragraphFinder = selectableTextWithPlainText(
      'Alpha bravo charlie omega',
    );
    expect(paragraphFinder, findsOneWidget);
    final paragraph = editableWithin(tester, paragraphFinder);
    final target = paragraph.localToGlobal(
      paragraph.getLocalRectForCaret(const TextPosition(offset: 8)).center,
    );

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, 19);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'bravo');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), line);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('inactive inline math keeps list source prefixes collapsed', (
    tester,
  ) async {
    const source = r'- Alpha $x + y$ omega';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              mathBuilder: (context, expression, {required displayMode}) =>
                  Text('formula:$expression'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Alpha').first);
    await tester.pumpAndSettle();

    final fieldFinder = find.descendant(
      of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    final leaves = _textSpanLeaves(
      field.controller!.buildTextSpan(
        context: tester.element(fieldFinder),
        style: field.style,
        withComposing: false,
      ),
    );
    final prefix = leaves.singleWhere((leaf) => leaf.text == '- ');
    expect(prefix.style?.fontSize, 4);
    expect(prefix.style?.color, Colors.transparent);
    expect(find.text('formula:x + y'), findsOneWidget);
    expect(controller.text, source);
  });

  testWidgets('live preview keeps inactive footnote markers as exact source', (
    tester,
  ) async {
    const source = '''
# Metadata

Visible %%secret%% after. ^block-id

Standard[^note] and inline ^[inline body].

[^note]: Definition with **bold**.
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.text('%%secret%%'), findsOneWidget);
    expect(selectableTextContainingPlainText('^block-id'), findsOneWidget);
    expect(find.text('[^note]'), findsOneWidget);
    expect(find.text('^[inline body]'), findsOneWidget);
    expect(find.text('1.'), findsNothing);
    expect(find.textContaining('Definition with'), findsOneWidget);
    expect(find.textContaining('[^note]:'), findsNothing);

    await tester.tap(find.text('[^note]'));
    await tester.pump();
    var active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(
      field.controller?.text,
      'Standard[^note] and inline ^[inline body].',
    );
    expect(controller.text, source);

    await tester.tap(find.text('%%secret%%'));
    await tester.pump();
    active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'Visible %%secret%% after. ^block-id');
  });

  testWidgets('footnote marker clicks preserve Obsidian source selections', (
    tester,
  ) async {
    const source = 'Before[^note] after.\n\n[^note]: Definition.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final marker = find.text('[^note]');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: marker, matching: find.byType(RichText)),
    );
    const markerOffset = 4;
    final caret = paragraph.getOffsetForCaret(
      const TextPosition(offset: markerOffset),
      Rect.zero,
    );
    final target = paragraph.localToGlobal(
      caret + Offset(.1, paragraph.size.height / 2),
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.isCollapsed, isTrue);
    expect(
      controller.selection.extentOffset,
      source.indexOf('[^note]') + markerOffset,
    );

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'note');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), 'Before[^note] after.');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('footnote definition clicks map its projection to source', (
    tester,
  ) async {
    const source = 'Before[^note] after.\n\n[^note]: Definition text.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final preview = find.text('note Definition text.');
    final editable = editableWithin(tester, preview);
    const bodyOffset = 8;
    const visibleOffset = 5 + bodyOffset;
    final target = editable.localToGlobal(
      editable
          .getLocalRectForCaret(const TextPosition(offset: visibleOffset))
          .center,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    final expectedOffset = source.indexOf('Definition') + bodyOffset;
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, expectedOffset);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'Definition');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(
      controller.selection.textInside(source),
      '[^note]: Definition text.',
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('footnote definition drag maps its projected body to source', (
    tester,
  ) async {
    const source = 'Before[^note] after.\n\n[^note]: Definition text.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final editable = editableWithin(tester, find.text('note Definition text.'));
    const visibleBodyStart = 5;
    const sourceStart = 2;
    const sourceEnd = 11;
    final start = editable.localToGlobal(
      editable
          .getLocalRectForCaret(
            const TextPosition(offset: visibleBodyStart + sourceStart),
          )
          .center,
    );
    final end = editable.localToGlobal(
      editable
          .getLocalRectForCaret(
            const TextPosition(offset: visibleBodyStart + sourceEnd),
          )
          .center,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pumpAndSettle();
    await mouse.up();
    await tester.pumpAndSettle();

    final bodyStart = source.indexOf('Definition');
    expect(
      controller.selection,
      TextSelection(
        baseOffset: bodyStart + sourceStart,
        extentOffset: bodyStart + sourceEnd,
        isDirectional: true,
      ),
    );
    expect(controller.selection.textInside(source), 'finition ');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('formatted footnote definition click keeps exact source offset', (
    tester,
  ) async {
    const source = 'Before[^note].\n\n[^note]: Definition **bold** tail.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final preview = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data ?? widget.textSpan?.toPlainText() ?? '') ==
              'note Definition bold tail.',
    );
    final editable = editableWithin(tester, preview);
    const visibleOffset = 5 + 11 + 2;
    final target = editable.localToGlobal(
      editable
          .getLocalRectForCaret(const TextPosition(offset: visibleOffset))
          .center,
    );
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, source.indexOf('bold') + 2);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('live preview edits a standalone comment across blank lines', (
    tester,
  ) async {
    const comment = '%%\nhidden first\n\nhidden second\n%%';
    const source = 'Before.\n\n$comment\n\nAfter.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.text(comment), findsOneWidget);
    await tester.tap(find.text(comment));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, comment);
    expect(controller.text, source);
  });

  testWidgets('live preview keeps code-shaped closers in one comment range', (
    tester,
  ) async {
    const comment = '%%open `%%inside%%` tail%%';
    const source = 'Before $comment after.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.text(comment), findsOneWidget);
    await tester.tap(find.text(comment));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(controller.text, source);
  });

  testWidgets('live preview binds blank-separated block IDs to source blocks', (
    tester,
  ) async {
    const paragraphBlock = 'Paragraph.\n\n^paragraph_id';
    const headingBlock = '# Heading\n\n^heading_id';
    const source = '$paragraphBlock\n\n$headingBlock\n\nAfter.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final paragraphId = selectableTextWithPlainText('^paragraph_id');
    expect(paragraphId, findsOneWidget);
    await tester.tap(paragraphId);
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, paragraphBlock);

    await tester.tap(selectableTextWithPlainText('^heading_id'));
    await tester.pump();
    field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, headingBlock);
    expect(controller.text, source);
  });

  testWidgets('block ID clicks preserve Obsidian source selections', (
    tester,
  ) async {
    const source = 'Before.\n\nParagraph end ^paragraph-id\n\nAfter.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final paragraph = editableWithin(
      tester,
      selectableTextWithPlainText('Paragraph end ^paragraph-id'),
    );
    const metadataOffset = 6;
    final caret = paragraph.getLocalRectForCaret(
      const TextPosition(offset: 13 + metadataOffset),
    );
    final target = paragraph.localToGlobal(caret.center);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    final expectedOffset = source.indexOf(' ^paragraph-id') + metadataOffset;
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, expectedOffset);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'paragraph');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(
      controller.selection.textInside(source),
      'Paragraph end ^paragraph-id',
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('block ID hides its caret without shifting source clicks', (
    tester,
  ) async {
    const source = 'Before\n\nAlpha bravo ^probe-id\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    Finder paragraphFinder() => find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data ?? widget.textSpan?.toPlainText()) ==
              'Alpha bravo ^probe-id',
    );
    TextSpan hiddenCaret(SelectableText text) =>
        _textSpanLeaves(text.textSpan!).singleWhere((span) => span.text == '^');

    var caret = hiddenCaret(tester.widget<SelectableText>(paragraphFinder()));
    expect(caret.style?.fontSize, 0);
    expect(caret.style?.color, Colors.transparent);

    var editable = editableWithin(tester, paragraphFinder());
    var target = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 10)).center,
    );
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, 18);
    var active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    var field = tester.widget<TextField>(fieldFinder);
    caret = _textSpanLeaves(
      field.controller!.buildTextSpan(
        context: tester.element(fieldFinder),
        style: field.style,
        withComposing: false,
      ),
    ).singleWhere((span) => span.text == '^');
    expect(caret.style?.fontSize, 0);
    expect(caret.style?.color, Colors.transparent);

    await tester.tap(find.text('After'));
    await tester.pumpAndSettle();
    editable = editableWithin(tester, paragraphFinder());
    final idCaret = editable.getLocalRectForCaret(
      const TextPosition(offset: 18),
    );
    target = editable.localToGlobal(idCaret.center);
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, 26);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('comment clicks preserve Obsidian source selections', (
    tester,
  ) async {
    const comment = '%%secret bravo%%';
    const source = 'Before\n\nAlpha $comment omega\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final metadata = find.text(comment);
    RenderParagraph renderedComment() => tester.renderObject<RenderParagraph>(
      find.descendant(of: metadata, matching: find.byType(RichText)),
    );
    var paragraph = renderedComment();
    const bodyOffset = 12;
    var caret = paragraph.getOffsetForCaret(
      const TextPosition(offset: bodyOffset),
      Rect.zero,
    );
    var target = paragraph.localToGlobal(
      caret + Offset(.1, paragraph.size.height / 2),
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, 26);

    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'bravo');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(
      controller.selection.textInside(source),
      'Alpha %%secret bravo%% omega',
    );

    await tester.tap(find.text('After'));
    await tester.pumpAndSettle();
    paragraph = renderedComment();
    caret = paragraph.getOffsetForCaret(
      const TextPosition(offset: 1),
      Rect.zero,
    );
    target = paragraph.localToGlobal(
      caret + Offset(.1, paragraph.size.height / 2),
    );
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, 15);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('live preview keeps a soft-line block ID candidate literal', (
    tester,
  ) async {
    const paragraph = 'Soft first ^soft-id\ncontinuation.';
    const source = '$paragraph\n\nFinal ^final-id';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('^soft-id'), findsOneWidget);
    expect(selectableTextWithPlainText('Final ^final-id'), findsOneWidget);

    await tester.tap(find.textContaining('^soft-id'));
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, paragraph);
    expect(controller.text, source);
  });

  testWidgets('live preview keeps mixed footnote markers literal', (
    tester,
  ) async {
    const source = '''
Inline ^[first], missing[^missing], standard[^a], repeated[^a], empty ^[], and second[^b].

[^a]: Alpha.

[^b]: Beta.
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.text('^[first]'), findsOneWidget);
    expect(find.text('[^missing]'), findsOneWidget);
    expect(find.text('[^a]'), findsNWidgets(2));
    expect(find.text('^[]'), findsOneWidget);
    expect(find.text('[^b]'), findsOneWidget);
    expect(find.text('2.'), findsNothing);
    expect(find.text('4.'), findsNothing);
    expect(find.textContaining('Alpha.'), findsOneWidget);
    expect(find.textContaining('Beta.'), findsOneWidget);

    await tester.tap(find.text('^[first]'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
        matching: find.byType(TextField),
      ),
    );
    expect(
      field.controller?.text,
      'Inline ^[first], missing[^missing], standard[^a], repeated[^a], '
      'empty ^[], and second[^b].',
    );
    expect(controller.text, source);
  });

  testWidgets('live preview keeps inline footnotes inside formatting literal', (
    tester,
  ) async {
    const source = r'''
Bold **before ^[bold body] after** and link [linked ^[link body]](https://example.com).

Code `^[code]`, escaped \^[escaped], and %% hidden ^[comment] %%.
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.text('^[bold body]'), findsOneWidget);
    final visibleSegments = <String>[
      ...tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? ''),
      ...tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? ''),
    ];
    expect(
      visibleSegments.any((text) => text.contains('^[link body]')),
      isTrue,
    );
    expect(controller.text, source);
  });

  testWidgets('multiline inline code keeps footnotes literal in live preview', (
    tester,
  ) async {
    const source = '''
`code
^[not-footnote]` standard[^a]

[^a]: Body.
''';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final code = find.byWidgetPredicate((widget) {
      final text = switch (widget) {
        Text() => widget.data ?? widget.textSpan?.toPlainText() ?? '',
        SelectableText() => widget.data ?? widget.textSpan?.toPlainText() ?? '',
        _ => '',
      };
      return text.contains('^[not-footnote]');
    });
    expect(code, findsAtLeastNWidgets(1));
    expect(find.text('[^a]'), findsOneWidget);
    expect(find.text('1.'), findsNothing);

    await tester.tap(find.text('[^a]'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller?.text, '`code\n^[not-footnote]` standard[^a]');
    expect(controller.text, source);
  });

  testWidgets('Tab indents an active list item without selecting its text', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '- Alpha\n- Beta');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beta'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
        matching: find.byType(TextField),
      ),
    );
    field.controller?.selection = TextSelection.collapsed(
      offset: field.controller!.text.length,
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, '- Alpha\n    - Beta');
    expect(controller.selection, const TextSelection.collapsed(offset: 18));
    expect(field.controller?.text, '    - Beta');
    expect(field.controller?.selection.isCollapsed, isTrue);
    expect(field.controller?.selection.extentOffset, 10);
    expect(
      tester
          .widget<IanvsMarkdownUnorderedListMarker>(
            find.descendant(
              of: find.byKey(
                const ValueKey('ianvs-markdown-active-list-marker'),
              ),
              matching: find.byType(IanvsMarkdownUnorderedListMarker),
            ),
          )
          .shape,
      IanvsMarkdownUnorderedListMarkerShape.square,
    );

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    final nestedMarker = tester.widget<IanvsMarkdownUnorderedListMarker>(
      find.byKey(const ValueKey('ianvs-markdown-unordered-marker-1')),
    );
    expect(nestedMarker.shape, IanvsMarkdownUnorderedListMarkerShape.square);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('Tab indents inside quote containers and Shift Tab reverses it', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '> - item')
      ..selection = const TextSelection.collapsed(offset: 8);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, '>     - item');
    expect(controller.selection, const TextSelection.collapsed(offset: 12));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.text, '> - item');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('Tab renumbers ordered siblings across the affected levels', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '1. A\n2. B\n3. C')
      ..selection = const TextSelection.collapsed(offset: 9);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 9);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, '1. A\n    1. B\n2. C');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.text, '1. A\n2. B\n3. C');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));
  });

  testWidgets('Tab leaves an active plain paragraph without changing source', (
    tester,
  ) async {
    const source = 'Plain paragraph';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text(source));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
        matching: find.byType(TextField),
      ),
    );
    field.controller?.selection = TextSelection.collapsed(
      offset: field.controller!.text.length,
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(field.focusNode?.hasFocus, isFalse);
  });

  testWidgets(
    'task checkbox updates Markdown without entering source editing',
    (tester) async {
      final controller = IanvsMarkdownController(text: '- [ ] Open');
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final checkbox = find.byType(IanvsMarkdownTaskCheckbox);
      expect(checkbox, findsOneWidget);
      expect(tester.widget<IanvsMarkdownTaskCheckbox>(checkbox).value, isFalse);
      final uncheckedBox = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('ianvs-markdown-task-checkbox-box')),
      );
      final uncheckedDecoration = uncheckedBox.decoration! as BoxDecoration;
      expect(uncheckedDecoration.color, Colors.transparent);
      expect(
        (uncheckedDecoration.border! as Border).top.color,
        IanvsMarkdownThemeData.light.taskCheckboxBorderColor,
      );
      expect(uncheckedDecoration.borderRadius, BorderRadius.circular(6));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(checkbox));
      await tester.pump(IanvsMarkdownTaskCheckbox.animationDuration);
      final outline = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('ianvs-markdown-task-checkbox-outline')),
      );
      final outlineBorder =
          (outline.decoration! as BoxDecoration).border! as Border;
      expect(
        outlineBorder.top.color,
        IanvsMarkdownThemeData.light.taskCheckboxHoverOutlineColor,
      );
      expect(outlineBorder.top.width, 2);

      await tester.tap(checkbox);
      await tester.pump();

      expect(controller.text, '- [x] Open');
      expect(controller.isDirty, isTrue);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-block')),
        findsNothing,
      );
      expect(tester.widget<IanvsMarkdownTaskCheckbox>(checkbox).value, isTrue);
      final checkedDecoration =
          tester
                  .widget<AnimatedContainer>(
                    find.byKey(
                      const ValueKey('ianvs-markdown-task-checkbox-box'),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(
        checkedDecoration.color,
        isNot(IanvsMarkdownThemeData.light.accent),
      );
      expect(
        find.byKey(const ValueKey('ianvs-markdown-task-checkbox-check')),
        findsOneWidget,
      );
      final completedText =
          tester
              .widgetList<RichText>(find.byType(RichText))
              .any(
                (richText) => _spanContainsDecoration(
                  richText.text,
                  text: 'Open',
                  decoration: TextDecoration.lineThrough,
                ),
              ) ||
          tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .any(
                (selectableText) =>
                    selectableText.textSpan != null &&
                    _spanContainsDecoration(
                      selectableText.textSpan!,
                      text: 'Open',
                      decoration: TextDecoration.lineThrough,
                    ),
              );
      expect(completedText, isTrue);
      final completedTextColor =
          tester
              .widgetList<RichText>(find.byType(RichText))
              .any(
                (richText) => _spanContainsColor(
                  richText.text,
                  text: 'Open',
                  color: IanvsMarkdownThemeData.light.taskDoneColor,
                ),
              ) ||
          tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .any(
                (selectableText) =>
                    selectableText.textSpan != null &&
                    _spanContainsColor(
                      selectableText.textSpan!,
                      text: 'Open',
                      color: IanvsMarkdownThemeData.light.taskDoneColor,
                    ),
              );
      expect(completedTextColor, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.text, '- [x] Open');
    },
  );

  testWidgets('active task checkbox preserves the editor caret focus', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '- [ ] Open');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pump();
    var active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    var fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(fieldFinder).focusNode?.hasFocus, isTrue);

    await tester.tap(
      find.descendant(
        of: active,
        matching: find.byType(IanvsMarkdownTaskCheckbox),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '- [x] Open');
    active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    fieldFinder = find.descendant(of: active, matching: find.byType(TextField));
    expect(tester.widget<TextField>(fieldFinder).focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.text, '- [x] Open');
  });

  testWidgets('alternate task states preserve markers and toggle exact items', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '- [!] Critical\n- [/] Moving\n- [-] Cancelled',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    var checkboxes = tester
        .widgetList<IanvsMarkdownTaskCheckbox>(
          find.byType(IanvsMarkdownTaskCheckbox),
        )
        .toList();
    expect(checkboxes.map((checkbox) => checkbox.marker), <String>[
      '!',
      '/',
      '-',
    ]);
    final boxes = tester
        .widgetList<AnimatedContainer>(
          find.byKey(const ValueKey('ianvs-markdown-task-checkbox-box')),
        )
        .toList();
    expect(
      (boxes.first.decoration! as BoxDecoration).color,
      IanvsMarkdownThemeData.light.taskStatusOrange,
    );
    expect(
      ((boxes[1].decoration! as BoxDecoration).border! as Border).top.width,
      2,
    );
    expect(
      find.byKey(
        const ValueKey('ianvs-markdown-task-checkbox-alternative-icon'),
      ),
      findsNWidgets(3),
    );
    final cancelledText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .any(
          (text) =>
              text.textSpan != null &&
              _spanContainsDecoration(
                text.textSpan!,
                text: 'Cancelled',
                decoration: TextDecoration.lineThrough,
              ) &&
              _spanContainsColor(
                text.textSpan!,
                text: 'Cancelled',
                color: IanvsMarkdownThemeData.light.taskDoneColor,
              ),
        );
    expect(cancelledText, isTrue);

    await tester.tap(find.byType(IanvsMarkdownTaskCheckbox).at(1));
    await tester.pump();
    expect(controller.text, '- [!] Critical\n- [ ] Moving\n- [-] Cancelled');
    checkboxes = tester
        .widgetList<IanvsMarkdownTaskCheckbox>(
          find.byType(IanvsMarkdownTaskCheckbox),
        )
        .toList();
    expect(checkboxes.map((checkbox) => checkbox.marker), <String>[
      '!',
      ' ',
      '-',
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.text, '- [!] Critical\n- [ ] Moving\n- [-] Cancelled');
  });

  testWidgets('ordered alternate tasks stay visual and continue unchecked', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '1. [/] Ongoing');
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IanvsMarkdownTaskCheckbox>(
            find.byType(IanvsMarkdownTaskCheckbox),
          )
          .marker,
      '/',
    );

    await tester.tap(find.text('Ongoing'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    final activeCheckbox = tester.widget<IanvsMarkdownTaskCheckbox>(
      find.descendant(
        of: active,
        matching: find.byType(IanvsMarkdownTaskCheckbox),
      ),
    );
    expect(activeCheckbox.marker, '/');
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = TextSelection.collapsed(
      offset: field.controller!.text.length,
    );
    expect(field.focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '${field.controller!.text}\n',
        selection: TextSelection.collapsed(
          offset: field.controller!.text.length + 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '1. [/] Ongoing\n2. [ ] ');
  });

  testWidgets('nested and quoted alternate tasks toggle exact markers', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '- [!] Parent\n  - [b] Child\n\n> - [-] Quoted cancelled',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    var checkboxes = tester
        .widgetList<IanvsMarkdownTaskCheckbox>(
          find.byType(IanvsMarkdownTaskCheckbox),
        )
        .toList();
    expect(checkboxes.map((checkbox) => checkbox.marker), <String>[
      '!',
      'b',
      '-',
    ]);
    expect(
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any(
            (text) =>
                text.textSpan != null &&
                _spanContainsDecoration(
                  text.textSpan!,
                  text: 'Quoted cancelled',
                  decoration: TextDecoration.lineThrough,
                ),
          ),
      isTrue,
    );

    await tester.tap(find.byType(IanvsMarkdownTaskCheckbox).at(1));
    await tester.pumpAndSettle();
    expect(
      controller.text,
      '- [!] Parent\n  - [ ] Child\n\n> - [-] Quoted cancelled',
    );

    checkboxes = tester
        .widgetList<IanvsMarkdownTaskCheckbox>(
          find.byType(IanvsMarkdownTaskCheckbox),
        )
        .toList();
    expect(checkboxes.map((checkbox) => checkbox.marker), <String>[
      '!',
      ' ',
      '-',
    ]);
    await tester.tap(find.byType(IanvsMarkdownTaskCheckbox).at(2));
    await tester.pumpAndSettle();
    expect(
      controller.text,
      '- [!] Parent\n  - [ ] Child\n\n> - [ ] Quoted cancelled',
    );
  });

  testWidgets('empty active task keeps a paintable caret beside its checkbox', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '- [ ] ');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(
      find.descendant(
        of: active,
        matching: find.byType(IanvsMarkdownTaskCheckbox),
      ),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '- [ ] ');
  });

  testWidgets('invalid backtick info strings stay ordinary paragraph source', (
    tester,
  ) async {
    const invalid = '```js`bad\ncode';
    final controller = IanvsMarkdownController(text: '$invalid\n\nAfter');
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('code').first);
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, invalid);
    expect(field.style?.fontFamily, isNull);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-code-pattern')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-code-line-rail')),
      findsNothing,
    );
    expect(find.text('After'), findsOneWidget);
  });

  testWidgets('active fenced code preserves the rendered surface hierarchy', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '```dart\nfinal value = 1;\n```',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final container = tester.widget<Container>(active);
    expect(container.clipBehavior, Clip.antiAlias);
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, IanvsMarkdownThemeData.light.surface);
    expect(decoration.border, isNull);
    final frame =
        container.foregroundDecoration! as IanvsMarkdownDashedBorderDecoration;
    expect(frame.strokeWidth, 1);
    expect(frame.dashLength, 3);
    expect(frame.gapLength, 3);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(IanvsMarkdownThemeData.light.smallRadius / 2),
    );
    expect(
      container.margin,
      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    );
    expect(container.foregroundDecoration, isNotNull);
    expect(container.padding, const EdgeInsets.symmetric(horizontal: 16));
    final pattern = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('ianvs-markdown-active-code-pattern')),
    );
    final patternPainter = pattern.painter! as IanvsMarkdownCodePatternPainter;
    expect(patternPainter.tileSize, 4);
    expect(patternPainter.dotSize, 1);
    expect(patternPainter.color, Colors.black.withValues(alpha: .12));
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-flair')),
      findsNothing,
    );
    expect(find.text('Dart'), findsNothing);
    final codeLineRail = find.byKey(
      const ValueKey('ianvs-markdown-active-code-line-rail'),
    );
    expect(codeLineRail, findsOneWidget);
    final positionedRail = tester.widget<PositionedDirectional>(codeLineRail);
    expect(positionedRail.start, -5);
    expect(positionedRail.top, isNotNull);
    expect(positionedRail.bottom, isNull);
    final rail = positionedRail.child as Container;
    expect(rail.constraints?.minWidth, 3);
    expect(tester.getSize(codeLineRail).height, inInclusiveRange(14, 16));
    expect(
      tester.getRect(codeLineRail).left,
      lessThan(tester.getRect(active).left),
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-code-line-marker')),
      findsNothing,
    );

    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    final span = field.controller!.buildTextSpan(
      context: tester.element(fieldFinder),
      style: field.style,
      withComposing: false,
    );
    expect(span.toPlainText(), controller.text);
    final keywordSpans = _textSpanLeaves(
      span,
    ).where((span) => span.text?.contains('final') ?? false);
    expect(keywordSpans, isNotEmpty);
    expect(
      keywordSpans.any((span) => span.style?.color != field.style?.color),
      isTrue,
    );
  });

  testWidgets('fenced code clicks map visual lines to exact source offsets', (
    tester,
  ) async {
    const source =
        'Before\n\n```dart\nalpha bravo\ncharlie delta\n```\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    RenderEditable renderedCode() => editableWithin(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('ianvs-markdown-code-block')),
        matching: find.byType(SelectableText),
      ),
    );

    var editable = renderedCode();
    var target = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 10)).center,
    );
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, 26);

    await tester.tap(find.text('After'));
    await tester.pumpAndSettle();
    editable = renderedCode();
    target = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 22)).center,
    );
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, 38);
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('fenced code multi-click selects only its physical body line', (
    tester,
  ) async {
    const source =
        'Before\n\n```dart\nalpha bravo\ncharlie delta\n```\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final editable = editableWithin(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('ianvs-markdown-code-block')),
        matching: find.byType(SelectableText),
      ),
    );
    final target = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 8)).center,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'bravo');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), 'alpha bravo');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('active nested fences hide flair and preserve exact source', (
    tester,
  ) async {
    const source = '````markdown\n```dart\nfinal value = 1;\n```\n\n````';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-flair')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsNothing,
    );
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(controller.text, source);
  });

  testWidgets('code flair returns after focus leaves the fenced block', (
    tester,
  ) async {
    const source = '```dart\nfinal value = 1;\n```\n\nAfter';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-flair')),
      findsNothing,
    );

    await tester.tap(find.text('After'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsOneWidget,
    );
    expect(find.text('Dart'), findsOneWidget);
    expect(controller.text, source);
  });

  testWidgets('empty fenced code renders a canvas until activated', (
    tester,
  ) async {
    const source = '```text\n\n```';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-live-empty-fenced-code')),
      findsNothing,
    );
    expect(find.byType(IanvsMarkdownCodeBlock), findsOneWidget);
    expect(find.text(source), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('ianvs-markdown-code-canvas')))
          .height,
      58,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsOneWidget,
    );
    expect(find.text('text'), findsOneWidget);

    await tester.tap(find.byType(IanvsMarkdownCodeBlock));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('ianvs-markdown-active-code-semantics')),
          )
          .value,
      source,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-flair')),
      findsNothing,
    );

    final contentStart = source.indexOf('\n') + 1;
    controller.selection = TextSelection.collapsed(offset: contentStart);
    await tester.pumpAndSettle();
    final rail = find.byKey(
      const ValueKey('ianvs-markdown-active-code-line-rail'),
    );
    expect(rail, findsOneWidget);
    final emptyLineTop = tester.getTopLeft(rail).dy;
    expect(tester.getSize(rail).height, inInclusiveRange(14, 16));

    controller.selection = TextSelection.collapsed(
      offset: source.lastIndexOf('```') + 1,
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(rail).dy, greaterThan(emptyLineTop));
    expect(tester.getSize(rail).height, inInclusiveRange(14, 16));
    expect(controller.text, source);

    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-live-empty-fenced-code')),
      findsNothing,
    );
    expect(find.byType(IanvsMarkdownCodeBlock), findsOneWidget);
    expect(find.text(source), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('ianvs-markdown-code-canvas')))
          .height,
      34,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsNothing,
    );
    expect(controller.text, source);
    semanticsHandle.dispose();
  });

  testWidgets('blank active code lines move one logical row at a time', (
    tester,
  ) async {
    const source = '```text\n\n\n```';
    final firstBlank = source.indexOf('\n') + 1;
    final controller = IanvsMarkdownController(text: source)
      ..selection = TextSelection.collapsed(offset: firstBlank);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = find.byKey(
      const ValueKey('ianvs-markdown-active-code-line-rail'),
    );
    expect(rail, findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-flair')),
      findsNothing,
    );
    final firstTop = tester.getTopLeft(rail).dy;
    expect(tester.getSize(rail).height, inInclusiveRange(14, 16));

    controller.selection = TextSelection.collapsed(offset: firstBlank + 1);
    await tester.pumpAndSettle();

    final secondTop = tester.getTopLeft(rail).dy;
    expect(secondTop, greaterThan(firstTop));
    expect(secondTop - firstTop, inInclusiveRange(20, 22));
    expect(tester.getSize(rail).height, inInclusiveRange(14, 16));
    expect(rail, findsOneWidget);
    expect(controller.text, source);
  });

  testWidgets(
    'live preview indented code uses line rails without fenced chrome',
    (tester) async {
      const source =
          'Before.\n\n'
          '    const first = %%inside%%; ^inside-id ^[inline] [^standard]\n'
          '\n'
          '\treturn %%tab%% first; ^tab-id\n\n'
          'After.';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ianvs-markdown-live-indented-code')),
        findsOneWidget,
      );
      expect(find.byType(IanvsMarkdownCodeBlock), findsNothing);
      expect(find.byTooltip('复制'), findsNothing);
      expect(
        find.text('const first = %%inside%%; ^inside-id ^[inline] [^standard]'),
        findsOneWidget,
      );
      expect(find.text('return %%tab%% first; ^tab-id'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-indented-code-line-1')),
        findsOneWidget,
      );
      final firstLine = tester.widget<Container>(
        find.byKey(const ValueKey('ianvs-markdown-indented-code-line-0')),
      );
      final lineDecoration = firstLine.decoration! as BoxDecoration;
      expect((lineDecoration.border! as Border).left.width, 1);

      await tester.tap(
        find.text('const first = %%inside%%; ^inside-id ^[inline] [^standard]'),
      );
      await tester.pumpAndSettle();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(
        field.controller?.text,
        '    const first = %%inside%%; ^inside-id ^[inline] [^standard]\n\n'
        '\treturn %%tab%% first; ^tab-id',
      );
      expect(controller.text, source);
    },
  );

  testWidgets('indented code taps map dedented visual text to exact source', (
    tester,
  ) async {
    const source =
        'Before.\n\n'
        '    four-one\n'
        '    four-two\n\n'
        'Middle.\n\n'
        '\tTab-one\n'
        '\tTab-two\n\n'
        'After.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final rendered = find.text('four-one');
    final inactiveEditable = editableWithin(tester, rendered);
    const visibleOffset = 4;
    final target = inactiveEditable.localToGlobal(
      inactiveEditable
          .getLocalRectForCaret(const TextPosition(offset: visibleOffset))
          .center,
    );
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    final expectedOffset = source.indexOf('four-one') + visibleOffset;
    expect(
      controller.selection,
      TextSelection.collapsed(offset: expectedOffset),
    );
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '    four-one\n    four-two');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 8),
    );
    expect(field.focusNode?.hasFocus, isTrue);
    expect(controller.text, source);

    final renderedTab = find.text('Tab-one');
    final inactiveTabEditable = editableWithin(tester, renderedTab);
    const tabVisibleOffset = 3;
    final tabTarget = inactiveTabEditable.localToGlobal(
      inactiveTabEditable
          .getLocalRectForCaret(const TextPosition(offset: tabVisibleOffset))
          .center,
    );
    await tester.tapAt(tabTarget);
    await tester.pumpAndSettle();

    final expectedTabOffset = source.indexOf('Tab-one') + tabVisibleOffset;
    expect(
      controller.selection,
      TextSelection.collapsed(offset: expectedTabOffset),
    );
    final tabField = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(tabField.controller?.text, '\tTab-one\n\tTab-two');
    expect(
      tabField.controller?.selection,
      const TextSelection.collapsed(offset: 4),
    );
    expect(tabField.focusNode?.hasFocus, isTrue);
    expect(controller.text, source);
  });

  testWidgets('indented code double click selects the visible word', (
    tester,
  ) async {
    const source = 'Before.\n\n    four-one\n    four-two\n\nAfter.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final inactiveEditable = editableWithin(tester, find.text('four-one'));
    final target = inactiveEditable.localToGlobal(
      inactiveEditable
          .getLocalRectForCaret(const TextPosition(offset: 2))
          .center,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'four');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), '    four-one');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('tab-indented code multi-click restores raw indentation', (
    tester,
  ) async {
    const source = 'Before.\n\n\tTab-one\n\tTab-two\n\nAfter.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final inactiveEditable = editableWithin(tester, find.text('Tab-one'));
    final target = inactiveEditable.localToGlobal(
      inactiveEditable
          .getLocalRectForCaret(const TextPosition(offset: 2))
          .center,
    );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selection.textInside(source), 'Tab');

    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), '\tTab-one');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('indented code gap activates its exact blank source line', (
    tester,
  ) async {
    const source = 'Before.\n\n    four-one\n    four-two\n\nMiddle.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    final codeBlock = parseMarkdownBlocks(
      source,
    ).singleWhere((block) => block.type == IanvsMarkdownBlockType.indentedCode);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('ianvs-markdown-gap-${codeBlock.end}')),
    );
    await tester.pumpAndSettle();

    expect(
      controller.selection,
      TextSelection.collapsed(offset: codeBlock.end + 1),
    );
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, '    four-one\n    four-two\n');

    await tester.enterText(fieldFinder, '    four-one\n    four-two\nZ');
    await tester.pumpAndSettle();

    expect(
      controller.text,
      'Before.\n\n    four-one\n    four-two\nZ\nMiddle.',
    );
  });

  testWidgets(
    'indented code drag maps its initial visual range to exact source',
    (tester) async {
      const source = 'Before.\n\n    four-one\n    four-two\n\nAfter.';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final firstEditable = editableWithin(tester, find.text('four-one'));
      final secondEditable = editableWithin(tester, find.text('four-two'));
      final start = firstEditable.localToGlobal(
        firstEditable
            .getLocalRectForCaret(const TextPosition(offset: 2))
            .center,
      );
      final end = secondEditable.localToGlobal(
        secondEditable
            .getLocalRectForCaret(const TextPosition(offset: 4))
            .center,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.down(start);
      await mouse.moveTo(end);
      await tester.pumpAndSettle();
      await mouse.up();
      await tester.pumpAndSettle();

      final blockStart = source.indexOf('    four-one');
      const firstLineLength = 12;
      expect(
        controller.selection,
        TextSelection(
          baseOffset: blockStart + 4 + 2,
          extentOffset: blockStart + firstLineLength + 1 + 4 + 4,
          isDirectional: true,
        ),
      );
      expect(controller.selection.textInside(source), 'ur-one\n    four');
      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
    },
  );

  testWidgets('tab-indented code reverse drag keeps exact source direction', (
    tester,
  ) async {
    const source = 'Before.\n\n\tTab-one\n\tTab-two\n\nAfter.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final firstEditable = editableWithin(tester, find.text('Tab-one'));
    final secondEditable = editableWithin(tester, find.text('Tab-two'));
    final start = secondEditable.localToGlobal(
      secondEditable.getLocalRectForCaret(const TextPosition(offset: 4)).center,
    );
    final end = firstEditable.localToGlobal(
      firstEditable.getLocalRectForCaret(const TextPosition(offset: 2)).center,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pumpAndSettle();
    await mouse.up();
    await tester.pumpAndSettle();

    final blockStart = source.indexOf('\tTab-one');
    const firstLineLength = 8;
    expect(
      controller.selection,
      TextSelection(
        baseOffset: blockStart + firstLineLength + 1 + 1 + 4,
        extentOffset: blockStart + 1 + 2,
        isDirectional: true,
      ),
    );
    expect(controller.selection.textInside(source), 'b-one\n\tTab-');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('active indented code keeps exact source and current-line rail', (
    tester,
  ) async {
    const source = '    const first = 1;\n\n\treturn first;';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('ianvs-markdown-active-indented-code-line-rail'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('ianvs-markdown-active-indented-code-line-marker'),
      ),
      findsOneWidget,
    );
    final container = tester.widget<Container>(active);
    expect(container.decoration, isNull);
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(
      field.style?.fontFamily,
      IanvsMarkdownThemeData.light.monoFontFamily,
    );
    expect(field.style?.color, IanvsMarkdownThemeData.light.accentDark);
    expect(controller.text, source);
  });

  testWidgets('active indented code rail follows one wrapped source line', (
    tester,
  ) async {
    final longToken = List.filled(12, 'abcdef0123456789').join();
    final source = '    $longToken\n    tail';
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection.collapsed(offset: 6);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = find.byKey(
      const ValueKey('ianvs-markdown-active-indented-code-line-rail'),
    );
    final firstTop = tester.getTopLeft(rail).dy;
    final wrappedHeight = tester.getSize(rail).height;
    expect(wrappedHeight, greaterThan(40));

    controller.selection = TextSelection.collapsed(
      offset: source.indexOf('tail') + 2,
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(rail).dy, greaterThan(firstTop));
    expect(tester.getSize(rail).height, lessThan(wrappedHeight));
  });

  testWidgets('active code rail covers the wrapped logical source line', (
    tester,
  ) async {
    final longToken = List.filled(12, 'abcdef0123456789').join();
    final source = '```text\n$longToken\n```';
    final contentStart = source.indexOf('\n') + 1;
    final contentEnd = contentStart + longToken.length;
    final controller = IanvsMarkdownController(text: source)
      ..selection = TextSelection.collapsed(offset: contentStart + 2);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = find.byKey(
      const ValueKey('ianvs-markdown-active-code-line-rail'),
    );
    expect(rail, findsOneWidget);
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final editable = editableWithin(tester, fieldFinder);
    final logicalStartCaret = editable.getLocalRectForCaret(
      TextPosition(offset: contentStart),
    );
    final logicalEndCaret = editable.getLocalRectForCaret(
      TextPosition(offset: contentEnd),
    );
    final logicalLineHeight =
        logicalEndCaret.top - logicalStartCaret.top + logicalStartCaret.height;
    final firstRowY = tester.getTopLeft(rail).dy;
    final railHeight = tester.getSize(rail).height;
    expect(railHeight, greaterThan(40));
    expect(railHeight, closeTo(logicalLineHeight - 6, 1));
    expect(
      firstRowY,
      closeTo(editable.localToGlobal(logicalStartCaret.topLeft).dy + 3, 1),
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-code-line-marker')),
      findsNothing,
    );

    controller.selection = TextSelection.collapsed(
      offset: contentStart + longToken.length - 2,
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(rail).dy, closeTo(firstRowY, .01));
    expect(tester.getSize(rail).height, railHeight);

    final closingFenceStart = source.lastIndexOf('```');
    controller.selection = TextSelection.collapsed(
      offset: closingFenceStart + 1,
    );
    await tester.pumpAndSettle();
    final closingTop = tester.getTopLeft(rail).dy;
    expect(closingTop, greaterThan(firstRowY));
    expect(tester.getSize(rail).height, inInclusiveRange(14, 16));

    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(rail).dy, lessThan(firstRowY));
    expect(tester.getSize(rail).height, inInclusiveRange(14, 16));
    expect(controller.text, source);
  });

  testWidgets('active code rail stays outside the logical start in RTL', (
    tester,
  ) async {
    const source = '```text\nalpha\n```';
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection.collapsed(offset: 10);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 600,
              height: 480,
              child: IanvsMarkdownLiveEditor(
                controller: controller,
                autofocus: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final rail = find.byKey(
      const ValueKey('ianvs-markdown-active-code-line-rail'),
    );
    expect(
      tester.getRect(rail).right,
      greaterThan(tester.getRect(active).right),
    );
    expect(tester.widget<PositionedDirectional>(rail).start, -5);
    expect(controller.text, source);
  });

  testWidgets('active syntax fences apply electric indentation through IME', (
    tester,
  ) async {
    const source = '```dart\nif (ready) {\n}\n```';
    final caret = source.indexOf('\n}');
    final controller = IanvsMarkdownController(text: source)
      ..selection = TextSelection.collapsed(offset: caret);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: source.replaceRange(caret, caret, '\n'),
        selection: TextSelection.collapsed(offset: caret + 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '```dart\nif (ready) {\n    \n}\n```');
    expect(controller.selection, TextSelection.collapsed(offset: caret + 5));
  });

  testWidgets('active fences keep list-shaped code literal through IME', (
    tester,
  ) async {
    const source = '```text\n- item\n```';
    final caret = source.indexOf('\n```');
    final controller = IanvsMarkdownController(text: source)
      ..selection = TextSelection.collapsed(offset: caret);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: source.replaceRange(caret, caret, '\n'),
        selection: TextSelection.collapsed(offset: caret + 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '```text\n- item\n\n```');
    expect(controller.selection, TextSelection.collapsed(offset: caret + 1));
  });

  testWidgets('active syntax fences outdent typed closers through IME', (
    tester,
  ) async {
    const source = '```dart\n    \n```';
    const caret = 12;
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection.collapsed(offset: caret);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '```dart\n    }\n```',
        selection: TextSelection.collapsed(offset: caret + 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '```dart\n}\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));
  });

  testWidgets('Tab indents the active fenced-code line by four spaces', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '```dart\nalpha\n```')
      ..selection = const TextSelection.collapsed(offset: 13);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, '```dart\n    alpha\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 17));
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Backspace retreats active code indentation by tab stops', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '```dart\n      alpha\n```',
    )..selection = const TextSelection.collapsed(offset: 14);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.text, '```dart\n    alpha\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 12));

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.text, '```dart\nalpha\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('source code Tab indents the line and Backspace reverses it', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '```dart\nalpha\n```',
      mode: IanvsMarkdownEditorMode.source,
    )..selection = const TextSelection.collapsed(offset: 10);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
    );
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, '```dart\n    alpha\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 14));

    controller.selection = const TextSelection.collapsed(offset: 12);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.text, '```dart\nalpha\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('source Tab indents inside a quote container', (tester) async {
    final controller = IanvsMarkdownController(text: '> - item')
      ..selection = const TextSelection.collapsed(offset: 8);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.text, '>     - item');
    expect(controller.selection, const TextSelection.collapsed(offset: 12));
  });

  testWidgets(
    'source editor keeps native newline after a tab-separated list marker',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: '-\tone',
        mode: IanvsMarkdownEditorMode.source,
      )..selection = const TextSelection.collapsed(offset: 5);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownEditor(
              controller: controller,
              autofocus: true,
              showToolbar: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '-\tone\n',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.text, '-\tone\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
    },
  );

  testWidgets('source Tab renumbers an ordered item inside a quote', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '> 9. item')
      ..selection = const TextSelection.collapsed(offset: 9);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, '>     1. item');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));
  });

  testWidgets('Shift Tab outdents the active fenced-code line', (tester) async {
    final controller = IanvsMarkdownController(text: '```dart\n    alpha\n```')
      ..selection = const TextSelection.collapsed(offset: 17);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(controller.text, '```dart\nalpha\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('Tab and Shift Tab indent selected fenced-code lines', (
    tester,
  ) async {
    const source = '```dart\nalpha\nbeta\n```';
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection(baseOffset: 8, extentOffset: 18);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    field.controller?.selection = const TextSelection(
      baseOffset: 8,
      extentOffset: 18,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, '```dart\n    alpha\n    beta\n```');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 12, extentOffset: 26),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.text, source);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 8, extentOffset: 18),
    );
  });

  testWidgets('live preview completes a third typed backtick in place', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '``')
      ..selection = const TextSelection.collapsed(offset: 2);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    await tester.enterText(
      find.descendant(of: active, matching: find.byType(TextField)),
      '```',
    );
    await tester.pumpAndSettle();

    expect(controller.text, '```\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(active, findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: active, matching: find.byType(TextField)),
          )
          .controller
          ?.text,
      '```\n```',
    );
  });

  testWidgets('live preview auto-pairs typed emphasis through IME', (
    tester,
  ) async {
    final controller = IanvsMarkdownController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(fieldFinder).focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '*',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(controller.text, '**');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '*x*',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(controller.text, '*x*');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '*x**',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '*x*');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(tester.widget<TextField>(fieldFinder).controller?.text, '*x*');
  });

  testWidgets(
    'live preview keeps a word-adjacent backtick single through IME',
    (tester) async {
      final controller = IanvsMarkdownController(text: 'word')
        ..selection = const TextSelection.collapsed(offset: 4);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final fieldFinder = find.descendant(
        of: active,
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(fieldFinder).focusNode?.hasFocus, isTrue);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'word`',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.text, 'word`');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      expect(tester.widget<TextField>(fieldFinder).controller?.text, 'word`');
    },
  );

  testWidgets('live preview keeps an in-word bracket single through IME', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'word')
      ..selection = const TextSelection.collapsed(offset: 2);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(fieldFinder).focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'wo(rd',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, 'wo(rd');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(tester.widget<TextField>(fieldFinder).controller?.text, 'wo(rd');
  });

  testWidgets('live preview completes a typed Wiki link pair through IME', (
    tester,
  ) async {
    final controller = IanvsMarkdownController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '[',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(controller.text, '[]');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '[[]',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '[[]]');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(tester.widget<TextField>(fieldFinder).controller?.text, '[[]]');
  });

  testWidgets('live preview does not re-complete an inner closing fence', (
    tester,
  ) async {
    const source = '```dart\n``\n```';
    const caret = 10;
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection.collapsed(offset: caret);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(fieldFinder).focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '```dart\n```\n```',
        selection: TextSelection.collapsed(offset: caret + 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '```dart\n```\n```');
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: caret + 1),
    );
  });

  testWidgets('paired fence info keeps repeated empty code lines active', (
    tester,
  ) async {
    const paired = '```dart\n```';
    final controller = IanvsMarkdownController(text: paired)
      ..selection = const TextSelection.collapsed(offset: 7);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(fieldFinder).focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '```dart\n\n```',
        selection: TextSelection.collapsed(offset: 8),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '```dart\n\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '```dart\n\n\n```',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '```dart\n\n\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));
    expect(tester.widget<TextField>(fieldFinder).focusNode?.hasFocus, isTrue);
  });

  testWidgets('Enter at a closing fence start inserts an empty code line', (
    tester,
  ) async {
    const source = '```dart\nline\n```\n\nAfter code.';
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection.collapsed(offset: 13);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IanvsMarkdownCodeBlock));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    field.controller!.selection = const TextSelection.collapsed(offset: 13);
    await tester.pump();
    expect(field.focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '```dart\nline\n\n```',
        selection: TextSelection.collapsed(offset: 14),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '```dart\nline\n\n```\n\nAfter code.');
    expect(controller.selection, const TextSelection.collapsed(offset: 14));
  });

  testWidgets('Backspace at a closing fence start merges the fence line', (
    tester,
  ) async {
    const source = '```dart\nline\n```\n\nAfter code.';
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection.collapsed(offset: 13);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IanvsMarkdownCodeBlock));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    field.controller!.selection = const TextSelection.collapsed(offset: 13);
    await tester.pump();
    expect(field.focusNode?.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '```dart\nline```',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '```dart\nline```\n\nAfter code.');
    expect(controller.selection, const TextSelection.collapsed(offset: 12));
  });

  testWidgets('four-backtick code keeps inner triples active on Enter', (
    tester,
  ) async {
    const paired =
        '````markdown\n'
        'literal ``` inner\n'
        '````';
    const source = '$paired\n\nAfter code.';
    final bodyEnd = paired.indexOf('\n````');
    final controller = IanvsMarkdownController(text: source)
      ..selection = TextSelection.collapsed(offset: bodyEnd);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IanvsMarkdownCodeBlock));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final fieldFinder = find.descendant(
      of: active,
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    field.controller!.selection = TextSelection.collapsed(offset: bodyEnd);
    await tester.pump();

    const expectedBlock =
        '````markdown\n'
        'literal ``` inner\n'
        '\n'
        '````';
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: expectedBlock,
        selection: TextSelection.collapsed(offset: bodyEnd + 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '$expectedBlock\n\nAfter code.');
    expect(controller.selection, TextSelection.collapsed(offset: bodyEnd + 1));
    expect(find.byType(IanvsMarkdownCodeBlock), findsNothing);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsOneWidget,
    );
  });

  testWidgets('Enter after a closing fence hands input to a new paragraph', (
    tester,
  ) async {
    const fenced = '```dart\nalpha\n```';
    final controller = IanvsMarkdownController(text: fenced);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 720,
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var field = tester.widget<TextField>(find.byType(TextField));
    field.controller!.value = const TextEditingValue(
      text: '$fenced\n',
      selection: TextSelection.collapsed(offset: fenced.length + 1),
    );
    await tester.pump();

    expect(controller.text, '$fenced\n');
    field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '$fenced\n');

    final local = field.controller!.value;
    field.controller!.value = TextEditingValue(
      text: '${local.text}tail',
      selection: TextSelection.collapsed(offset: local.text.length + 4),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '$fenced\ntail');
    field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'tail');
    expect(controller.selection, const TextSelection.collapsed(offset: 22));
  });

  testWidgets('live preview continues an indented list inside a quote', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '>     - item')
      ..selection = const TextSelection.collapsed(offset: 12);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '>     - item\n',
        selection: TextSelection.collapsed(offset: 13),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '>     - item\n>     - ');
    expect(controller.selection, const TextSelection.collapsed(offset: 21));
  });

  testWidgets(
    'tab-separated rendered list keeps native newline editing semantics',
    (tester) async {
      final controller = IanvsMarkdownController(text: '-\tone')
        ..selection = const TextSelection.collapsed(offset: 5);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '-\tone\n',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.text, '-\tone\n');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
    },
  );

  testWidgets('live preview exits an empty EOF list without an extra gap', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '- root')
      ..selection = const TextSelection.collapsed(offset: 6);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '- root\n',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '- root\n- ');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '- \n',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '- root\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 7));

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = find.descendant(of: active, matching: find.byType(TextField));
    expect(tester.widget<TextField>(field).controller!.text, '- root\n');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '- root\nplain',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '- root\nplain');
    expect(controller.selection, const TextSelection.collapsed(offset: 12));
  });

  testWidgets('live preview renumbers ordered siblings inserted with Enter', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '1. A\n2. B')
      ..selection = const TextSelection.collapsed(offset: 4);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '1. A\n',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '1. A\n2. \n3. B');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = find.descendant(of: active, matching: find.byType(TextField));
    expect(tester.widget<TextField>(field).controller!.text, '2. ');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '2. \n',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '1. A\n\n2. B');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
  });

  testWidgets('live preview renumbers nested siblings after empty outdent', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '1. A\n    1. B\n    2. C\n2. D',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = find.descendant(of: active, matching: find.byType(TextField));
    final activatedField = tester.widget<TextField>(field);
    expect(activatedField.controller!.text, '    1. B');
    activatedField.controller!.selection = const TextSelection.collapsed(
      offset: 8,
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '    1. B\n',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '1. A\n    1. B\n    2. \n    3. C\n2. D');

    final activeField = tester.widget<TextField>(field);
    final beforeOutdent = activeField.controller!.text;
    expect(beforeOutdent, '    2. ');
    final localCaret = activeField.controller!.selection.extentOffset;
    expect(localCaret, 7);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: beforeOutdent.replaceRange(localCaret, localCaret, '\n'),
        selection: TextSelection.collapsed(offset: localCaret + 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '1. A\n    1. B\n2. \n    1. C\n3. D');
    expect(controller.selection, const TextSelection.collapsed(offset: 17));
  });

  testWidgets('mismatched table headers remain one editable paragraph', (
    tester,
  ) async {
    const source =
        '| A | B |\n'
        '| --- | --- | --- |\n'
        '| one | two | three |';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Editable Markdown table'), findsNothing);
    await tester.tap(find.textContaining('| A | B |'));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
  });

  testWidgets('single-column tables expose editable cells', (tester) async {
    const source = '| A |\n| --- |\n| one |';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.bySemanticsLabel('Editable Markdown table'),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    expect(tester.widget<TextField>(fields.first).controller?.text, 'A');
    expect(tester.widget<TextField>(fields.last).controller?.text, 'one');
  });

  testWidgets('code-indented table delimiters stay in one source paragraph', (
    tester,
  ) async {
    const source =
        '| A | B |\n'
        '    | --- | --- |\n'
        '| one | two |';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Editable Markdown table'), findsNothing);
    await tester.tap(find.textContaining('| A | B |'));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
  });

  testWidgets('inline HTML stays in table rows but HTML comments interrupt', (
    tester,
  ) async {
    final inlineController = IanvsMarkdownController(
      text:
          '| A | B |\n'
          '| --- | --- |\n'
          '<em>one</em> | two',
    );
    addTearDown(inlineController.dispose);
    await tester.pumpWidget(app(inlineController));
    await tester.pumpAndSettle();

    var fields = find.descendant(
      of: find.bySemanticsLabel('Editable Markdown table'),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(4));
    expect(
      tester.widget<TextField>(fields.at(2)).controller?.text,
      '<em>one</em>',
    );

    final commentController = IanvsMarkdownController(
      text:
          '| A | B |\n'
          '| --- | --- |\n'
          '| one | two |\n'
          '<!-- stop -->\n'
          'After',
    );
    addTearDown(commentController.dispose);
    await tester.pumpWidget(app(commentController));
    await tester.pumpAndSettle();

    fields = find.descendant(
      of: find.bySemanticsLabel('Editable Markdown table'),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(4));
    expect(find.text('After'), findsOneWidget);
  });

  testWidgets('table cells edit their source ranges without exposing pipes', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '| A | B |\n| :--- | ---: |\n| one | two |',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.bySemanticsLabel('Editable Markdown table'),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(4));
    expect(tester.widget<TextField>(fields.at(1)).textAlign, TextAlign.right);
    await tester.tap(fields.at(3));
    await tester.pump();
    final editedField = tester.widget<TextField>(fields.at(3));
    editedField.controller?.selection = const TextSelection.collapsed(
      offset: 3,
    );
    await tester.pump();
    final originalCellEnd = controller.text.indexOf('two') + 'two'.length;
    expect(
      controller.selection,
      TextSelection.collapsed(offset: originalCellEnd),
    );
    await tester.enterText(fields.at(3), 'updated');
    await tester.pump();

    expect(controller.text, '| A | B |\n| :--- | ---: |\n| one | updated |');
    expect(
      controller.selection,
      TextSelection.collapsed(
        offset: controller.text.indexOf('updated') + 'updated'.length,
      ),
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
    controller.undo();
    await tester.pump();
    expect(controller.text, '| A | B |\n| :--- | ---: |\n| one | two |');
    expect(
      controller.selection,
      TextSelection.collapsed(offset: originalCellEnd),
    );
  });

  testWidgets('stale table input cannot edit an externally shifted table', (
    tester,
  ) async {
    const source =
        '| H | I |\n'
        '| --- | --- |\n'
        '| alpha | beta |';
    const shifted = 'prefix\n\n$source';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
    await tester.tap(cell);
    await tester.pump();
    await tester.showKeyboard(cell);
    expect(tester.testTextInput.isVisible, isTrue);

    controller.text = shifted;
    tester.testTextInput.enterText('Z');
    await tester.pumpAndSettle();

    expect(controller.text, shifted);
    expect(find.text('prefix'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('ianvs-markdown-table-1-0')),
          )
          .controller
          ?.text,
      'alpha',
    );
  });

  testWidgets('rapid table input resolves the latest cell source', (
    tester,
  ) async {
    const source =
        '| H | I |\n'
        '| --- | --- |\n'
        '| alpha | beta |';
    const expected =
        '| H | I |\n'
        '| --- | --- |\n'
        '| AB | beta |';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
    await tester.tap(cell);
    await tester.pump();
    await tester.showKeyboard(cell);

    tester.testTextInput.enterText('A');
    tester.testTextInput.enterText('AB');
    await tester.pumpAndSettle();

    expect(controller.text, expected);
    expect(
      controller.selection,
      TextSelection.collapsed(offset: expected.indexOf('AB') + 'AB'.length),
    );
  });

  testWidgets('inactive table cells render inline Markdown until focused', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '| A | B |\n| --- | --- |\n| **Bold** | `code` |',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final boldFinder = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
    TextSpan span() {
      final field = tester.widget<TextField>(boldFinder);
      return field.controller!.buildTextSpan(
        context: tester.element(boldFinder),
        style: field.style,
        withComposing: false,
      );
    }

    var boldSpan = span().children!.cast<TextSpan>().toList();
    final hiddenMarkers = boldSpan.where((item) => item.text == '**').toList();
    expect(hiddenMarkers, hasLength(2));
    expect(hiddenMarkers.every((item) => item.style?.fontSize == .01), isTrue);
    expect(
      boldSpan.singleWhere((item) => item.text == 'Bold').style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      boldSpan.singleWhere((item) => item.text == 'Bold').style?.color,
      IanvsMarkdownThemeData.light.strongForeground,
    );

    await tester.tap(boldFinder);
    await tester.pump();
    expect(
      tester.widget<TextField>(boldFinder).controller?.selection.isCollapsed,
      isTrue,
    );
    boldSpan = span().children!.cast<TextSpan>().toList();
    expect(
      boldSpan
          .where((item) => item.text == '**')
          .every((item) => item.style?.fontSize == 13.5),
      isTrue,
    );
  });

  testWidgets('first table cell click keeps its visual caret position', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text:
          '| Left | Center |\n'
          '| --- | --- |\n'
          '| abcdefghij | alpha beta |',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final first = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
    final firstField = tester.widget<TextField>(first);
    final editable = editableWithin(tester, first);
    final caret = editable.getLocalRectForCaret(const TextPosition(offset: 5));
    await tester.tapAt(
      editable.localToGlobal(Offset(caret.left, caret.center.dy)),
    );
    await tester.pump();

    expect(firstField.focusNode?.hasFocus, isTrue);
    expect(
      firstField.controller?.selection,
      const TextSelection.collapsed(offset: 5),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final second = tester.widget<TextField>(
      find.byKey(const ValueKey('ianvs-markdown-table-1-1')),
    );
    expect(second.focusNode?.hasFocus, isTrue);
    expect(
      second.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 10),
    );
  });

  testWidgets('tables use content-aware columns and compact Obsidian rows', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text:
          '| Wide | Center | Right |\n'
          '| --- | :---: | ---: |\n'
          '| A deliberately long first-column value | code | '
          '[Guide](docs/a/very/long/path/that/is/not-visible.md) |',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final first = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
    final center = find.byKey(const ValueKey('ianvs-markdown-table-1-1'));
    final right = find.byKey(const ValueKey('ianvs-markdown-table-1-2'));
    expect(
      tester.getSize(first).width,
      greaterThan(tester.getSize(center).width),
    );
    expect(
      tester.getSize(first).width,
      greaterThan(tester.getSize(right).width),
    );
    expect(tester.getSize(center).height, 27);

    final table = tester.widget<Table>(find.byType(Table));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('ianvs-markdown-editable-table')))
          .width,
      greaterThan(700),
    );
    expect(tester.getSize(find.byType(Table)).width, greaterThan(670));
    expect(table.defaultColumnWidth, isA<IntrinsicColumnWidth>());
    expect(table.columnWidths?[0], isA<IntrinsicColumnWidth>());
    expect(table.columnWidths?[1], isA<IntrinsicColumnWidth>());
    final border = table.border!;
    expect(border.top.color, IanvsMarkdownThemeData.light.borderSoft);
    expect(
      (table.children.first.decoration! as BoxDecoration).color,
      IanvsMarkdownThemeData.light.surfaceMuted,
    );
  });

  testWidgets('table semantics expose headers and inactive cells before edit', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: r'''| Left | Right |
| --- | ---: |
| **Bold** | Escaped \| pipe |
| Double \\*em* | Triple \\\*literal* |
| Non \\a | Plain |''',
    );
    addTearDown(controller.dispose);
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(tester.getSemantics(find.byType(Table)).role, SemanticsRole.table);
    final header = tester.getSemantics(
      find.byKey(const ValueKey('ianvs-markdown-table-cell-semantics-0-0')),
    );
    final body = tester.getSemantics(
      find.byKey(const ValueKey('ianvs-markdown-table-cell-semantics-1-1')),
    );
    expect(header.role, SemanticsRole.columnHeader);
    expect(header.label, 'Left');
    expect(body.role, SemanticsRole.cell);
    expect(body.label, 'Escaped | pipe');
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('ianvs-markdown-table-cell-semantics-2-0'),
            ),
          )
          .label,
      r'Double \em',
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('ianvs-markdown-table-cell-semantics-2-1'),
            ),
          )
          .label,
      r'Triple \*literal*',
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('ianvs-markdown-table-cell-semantics-3-0'),
            ),
          )
          .label,
      r'Non \a',
    );

    final escapedFinder = find.byKey(
      const ValueKey('ianvs-markdown-table-1-1'),
    );
    TextSpan escapedSpan() {
      final field = tester.widget<TextField>(escapedFinder);
      return field.controller!.buildTextSpan(
        context: tester.element(escapedFinder),
        style: field.style,
        withComposing: false,
      );
    }

    expect(
      escapedSpan().children!
          .cast<TextSpan>()
          .singleWhere((item) => item.text == r'\')
          .style
          ?.fontSize,
      .01,
    );

    await tester.tap(escapedFinder);
    await tester.pump();

    final revealedEscapedSpans = escapedSpan().children!.cast<TextSpan>();
    expect(
      revealedEscapedSpans.map((item) => item.text).join(),
      r'Escaped \| pipe',
    );
    expect(
      revealedEscapedSpans
          .where((item) => item.text?.contains(r'\') ?? false)
          .every((item) => item.style?.fontSize == 13.5),
      isTrue,
    );

    final activeBody = tester.getSemantics(
      find.byKey(const ValueKey('ianvs-markdown-table-cell-semantics-1-1')),
    );
    expect(activeBody.role, SemanticsRole.cell);
    expect(activeBody.label, isEmpty);
    expect(activeBody.value, r'Escaped \| pipe');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('ianvs-markdown-table-1-1')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    semanticsHandle.dispose();
  });

  testWidgets('irregular table rows retain extra cells and pad missing cells', (
    tester,
  ) async {
    const source =
        '| A | B | C |\n'
        '| --- | --- | --- |\n'
        '| one |\n'
        '| x | y | z | extra |';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.bySemanticsLabel('Editable Markdown table'),
        matching: find.byType(TextField),
      ),
      findsNWidgets(12),
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('ianvs-markdown-table-cell-semantics-1-1'),
            ),
          )
          .label,
      isEmpty,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('ianvs-markdown-table-cell-semantics-2-3'),
            ),
          )
          .label,
      'extra',
    );

    final paddedCell = find.byKey(const ValueKey('ianvs-markdown-table-1-2'));
    await tester.tap(paddedCell);
    await tester.pump();
    await tester.enterText(paddedCell, 'filled');
    await tester.pumpAndSettle();

    expect(
      controller.text,
      '| A | B | C |\n'
      '| --- | --- | --- |\n'
      '| one |  | filled |\n'
      '| x | y | z | extra |',
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('ianvs-markdown-table-cell-semantics-1-2'),
            ),
          )
          .value,
      'filled',
    );
    semanticsHandle.dispose();
  });

  testWidgets('pipe-less table rows stay editable until a blank boundary', (
    tester,
  ) async {
    const source =
        '| A | B |\n'
        '| --- | --- |\n'
        '| one | two |\n'
        'three\n'
        '\n'
        'After.';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.bySemanticsLabel('Editable Markdown table'),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(6));
    expect(tester.widget<TextField>(fields.at(4)).controller?.text, 'three');
    expect(tester.widget<TextField>(fields.at(5)).controller?.text, isEmpty);

    await tester.enterText(fields.at(5), 'filled');
    await tester.pumpAndSettle();

    expect(
      controller.text,
      '| A | B |\n'
      '| --- | --- |\n'
      '| one | two |\n'
      'three | filled |\n'
      '\n'
      'After.',
    );
  });

  testWidgets('table structure controls append and focus rows and columns', (
    tester,
  ) async {
    const original = '| A | B |\n| :--- | ---: |\n| one | two |';
    const withBlankRow =
        '| A   |   B |\n'
        '| :-- | --: |\n'
        '| one | two |\n'
        '|     |     |';
    final controller = IanvsMarkdownController(text: original);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    final firstCell = find.byKey(const ValueKey('ianvs-markdown-table-0-0'));
    await tester.tap(firstCell);
    await tester.pump();
    final addRow = find.bySemanticsLabel('在下方新增行');
    expect(addRow, findsOneWidget);
    await tester.tap(addRow);
    await tester.pumpAndSettle();

    expect(controller.text, withBlankRow);
    final newRowCell = tester.widget<TextField>(
      find.byKey(const ValueKey('ianvs-markdown-table-2-0')),
    );
    expect(newRowCell.focusNode?.hasFocus, isTrue);

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, original);

    await tester.tap(firstCell);
    await tester.pump();
    final addColumn = find.bySemanticsLabel('在右侧新增列');
    expect(addColumn, findsOneWidget);
    await tester.tap(addColumn);
    await tester.pumpAndSettle();

    expect(
      controller.text,
      '| A   |   B |     |\n'
      '| :-- | --: | --- |\n'
      '| one | two |     |',
    );
    final newHeaderCell = tester.widget<TextField>(
      find.byKey(const ValueKey('ianvs-markdown-table-0-2')),
    );
    expect(newHeaderCell.focusNode?.hasFocus, isTrue);
  });

  testWidgets(
    'table row drag handles reorder and normalize the exact source',
    (tester) async {
      const original =
          '| Name | Qty |\n'
          '| :--- | ---: |\n'
          '| Apples | 10 |\n'
          '| Pears | 2 |';
      final controller = IanvsMarkdownController(text: original);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final sourceHandle = find.byKey(
        const ValueKey('ianvs-markdown-table-row-drag-2'),
      );
      final targetHandle = find.byKey(
        const ValueKey('ianvs-markdown-table-row-drag-1'),
      );
      final opacity = find.byKey(
        const ValueKey('ianvs-markdown-table-row-drag-2-opacity'),
      );
      expect(tester.getSize(sourceHandle).width, 16);
      expect(
        tester.getSize(sourceHandle).height,
        tester
            .getSize(
              find.byKey(
                const ValueKey('ianvs-markdown-table-cell-surface-2-0'),
              ),
            )
            .height,
      );
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(sourceHandle));
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
      await mouse.down(tester.getCenter(sourceHandle));
      await tester.pump();
      await mouse.moveTo(tester.getCenter(targetHandle));
      await tester.pump();
      final draggingSourceSurface = tester.widget<Container>(
        find.byKey(const ValueKey('ianvs-markdown-table-cell-surface-2-0')),
      );
      final rowDropSurface = tester.widget<Container>(
        find.byKey(const ValueKey('ianvs-markdown-table-cell-surface-1-0')),
      );
      expect(
        (draggingSourceSurface.decoration! as BoxDecoration).color,
        isNotNull,
      );
      expect(
        ((rowDropSurface.decoration! as BoxDecoration).border! as Border)
            .top
            .width,
        2,
      );
      await mouse.up();
      await tester.pumpAndSettle();

      expect(
        controller.text,
        '| Name   | Qty |\n'
        '| :----- | --: |\n'
        '| Pears  |   2 |\n'
        '| Apples |  10 |',
      );
      final selectedSurface = tester.widget<Container>(
        find.byKey(const ValueKey('ianvs-markdown-table-cell-surface-1-0')),
      );
      expect((selectedSurface.decoration! as BoxDecoration).color, isNotNull);

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, original);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table column drag handles move alignment and every cell together',
    (tester) async {
      const original =
          '| Name | Qty |\n'
          '| :--- | ---: |\n'
          '| Apples | 10 |\n'
          '| Pears | 2 |';
      final controller = IanvsMarkdownController(text: original);
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final sourceHandle = find.byKey(
        const ValueKey('ianvs-markdown-table-column-drag-1'),
      );
      final targetHandle = find.byKey(
        const ValueKey('ianvs-markdown-table-column-drag-0'),
      );
      expect(tester.getSize(sourceHandle).height, 16);
      expect(
        tester.getSize(sourceHandle).width,
        tester
            .getSize(
              find.byKey(
                const ValueKey('ianvs-markdown-table-cell-surface-0-1'),
              ),
            )
            .width,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(sourceHandle));
      await tester.pump(const Duration(milliseconds: 120));
      await mouse.down(tester.getCenter(sourceHandle));
      await tester.pump();
      await mouse.moveTo(tester.getCenter(targetHandle));
      await tester.pump();
      final columnDropSurface = tester.widget<Container>(
        find.byKey(const ValueKey('ianvs-markdown-table-cell-surface-0-0')),
      );
      expect(
        ((columnDropSurface.decoration! as BoxDecoration).border! as Border)
            .left
            .width,
        2,
      );
      await mouse.up();
      await tester.pumpAndSettle();

      expect(
        controller.text,
        '| Qty | Name   |\n'
        '| --: | :----- |\n'
        '|  10 | Apples |\n'
        '|   2 | Pears  |',
      );
      final selectedSurface = tester.widget<Container>(
        find.byKey(const ValueKey('ianvs-markdown-table-cell-surface-0-0')),
      );
      expect((selectedSurface.decoration! as BoxDecoration).color, isNotNull);

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, original);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'mobile tables expose only the active row and column drag handles',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: '| A | B |\n| --- | --- |\n| one | two |',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      AnimatedOpacity handleOpacity(String axis, int index) =>
          tester.widget<AnimatedOpacity>(
            find.byKey(
              ValueKey('ianvs-markdown-table-$axis-drag-$index-opacity'),
            ),
          );

      expect(handleOpacity('row', 1).opacity, 0);
      expect(handleOpacity('column', 0).opacity, 0);
      await tester.tap(find.byKey(const ValueKey('ianvs-markdown-table-1-0')));
      await tester.pumpAndSettle();

      expect(handleOpacity('row', 1).opacity, 1);
      expect(handleOpacity('column', 0).opacity, 1);
      expect(handleOpacity('row', 0).opacity, 0);
      expect(handleOpacity('column', 1).opacity, 0);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'desktop table add strips reveal only when their edge is hovered',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: '| A | B |\n| --- | --- |\n| one | two |',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      final addRow = find.byKey(const ValueKey('ianvs-markdown-table-add-row'));
      final addColumn = find.byKey(
        const ValueKey('ianvs-markdown-table-add-column'),
      );
      AnimatedOpacity opacity(Finder control) => tester.widget<AnimatedOpacity>(
        find.descendant(of: control, matching: find.byType(AnimatedOpacity)),
      );
      expect(tester.getSize(addRow).height, 16);
      expect(tester.getSize(addColumn).width, 16);
      expect(opacity(addRow).opacity, 0);
      expect(opacity(addColumn).opacity, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('ianvs-markdown-table-1-0')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(opacity(addRow).opacity, 0);
      expect(opacity(addColumn).opacity, 0);

      await mouse.moveTo(tester.getCenter(addRow));
      await tester.pump(const Duration(milliseconds: 120));
      expect(opacity(addRow).opacity, 1);
      expect(opacity(addColumn).opacity, 0);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'RTL table column drag geometry follows logical column order',
    (tester) async {
      const original =
          '| A | B | C |\n'
          '| --- | --- | --- |\n'
          '| 1 | 2 | 3 |';
      final controller = IanvsMarkdownController(text: original);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 1000,
                height: 720,
                child: IanvsMarkdownLiveEditor(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sourceHandle = find.byKey(
        const ValueKey('ianvs-markdown-table-column-drag-2'),
      );
      final targetHandle = find.byKey(
        const ValueKey('ianvs-markdown-table-column-drag-0'),
      );
      expect(
        tester.getCenter(sourceHandle).dx,
        lessThan(tester.getCenter(targetHandle).dx),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(sourceHandle));
      await tester.pump(const Duration(milliseconds: 120));
      await mouse.down(tester.getCenter(sourceHandle));
      await tester.pump();
      await mouse.moveTo(tester.getCenter(targetHandle));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();

      expect(
        controller.text,
        '| C   | A   | B   |\n'
        '| --- | --- | --- |\n'
        '| 3   | 1   | 2   |',
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets('table keyboard navigation follows Obsidian cell flow', (
    tester,
  ) async {
    const original = '| A | B |\n| :--- | ---: |\n| one | two |';
    const withBlankRow =
        '| A   |   B |\n'
        '| :-- | --: |\n'
        '| one | two |\n'
        '|     |     |';
    final controller = IanvsMarkdownController(text: original);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    TextField field(String key) => tester.widget<TextField>(
      find.byKey(ValueKey('ianvs-markdown-table-$key')),
    );

    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-table-1-0')));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(field('1-1').focusNode?.hasFocus, isTrue);
    expect(
      field('1-1').controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, withBlankRow);
    expect(field('2-0').focusNode?.hasFocus, isTrue);

    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, original);

    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-table-0-0')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      controller.text,
      '|     |     |\n'
      '| :-- | --: |\n'
      '| A   |   B |\n'
      '| one | two |',
    );
    expect(field('0-1').focusNode?.hasFocus, isTrue);

    controller.undo();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-table-0-0')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(field('1-0').focusNode?.hasFocus, isTrue);
    expect(
      field('1-0').controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );

    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-table-1-1')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, withBlankRow);
    expect(field('2-1').focusNode?.hasFocus, isTrue);

    controller.undo();
    await tester.pumpAndSettle();
    final header = field('0-0');
    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-table-0-0')));
    header.controller?.selection = const TextSelection.collapsed(offset: 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(field('1-0').focusNode?.hasFocus, isTrue);
    expect(field('1-0').controller?.selection.extentOffset, 1);

    field('1-0').controller?.selection = const TextSelection.collapsed(
      offset: 3,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(field('1-1').focusNode?.hasFocus, isTrue);
    expect(field('1-1').controller?.selection.extentOffset, 0);
  });

  testWidgets(
    'table Option+Right stays in the focused cell at its boundary',
    (tester) async {
      const source = '| A | B |\n| --- | --- |\n| alpha | beta |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      final second = find.byKey(const ValueKey('ianvs-markdown-table-1-1'));
      await tester.tap(first);
      tester.widget<TextField>(first).controller?.selection =
          const TextSelection.collapsed(offset: 'alpha'.length);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(first).focusNode?.hasFocus, isTrue);
      expect(tester.widget<TextField>(second).focusNode?.hasFocus, isFalse);
      expect(
        tester.widget<TextField>(first).controller?.selection,
        const TextSelection.collapsed(offset: 'alpha'.length),
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table Command+A selects and replaces the entire Markdown document',
    (tester) async {
      const source =
          'pre\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| alpha | beta |\n\n'
          'post';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ianvs-markdown-table-1-0')));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(
        controller.selection,
        TextSelection(
          baseOffset: 0,
          extentOffset: source.length,
          isDirectional: true,
        ),
      );
      expect(controller.selection.textInside(controller.text), source);
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      expect(active, findsOneWidget);
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, source);

      field.controller?.value = const TextEditingValue(
        text: 'Z',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pumpAndSettle();
      expect(controller.text, 'Z');

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, source);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table formatting shortcuts target the focused cell and undo cleanly',
    (tester) async {
      const source =
          'pre\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| alpha | beta |\n\n'
          'post';
      final controller = IanvsMarkdownController(text: source)
        ..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      await tester.pump();

      Future<void> format(LogicalKeyboardKey key, String expectedCell) async {
        tester.widget<TextField>(cell).controller?.selection =
            const TextSelection(baseOffset: 0, extentOffset: 5);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(controller.text, contains('| $expectedCell | beta |'));
        expect(controller.text, startsWith('pre\n\n'));
        expect(tester.widget<TextField>(cell).controller?.text, expectedCell);

        controller.undo();
        await tester.pumpAndSettle();
        expect(controller.text, source);
        expect(tester.widget<TextField>(cell).controller?.text, 'alpha');
      }

      await format(LogicalKeyboardKey.keyB, '**alpha**');
      await format(LogicalKeyboardKey.keyI, '*alpha*');
      await format(LogicalKeyboardKey.keyK, '[alpha]()');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table formatting keeps preceding typing in a separate undo step',
    (tester) async {
      const source =
          '| H |\n'
          '| --- |\n'
          '| alpha |';
      const typed =
          '| H |\n'
          '| --- |\n'
          '| alphax |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      await tester.pump();
      await tester.enterText(cell, 'alphax');
      await tester.pump();
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection(baseOffset: 0, extentOffset: 6);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(controller.text, contains('| **alphax** |'));

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, typed);
      expect(tester.widget<TextField>(cell).controller?.text, 'alphax');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table smart paste targets the focused cell instead of stale selection',
    (tester) async {
      const url = 'https://example.com';
      const source =
          'pre\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| alpha | beta |\n\n'
          'post';
      const expected =
          'pre\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| [alpha](https://example.com) | beta |\n\n'
          'post';
      final controller = IanvsMarkdownController(text: source)
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      addTearDown(controller.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async => methodCall.method == 'Clipboard.getData'
            ? const <String, dynamic>{'text': url}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection(baseOffset: 0, extentOffset: 5);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, expected);
      expect(tester.widget<TextField>(cell).controller?.text, '[alpha]($url)');

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, source);
      expect(tester.widget<TextField>(cell).controller?.text, 'alpha');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table smart paste resolves the cell after awaiting the clipboard',
    (tester) async {
      const url = 'https://example.com';
      const source =
          '| H | I |\n'
          '| --- | --- |\n'
          '| alpha | beta |';
      const expected =
          '| H | I |\n'
          '| --- | --- |\n'
          '| LONGalpha | [beta](https://example.com) |';
      final clipboard = Completer<Map<String, dynamic>?>();
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) {
          if (methodCall.method == 'Clipboard.getData') {
            return clipboard.future;
          }
          return Future<Object?>.value();
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      final second = find.byKey(const ValueKey('ianvs-markdown-table-1-1'));
      await tester.tap(second);
      tester.widget<TextField>(second).controller?.selection =
          const TextSelection(baseOffset: 0, extentOffset: 4);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.tap(first);
      await tester.pump();
      await tester.enterText(first, 'LONGalpha');
      await tester.pump();
      expect(controller.text, contains('| LONGalpha | beta |'));

      clipboard.complete(const <String, dynamic>{'text': url});
      await tester.pumpAndSettle();

      expect(controller.text, expected);
      expect(tester.widget<TextField>(second).controller?.text, '[beta]($url)');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table smart paste keeps preceding typing in a separate undo step',
    (tester) async {
      const url = 'https://example.com';
      const source =
          '| H |\n'
          '| --- |\n'
          '| alpha |';
      const typed =
          '| H |\n'
          '| --- |\n'
          '| alphax |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async => methodCall.method == 'Clipboard.getData'
            ? const <String, dynamic>{'text': url}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      await tester.pump();
      await tester.enterText(cell, 'alphax');
      await tester.pump();
      expect(tester.widget<TextField>(cell).controller?.text, 'alphax');
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection(baseOffset: 0, extentOffset: 6);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(controller.text, contains('| [alphax]($url) |'));

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, typed);
      expect(tester.widget<TextField>(cell).controller?.text, 'alphax');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table smart paste escapes URL pipes without adding a column',
    (tester) async {
      const url = 'https://example.com/a|b';
      const source =
          '| H | I |\n'
          '| --- | --- |\n'
          '| alpha | beta |';
      const expected =
          '| H | I |\n'
          '| --- | --- |\n'
          r'| [alpha](https://example.com/a\|b) | beta |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async => methodCall.method == 'Clipboard.getData'
            ? const <String, dynamic>{'text': url}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      final second = find.byKey(const ValueKey('ianvs-markdown-table-1-1'));
      await tester.tap(first);
      tester.widget<TextField>(first).controller?.selection =
          const TextSelection(baseOffset: 0, extentOffset: 5);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, expected);
      expect(tester.widget<TextField>(second).controller?.text, 'beta');
      expect(
        find.byKey(const ValueKey('ianvs-markdown-table-1-2')),
        findsNothing,
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table plain paste reads once, filters, and keeps typing separate',
    (tester) async {
      const source =
          '| H |\n'
          '| --- |\n'
          '| alpha |';
      const typed =
          '| H |\n'
          '| --- |\n'
          '| alphax |';
      var clipboardReads = 0;
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method != 'Clipboard.getData') return null;
          clipboardReads += 1;
          return const <String, dynamic>{'text': 'plain|\ntext'};
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      await tester.pump();
      await tester.enterText(cell, 'alphax');
      await tester.pump();
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection(baseOffset: 0, extentOffset: 6);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(clipboardReads, 1);
      expect(controller.text, contains('| plaintext |'));
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, typed);
      controller.redo();
      await tester.pumpAndSettle();
      expect(controller.text, contains('| plaintext |'));
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table collapsed paste keeps preceding typing in a separate undo step',
    (tester) async {
      const source =
          '| H |\n'
          '| --- |\n'
          '| alpha |';
      const typed =
          '| H |\n'
          '| --- |\n'
          '| alphax |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async => methodCall.method == 'Clipboard.getData'
            ? const <String, dynamic>{'text': '-paste'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      await tester.pump();
      await tester.enterText(cell, 'alphax');
      await tester.pump();
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection.collapsed(offset: 6);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(controller.text, contains('| alphax-paste |'));

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, typed);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table paste ignores an unavailable platform clipboard',
    (tester) async {
      const source =
          '| H |\n'
          '| --- |\n'
          '| alpha |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            throw PlatformException(code: 'clipboard-unavailable');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection(baseOffset: 0, extentOffset: 5);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(controller.text, source);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table Option+Backspace deletes focused cell Markdown punctuation',
    (tester) async {
      const source =
          '**doc**\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| **cell** | beta |';
      const expected =
          '**doc**\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| **cell | beta |';
      final documentCaret = source.indexOf('**doc**') + '**doc**'.length;
      final controller = IanvsMarkdownController(text: source)
        ..selection = TextSelection.collapsed(offset: documentCaret);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection.collapsed(offset: '**cell**'.length);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(controller.text, expected);
      expect(tester.widget<TextField>(cell).controller?.text, '**cell');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table Option+Backspace keeps preceding deletion in a separate undo step',
    (tester) async {
      const source =
          '| H | I |\n'
          '| --- | --- |\n'
          '| x**cell** | beta |';
      const typed =
          '| H | I |\n'
          '| --- | --- |\n'
          '| **cell** | beta |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      await tester.pump();
      await tester.enterText(cell, '**cell**');
      await tester.pump();
      expect(controller.text, typed);
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection.collapsed(offset: '**cell**'.length);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(controller.text, contains('| **cell | beta |'));

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, typed);
      expect(tester.widget<TextField>(cell).controller?.text, '**cell**');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table Option+Left moves within focused cell Markdown punctuation',
    (tester) async {
      const source =
          '**doc**\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| **cell** | beta |';
      final documentCaret = source.indexOf('**doc**') + '**doc**'.length;
      final controller = IanvsMarkdownController(text: source)
        ..selection = TextSelection.collapsed(offset: documentCaret);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection.collapsed(offset: '**cell**'.length);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(controller.text, source);
      expect(
        controller.selection,
        TextSelection.collapsed(offset: source.indexOf('**cell**') + 6),
      );
      expect(
        tester.widget<TextField>(cell).controller?.selection,
        const TextSelection.collapsed(offset: 6),
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table Option+Delete deletes forward focused cell punctuation',
    (tester) async {
      const source =
          '**doc**\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| **cell** | beta |';
      const expected =
          '**doc**\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| cell** | beta |';
      final controller = IanvsMarkdownController(text: source)
        ..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection.collapsed(offset: 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(controller.text, expected);
      expect(tester.widget<TextField>(cell).controller?.text, 'cell**');
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table Shift+Option+Right extends within focused cell punctuation',
    (tester) async {
      const source =
          '**doc**\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| **cell** | beta |';
      final controller = IanvsMarkdownController(text: source)
        ..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection.collapsed(offset: 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(controller.text, source);
      final cellStart = source.indexOf('**cell**');
      expect(
        controller.selection,
        TextSelection(
          baseOffset: cellStart,
          extentOffset: cellStart + 2,
          isDirectional: true,
        ),
      );
      expect(
        tester.widget<TextField>(cell).controller?.selection,
        const TextSelection(
          baseOffset: 0,
          extentOffset: 2,
          isDirectional: true,
        ),
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table Option+Backspace keeps native fallback inside a plain cell',
    (tester) async {
      const source =
          '**doc**\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| alpha | beta |';
      const expected =
          '**doc**\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '|  | beta |';
      final documentCaret = source.indexOf('**doc**') + '**doc**'.length;
      final controller = IanvsMarkdownController(text: source)
        ..selection = TextSelection.collapsed(offset: documentCaret);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      await tester.tap(cell);
      tester.widget<TextField>(cell).controller?.selection =
          const TextSelection.collapsed(offset: 'alpha'.length);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(controller.text, expected);
      expect(tester.widget<TextField>(cell).controller?.text, isEmpty);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'table Command+D deletes the focused physical row',
    (tester) async {
      const source =
          'pre\n\n'
          '| H | I |\n'
          '| --- | --- |\n'
          '| a | b |\n'
          '| c | d |\n\n'
          'post';
      final controller = IanvsMarkdownController(text: source)
        ..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(controller.dispose);

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ianvs-markdown-table-1-0')));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(
        controller.text,
        'pre\n\n'
        '| H | I |\n'
        '| --- | --- |\n'
        '| c | d |\n\n'
        'post',
      );
      expect(controller.text, isNot(contains('| a | b |')));
      expect(controller.text, startsWith('pre\n\n'));

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, source);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets('source editor reports programmatic and history changes', (
    tester,
  ) async {
    final changes = <String>[];
    final controller = IanvsMarkdownController(text: 'one');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            onChanged: changes.add,
          ),
        ),
      ),
    );

    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.toggleInline('**');
    await tester.pump();
    controller.undo();
    await tester.pump();

    expect(changes, <String>['one****', 'one']);
  });

  testWidgets('source list prefixes degrade one source character at a time', (
    tester,
  ) async {
    const cases = <({String source, int caret, String after, int afterCaret})>[
      (source: '- root item', caret: 2, after: '-root item', afterCaret: 1),
      (
        source: '- [ ] task item',
        caret: 6,
        after: '- [ ]task item',
        afterCaret: 5,
      ),
      (
        source: '12. ordered item',
        caret: 4,
        after: '12.ordered item',
        afterCaret: 3,
      ),
      (
        source: '  - nested item',
        caret: 4,
        after: '  -nested item',
        afterCaret: 3,
      ),
    ];

    for (final testCase in cases) {
      final controller = IanvsMarkdownController(text: testCase.source)
        ..selection = TextSelection.collapsed(offset: testCase.caret);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownEditor(
              controller: controller,
              autofocus: true,
              showToolbar: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.text, testCase.after);
      expect(
        controller.selection,
        TextSelection.collapsed(offset: testCase.afterCaret),
      );
    }
  });

  testWidgets('source editor Command+D deletes selected physical lines', (
    tester,
  ) async {
    const source = 'alpha\nbeta\ngamma';
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection.collapsed(offset: 8);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.text, 'alpha\ngamma');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
    expect(controller.isDirty, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(controller.text, source);
    expect(controller.selection, const TextSelection.collapsed(offset: 8));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(controller.text, 'alpha\ngamma');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('source Command+D renumbers ordered siblings', (tester) async {
    final controller = IanvsMarkdownController(text: '1. A\n2. B\n3. C')
      ..selection = const TextSelection.collapsed(offset: 9);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.text, '1. A\n2. C');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));
  });

  testWidgets('source Command+D preserves visual position across emoji', (
    tester,
  ) async {
    const source = '😀😀\nabcdef\nlast';
    final controller = IanvsMarkdownController(text: source)
      ..selection = const TextSelection.collapsed(offset: 4);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fieldFinder = find.byKey(
      const ValueKey('ianvs-markdown-source-field'),
    );
    final editable = editableWithin(tester, fieldFinder);
    final headRect = editable.getLocalRectForCaret(
      const TextPosition(offset: 4),
    );
    final nextLineRect = editable.getLocalRectForCaret(
      const TextPosition(offset: 5),
    );
    final targetBeforeDelete = editable
        .getPositionForPoint(
          editable.localToGlobal(Offset(headRect.left, nextLineRect.center.dy)),
        )
        .offset
        .clamp(5, 11);
    final expectedCaret = targetBeforeDelete - 5;
    expect(expectedCaret, isNot(4));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(controller.text, 'abcdef\nlast');
    expect(
      controller.selection,
      TextSelection.collapsed(offset: expectedCaret),
    );
  });

  testWidgets('macOS Control+D keeps grapheme deletion in source mode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'A😀B\nnext')
        ..selection = const TextSelection.collapsed(offset: 1);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownEditor(
              controller: controller,
              autofocus: true,
              showToolbar: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );

      Future<void> controlD() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      controller.selection = const TextSelection.collapsed(offset: 1);
      await controlD();
      expect(controller.text, 'AB\nnext');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));

      controller.value = const TextEditingValue(
        text: 'alpha\nbeta',
        selection: TextSelection.collapsed(offset: 5),
      );
      await tester.pump();
      await controlD();
      expect(controller.text, 'alphabeta');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));

      controller.value = const TextEditingValue(
        text: 'alpha beta',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tester.pump();
      await controlD();
      expect(controller.text, ' beta');
      expect(controller.selection, const TextSelection.collapsed(offset: 0));

      controller.value = const TextEditingValue(
        text: 'last',
        selection: TextSelection.collapsed(offset: 4),
      );
      await tester.pump();
      await controlD();
      expect(controller.text, 'last');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+B and F keep source grapheme navigation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'A😀B\nnext')
        ..selection = const TextSelection.collapsed(offset: 1);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownEditor(
              controller: controller,
              autofocus: true,
              showToolbar: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );

      Future<void> control(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      controller.selection = const TextSelection.collapsed(offset: 1);
      await control(LogicalKeyboardKey.keyF);
      expect(controller.selection, const TextSelection.collapsed(offset: 3));

      await control(LogicalKeyboardKey.keyB);
      expect(controller.selection, const TextSelection.collapsed(offset: 1));

      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      await tester.pump();
      await control(LogicalKeyboardKey.keyF);
      expect(controller.selection, const TextSelection.collapsed(offset: 3));

      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      await tester.pump();
      await control(LogicalKeyboardKey.keyB);
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      expect(controller.text, 'A😀B\nnext');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS Control+P and N keep source visual-row navigation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = IanvsMarkdownController(text: 'abcd\nXY\nwxyz')
        ..selection = const TextSelection.collapsed(offset: 2);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownEditor(
              controller: controller,
              autofocus: true,
              showToolbar: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
      );

      Future<void> control(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      controller.selection = const TextSelection.collapsed(offset: 2);
      await control(LogicalKeyboardKey.keyN);
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.extentOffset, 7);
      await control(LogicalKeyboardKey.keyP);
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.extentOffset, 2);

      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      await tester.pump();
      await control(LogicalKeyboardKey.keyN);
      expect(controller.selection, const TextSelection.collapsed(offset: 3));

      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      await tester.pump();
      await control(LogicalKeyboardKey.keyP);
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      expect(controller.text, 'abcd\nXY\nwxyz');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('source editor completes a third typed backtick', (tester) async {
    final controller = IanvsMarkdownController(text: '``')
      ..selection = const TextSelection.collapsed(offset: 2);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      '```',
    );
    await tester.pump();

    expect(controller.text, '```\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));

    controller.undo();
    await tester.pump();
    expect(controller.text, '``');
    controller.redo();
    await tester.pump();
    expect(controller.text, '```\n```');
  });

  testWidgets('source editor auto-pairs typed underscore emphasis', (
    tester,
  ) async {
    final controller = IanvsMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '_',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(controller.text, '__');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '_x_',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '_x__',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    expect(controller.text, '_x_');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
  });

  testWidgets('source editor preserves word-adjacent backtick context', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'word')
      ..selection = const TextSelection.collapsed(offset: 4);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'word`',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(controller.text, 'word`');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'word``',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'word```',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.pump();

    expect(controller.text, 'word```\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
  });

  testWidgets('source editor preserves in-word bracket context', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'word')
      ..selection = const TextSelection.collapsed(offset: 2);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'wo(rd',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    expect(controller.text, 'wo(rd');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
  });

  testWidgets('source editor completes a typed Wiki link pair', (tester) async {
    final controller = IanvsMarkdownController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '[',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(controller.text, '[]');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '[[]',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    expect(controller.text, '[[]]');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });

  testWidgets('source editor continues an indented list inside a quote', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '>     - item')
      ..selection = const TextSelection.collapsed(offset: 12);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '>     - item\n',
        selection: TextSelection.collapsed(offset: 13),
      ),
    );
    await tester.pump();

    expect(controller.text, '>     - item\n>     - ');
    expect(controller.selection, const TextSelection.collapsed(offset: 21));
  });

  testWidgets('source editor renumbers ordered siblings inserted with Enter', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '1. A\n2. B')
      ..selection = const TextSelection.collapsed(offset: 4);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownEditor(
            controller: controller,
            autofocus: true,
            showToolbar: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '1. A\n\n2. B',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(controller.text, '1. A\n2. \n3. B');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('source editor layers fenced code surfaces behind text', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '# Source\n\n```dart\nfinal value = 1;\n```\n\nTail',
    )..selection = const TextSelection.collapsed(offset: 24);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 560,
            child: IanvsMarkdownEditor(
              controller: controller,
              showToolbar: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final background = find.byKey(
      const ValueKey('ianvs-markdown-source-code-backgrounds'),
    );
    expect(background, findsOneWidget);
    expect(tester.getSize(background), const Size(800, 560));
    expect(tester.widget<CustomPaint>(background).painter, isNotNull);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
    );
    expect(field.decoration?.filled, isFalse);

    controller.text = 'Plain source';
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('source editor paints Border quote surfaces behind text', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(
      text: '> Outer\n> > Nested\nLazy continuation\n\nTail',
    )..selection = const TextSelection.collapsed(offset: 18);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 560,
            child: IanvsMarkdownEditor(
              controller: controller,
              showToolbar: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final quoteBackground = find.byKey(
      const ValueKey('ianvs-markdown-source-quote-backgrounds'),
    );
    expect(quoteBackground, findsOneWidget);
    expect(tester.getSize(quoteBackground), const Size(800, 560));
    expect(tester.widget<CustomPaint>(quoteBackground).painter, isNotNull);
    final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
    expect(field, findsOneWidget);

    final stack = tester.widget<Stack>(
      find.ancestor(of: field, matching: find.byType(Stack)).first,
    );
    final quoteIndex = stack.children.indexWhere(
      (child) =>
          child is IgnorePointer &&
          child.child is CustomPaint &&
          (child.child! as CustomPaint).key ==
              const ValueKey('ianvs-markdown-source-quote-backgrounds'),
    );
    final fieldIndex = stack.children.indexWhere((child) => child is Focus);
    expect(quoteIndex, greaterThanOrEqualTo(0));
    expect(fieldIndex, greaterThan(quoteIndex));

    controller.text = 'Plain source';
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Iterable<TextSpan> _textSpanLeaves(TextSpan span) sync* {
  if (span.text != null) yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) yield* _textSpanLeaves(child);
  }
}

bool _spanContainsDecoration(
  InlineSpan span, {
  required String text,
  required TextDecoration decoration,
  TextDecoration? inheritedDecoration,
}) {
  if (span is! TextSpan) return false;
  final effectiveDecoration = span.style?.decoration ?? inheritedDecoration;
  if ((span.text?.contains(text) ?? false) &&
      (effectiveDecoration?.contains(decoration) ?? false)) {
    return true;
  }
  return (span.children ?? const <InlineSpan>[]).any(
    (child) => _spanContainsDecoration(
      child,
      text: text,
      decoration: decoration,
      inheritedDecoration: effectiveDecoration,
    ),
  );
}

bool _spanContainsColor(
  InlineSpan span, {
  required String text,
  required Color color,
  Color? inheritedColor,
}) {
  if (span is! TextSpan) return false;
  final effectiveColor = span.style?.color ?? inheritedColor;
  if ((span.text?.contains(text) ?? false) && effectiveColor == color) {
    return true;
  }
  return (span.children ?? const <InlineSpan>[]).any(
    (child) => _spanContainsColor(
      child,
      text: text,
      color: color,
      inheritedColor: effectiveColor,
    ),
  );
}
