import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import 'support/fakes.dart';

const _source =
    'Alpha paragraph.\n\n    indented code\n\nSecond **paragraph**.';

void main() {
  final shortcuts =
      <({String name, LogicalKeyboardKey key, bool command, bool shift})>[
        (
          name: 'Cmd+B',
          key: LogicalKeyboardKey.keyB,
          command: true,
          shift: false,
        ),
        (
          name: 'Cmd+I',
          key: LogicalKeyboardKey.keyI,
          command: true,
          shift: false,
        ),
        (
          name: 'Cmd+K',
          key: LogicalKeyboardKey.keyK,
          command: true,
          shift: false,
        ),
        (
          name: 'Cmd+D',
          key: LogicalKeyboardKey.keyD,
          command: true,
          shift: false,
        ),
        (
          name: 'Tab',
          key: LogicalKeyboardKey.tab,
          command: false,
          shift: false,
        ),
        (
          name: 'Shift+Tab',
          key: LogicalKeyboardKey.tab,
          command: false,
          shift: true,
        ),
        (
          name: 'Cmd+V',
          key: LogicalKeyboardKey.keyV,
          command: true,
          shift: false,
        ),
        (
          name: 'Cmd+X',
          key: LogicalKeyboardKey.keyX,
          command: true,
          shift: false,
        ),
      ];

  for (final shortcut in shortcuts) {
    testWidgets(
      'Read ${shortcut.name} cannot modify the retained Live selection',
      (tester) async {
        _mockNativeChannels(tester);
        final workspace = await _pumpReadApp(
          tester,
          selectIndentedCode: shortcut.shift,
        );
        final controller = workspace.activeDocument!.controller;
        expect(controller.selection.isValid, isTrue);
        expect(controller.selection.isCollapsed, isFalse);

        await _press(
          tester,
          shortcut.key,
          command: shortcut.command,
          shift: shortcut.shift,
        );

        expect(controller.text, _source);
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
        expect(controller.mode, IanvsMarkdownEditorMode.preview);
        await tester.tap(find.text('Source'));
        await tester.pumpAndSettle();
        final sourceField = tester.widget<TextField>(
          find.byKey(const ValueKey('ianvs-markdown-source-field')),
        );
        expect(sourceField.controller!.text, _source);
        await _finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final redo in [false, true]) {
    testWidgets(
      'Read ${redo ? 'redo' : 'undo'} keeps the document unchanged',
      (tester) async {
        _mockNativeChannels(tester);
        final workspace = await _pumpReadApp(tester, prepareHistory: redo);
        final controller = workspace.activeDocument!.controller;
        expect(redo ? controller.canRedo : controller.canUndo, isTrue);

        await _press(tester, LogicalKeyboardKey.keyZ, shift: redo);

        expect(controller.text, _source);
        expect(controller.isDirty, isFalse);
        expect(controller.mode, IanvsMarkdownEditorMode.preview);
        await _finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'Read native ${redo ? 'Redo' : 'Undo'} keeps the document unchanged',
      (tester) async {
        _mockNativeChannels(tester);
        final workspace = await _pumpReadApp(tester, prepareHistory: redo);
        final controller = workspace.activeDocument!.controller;
        final menu = tester.widget<PlatformMenuBar>(
          find.byType(PlatformMenuBar),
        );
        final edit = menu.menus.whereType<PlatformMenu>().singleWhere(
          (item) => item.label == 'Edit',
        );
        final command = edit.menus.singleWhere(
          (item) => item.label == (redo ? 'Redo' : 'Undo'),
        );

        command.onSelected!();
        await tester.pumpAndSettle();

        expect(controller.text, _source);
        expect(controller.isDirty, isFalse);
        expect(controller.mode, IanvsMarkdownEditorMode.preview);
        await _finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final mode in ['Live', 'Source']) {
    testWidgets(
      '$mode editing shortcuts still work after leaving Read',
      (tester) async {
        _mockNativeChannels(tester);
        final workspace = await _pumpReadApp(tester);
        final controller = workspace.activeDocument!.controller;
        await tester.tap(find.text(mode));
        await tester.pumpAndSettle();
        if (mode == 'Live') {
          await tester.tap(find.text('Alpha paragraph.'));
          await tester.pumpAndSettle();
        }
        final fieldFinder = mode == 'Source'
            ? find.byKey(const ValueKey('ianvs-markdown-source-field'))
            : find.descendant(
                of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
                matching: find.byType(TextField),
              );
        await tester.tap(fieldFinder);
        final field = tester.widget<TextField>(fieldFinder);
        field.controller!.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 5,
        );
        await tester.pump();

        await _press(tester, LogicalKeyboardKey.keyB);
        expect(controller.text, '**Alpha**${_source.substring(5)}');
        expect(controller.isDirty, isTrue);
        await _press(tester, LogicalKeyboardKey.keyZ);
        expect(controller.text, _source);
        await _finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'Read retains document selection, mouse selection, and copying',
    (tester) async {
      final copied = <String>[];
      _mockNativeChannels(tester, copied: copied);
      final workspace = await _pumpReadApp(tester);
      final controller = workspace.activeDocument!.controller;
      expect(find.byType(SelectionArea), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.keyA);
      await _press(tester, LogicalKeyboardKey.keyC);
      expect(copied.last, _source);

      await tester.tap(find.text('Alpha paragraph.'));
      await tester.pump();
      copied.clear();
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.text('Alpha paragraph.')) + const Offset(1, 8),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        tester.getBottomRight(find.text('Second paragraph.')) -
            const Offset(1, 8),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.keyC);
      expect(copied, isNotEmpty);
      expect(copied.last, contains('Alpha paragraph.'));
      expect(copied.last, contains('Second paragraph'));
      expect(controller.text, _source);
      expect(controller.isDirty, isFalse);
      await _finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

void _mockNativeChannels(WidgetTester tester, {List<String>? copied}) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') {
      return <String, dynamic>{'text': 'https://example.com'};
    }
    if (call.method == 'Clipboard.setData') {
      copied?.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.menu, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

Future<WorkspaceController> _pumpReadApp(
  WidgetTester tester, {
  bool selectIndentedCode = false,
  bool? prepareHistory,
}) async {
  tester.view.physicalSize = const Size(1182, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final files = MemoryMarkdownFileService()..files['/vault/read.md'] = _source;
  final workspace = WorkspaceController(
    fileService: files,
    sessionStore: MemoryWorkspaceSessionStore(),
  );
  addTearDown(() async {
    workspace.dispose();
    await files.dispose();
  });
  await workspace.initialize();
  final document = (await workspace.openPath('/vault/read.md'))!;
  await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alpha paragraph.'));
  await tester.pumpAndSettle();
  final activeField = tester.widget<TextField>(
    find.descendant(
      of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
      matching: find.byType(TextField),
    ),
  );
  activeField.controller!.selection = const TextSelection(
    baseOffset: 0,
    extentOffset: 5,
  );
  await tester.pump();
  expect(document.controller.selection.textInside(_source), 'Alpha');
  if (selectIndentedCode) {
    final start = _source.indexOf('indented code');
    document.controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + 'indented code'.length,
    );
  }
  if (prepareHistory != null) {
    document.controller.text = '$_source\n\nLater edit';
    if (prepareHistory) {
      document.controller.undo();
    } else {
      document.controller.text = _source;
    }
    document.controller.markSaved();
  }
  await tester.tap(find.text('Read'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Second paragraph.'));
  await tester.pumpAndSettle();
  expect(document.controller.mode, IanvsMarkdownEditorMode.preview);
  return workspace;
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool command = true,
  bool shift = false,
}) async {
  if (command) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (command) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull);
}
