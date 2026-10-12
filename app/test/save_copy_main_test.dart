import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import 'support/fakes.dart';

class _DelayedFiles extends MemoryMarkdownFileService {
  Completer<void>? completion;
  final started = <String>[];
  @override
  Future<void> writeMarkdownFileAtomic(String path, String contents) async {
    started.add(contents);
    await completion?.future;
    files[path] = contents;
    events.add(FileSystemModifyEvent(path, false, true));
  }
}

void main() {
  for (final nativeMenu in [false, true]) {
    for (final fail in [false, true]) {
      testWidgets(
        'main save then type/copy retains latest draft; failure=$fail nativeMenu=$nativeMenu',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final copied = <String>[];
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(
            SystemChannels.menu,
            (_) async => null,
          );
          messenger.setMockMethodCallHandler(SystemChannels.platform, (
            call,
          ) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
          addTearDown(() {
            messenger.setMockMethodCallHandler(SystemChannels.menu, null);
            messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          });
          const original = '# Original\r\n';
          const saved = '# Saved 中文😀\r\n';
          const later = '$saved\r\n**Later draft**  ';
          final files = _DelayedFiles()..files['/notes/source.md'] = original;
          final workspace = WorkspaceController(
            fileService: files,
            sessionStore: MemoryWorkspaceSessionStore(),
          );
          addTearDown(workspace.dispose);
          addTearDown(files.dispose);
          await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
          await tester.pumpAndSettle();
          final document = (await workspace.openPath('/notes/source.md'))!;
          document.controller.mode = IanvsMarkdownEditorMode.source;
          await tester.pumpAndSettle();
          final field = find.byKey(
            const ValueKey('ianvs-markdown-source-field'),
          );
          await tester.enterText(field, saved);
          await tester.pumpAndSettle();
          files.completion = Completer<void>();
          if (nativeMenu) {
            final menu = tester.widget<PlatformMenuBar>(
              find.byType(PlatformMenuBar),
            );
            final file = menu.menus.whereType<PlatformMenu>().singleWhere(
              (item) => item.label == 'File',
            );
            final group = file.menus.whereType<PlatformMenuItemGroup>().first;
            group.members
                .singleWhere((item) => item.label == 'Save')
                .onSelected!();
            await tester.pumpAndSettle();
          } else {
            await _press(tester, LogicalKeyboardKey.keyS);
          }
          expect(files.started, [saved]);
          await tester.enterText(field, later);
          await tester.pumpAndSettle();
          await _press(tester, LogicalKeyboardKey.keyA);
          await _press(tester, LogicalKeyboardKey.keyC);
          expect(
            copied.last,
            later,
            reason: 'copy uses current source, not the pending save',
          );
          if (fail) {
            files.completion!.completeError(
              StateError('Test disk unavailable'),
            );
          } else {
            files.completion!.complete();
          }
          await tester.pumpAndSettle();
          expect(document.controller.text, later);
          expect(document.controller.isDirty, isTrue);
          expect(document.persistedText, fail ? original : saved);
          expect(files.files[document.path], fail ? original : saved);
          expect(document.hasExternalChanges, isFalse);
          if (fail) {
            expect(
              find.textContaining('Test disk unavailable'),
              findsOneWidget,
            );
          }
          files.completion = null;
          if (nativeMenu) {
            final menu = tester.widget<PlatformMenuBar>(
              find.byType(PlatformMenuBar),
            );
            final file = menu.menus.whereType<PlatformMenu>().singleWhere(
              (item) => item.label == 'File',
            );
            final group = file.menus.whereType<PlatformMenuItemGroup>().first;
            group.members
                .singleWhere((item) => item.label == 'Save')
                .onSelected!();
            await tester.pumpAndSettle();
          } else {
            await _press(tester, LogicalKeyboardKey.keyS);
          }
          expect(document.controller.isDirty, isFalse);
          expect(document.persistedText, later);
          expect(files.files[document.path], later);
          expect(document.hasExternalChanges, isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}
