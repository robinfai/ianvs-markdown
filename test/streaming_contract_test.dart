import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

String _visibleText(WidgetTester tester) => [
  ...tester
      .widgetList<RichText>(find.byType(RichText))
      .map((widget) => widget.text.toPlainText()),
  ...tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .map((widget) => widget.data ?? widget.textSpan!.toPlainText()),
  ...tester
      .widgetList<EditableText>(find.byType(EditableText))
      .map((widget) => widget.controller.text),
].join('\n');

Future<void> _controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.android),
  home: Scaffold(body: child),
);

void main() {
  final fragments = <String, List<String>>{
    'fence': ['```dart\n', 'final value = 1;\n', '``', '`\n\nTail.'],
    'table': [
      '| Name | Count |\n',
      '| --- | --- |\n| Alpha | 1',
      ' |\n| Beta | 2 |\n\nTail.',
    ],
    'inline link': ['[Guide', '](docs/guide', '.md)', '\n\nTail.'],
    'reference link': [
      '[Guide][target]',
      '\n\n[target]: docs/',
      'guide.md "Title"\n\nTail.',
    ],
  };

  for (final surface in ['body', 'view', 'live', 'reading']) {
    final presets = surface == 'body' || surface == 'view'
        ? IanvsMarkdownSyntaxPreset.values
        : [IanvsMarkdownSyntaxPreset.obsidian];
    for (final preset in presets) {
      for (final entry in fragments.entries) {
        testWidgets('$surface ${preset.name}: appended ${entry.key} converges', (
          tester,
        ) async {
          final controller = IanvsMarkdownController(
            text: 'Anchor.\n\n',
            mode: surface == 'reading'
                ? IanvsMarkdownEditorMode.preview
                : IanvsMarkdownEditorMode.livePreview,
          );
          addTearDown(controller.dispose);
          String? destination;
          void onLink(String text, String? href, String title) =>
              destination = href;
          Widget host(String source, {String identity = 'same-document'}) {
            final key = ValueKey(identity);
            return _app(switch (surface) {
              'body' => SingleChildScrollView(
                child: IanvsMarkdown(
                  key: key,
                  data: source,
                  syntaxPreset: preset,
                  onTapLink: onLink,
                ),
              ),
              'view' => IanvsMarkdownView(
                key: key,
                data: source,
                syntaxPreset: preset,
                showOutline: false,
                onTapLink: onLink,
              ),
              _ => IanvsMarkdownLiveEditor(
                key: key,
                controller: controller,
                autofocus: false,
                onTapLink: onLink,
              ),
            });
          }

          var source = 'Anchor.\n\n';
          await tester.pumpWidget(host(source));
          for (var index = 0; index < entry.value.length; index += 1) {
            source += entry.value[index];
            // Host policy: preserve the existing caret in the anchor paragraph.
            controller.value = TextEditingValue(
              text: source,
              selection: const TextSelection.collapsed(offset: 0),
            );
            await tester.pumpWidget(host(source));
            await tester.pumpAndSettle();
            expect(controller.text, source);
            expect(tester.takeException(), isNull, reason: 'fragment $index');
            if (entry.key == 'inline link' && index == 0) {
              expect(_visibleText(tester), contains('[Guide'));
            }
            if (entry.key == 'table' && index == 0) {
              expect(find.byType(Table), findsNothing);
            }
          }
          expect(_visibleText(tester), contains('Tail.'));
          if (entry.key == 'fence') {
            expect(
              tester
                  .widget<IanvsMarkdownCodeBlock>(
                    find.byType(IanvsMarkdownCodeBlock),
                  )
                  .source,
              'final value = 1;',
            );
          } else if (entry.key == 'table') {
            expect(_visibleText(tester), contains('Alpha'));
            expect(_visibleText(tester), contains('Beta'));
          } else if (surface != 'live') {
            await tester.tap(find.text('Guide', findRichText: true));
            expect(destination, 'docs/guide.md');
          }
          final streamed = _visibleText(tester);
          await tester.pumpWidget(host(source, identity: 'fresh-document'));
          await tester.pumpAndSettle();
          expect(_visibleText(tester), streamed);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(milliseconds: 500));
        });
      }
    }
  }

  for (final view in [false, true]) {
    for (final preset in IanvsMarkdownSyntaxPreset.values) {
      testWidgets(
        '${view ? 'view' : 'body'} ${preset.name}: append clears copy selection',
        (tester) async {
          final focus = FocusNode();
          addTearDown(focus.dispose);
          final copied = <String>[];
          Future<void> copy(IanvsMarkdownClipboardData data) async =>
              copied.add(data.markdown);
          Widget host(String source, {String id = 'A'}) => _app(
            view
                ? IanvsMarkdownView(
                    key: ValueKey(id),
                    data: source,
                    syntaxPreset: preset,
                    showOutline: false,
                    focusNode: focus,
                    autofocus: true,
                    clipboardWriter: copy,
                  )
                : IanvsMarkdown(
                    key: ValueKey(id),
                    data: source,
                    syntaxPreset: preset,
                    focusNode: focus,
                    autofocus: true,
                    clipboardWriter: copy,
                  ),
          );
          await tester.pumpWidget(host('First.'));
          await tester.pumpAndSettle();
          await _controlKey(tester, LogicalKeyboardKey.keyA);
          await _controlKey(tester, LogicalKeyboardKey.keyC);
          expect(copied, ['First.']);
          const appended = 'First.\n\n**中文😀 appended**';
          await tester.pumpWidget(host(appended));
          await tester.pumpAndSettle();
          await _controlKey(tester, LogicalKeyboardKey.keyC);
          expect(copied, ['First.']);
          await _controlKey(tester, LogicalKeyboardKey.keyA);
          await _controlKey(tester, LogicalKeyboardKey.keyC);
          expect(copied.last, appended);
          // Equal source still represents a different document when its key changes.
          await tester.pumpWidget(host(appended, id: 'B'));
          await tester.pumpAndSettle();
          await _controlKey(tester, LogicalKeyboardKey.keyC);
          expect(copied, hasLength(2));
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final live in [false, true]) {
    testWidgets(
      '${live ? 'Live' : 'Source'} host append preserves caret and composing',
      (tester) async {
        final controller = IanvsMarkdownController(text: '中文😀');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            live
                ? IanvsMarkdownLiveEditor(
                    controller: controller,
                    autofocus: true,
                  )
                : IanvsMarkdownEditor(controller: controller, autofocus: true),
          ),
        );
        await tester.pumpAndSettle();
        controller.value = const TextEditingValue(
          text: '中文😀',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        );
        await tester.pump();
        for (final fragment in ['\n\n[more', '](guide.md)']) {
          controller.value = controller.value.copyWith(
            text: controller.text + fragment,
          );
          await tester.pump();
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 2),
          );
          expect(controller.value.composing, const TextRange(start: 0, end: 2));
        }
        expect(controller.text, '中文😀\n\n[more](guide.md)');
        controller.clearComposing();
        await tester.pumpAndSettle();
        expect(controller.text, '中文😀\n\n[more](guide.md)');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an older copy cannot restart feedback after the newest copy expires',
    (tester) async {
      final pending = <Completer<void>>[];
      await tester.pumpWidget(
        _app(
          IanvsMarkdownCodeBlock(
            source: 'code',
            onCopyCode: (_) {
              final result = Completer<void>();
              pending.add(result);
              return result.future;
            },
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.content_copy_rounded));
      await tester.tap(find.byIcon(Icons.content_copy_rounded));
      expect(pending, hasLength(2));
      pending.last.complete();
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      pending.first.complete();
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final replacement in ['source', 'round trip', 'handler', 'unmount']) {
    testWidgets('code copy completion ignores $replacement replacement', (
      tester,
    ) async {
      final pending = Completer<void>();
      final captured = <String>[];
      Future<void> oldCopy(String source) {
        captured.add(source);
        return pending.future;
      }

      Future<void> newCopy(String source) async => captured.add(source);
      Widget host(String source, {bool newHandler = false}) => _app(
        IanvsMarkdownCodeBlock(
          source: source,
          onCopyCode: newHandler ? newCopy : oldCopy,
        ),
      );
      await tester.pumpWidget(host('old code'));
      await tester.tap(find.byIcon(Icons.content_copy_rounded));
      await tester.pump();
      expect(captured, ['old code']);
      if (replacement == 'unmount') {
        await tester.pumpWidget(const SizedBox());
      } else if (replacement == 'handler') {
        await tester.pumpWidget(host('old code', newHandler: true));
      } else {
        await tester.pumpWidget(host('new code'));
        if (replacement == 'round trip') {
          await tester.pumpWidget(host('old code'));
        }
      }
      pending.complete();
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
