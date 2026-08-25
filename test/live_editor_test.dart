import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/code_surface.dart';

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

  testWidgets('live links absorb normal clicks while line space edits source', (
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
    await tester.pump();
    expect(openedHref, isNull);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );

    final renderedBlock = find.byKey(
      const ValueKey('ianvs-markdown-block-0-paragraph'),
    );
    final rect = tester.getRect(renderedBlock);
    await tester.tapAt(Offset(rect.right - 16, rect.center.dy));
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, source);
    expect(controller.text, source);

    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Label'));
    await tester.pump();
    expect(openedHref, 'https://example.com/path');
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
          find.descendant(of: active, matching: find.byType(Checkbox)),
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
        find.descendant(of: active, matching: find.byType(Checkbox)),
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

  testWidgets('empty ATX prefix immediately paints its heading rail', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: '# ');
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
      findsOneWidget,
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '# ');
    expect(controller.text, '# ');
  });

  testWidgets('bare ATX markers wait for a space before entering heading UI', (
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

  testWidgets('compact properties expand and activate exact YAML source', (
    tester,
  ) async {
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
    expect(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-row-status')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.text('status'), findsOneWidget);
    expect(find.text('没有值'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-row-status')),
    );
    await tester.pump();

    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    expect(active, findsOneWidget);
    final field = find.descendant(of: active, matching: find.byType(TextField));
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
      find.descendant(of: active, matching: find.byType(Checkbox)),
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
          .widget<Text>(
            find.descendant(
              of: find.byKey(
                const ValueKey('ianvs-markdown-active-list-marker'),
              ),
              matching: find.byType(Text),
            ),
          )
          .data,
      '•',
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
    final active = tester.widget<Container>(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
    );
    expect(
      (active.decoration! as BoxDecoration).color,
      IanvsMarkdownThemeData.light.surfaceRaised,
    );
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

    final leftOffset = await activateAt(44);
    final rightOffset = await activateAt(170);

    expect(leftOffset, greaterThanOrEqualTo(2));
    expect(rightOffset, greaterThan(leftOffset));
    expect(rightOffset, lessThanOrEqualTo(source.length));
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
    expect(find.textContaining('Hidden'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-callout-toggle-warning')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Hidden'), findsOneWidget);
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
    'active inline code keeps compact mono styling and local markers',
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
        code.style?.backgroundColor,
        IanvsMarkdownThemeData.light.surfaceHover,
      );
      var markers = leaves.where((leaf) => leaf.text == '`').toList();
      expect(markers, hasLength(2));
      expect(markers.every((leaf) => leaf.style?.fontSize == .01), isTrue);

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
      expect(controller.text, source);
    },
  );

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

    await tester.tap(find.text('formula:E = mc^2'));
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
    var delimiters = _textSpanLeaves(
      span(),
    ).where((leaf) => leaf.text == r'$').toList();
    expect(delimiters, hasLength(2));
    expect(delimiters.every((leaf) => leaf.style?.fontSize == .01), isTrue);

    field.controller!.selection = TextSelection.collapsed(
      offset: source.indexOf('mc'),
    );
    await tester.pump();
    delimiters = _textSpanLeaves(
      span(),
    ).where((leaf) => leaf.text == r'$').toList();
    expect(delimiters.every((leaf) => leaf.style?.fontSize != .01), isTrue);
    expect(controller.text, source);
  });

  testWidgets('live preview keeps Obsidian editing metadata visible', (
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
    expect(find.text(' ^block-id'), findsOneWidget);
    expect(find.text('[^note]'), findsOneWidget);
    expect(find.text('^[inline body]'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.textContaining('Definition with'), findsOneWidget);
    expect(find.textContaining('[^note]:'), findsNothing);

    await tester.tap(find.text('%%secret%%'));
    await tester.pump();
    final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, 'Visible %%secret%% after. ^block-id');
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
    expect(field.controller?.selection.isCollapsed, isTrue);
    expect(field.controller?.selection.extentOffset, 18);
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
      '•',
    );
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
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(controller.text, '- [x] Open');
      expect(controller.isDirty, isTrue);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-block')),
        findsNothing,
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
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
    },
  );

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
      find.descendant(of: active, matching: find.byType(Checkbox)),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(
      find.descendant(of: active, matching: find.byType(TextField)),
    );
    expect(field.controller?.text, '- [ ] ');
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
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, IanvsMarkdownThemeData.light.surfaceRaised);
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
    expect(
      container.padding,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
    final codeLineRail = find.byKey(
      const ValueKey('ianvs-markdown-active-code-line-rail'),
    );
    expect(codeLineRail, findsOneWidget);
    final positionedRail = tester.widget<Positioned>(codeLineRail);
    expect(positionedRail.left, -31);
    expect(positionedRail.top, isNotNull);
    expect(positionedRail.bottom, isNull);
    final rail = positionedRail.child as Container;
    expect(rail.constraints?.minWidth, 3);
    expect(tester.getSize(codeLineRail).height, inInclusiveRange(14, 16));
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
      tester.getSize(find.byType(IanvsMarkdownCodeBlock)).height,
      greaterThanOrEqualTo(36),
    );

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

    controller.mode = IanvsMarkdownEditorMode.preview;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-live-empty-fenced-code')),
      findsNothing,
    );
    expect(find.byType(IanvsMarkdownCodeBlock), findsOneWidget);
    expect(find.text(source), findsNothing);
    semanticsHandle.dispose();
  });

  testWidgets(
    'live preview indented code uses line rails without fenced chrome',
    (tester) async {
      const source =
          'Before.\n\n'
          '    const first = 1;\n'
          '\n'
          '\treturn first;\n\n'
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
      expect(find.text('const first = 1;'), findsOneWidget);
      expect(find.text('return first;'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-indented-code-line-1')),
        findsOneWidget,
      );
      final firstLine = tester.widget<Container>(
        find.byKey(const ValueKey('ianvs-markdown-indented-code-line-0')),
      );
      final lineDecoration = firstLine.decoration! as BoxDecoration;
      expect((lineDecoration.border! as Border).left.width, 1);

      await tester.tap(find.text('const first = 1;'));
      await tester.pumpAndSettle();
      final active = find.byKey(const ValueKey('ianvs-markdown-active-block'));
      final field = tester.widget<TextField>(
        find.descendant(of: active, matching: find.byType(TextField)),
      );
      expect(field.controller?.text, '    const first = 1;\n\n\treturn first;');
      expect(controller.text, source);
    },
  );

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

  testWidgets('active code rail follows the caret visual row', (tester) async {
    final longToken = List.filled(12, 'abcdef0123456789').join();
    final source = '```text\n$longToken\n```';
    final contentStart = source.indexOf('\n') + 1;
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
    final firstRowY = tester.getTopLeft(rail).dy;
    final railHeight = tester.getSize(rail).height;
    expect(railHeight, inInclusiveRange(14, 16));
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-code-line-marker')),
      findsNothing,
    );

    controller.selection = TextSelection.collapsed(
      offset: contentStart + longToken.length - 2,
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(rail).dy, greaterThan(firstRowY));
    expect(tester.getSize(rail).height, railHeight);
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
    expect(activatedField.controller!.text, '1. A\n    1. B\n    2. C');
    activatedField.controller!.selection = const TextSelection.collapsed(
      offset: 13,
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '1. A\n    1. B\n\n    2. C',
        selection: TextSelection.collapsed(offset: 14),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '1. A\n    1. B\n    2. \n    3. C\n2. D');

    final activeField = tester.widget<TextField>(field);
    final beforeOutdent = activeField.controller!.text;
    expect(beforeOutdent, '1. A\n    1. B\n    2. \n    3. C');
    final localCaret = activeField.controller!.selection.extentOffset;
    expect(localCaret, 21);
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
    await tester.enterText(fields.at(3), 'updated');
    await tester.pump();

    expect(controller.text, '| A | B |\n| :--- | ---: |\n| one | updated |');
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
    controller.undo();
    await tester.pump();
    expect(controller.text, '| A | B |\n| :--- | ---: |\n| one | two |');
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
      FontWeight.w700,
    );

    await tester.tap(boldFinder);
    await tester.pump();
    expect(
      tester.widget<TextField>(boldFinder).controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 8),
    );
    boldSpan = span().children!.cast<TextSpan>().toList();
    expect(
      boldSpan
          .where((item) => item.text == '**')
          .every((item) => item.style?.fontSize == 13.5),
      isTrue,
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
    expect(tester.getSize(center).height, inInclusiveRange(20, 26));

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
      text:
          '| Left | Right |\n'
          '| --- | ---: |\n'
          '| **Bold** | Escaped \\| pipe |',
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

  testWidgets('table structure controls append and focus rows and columns', (
    tester,
  ) async {
    const original = '| A | B |\n| :--- | ---: |\n| one | two |';
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

    expect(controller.text, '$original\n|  |  |');
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
      '| A | B |  |\n| :--- | ---: | --- |\n| one | two |  |',
    );
    final newHeaderCell = tester.widget<TextField>(
      find.byKey(const ValueKey('ianvs-markdown-table-0-2')),
    );
    expect(newHeaderCell.focusNode?.hasFocus, isTrue);
  });

  testWidgets('table keyboard navigation follows Obsidian cell flow', (
    tester,
  ) async {
    const original = '| A | B |\n| :--- | ---: |\n| one | two |';
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
    expect(controller.text, '$original\n|  |  |');
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
      '|  |  |\n| :--- | ---: |\n| A | B |\n| one | two |',
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
    expect(controller.text, '$original\n|  |  |');
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
