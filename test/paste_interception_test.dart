import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

const _otherKey = ValueKey('other-input');

Widget _host({
  required IanvsMarkdownController controller,
  required FocusNode focus,
  Future<bool> Function()? onPaste,
  bool live = false,
  bool readOnly = false,
  bool fallback = false,
}) => MaterialApp(
  home: Scaffold(
    body: IanvsMarkdownLocalization(
      strings: const IanvsMarkdownStrings.english(),
      child: Column(
        children: [
          const TextField(key: _otherKey),
          Expanded(
            child: live
                ? IanvsMarkdownLiveEditor(
                    controller: controller,
                    focusNode: focus,
                    onPaste: onPaste,
                    showToolbar: false,
                    showFrontMatter: true,
                    normalizeTablesOnEdit: false,
                    renderBudget: fallback
                        ? const IanvsMarkdownRenderBudget(maxSourceCodeUnits: 3)
                        : null,
                  )
                : IanvsMarkdownEditor(
                    controller: controller,
                    focusNode: focus,
                    onPaste: onPaste,
                    readOnly: readOnly,
                    showToolbar: false,
                  ),
          ),
        ],
      ),
    ),
  ),
);

Finder get _editorField => find.byType(TextField).last;
Finder get _editorEditable =>
    find.descendant(of: _editorField, matching: find.byType(EditableText));

Future<void> _focus(WidgetTester tester, {bool live = false}) async {
  if (live) {
    await tester.tap(find.text('Label'));
    await tester.pumpAndSettle();
  }
  await tester.tap(_editorField);
  await tester.pump();
}

Future<void> _pasteKey(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  var clipboardReads = 0;
  String? clipboardText;
  Future<Map<String, String>?>? pendingClipboard;

  setUp(() {
    clipboardReads = 0;
    clipboardText = 'plain';
    pendingClipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            clipboardReads++;
            return pendingClipboard ??
                (clipboardText == null ? null : {'text': clipboardText!});
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboardText != null};
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final live in [false, true]) {
    final surface = live ? 'Live' : 'Source';
    for (final install in [false, true]) {
      testWidgets('$surface ${install ? 'declined' : 'absent'} hook preserves '
          'collapsed and selected plain/URL paste', (tester) async {
        final controller = IanvsMarkdownController(text: 'Label');
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        var calls = 0;
        await tester.pumpWidget(
          _host(
            controller: controller,
            focus: focus,
            live: live,
            onPaste: install
                ? () async {
                    calls++;
                    return false;
                  }
                : null,
          ),
        );
        await tester.pumpAndSettle();
        await _focus(tester, live: live);
        for (final selected in [false, true]) {
          for (final text in ['plain', 'https://example.com']) {
            clipboardText = text;
            controller.value = const TextEditingValue(
              text: 'Label',
              selection: TextSelection.collapsed(offset: 5),
            );
            await tester.pumpAndSettle();
            tester
                .widget<TextField>(_editorField)
                .controller!
                .selection = selected
                ? const TextSelection(baseOffset: 0, extentOffset: 5)
                : const TextSelection.collapsed(offset: 5);
            await tester.pump();
            final readsBefore = clipboardReads;
            expect(
              IanvsMarkdownShortcuts.invoke(
                IanvsMarkdownCommand.paste,
                controller: controller,
              ),
              isTrue,
            );
            await tester.pumpAndSettle();
            expect(
              controller.text,
              !selected
                  ? 'Label$text'
                  : text.startsWith('https:')
                  ? '[Label]($text)'
                  : text,
            );
            if (install) expect(clipboardReads - readsBefore, 1);
          }
        }
        expect(calls, install ? 4 : 0);
      });
    }

    testWidgets(
      '$surface handled hook intercepts Ctrl/Cmd+V with collapsed selection',
      (tester) async {
        final controller = IanvsMarkdownController(text: 'Label');
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        var calls = 0;
        await tester.pumpWidget(
          _host(
            controller: controller,
            focus: focus,
            live: live,
            onPaste: () async {
              calls++;
              return true;
            },
          ),
        );
        await tester.pumpAndSettle();
        await _focus(tester, live: live);
        tester.widget<TextField>(_editorField).controller!.selection =
            const TextSelection.collapsed(offset: 5);
        await _pasteKey(tester);
        expect(calls, 1);
        expect(controller.text, 'Label');
        expect(clipboardReads, 0);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );

    testWidgets('$surface image-only context menu invokes hook only on Paste', (
      tester,
    ) async {
      clipboardText = null;
      final controller = IanvsMarkdownController(text: 'Label');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var calls = 0;
      await tester.pumpWidget(
        _host(
          controller: controller,
          focus: focus,
          live: live,
          onPaste: () async {
            calls++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      await _focus(tester, live: live);
      final state = tester.state<EditableTextState>(_editorEditable);
      state.showToolbar();
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);
      expect(calls, 0);
      expect(clipboardReads, 0);
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(clipboardReads, 0);
      expect(controller.text, 'Label');
    });
  }

  testWidgets('Live source and budget fallback forward the hook once', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Label');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var calls = 0;
    Future<bool> onPaste() async {
      calls++;
      return true;
    }

    for (final fallback in [false, true]) {
      controller.mode = fallback
          ? IanvsMarkdownEditorMode.livePreview
          : IanvsMarkdownEditorMode.source;
      await tester.pumpWidget(
        _host(
          controller: controller,
          focus: focus,
          live: true,
          fallback: fallback,
          onPaste: onPaste,
        ),
      );
      await tester.pumpAndSettle();
      await _focus(tester);
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.paste,
        controller: controller,
      );
      await tester.pumpAndSettle();
    }
    expect(calls, 2);
    expect(clipboardReads, 0);
  });

  for (final disabled in ['read-only', 'preview', 'composing']) {
    testWidgets('$disabled never invokes hook', (tester) async {
      final controller = IanvsMarkdownController(text: 'Label');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var calls = 0;
      await tester.pumpWidget(
        _host(
          controller: controller,
          focus: focus,
          readOnly: disabled == 'read-only',
          onPaste: () async {
            calls++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      await _focus(tester);
      if (disabled == 'preview') {
        controller.mode = IanvsMarkdownEditorMode.preview;
      } else if (disabled == 'composing') {
        controller.value = const TextEditingValue(
          text: 'Label',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        );
      }
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.paste,
        controller: controller,
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      if (disabled != 'preview') expect(controller.text, 'Label');
      if (disabled == 'composing') {
        expect(controller.value.composing, const TextRange(start: 0, end: 3));
      }
    });
  }

  for (final outcome in ['true', 'throw', 'changed then false']) {
    testWidgets('host $outcome consumes paste without a fallback read', (
      tester,
    ) async {
      final controller = IanvsMarkdownController(text: 'Label');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(
          controller: controller,
          focus: focus,
          onPaste: () async {
            if (outcome == 'throw') throw StateError('host failed');
            if (outcome == 'changed then false') {
              controller.text = 'host result';
              return false;
            }
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      await _focus(tester);
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.paste,
        controller: controller,
      );
      await tester.pumpAndSettle();
      expect(clipboardReads, 0);
      expect(
        controller.text,
        outcome == 'changed then false' ? 'host result' : 'Label',
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final transition in [
    'read-only',
    'controller swap',
    'unmount',
    'mode',
    'focus',
    'selection',
    'text',
    'composition',
    'callback removed',
    'selection restored',
  ]) {
    testWidgets('$transition discards pending declined hook', (tester) async {
      final controller = IanvsMarkdownController(text: 'Label');
      final replacement = IanvsMarkdownController(text: 'Other');
      final focus = FocusNode();
      final result = Completer<bool>();
      addTearDown(controller.dispose);
      addTearDown(replacement.dispose);
      addTearDown(focus.dispose);
      Future<bool> onPaste() => result.future;
      await tester.pumpWidget(
        _host(controller: controller, focus: focus, onPaste: onPaste),
      );
      await tester.pumpAndSettle();
      await _focus(tester);
      controller.selection = const TextSelection.collapsed(offset: 5);
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.paste,
        controller: controller,
      );
      switch (transition) {
        case 'read-only':
          await tester.pumpWidget(
            _host(
              controller: controller,
              focus: focus,
              onPaste: onPaste,
              readOnly: true,
            ),
          );
        case 'controller swap':
          await tester.pumpWidget(
            _host(controller: replacement, focus: focus, onPaste: onPaste),
          );
        case 'unmount':
          await tester.pumpWidget(const SizedBox());
        case 'callback removed':
          await tester.pumpWidget(_host(controller: controller, focus: focus));
        case 'mode':
          controller.mode = IanvsMarkdownEditorMode.source;
        case 'focus':
          await tester.tap(find.byKey(_otherKey));
          await tester.pump();
        case 'selection' || 'selection restored':
          controller.selection = const TextSelection.collapsed(offset: 0);
          if (transition == 'selection restored') {
            controller.selection = const TextSelection.collapsed(offset: 5);
          }
        case 'text':
          controller.text = 'Changed';
        case 'composition':
          controller.value = controller.value.copyWith(
            composing: const TextRange(start: 0, end: 3),
          );
      }
      result.complete(false);
      await tester.pumpAndSettle();
      expect(controller.text, transition == 'text' ? 'Changed' : 'Label');
      expect(replacement.text, 'Other');
      expect(clipboardReads, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('host busy-state rebuild does not cancel declined text paste', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Label');
    final focus = FocusNode();
    final result = Completer<bool>();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(controller: controller, focus: focus, onPaste: () => result.future),
    );
    await tester.pumpAndSettle();
    await _focus(tester);
    controller.selection = const TextSelection.collapsed(offset: 5);
    IanvsMarkdownShortcuts.invoke(
      IanvsMarkdownCommand.paste,
      controller: controller,
    );
    await tester.pumpWidget(
      _host(controller: controller, focus: focus, onPaste: () async => false),
    );
    result.complete(false);
    await tester.pumpAndSettle();
    expect(controller.text, 'Labelplain');
    expect(clipboardReads, 1);
  });

  testWidgets('Live block switch discards pending declined hook', (
    tester,
  ) async {
    const source = 'Label\n\nOther';
    final controller = IanvsMarkdownController(text: source);
    final focus = FocusNode();
    final result = Completer<bool>();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(
        controller: controller,
        focus: focus,
        live: true,
        onPaste: () => result.future,
      ),
    );
    await tester.pumpAndSettle();
    await _focus(tester, live: true);
    IanvsMarkdownShortcuts.invoke(
      IanvsMarkdownCommand.paste,
      controller: controller,
    );
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    result.complete(false);
    await tester.pumpAndSettle();
    expect(controller.text, source);
    expect(clipboardReads, 0);
  });

  testWidgets(
    'selection change during declined-hook text read discards paste',
    (tester) async {
      final controller = IanvsMarkdownController(text: 'Label');
      final focus = FocusNode();
      final clipboard = Completer<Map<String, String>?>();
      pendingClipboard = clipboard.future;
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(controller: controller, focus: focus, onPaste: () async => false),
      );
      await tester.pumpAndSettle();
      await _focus(tester);
      controller.selection = const TextSelection.collapsed(offset: 5);
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.paste,
        controller: controller,
      );
      await tester.pumpAndSettle();
      expect(clipboardReads, 1);
      controller.selection = const TextSelection.collapsed(offset: 0);
      clipboard.complete({'text': 'plain'});
      await tester.pumpAndSettle();
      expect(controller.text, 'Label');
      expect(clipboardReads, 1);
    },
  );

  for (final property in [false, true]) {
    testWidgets('${property ? 'property' : 'table'} paste stays local and '
        'does not call host', (tester) async {
      final source = property
          ? '---\ntitle: Alpha\n---\nLabel'
          : '| H | I |\n| --- | --- |\n| Alpha | Beta |';
      final controller = IanvsMarkdownController(text: source);
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var calls = 0;
      await tester.pumpWidget(
        _host(
          controller: controller,
          focus: focus,
          live: true,
          onPaste: () async {
            calls++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(
        ValueKey(
          property
              ? 'ianvs-markdown-front-matter-input-title'
              : 'ianvs-markdown-table-1-0',
        ),
      );
      await tester.tap(field);
      tester.widget<TextField>(field).controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 5);
      IanvsMarkdownShortcuts.invoke(
        IanvsMarkdownCommand.paste,
        controller: controller,
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(tester.widget<TextField>(field).controller!.text, 'plain');
      expect(
        controller.text,
        property ? source : source.replaceFirst('Alpha', 'plain'),
      );
    });
  }
}
