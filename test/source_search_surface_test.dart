import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

const _sourceFieldKey = ValueKey('ianvs-markdown-source-field');
const _highlightKey = ValueKey('ianvs-markdown-source-highlight');
const _findFieldKey = ValueKey('find-field');

Finder get _editable => find.descendant(
  of: find.byKey(_sourceFieldKey),
  matching: find.byType(EditableText),
);

Widget _host({
  required IanvsMarkdownController controller,
  ScrollController? scroll,
  FocusNode? sourceFocus,
  FocusNode? findFocus,
  IanvsMarkdownSourceHighlight? highlight,
  bool readOnly = false,
  bool showToolbar = false,
  bool highlightSyntax = false,
  bool enclosingShortcuts = false,
  bool enableModeShortcuts = true,
  IanvsMarkdownSaveCallback? onSaveRequested,
}) {
  Widget source = IanvsMarkdownEditor(
    controller: controller,
    scrollController: scroll,
    focusNode: sourceFocus,
    readOnly: readOnly,
    highlightedRange: highlight,
    showToolbar: showToolbar,
    highlightSyntax: highlightSyntax,
    enableModeShortcuts: enableModeShortcuts,
    onSaveRequested: onSaveRequested,
  );
  if (enclosingShortcuts) {
    source = IanvsMarkdownEditorShortcuts(
      controller: controller,
      child: source,
    );
  }
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 420,
        height: 340,
        child: Column(
          children: [
            TextField(key: _findFieldKey, focusNode: findFocus),
            Expanded(child: source),
          ],
        ),
      ),
    ),
  );
}

List<Rect> _paintedHighlights(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  tester
      .widget<CustomPaint>(find.byKey(_highlightKey))
      .painter!
      .paint(canvas, tester.getSize(find.byKey(_highlightKey)));
  return canvas.invocations
      .where((call) => call.invocation.memberName == #drawRect)
      .map((call) => call.invocation.positionalArguments.first as Rect)
      .toList();
}

void _expectExactHighlight(WidgetTester tester, TextRange range) {
  final editable = tester.state<EditableTextState>(_editable).renderEditable;
  final origin =
      editable.localToGlobal(Offset.zero) -
      tester.getTopLeft(find.byKey(_highlightKey));
  final expected = editable
      .getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      )
      .map((box) => box.toRect().shift(origin))
      .toList();
  expect(_paintedHighlights(tester), expected);
  expect(expected, isNotEmpty);
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool control = false,
  bool shift = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

void main() {
  for (final readOnly in [false, true]) {
    testWidgets('remote match keeps focus/value with readOnly=$readOnly', (
      tester,
    ) async {
      final text =
          '${List.generate(70, (i) => 'Line $i\n').join()}match 😀 中\n';
      final range = TextRange(
        start: text.indexOf('match'),
        end: text.length - 1,
      );
      final controller = IanvsMarkdownController(text: text)
        ..selection = const TextSelection.collapsed(offset: 2);
      controller.mode = readOnly
          ? IanvsMarkdownEditorMode.preview
          : IanvsMarkdownEditorMode.source;
      final scroll = ScrollController();
      final findFocus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      addTearDown(findFocus.dispose);
      await tester.pumpWidget(
        _host(
          controller: controller,
          scroll: scroll,
          findFocus: findFocus,
          readOnly: readOnly,
        ),
      );
      findFocus.requestFocus();
      await tester.pump();
      final before = controller.value;
      final history = controller.retainedHistoryEntries;
      final request = IanvsMarkdownSourceHighlight(source: text, range: range);
      await tester.pumpWidget(
        _host(
          controller: controller,
          readOnly: readOnly,
          scroll: scroll,
          findFocus: findFocus,
          highlight: request,
        ),
      );
      await tester.pump();
      expect(scroll.offset, greaterThan(500));
      expect(findFocus.hasFocus, isTrue);
      expect(controller.value, before);
      expect(controller.retainedHistoryEntries, history);
      expect(controller.isDirty, isFalse);
      final editable = tester
          .state<EditableTextState>(_editable)
          .renderEditable;
      final box = editable
          .getBoxesForSelection(
            TextSelection(baseOffset: range.start, extentOffset: range.end),
          )
          .first;
      expect(box.top, greaterThanOrEqualTo(0));
      expect(box.bottom, lessThanOrEqualTo(editable.size.height));
      _expectExactHighlight(tester, range);

      await tester.enterText(find.byKey(_findFieldKey), 'new query');
      await tester.pump();
      _expectExactHighlight(tester, range);
      expect(controller.value, before);
      expect(findFocus.hasFocus, isTrue);

      scroll.jumpTo(0);
      await tester.pumpWidget(
        _host(
          controller: controller,
          readOnly: readOnly,
          scroll: scroll,
          findFocus: findFocus,
          highlight: request,
        ),
      );
      expect(scroll.offset, 0, reason: 'same request is not a new navigation');
      await tester.pumpWidget(
        _host(
          controller: controller,
          readOnly: readOnly,
          scroll: scroll,
          findFocus: findFocus,
          highlight: IanvsMarkdownSourceHighlight(source: text, range: range),
        ),
      );
      await tester.pump();
      expect(scroll.offset, greaterThan(500));
      expect(findFocus.hasFocus, isTrue);
      _expectExactHighlight(tester, range);

      await tester.pumpWidget(
        _host(
          controller: controller,
          scroll: scroll,
          findFocus: findFocus,
          readOnly: readOnly,
        ),
      );
      expect(_paintedHighlights(tester), isEmpty);
      expect(scroll.offset, greaterThan(500));
    });
  }

  testWidgets('stale and invalid requests never paint or revive on undo', (
    tester,
  ) async {
    const text = 'one two three';
    final controller = IanvsMarkdownController(text: text);
    final request = IanvsMarkdownSourceHighlight(
      source: text,
      range: const TextRange(start: 4, end: 7),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller: controller, highlight: request));
    _expectExactHighlight(tester, request.range);
    controller.text = 'ONE two three';
    controller.commitHistoryGroup();
    await tester.pump();
    expect(_paintedHighlights(tester), isEmpty);
    controller.undo();
    await tester.pump();
    expect(controller.text, text);
    expect(_paintedHighlights(tester), isEmpty);
    await tester.pumpWidget(_host(controller: controller, highlight: request));
    expect(_paintedHighlights(tester), isEmpty);
    for (final invalid in [
      IanvsMarkdownSourceHighlight(
        source: 'old two three',
        range: const TextRange(start: 4, end: 7),
      ),
      IanvsMarkdownSourceHighlight(source: text, range: TextRange.empty),
      IanvsMarkdownSourceHighlight(
        source: text,
        range: const TextRange(start: 6, end: 4),
      ),
      IanvsMarkdownSourceHighlight(
        source: text,
        range: const TextRange(start: 4, end: 4),
      ),
      IanvsMarkdownSourceHighlight(
        source: text,
        range: const TextRange(start: 4, end: 40),
      ),
    ]) {
      await tester.pumpWidget(
        _host(controller: controller, highlight: invalid),
      );
      expect(_paintedHighlights(tester), isEmpty);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      _host(
        controller: controller,
        highlight: IanvsMarkdownSourceHighlight(
          source: text,
          range: request.range,
        ),
      ),
    );
    _expectExactHighlight(tester, request.range);
  });

  testWidgets(
    'text changes before the reveal frame cancel pending navigation',
    (tester) async {
      final text = '${List.filled(70, 'before\n').join()}match';
      final controller = IanvsMarkdownController(text: text);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.text = text.replaceFirst('before', 'AFTER!');
      });
      await tester.pumpWidget(
        _host(
          controller: controller,
          scroll: scroll,
          highlight: IanvsMarkdownSourceHighlight(
            source: text,
            range: TextRange(start: text.length - 5, end: text.length),
          ),
        ),
      );
      await tester.pump();
      expect(scroll.offset, 0);
      expect(_paintedHighlights(tester), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multiline highlight follows wrapping, scrolling and syntax layout',
    (tester) async {
      final text =
          '> ${List.filled(16, 'wide text 😀').join(' ')}\n> second line\n';
      final range = TextRange(start: 2, end: text.length - 1);
      final controller = IanvsMarkdownController(text: text);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          controller: controller,
          scroll: scroll,
          highlightSyntax: true,
          highlight: IanvsMarkdownSourceHighlight(source: text, range: range),
        ),
      );
      await tester.pump();
      _expectExactHighlight(tester, range);
      scroll.jumpTo(20);
      await tester.pump();
      _expectExactHighlight(tester, range);
      expect(_paintedHighlights(tester).length, greaterThan(2));
    },
  );

  testWidgets(
    'controller and scroll swaps invalidate old requests without owning host objects',
    (tester) async {
      final text = '${List.filled(70, 'before\n').join()}match';
      final first = IanvsMarkdownController(text: text);
      final second = IanvsMarkdownController(text: text);
      final firstScroll = ScrollController();
      final secondScroll = ScrollController();
      final firstFocus = FocusNode();
      final secondFocus = FocusNode();
      final range = TextRange(start: text.length - 5, end: text.length);
      final request = IanvsMarkdownSourceHighlight(source: text, range: range);
      for (final controller in [first, second]) {
        addTearDown(controller.dispose);
      }
      for (final scroll in [firstScroll, secondScroll]) {
        addTearDown(scroll.dispose);
      }
      for (final focus in [firstFocus, secondFocus]) {
        addTearDown(focus.dispose);
      }
      await tester.pumpWidget(
        _host(
          controller: first,
          scroll: firstScroll,
          sourceFocus: firstFocus,
          highlight: request,
        ),
      );
      await tester.pump();
      expect(firstScroll.offset, greaterThan(500));
      await tester.pumpWidget(
        _host(
          controller: second,
          scroll: secondScroll,
          sourceFocus: secondFocus,
          highlight: request,
        ),
      );
      await tester.pump();
      expect(_paintedHighlights(tester), isEmpty);
      // Flutter transfers the old ScrollPosition when swapping controllers;
      // invalidating a highlight does not reset the user's scroll position.
      secondScroll.jumpTo(0);
      await tester.pump();
      expect(secondScroll.offset, 0);
      first.text = 'stale controller changed';
      await tester.pump();
      expect(second.text, text);
      final freshRequest = IanvsMarkdownSourceHighlight(
        source: text,
        range: range,
      );
      await tester.pumpWidget(
        _host(
          controller: second,
          scroll: secondScroll,
          sourceFocus: secondFocus,
          highlight: freshRequest,
        ),
      );
      await tester.pump();
      _expectExactHighlight(tester, range);
      expect(secondScroll.offset, greaterThan(500));
      secondScroll.jumpTo(0);
      await tester.pumpWidget(
        _host(
          controller: second,
          scroll: firstScroll,
          sourceFocus: firstFocus,
          highlight: freshRequest,
        ),
      );
      await tester.pump();
      expect(firstScroll.offset, greaterThan(500));
      _expectExactHighlight(tester, range);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      firstFocus.addListener(() {});
      secondFocus.addListener(() {});
      firstScroll.addListener(() {});
      secondScroll.addListener(() {});
      first.text = 'host still owns first';
      second.text = 'host still owns second';
      first.commitHistoryGroup();
      second.commitHistoryGroup();
    },
  );

  for (final mode in IanvsMarkdownEditorMode.values) {
    testWidgets(
      'read-only $mode preserves save and explicit mode commands',
      (tester) async {
        final controller = IanvsMarkdownController(text: 'saved text')
          ..text = 'keyboard save'
          ..mode = mode;
        final focus = FocusNode();
        final saves = <String>[];
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          _host(
            controller: controller,
            sourceFocus: focus,
            readOnly: true,
            enableModeShortcuts: false,
            onSaveRequested: (text) async {
              saves.add(text);
            },
          ),
        );
        focus.requestFocus();
        await tester.pump();
        expect(controller.isDirty, isTrue);
        final apple = defaultTargetPlatform == TargetPlatform.macOS;
        await _chord(
          tester,
          LogicalKeyboardKey.keyS,
          meta: apple,
          control: !apple,
        );
        expect(saves, ['keyboard save']);
        expect(controller.isDirty, isFalse);
        expect(controller.mode, mode);

        controller.text = 'native save';
        expect(
          IanvsMarkdownShortcuts.invoke(
            IanvsMarkdownCommand.save,
            controller: controller,
          ),
          isTrue,
        );
        await tester.pump();
        expect(saves, ['keyboard save', 'native save']);
        expect(controller.isDirty, isFalse);

        // Disabled mode keys must not change mode, while explicit menu commands
        // remain available to leave the temporary read-only search surface.
        await _chord(
          tester,
          mode == IanvsMarkdownEditorMode.livePreview
              ? LogicalKeyboardKey.digit2
              : LogicalKeyboardKey.digit1,
          meta: apple,
          control: !apple,
        );
        expect(controller.mode, mode);
        for (final (command, expected) in const [
          (IanvsMarkdownCommand.source, IanvsMarkdownEditorMode.source),
          (IanvsMarkdownCommand.reading, IanvsMarkdownEditorMode.preview),
          (
            IanvsMarkdownCommand.livePreview,
            IanvsMarkdownEditorMode.livePreview,
          ),
          (IanvsMarkdownCommand.togglePreview, IanvsMarkdownEditorMode.preview),
        ]) {
          expect(
            IanvsMarkdownShortcuts.invoke(command, controller: controller),
            isTrue,
          );
          await tester.pump();
          expect(controller.mode, expected);
          expect(
            tester.widget<TextField>(find.byKey(_sourceFieldKey)).readOnly,
            isTrue,
          );
          controller.selection = const TextSelection(
            baseOffset: 0,
            extentOffset: 6,
          );
          for (final mutation in const [
            IanvsMarkdownCommand.bold,
            IanvsMarkdownCommand.undo,
            IanvsMarkdownCommand.cut,
            IanvsMarkdownCommand.paste,
          ]) {
            expect(
              IanvsMarkdownShortcuts.invoke(mutation, controller: controller),
              isTrue,
            );
            await tester.pump();
            expect(controller.text, 'native save');
          }
        }
        expect(saves, ['keyboard save', 'native save']);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );

    testWidgets(
      'read-only $mode blocks commands, native edits and history but permits select/copy',
      (tester) async {
        final controller = IanvsMarkdownController(text: 'old')
          ..text = 'source text';
        controller.commitHistoryGroup();
        controller.mode = mode;
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': 'https://example.com'};
            }
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
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
        await tester.pumpWidget(
          _host(
            controller: controller,
            sourceFocus: focus,
            readOnly: true,
            showToolbar: true,
            enclosingShortcuts: true,
          ),
        );
        focus.requestFocus();
        await tester.pump();
        expect(find.byType(IanvsMarkdownEditorToolbar), findsNothing);
        expect(
          tester.widget<TextField>(find.byKey(_sourceFieldKey)).readOnly,
          isTrue,
        );
        expect(
          IanvsMarkdownShortcuts.invoke(
            IanvsMarkdownCommand.selectAll,
            controller: controller,
          ),
          isTrue,
        );
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 11),
        );
        expect(
          IanvsMarkdownShortcuts.invoke(
            IanvsMarkdownCommand.copy,
            controller: controller,
          ),
          isTrue,
        );
        await tester.pump();
        expect(copied, 'source text');
        for (final command in const [
          IanvsMarkdownCommand.undo,
          IanvsMarkdownCommand.redo,
          IanvsMarkdownCommand.bold,
          IanvsMarkdownCommand.italic,
          IanvsMarkdownCommand.insertLink,
          IanvsMarkdownCommand.deleteLine,
          IanvsMarkdownCommand.indent,
          IanvsMarkdownCommand.outdent,
          IanvsMarkdownCommand.cut,
          IanvsMarkdownCommand.paste,
        ]) {
          expect(
            IanvsMarkdownShortcuts.invoke(command, controller: controller),
            isTrue,
          );
          await tester.pump();
          expect(
            controller.text,
            'source text',
            reason: '$command cannot edit',
          );
          expect(controller.mode, mode);
        }
        final apple = defaultTargetPlatform == TargetPlatform.macOS;
        for (final key in [
          LogicalKeyboardKey.keyZ,
          LogicalKeyboardKey.keyY,
          LogicalKeyboardKey.keyB,
          LogicalKeyboardKey.keyI,
          LogicalKeyboardKey.keyK,
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.keyX,
          LogicalKeyboardKey.keyV,
        ]) {
          await _chord(tester, key, meta: apple, control: !apple);
          expect(controller.text, 'source text', reason: '$key cannot edit');
        }
        for (final key in [
          LogicalKeyboardKey.keyH,
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.keyK,
        ]) {
          await _chord(tester, key, control: true);
          expect(controller.text, 'source text');
        }
        final state = tester.state<EditableTextState>(_editable);
        final historyEntries = controller.retainedHistoryEntries;
        state.updateEditingValue(
          const TextEditingValue(
            text: 'typed',
            selection: TextSelection.collapsed(offset: 2),
          ),
        );
        state.userUpdateTextEditingValue(
          const TextEditingValue(
            text: 'native undo',
            selection: TextSelection.collapsed(offset: 2),
          ),
          SelectionChangedCause.keyboard,
        );
        await tester.pump();
        expect(controller.text, 'source text');
        expect(controller.retainedHistoryEntries, historyEntries);
        final context = FocusManager.instance.primaryFocus!.context!;
        for (final intent in <Intent>[
          const UndoTextIntent(SelectionChangedCause.keyboard),
          const RedoTextIntent(SelectionChangedCause.keyboard),
          const PasteTextIntent(SelectionChangedCause.keyboard),
          const DeleteToNextWordBoundaryIntent(forward: true),
        ]) {
          Actions.maybeInvoke(context, intent);
          await tester.pump();
          expect(controller.text, 'source text');
        }
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 6,
        );
        await tester.pump();
        expect(state.cutEnabled, isFalse);
        expect(state.pasteEnabled, isFalse);
        expect(state.copyEnabled, isTrue);
        expect(
          state.contextMenuButtonItems.map((item) => item.type),
          isNot(contains(ContextMenuButtonType.cut)),
        );
        expect(
          state.contextMenuButtonItems.map((item) => item.type),
          isNot(contains(ContextMenuButtonType.paste)),
        );
        state.contextMenuButtonItems
            .firstWhere((item) => item.type == ContextMenuButtonType.copy)
            .onPressed!();
        await tester.pump();
        expect(copied, 'source');
        controller.text = 'programmatic update';
        await tester.pump();
        expect(controller.text, 'programmatic update');
        controller.undo();
        await tester.pump();
        expect(controller.text, 'source text');
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );
  }

  for (final transition in ['read-only', 'controller swap', 'unmount']) {
    testWidgets('$transition rejects a pending smart URL paste', (
      tester,
    ) async {
      final controller = IanvsMarkdownController(text: 'selected text');
      final replacement = IanvsMarkdownController(text: 'other document');
      final focus = FocusNode();
      final clipboard = Completer<Map<String, String>>();
      addTearDown(controller.dispose);
      addTearDown(replacement.dispose);
      addTearDown(focus.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') return clipboard.future;
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        _host(controller: controller, sourceFocus: focus),
      );
      focus.requestFocus();
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 13,
      );
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.paste,
        controller: controller,
      );
      await tester.pumpWidget(switch (transition) {
        'read-only' => _host(
          controller: controller,
          sourceFocus: focus,
          readOnly: true,
        ),
        'controller swap' => _host(controller: replacement, sourceFocus: focus),
        _ => const SizedBox(),
      });
      clipboard.complete({'text': 'https://example.com'});
      await tester.pump();
      expect(controller.text, 'selected text');
      expect(replacement.text, 'other document');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('read-only can be toggled and default source remains editable', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'original');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(_host(controller: controller, sourceFocus: focus));
    await tester.enterText(find.byKey(_sourceFieldKey), 'editable');
    await tester.pump();
    expect(controller.text, 'editable');
    await tester.pumpWidget(
      _host(controller: controller, sourceFocus: focus, readOnly: true),
    );
    await tester.pump();
    tester
        .state<EditableTextState>(_editable)
        .userUpdateTextEditingValue(
          const TextEditingValue(text: 'blocked'),
          SelectionChangedCause.keyboard,
        );
    await tester.pump();
    expect(controller.text, 'editable');
    await tester.pumpWidget(_host(controller: controller, sourceFocus: focus));
    await tester.enterText(find.byKey(_sourceFieldKey), 'editable again');
    await tester.pump();
    expect(controller.text, 'editable again');
    expect(tester.takeException(), isNull);
  });
}
