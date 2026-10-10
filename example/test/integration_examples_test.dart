import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_example/body.dart';
import 'package:ianvs_markdown_example/editor.dart';
import 'package:ianvs_markdown_example/reading.dart';

Future<void> controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'editor reports simplified display and saves the complete source',
    (tester) async {
      String? saved;
      await tester.pumpWidget(
        EditorExampleApp(write: (_, source) async => saved = source),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<IanvsMarkdownLiveEditor>(
        find.byType(IanvsMarkdownLiveEditor),
      );
      final source = '[${'a' * 4096}\r\n中文😀';
      editor.controller.text = source;
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Large document: simplified display'),
        findsOneWidget,
      );
      expect(editor.controller.text, source);
      await tester.tap(find.byTooltip('Save draft'));
      await tester.pumpAndSettle();
      expect(saved, source);
      editor.controller.text = '# Small again';
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Large document: simplified display'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'body example switches syntax and handles only approved resources',
    (tester) async {
      await tester.pumpWidget(const BodyExampleApp());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('==highlighted words==', findRichText: true),
        findsWidgets,
      );
      expect(find.byType(FlutterLogo), findsOneWidget);
      expect(find.text('Image not approved by this host'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.text('Obsidian'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('==highlighted words==', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('highlighted words', findRichText: true),
        findsWidgets,
      );
      await tester.tap(find.text('Open the guide', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Host received link: guide.md'), findsOneWidget);
    },
  );

  testWidgets(
    'reader navigates and copies the current document with exact source',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final copied = <IanvsMarkdownClipboardData>[];
      await tester.pumpWidget(
        ReadingExampleApp(clipboardWriter: (data) async => copied.add(data)),
      );
      await tester.pumpAndSettle();
      final view = tester.widget<IanvsMarkdownView>(
        find.byType(IanvsMarkdownView),
      );
      await controlKey(tester, LogicalKeyboardKey.keyA);
      await controlKey(tester, LogicalKeyboardKey.keyC);
      expect(copied.single.markdown, readingGuide);
      expect(copied.single.html, contains('<strong>Markdown</strong>'));
      await tester.tap(find.text('Jump to checklist'));
      await tester.pumpAndSettle();
      expect(view.controller!.offset, greaterThan(0));
      await tester.tap(find.text('Switch document'));
      await tester.pumpAndSettle();
      expect(view.controller!.offset, 0);
      // A document update clears the previous selection before the next copy.
      await controlKey(tester, LogicalKeyboardKey.keyC);
      expect(copied, hasLength(1));
      await controlKey(tester, LogicalKeyboardKey.keyA);
      await controlKey(tester, LogicalKeyboardKey.keyC);
      expect(copied.last.markdown, readingNotes);
      expect(copied.last.markdown, isNot(contains('Reading guide')));
      expect(find.text('Copied selection'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor saves captured text and preserves newer edits and focus',
    (tester) async {
      final pending = Completer<void>();
      final writes = <String>[];
      await tester.pumpWidget(
        EditorExampleApp(
          write: (id, source) async {
            writes.add('$id:$source');
            if (writes.length == 1) await pending.future;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Source mode'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
      await tester.enterText(field, '# Saved first');
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(writes, ['draft.md:# Saved first']);
      await tester.enterText(field, '# Newer draft');
      pending.complete();
      await tester.pumpAndSettle();
      final editor = tester.widget<IanvsMarkdownLiveEditor>(
        find.byType(IanvsMarkdownLiveEditor),
      );
      expect(editor.controller.isDirty, isTrue);
      expect(editor.controller.text, '# Newer draft');
      expect(
        find.textContaining('Saved draft.md: 13 characters'),
        findsOneWidget,
      );
      await controlKey(tester, LogicalKeyboardKey.keyL);
      expect(find.byTooltip('保存草稿'), findsOneWidget);
      expect(editor.focusNode!.hasFocus, isTrue);
      await tester.tap(find.byTooltip('保存草稿'));
      await tester.pumpAndSettle();
      expect(writes, ['draft.md:# Saved first', 'draft.md:# Newer draft']);
      expect(editor.controller.isDirty, isFalse);
      expect(editor.focusNode!.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
