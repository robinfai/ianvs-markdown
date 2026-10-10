import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool control = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

void keyboardTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );

void macKeyboardTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );

void main() {
  for (final view in [false, true]) {
    keyboardTest(
      '${view ? 'View' : 'body'} focus replacement keeps host ownership and current document',
      (tester) async {
        final first = _TrackedFocusNode();
        final second = _TrackedFocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        String? copied;
        Future<void> write(IanvsMarkdownClipboardData data) async =>
            copied = data.markdown;
        Widget page(String text, FocusNode focus) => host(
          IanvsMarkdownShortcuts(
            bindings: const {
              IanvsMarkdownCommand.selectAll: [
                SingleActivator(LogicalKeyboardKey.f2),
              ],
              IanvsMarkdownCommand.copy: [
                SingleActivator(LogicalKeyboardKey.f3),
              ],
            },
            child: view
                ? IanvsMarkdownView(
                    data: text,
                    focusNode: focus,
                    autofocus: true,
                    clipboardWriter: write,
                  )
                : IanvsMarkdown(
                    data: text,
                    focusNode: focus,
                    autofocus: true,
                    clipboardWriter: write,
                  ),
          ),
        );
        await tester.pumpWidget(page('Old document', first));
        await tester.pumpAndSettle();
        expect(first.hasFocus, isTrue);
        await tester.pumpWidget(page('New document', second));
        await tester.pumpAndSettle();
        expect(first.disposals, 0);
        expect(first.hasFocus, isFalse);
        expect(second.hasFocus, isTrue);
        await chord(tester, LogicalKeyboardKey.f2);
        await chord(tester, LogicalKeyboardKey.f3);
        expect(copied, 'New document');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(second.disposals, 0);
      },
    );
  }

  for (final table in [false, true]) {
    keyboardTest(
      '${table ? 'table' : 'property'} composition cannot execute mapped commands',
      (tester) async {
        final source = table
            ? '| A | B |\n| --- | --- |\n| C | D |'
            : '---\nauthor: Alice\n---\n\nBody';
        final controller = IanvsMarkdownController(text: source);
        addTearDown(controller.dispose);
        var saves = 0;
        await tester.pumpWidget(
          host(
            IanvsMarkdownShortcuts(
              bindings: const {
                IanvsMarkdownCommand.bold: [
                  SingleActivator(LogicalKeyboardKey.f2),
                ],
                IanvsMarkdownCommand.save: [
                  SingleActivator(LogicalKeyboardKey.f3),
                ],
              },
              child: IanvsMarkdownLiveEditor(
                controller: controller,
                showFrontMatter: true,
                onSaveRequested: (_) => saves++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(
          ValueKey(
            table
                ? 'ianvs-markdown-table-0-0'
                : 'ianvs-markdown-front-matter-input-author',
          ),
        );
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.showKeyboard(field);
        final text = tester.widget<TextField>(field).controller!.text;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: 1),
            composing: const TextRange(start: 0, end: 1),
          ),
        );
        await tester.pump();
        expect(
          tester.widget<TextField>(field).controller!.value.composing,
          const TextRange(start: 0, end: 1),
          reason: 'IME active before shortcut',
        );
        await chord(tester, LogicalKeyboardKey.f2);
        await chord(tester, LogicalKeyboardKey.f3);
        expect(controller.text, source);
        expect(
          tester.widget<TextField>(field).controller!.value.composing,
          const TextRange(start: 0, end: 1),
        );
        expect(saves, 0);
      },
    );
  }

  keyboardTest(
    'mode gate and external focus survive configured shortcuts and updates',
    (tester) async {
      final controller = IanvsMarkdownController(text: 'Original');
      final externalFocus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(externalFocus.dispose);
      await tester.pumpWidget(
        host(
          Column(
            children: [
              TextField(focusNode: externalFocus),
              Expanded(
                child: IanvsMarkdownShortcuts(
                  bindings: const {
                    IanvsMarkdownCommand.source: [
                      SingleActivator(LogicalKeyboardKey.f2),
                    ],
                  },
                  child: IanvsMarkdownLiveEditor(
                    controller: controller,
                    enableModeShortcuts: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.f2);
      expect(controller.mode, IanvsMarkdownEditorMode.livePreview);
      externalFocus.requestFocus();
      await tester.pumpAndSettle();
      controller.mode = IanvsMarkdownEditorMode.preview;
      await tester.pumpAndSettle();
      expect(externalFocus.hasFocus, isTrue);
      controller.mode = IanvsMarkdownEditorMode.source;
      await tester.pumpAndSettle();
      expect(externalFocus.hasFocus, isTrue);
    },
  );

  keyboardTest('custom toolbar restores its host-owned editor focus', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Original');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      host(
        Column(
          children: [
            IanvsMarkdownEditorToolbar(
              controller: controller,
              focusNode: focus,
            ),
            Expanded(
              child: IanvsMarkdownLiveEditor(
                controller: controller,
                focusNode: focus,
                autofocus: true,
                showToolbar: false,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    await tester.pump();
    await tester.tap(find.byTooltip('粗体'));
    await tester.pumpAndSettle();
    expect(controller.text, '**Original**');
    expect(focus.hasFocus, isTrue);
  });

  keyboardTest(
    'keyboard mode switching retains focus and selection without a mouse',
    (tester) async {
      const source = 'One\n\nTwo';
      final controller = IanvsMarkdownController(text: source);
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      IanvsMarkdownClipboardData? copied;
      await tester.pumpWidget(
        host(
          IanvsMarkdownShortcuts(
            bindings: const {
              IanvsMarkdownCommand.source: [
                SingleActivator(LogicalKeyboardKey.f2),
              ],
              IanvsMarkdownCommand.reading: [
                SingleActivator(LogicalKeyboardKey.f3),
              ],
              IanvsMarkdownCommand.livePreview: [
                SingleActivator(LogicalKeyboardKey.f4),
              ],
              IanvsMarkdownCommand.copy: [
                SingleActivator(LogicalKeyboardKey.f5),
              ],
              IanvsMarkdownCommand.selectAll: [
                SingleActivator(LogicalKeyboardKey.f6),
              ],
              IanvsMarkdownCommand.bold: [
                SingleActivator(LogicalKeyboardKey.f7),
              ],
            },
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              clipboardWriter: (data) async => copied = data,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.f2);
      expect(controller.mode, IanvsMarkdownEditorMode.source);
      expect(focus.hasFocus, isTrue);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      await chord(tester, LogicalKeyboardKey.f3);
      expect(controller.mode, IanvsMarkdownEditorMode.preview);
      expect(focus.hasFocus, isTrue);
      await chord(tester, LogicalKeyboardKey.f6);
      await chord(tester, LogicalKeyboardKey.f5);
      expect(copied?.markdown, source);
      await chord(tester, LogicalKeyboardKey.f4);
      expect(controller.mode, IanvsMarkdownEditorMode.livePreview);
      expect(focus.hasFocus, isTrue);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      await chord(tester, LogicalKeyboardKey.f7);
      expect(controller.text, '**One**\n\nTwo');
    },
  );

  keyboardTest(
    'remapped native paste retains smart URL paste and clipboard actions',
    (tester) async {
      final controller = IanvsMarkdownController(text: 'Original');
      addTearDown(controller.dispose);
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
        host(
          IanvsMarkdownShortcuts(
            bindings: const {
              IanvsMarkdownCommand.paste: [
                SingleActivator(LogicalKeyboardKey.f2),
              ],
              IanvsMarkdownCommand.copy: [
                SingleActivator(LogicalKeyboardKey.f3),
              ],
              IanvsMarkdownCommand.cut: [
                SingleActivator(LogicalKeyboardKey.f4),
              ],
              IanvsMarkdownCommand.selectAll: [
                SingleActivator(LogicalKeyboardKey.f5),
              ],
            },
            child: IanvsMarkdownEditor(controller: controller, autofocus: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.f5);
      await chord(tester, LogicalKeyboardKey.f2);
      expect(controller.text, '[Original](https://example.com)');
      await chord(tester, LogicalKeyboardKey.f5);
      await chord(tester, LogicalKeyboardKey.f3);
      expect(copied, controller.text);
      await chord(tester, LogicalKeyboardKey.f4);
      expect(controller.text, '');
      expect(copied, '[Original](https://example.com)');
      controller.undo();
      expect(controller.text, '[Original](https://example.com)');
    },
  );

  keyboardTest('per-block body selection also supports configured commands', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
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
      host(
        const IanvsMarkdownShortcuts(
          bindings: {
            IanvsMarkdownCommand.copy: [SingleActivator(LogicalKeyboardKey.f2)],
            IanvsMarkdownCommand.selectAll: [
              SingleActivator(LogicalKeyboardKey.f3),
            ],
          },
          child: IanvsMarkdown(data: 'Original text', documentSelection: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SelectableText));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.f3);
    await chord(tester, LogicalKeyboardKey.f2);
    expect(copied, 'Original text');
  });

  macKeyboardTest('raw macOS modifier-only shortcuts execute once', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Original');
    addTearDown(controller.dispose);
    var hostCalls = 0;
    await tester.pumpWidget(
      host(
        IanvsMarkdownShortcuts(
          bindings: const {
            IanvsMarkdownCommand.bold: [
              SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true),
            ],
          },
          hostShortcuts: {
            const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
                hostCalls++,
          },
          child: IanvsMarkdownEditor(controller: controller, autofocus: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    await tester.pump();
    Future<void> raw(String type, int modifiers) async {
      final done = Completer<void>();
      // Exercise a platform message without separate physical modifier events.
      // ignore: deprecated_member_use
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/keyevent',
        const JSONMessageCodec().encodeMessage({
          'type': type,
          'keymap': 'macos',
          'keyCode': 11,
          'characters': 'b',
          'charactersIgnoringModifiers': 'b',
          'modifiers': modifiers,
        }),
        (_) => done.complete(),
      );
      await done.future;
      await tester.pumpAndSettle();
    }

    await raw('keydown', 0x100000);
    await raw('keyup', 0);
    expect(hostCalls, 1);
    expect(controller.text, 'Original');
    await raw('keydown', 0x120000);
    await raw('keyup', 0);
    expect(hostCalls, 1);
    expect(controller.text, '**Original**');
  });

  keyboardTest(
    'non-repeating host binding wins over parent shortcuts and native editing',
    (tester) async {
      final controller = IanvsMarkdownController(text: 'Text');
      addTearDown(controller.dispose);
      var parentCalls = 0;
      var hostCalls = 0;
      await tester.pumpWidget(
        host(
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.f2): () => parentCalls++,
            },
            child: IanvsMarkdownShortcuts(
              hostShortcuts: {
                const SingleActivator(
                  LogicalKeyboardKey.f2,
                  includeRepeats: false,
                ): () =>
                    hostCalls++,
              },
              child: IanvsMarkdownEditor(
                controller: controller,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f2);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(hostCalls, 1);
      expect(parentCalls, 0);
      expect(controller.text, 'Text');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  keyboardTest(
    'conflicting explicit command bindings fail before registration',
    (tester) async {
      await tester.pumpWidget(
        host(
          const IanvsMarkdownShortcuts(
            bindings: {
              IanvsMarkdownCommand.bold: [
                SingleActivator(LogicalKeyboardKey.f2),
              ],
              IanvsMarkdownCommand.save: [
                SingleActivator(LogicalKeyboardKey.f2),
              ],
            },
            child: SizedBox(),
          ),
        ),
      );
      expect(tester.takeException(), isArgumentError);
    },
  );

  for (final live in [false, true]) {
    keyboardTest(
      '${live ? 'Live' : 'Source'} remaps commands before text defaults',
      (tester) async {
        final controller = IanvsMarkdownController(text: 'Original');
        addTearDown(controller.dispose);
        var hostCalls = 0;
        await tester.pumpWidget(
          host(
            IanvsMarkdownShortcuts(
              bindings: const {
                IanvsMarkdownCommand.bold: [
                  SingleActivator(LogicalKeyboardKey.f2),
                ],
                IanvsMarkdownCommand.undo: [
                  SingleActivator(LogicalKeyboardKey.f3),
                ],
                IanvsMarkdownCommand.italic: [],
              },
              hostShortcuts: {
                const SingleActivator(
                  LogicalKeyboardKey.keyD,
                  meta: true,
                ): () =>
                    hostCalls++,
                const SingleActivator(
                  LogicalKeyboardKey.keyK,
                  control: true,
                ): () =>
                    hostCalls++,
              },
              child: live
                  ? IanvsMarkdownLiveEditor(
                      controller: controller,
                      showToolbar: false,
                    )
                  : IanvsMarkdownEditor(
                      controller: controller,
                      showToolbar: false,
                      autofocus: true,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (live) {
          await tester.tap(find.text('Original'));
          await tester.pumpAndSettle();
        }
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 8,
        );
        await tester.pumpAndSettle();
        await chord(tester, LogicalKeyboardKey.keyB, meta: true);
        if (defaultTargetPlatform == TargetPlatform.linux) {
          await chord(tester, LogicalKeyboardKey.keyB, control: true);
        }
        await chord(tester, LogicalKeyboardKey.keyI, meta: true);
        expect(controller.text, 'Original');
        await chord(tester, LogicalKeyboardKey.f2);
        expect(controller.text, '**Original**');
        await chord(tester, LogicalKeyboardKey.keyZ, meta: true);
        expect(controller.text, '**Original**');
        await chord(tester, LogicalKeyboardKey.f3);
        expect(controller.text, 'Original');
        await chord(tester, LogicalKeyboardKey.keyD, meta: true);
        await chord(tester, LogicalKeyboardKey.keyK, control: true);
        expect(hostCalls, 2);
        expect(controller.text, 'Original');
      },
    );
  }

  for (final live in [false, true]) {
    keyboardTest(
      '${live ? 'Live' : 'Source'} toolbar returns keyboard focus to editing',
      (tester) async {
        final controller = IanvsMarkdownController(text: 'Original');
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          host(
            IanvsMarkdownShortcuts(
              bindings: const {
                IanvsMarkdownCommand.undo: [
                  SingleActivator(LogicalKeyboardKey.f2),
                ],
              },
              child: live
                  ? IanvsMarkdownLiveEditor(
                      controller: controller,
                      focusNode: focus,
                      autofocus: true,
                    )
                  : IanvsMarkdownEditor(
                      controller: controller,
                      focusNode: focus,
                      autofocus: true,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 8,
        );
        await tester.pump();
        await tester.tap(find.byTooltip('粗体'));
        await tester.pumpAndSettle();
        expect(controller.text, '**Original**');
        expect(focus.hasFocus, isTrue);
        await chord(tester, LogicalKeyboardKey.f2);
        expect(controller.text, 'Original');
      },
    );
  }

  for (final view in [false, true]) {
    keyboardTest(
      '${view ? 'View' : 'body'} remaps selection and rich copy once',
      (tester) async {
        const source = '# Heading\n\n**Original** text.';
        final copies = <IanvsMarkdownClipboardData>[];
        var hostCalls = 0;
        Future<void> write(IanvsMarkdownClipboardData data) async =>
            copies.add(data);
        await tester.pumpWidget(
          host(
            IanvsMarkdownShortcuts(
              bindings: const {
                IanvsMarkdownCommand.selectAll: [
                  SingleActivator(LogicalKeyboardKey.f2),
                ],
                IanvsMarkdownCommand.copy: [
                  SingleActivator(LogicalKeyboardKey.f3),
                ],
              },
              hostShortcuts: {
                const SingleActivator(
                  LogicalKeyboardKey.keyC,
                  meta: true,
                ): () =>
                    hostCalls++,
              },
              child: view
                  ? IanvsMarkdownView(data: source, clipboardWriter: write)
                  : IanvsMarkdown(data: source, clipboardWriter: write),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Original').first);
        await chord(tester, LogicalKeyboardKey.f2);
        await chord(tester, LogicalKeyboardKey.f3);
        expect(copies, hasLength(1));
        expect(copies.single.markdown, source);
        expect(copies.single.html, contains('<strong>Original</strong>'));
        await chord(tester, LogicalKeyboardKey.keyC, meta: true);
        await chord(tester, LogicalKeyboardKey.keyC, control: true);
        expect(hostCalls, 1);
        expect(copies, hasLength(1));
      },
    );
  }

  keyboardTest(
    'table formatting stays local and remapped undo uses document history',
    (tester) async {
      const source = '| Original | B |\n| --- | --- |\n| C | D |';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          IanvsMarkdownShortcuts(
            bindings: const {
              IanvsMarkdownCommand.bold: [
                SingleActivator(LogicalKeyboardKey.f2),
              ],
              IanvsMarkdownCommand.undo: [
                SingleActivator(LogicalKeyboardKey.f3),
              ],
              IanvsMarkdownCommand.indent: [
                SingleActivator(LogicalKeyboardKey.f4),
              ],
            },
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              showToolbar: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('ianvs-markdown-table-0-0'));
      await tester.tap(cell);
      await tester.pumpAndSettle();
      tester.widget<TextField>(cell).controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 8);
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyB, meta: true);
      expect(controller.text, source);
      await chord(tester, LogicalKeyboardKey.f2);
      expect(
        controller.text
            .split('\n')
            .first
            .split('|')
            .map((cell) => cell.trim())
            .toList(),
        ['', '**Original**', 'B', ''],
      );
      await chord(tester, LogicalKeyboardKey.f3);
      expect(controller.text, source);
      await chord(tester, LogicalKeyboardKey.f4);
      final next = tester.widget<TextField>(
        find.byKey(const ValueKey('ianvs-markdown-table-0-1')),
      );
      expect(next.focusNode!.hasFocus, isTrue);
      expect(controller.text, source);
    },
  );

  keyboardTest(
    'property commands keep local undo and commit before remapped save',
    (tester) async {
      const source = '---\nauthor: Alice\n---\n\nBody';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      String? saved;
      await tester.pumpWidget(
        host(
          IanvsMarkdownShortcuts(
            bindings: const {
              IanvsMarkdownCommand.bold: [
                SingleActivator(LogicalKeyboardKey.f2),
              ],
              IanvsMarkdownCommand.undo: [
                SingleActivator(LogicalKeyboardKey.f3),
              ],
              IanvsMarkdownCommand.save: [
                SingleActivator(LogicalKeyboardKey.f4),
              ],
            },
            child: IanvsMarkdownLiveEditor(
              controller: controller,
              showFrontMatter: true,
              onSaveRequested: (value) => saved = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(
        const ValueKey('ianvs-markdown-front-matter-input-author'),
      );
      await tester.tap(field);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(field, 'Bob');
      await tester.pump(const Duration(milliseconds: 600));
      await chord(tester, LogicalKeyboardKey.f2);
      expect(tester.widget<TextField>(field).controller!.text, 'Bob');
      expect(controller.text, source);
      await chord(tester, LogicalKeyboardKey.f3);
      expect(tester.widget<TextField>(field).controller!.text, 'Alice');
      expect(controller.text, source);
      await tester.enterText(field, 'Carol');
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.f4);
      expect(saved, contains('author: Carol'));
      expect(controller.isDirty, isFalse);
    },
  );

  keyboardTest(
    'composition suppresses mapped and reserved commands until committed',
    (tester) async {
      final controller = IanvsMarkdownController(text: 'ni');
      addTearDown(controller.dispose);
      var calls = 0;
      await tester.pumpWidget(
        host(
          IanvsMarkdownShortcuts(
            bindings: const {
              IanvsMarkdownCommand.bold: [
                SingleActivator(LogicalKeyboardKey.f2),
              ],
            },
            hostShortcuts: {
              const SingleActivator(LogicalKeyboardKey.f3): () => calls++,
            },
            child: IanvsMarkdownEditor(controller: controller, autofocus: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.f2);
      await chord(tester, LogicalKeyboardKey.f3);
      expect(controller.text, 'ni');
      expect(controller.value.composing, const TextRange(start: 0, end: 2));
      expect(calls, 0);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '你',
          selection: TextSelection(baseOffset: 0, extentOffset: 1),
        ),
      );
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.f2);
      expect(controller.text, '**你**');
      await chord(tester, LogicalKeyboardKey.f3);
      expect(calls, 1);
    },
  );

  keyboardTest('nearest scope updates and never captures an unrelated input', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Text');
    final outside = TextEditingController(text: 'Host');
    addTearDown(controller.dispose);
    addTearDown(outside.dispose);
    var outerCalls = 0;
    var innerCalls = 0;
    Widget page(bool nested) => host(
      IanvsMarkdownShortcuts(
        hostShortcuts: {
          const SingleActivator(LogicalKeyboardKey.f2): () => outerCalls++,
        },
        child: Column(
          children: [
            TextField(key: const ValueKey('host-field'), controller: outside),
            Expanded(
              child: IanvsMarkdownShortcuts(
                hostShortcuts: {
                  const SingleActivator(LogicalKeyboardKey.f2): () =>
                      innerCalls += nested ? 1 : 10,
                },
                child: IanvsMarkdownEditor(
                  controller: controller,
                  autofocus: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.f2);
    expect(innerCalls, 1);
    expect(outerCalls, 0);
    await tester.pumpWidget(page(false));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.f2);
    expect(innerCalls, 11);
    await tester.tap(find.byKey(const ValueKey('host-field')));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.f2);
    expect(innerCalls, 11);
    expect(outerCalls, 0);
    expect(outside.text, 'Host');
  });
}

class _TrackedFocusNode extends FocusNode {
  var disposals = 0;
  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}
