import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

// Exercise the actual host typography without a package dependency on the app.
// ignore: avoid_relative_lib_imports
import '../app/lib/src/desktop_theme.dart';

RenderEditable _editableWithin(WidgetTester tester, Finder finder) {
  RenderEditable? editable;
  void visit(RenderObject child) {
    if (editable != null) return;
    if (child is RenderEditable) {
      editable = child;
      return;
    }
    child.visitChildren(visit);
  }

  visit(tester.renderObject(finder));
  return editable!;
}

Finder _selectableContaining(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is SelectableText &&
      (widget.data ?? widget.textSpan?.toPlainText() ?? '').contains(text),
);

double _baselineFor(RenderEditable editable, int offset) {
  if (editable.text!.toPlainText().contains('\uFFFC')) {
    // This reads the already laid-out paragraph; dry layout is unsupported by
    // some inline link widgets and would rerun their LayoutBuilder callbacks.
    // ignore: invalid_use_of_protected_member
    final baseline = editable.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    return editable.localToGlobal(Offset.zero).dy + baseline;
  }
  final painter = TextPainter(
    text: editable.text,
    textDirection: editable.textDirection,
    textScaler: editable.textScaler,
    strutStyle: editable.strutStyle,
  )..layout(maxWidth: editable.size.width);
  final caret = painter.getOffsetForCaret(
    TextPosition(offset: offset),
    Rect.zero,
  );
  final baseline = painter
      .computeLineMetrics()
      .firstWhere((line) => line.baseline > caret.dy)
      .baseline;
  painter.dispose();
  return editable.localToGlobal(Offset(0, baseline)).dy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Opt in on macOS to repeat these checks with the app's actual Latin fonts;
  // the default run remains portable and catches layout drift with Ahem.
  setUpAll(() async {
    if (Platform.isMacOS &&
        const bool.fromEnvironment('LINEFOLD_SYSTEM_FONTS')) {
      for (final entry in {
        '.AppleSystemUIFont': '/System/Library/Fonts/SFNS.ttf',
        'SF Mono': '/System/Library/Fonts/SFNSMono.ttf',
        // Flutter tests use Ahem as the fallback family. Supply host CJK
        // glyphs for this opt-in run so Chinese line breaking is measured.
        'Ahem': '/System/Library/Fonts/Hiragino Sans GB.ttc',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            Future.value(
              ByteData.sublistView(File(entry.value).readAsBytesSync()),
            ),
          );
        await loader.load();
      }
    }
  });

  testWidgets(
    'hidden front matter has zero Live space and preserves Source',
    (tester) async {
      const header =
          '---\ntitle: Linefold 体验样本\ntags: [writing, audit]\n---\n\n';
      const body = '# Linefold Markdown 体验\n\n正文 body';
      final controller = IanvsMarkdownController(text: '$header$body');
      addTearDown(controller.dispose);
      Widget app() => MaterialApp(
        theme: desktopTheme(Brightness.light),
        home: Scaffold(
          body: IanvsMarkdownLiveEditor(
            controller: controller,
            showToolbar: false,
            showFrontMatter: false,
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(_selectableContaining('title:'), findsNothing);
      expect(_selectableContaining('tags:'), findsNothing);
      final bodyTop = tester.getTopLeft(find.text('Linefold Markdown 体验')).dy;
      controller.text = body;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Linefold Markdown 体验')).dy, bodyTop);
      controller.text = '$header$body';
      for (final mode in [
        IanvsMarkdownEditorMode.preview,
        IanvsMarkdownEditorMode.source,
      ]) {
        controller.mode = mode;
        await tester.pumpAndSettle();
        if (mode == IanvsMarkdownEditorMode.preview) {
          expect(
            find.textContaining('title:', findRichText: true),
            findsNothing,
          );
          expect(find.byType(IanvsMarkdownFrontMatterCard), findsNothing);
        } else {
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '$header$body',
          );
        }
      }
      expect(controller.text, '$header$body');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'hidden YAML never captures autofocus or a Live source caret',
    (tester) async {
      const header = '---\ntitle: Hidden properties\n---\n\n';
      const body = 'Alpha 中文 body';
      const source = '$header$body';
      final controller = IanvsMarkdownController(text: source)
        ..selection = const TextSelection.collapsed(offset: 0);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(Brightness.light),
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              showFrontMatter: false,
              showToolbar: false,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).controller!.text, body);
      expect(controller.selection.extentOffset, header.length);
      controller.selection = const TextSelection.collapsed(offset: 5);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, body);
      expect(controller.selection.extentOffset, header.length);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, body);
      controller.mode = IanvsMarkdownEditorMode.source;
      await tester.pumpAndSettle();
      controller.selection = const TextSelection.collapsed(offset: 5);
      controller.mode = IanvsMarkdownEditorMode.livePreview;
      await tester.pumpAndSettle();
      expect(_selectableContaining('title:'), findsNothing);
      expect(
        find.textContaining('Hidden properties', findRichText: true),
        findsNothing,
      );
      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'unselected inline link stays rendered and its source still edits',
    (tester) async {
      const source = 'Alpha 中文 [链接 example](https://example.com) 正文。';
      final controller = IanvsMarkdownController(text: source)
        ..selection = const TextSelection.collapsed(offset: 1);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: IanvsMarkdownLiveEditor(
              controller: controller,
              showToolbar: false,
              autofocus: true,
              contentMaxWidth: 320,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      final link = find.byKey(const ValueKey('ianvs-markdown-ordinary-link'));
      expect(link, findsOneWidget);
      final renderedHeight = tester.getSize(field).height;
      controller.selection = TextSelection.collapsed(
        offset: source.indexOf('https'),
      );
      await tester.pumpAndSettle();
      expect(link, findsNothing);
      expect(tester.widget<TextField>(field).controller!.text, source);
      final editable = _editableWithin(tester, field);
      expect(editable.text!.toPlainText(), source);
      // Explicit URL editing reveals the complete source and may wrap further.
      expect(
        tester.getSize(field).height,
        greaterThanOrEqualTo(renderedHeight),
      );
      final modified = source.replaceFirst('example.com', 'example.org');
      await tester.enterText(field, modified);
      await tester.pumpAndSettle();
      expect(controller.text, modified);
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, source);
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pumpAndSettle();
      expect(link, findsOneWidget);
      expect(tester.getSize(field).height, closeTo(renderedHeight, .01));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final blankLines in [0, 1, 2, 4]) {
    testWidgets(
      'blank fenced code keeps its canvas with $blankLines blank lines',
      (tester) async {
        final code = '```text\n${'\n' * blankLines}```';
        final controller = IanvsMarkdownController(text: '$code\n\nAfter');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(Brightness.light),
            home: Scaffold(
              body: IanvsMarkdownLiveEditor(
                controller: controller,
                showToolbar: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final block = find.byKey(
          const ValueKey('ianvs-markdown-block-0-fencedCode'),
        );
        final height = tester.getSize(block).height;
        final followingTop = tester.getTopLeft(find.text('After')).dy;
        await tester.tap(find.byType(IanvsMarkdownCodeBlock));
        await tester.pumpAndSettle();
        expect(tester.getSize(block).height, closeTo(height, .01));
        expect(
          tester.getTopLeft(find.text('After')).dy,
          closeTo(followingTop, .01),
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          code,
        );
        expect(controller.isDirty, isFalse);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  const mixed = 'Alpha 中英混排 English 123，点击前后应保持行高与文字基线。';
  const long =
      '$mixed 更长的内容用于检查窄窗口自动换行，不应该因焦点而改变。More text keeps the next block in place.';
  const cases = <String, String>{
    'paragraph': mixed,
    'soft lines': '$mixed\nDelta 第二行文字 second line.',
    'wrapped paragraph': long,
    'strong emphasis':
        'Alpha **粗体 bold** *斜体 italic* ~~删除线 strike~~ ==高亮 highlight==。',
    'inline code': 'Alpha 中文 `inline code` 正文结束。',
    'inline link': 'Alpha 中文 [链接 example](https://example.com) 正文。',
    'heading 1': '# $mixed',
    'heading 2': '## $mixed',
    'heading 3': '### $mixed',
    'heading 4': '#### $mixed',
    'heading 5': '##### $mixed',
    'heading 6': '###### $mixed',
    'setext heading': '$mixed\n===',
    'unordered list': '- $mixed',
    'ordered list': '12. $mixed',
    'nested list': '- Parent 父项\n  - $mixed',
    'task list': '- [ ] $mixed',
    'done task': '- [x] $mixed',
    'quote': '> $mixed',
    'multiline quote': '> $mixed\n> Delta 第二行 second line.',
    'nested quote': '> > $mixed\n> > Delta 第二行 second line.',
    'fenced code': '```text\n$mixed\nDelta 第二行 second line.\n```',
    'long fenced code': '```text\n$long\nDelta second line\n```',
    'indented code': '    $mixed\n    Delta 第二行 second line.',
    'long indented code': '    $long\n    Delta second line',
  };

  for (final width in [720.0, 320.0]) {
    for (final scale in [1.0, 1.3]) {
      for (final entry in cases.entries) {
        testWidgets(
          'focus keeps geometry: ${entry.key}, width=$width, scale=$scale',
          (tester) async {
            tester.view.physicalSize = const Size(1000, 1800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final source = 'Before\n\n${entry.value}\n\nAfter';
            final controller = IanvsMarkdownController(text: source);
            final scroll = ScrollController();
            addTearDown(controller.dispose);
            addTearDown(scroll.dispose);
            await tester.pumpWidget(
              MaterialApp(
                theme: desktopTheme(Brightness.light),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: IanvsMarkdownLiveEditor(
                    controller: controller,
                    scrollController: scroll,
                    showToolbar: false,
                    contentMaxWidth: width,
                    padding: const EdgeInsets.all(24),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final block = parseMarkdownBlocks(
              source,
              splitListItems: true,
            ).firstWhere((block) => block.source.contains('Alpha'));
            final blockFinder = find.byKey(
              ValueKey(
                'ianvs-markdown-block-${block.start}-${block.type.name}',
              ),
            );
            final renderedFinder = find
                .descendant(
                  of: blockFinder,
                  matching: _selectableContaining('Alpha'),
                )
                .first;
            final beforeHeight = tester.getSize(blockFinder).height;
            final followingTop = tester.getTopLeft(find.text('After')).dy;
            final rendered = _editableWithin(tester, renderedFinder);
            final renderedText = rendered.text!.toPlainText();
            final payloadOffset = renderedText.indexOf('Alpha');
            final beforeBaseline = _baselineFor(rendered, payloadOffset);
            final renderedCaret = rendered.getLocalRectForCaret(
              TextPosition(offset: payloadOffset + 1),
            );
            final scrollOffset = scroll.offset;
            await tester.tapAt(rendered.localToGlobal(renderedCaret.center));
            await tester.pumpAndSettle();
            final fieldFinder = find.descendant(
              of: find.byKey(const ValueKey('ianvs-markdown-active-block')),
              matching: find.byType(TextField),
            );
            expect(fieldFinder, findsOneWidget);
            final active = _editableWithin(tester, fieldFinder);
            final afterBaseline = _baselineFor(
              active,
              block.source.indexOf('Alpha'),
            );
            final afterHeight = tester.getSize(blockFinder).height;
            final afterFollowingTop = tester.getTopLeft(find.text('After')).dy;
            expect(
              afterHeight,
              closeTo(beforeHeight, .01),
              reason: 'Focus must not resize the block.',
            );
            expect(
              afterBaseline,
              closeTo(beforeBaseline, .01),
              reason: 'Payload baseline must stay fixed.',
            );
            expect(
              afterFollowingTop,
              closeTo(followingTop, .01),
              reason: 'Following blocks must stay fixed.',
            );
            expect(scroll.offset, scrollOffset);
            expect(controller.text, source);
            expect(controller.isDirty, isFalse);
            expect(controller.canUndo, isFalse);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('After'));
            await tester.pumpAndSettle();
            expect(
              tester.getSize(blockFinder).height,
              closeTo(beforeHeight, .01),
            );
            expect(controller.text, source);
            expect(controller.isDirty, isFalse);
          },
          variant: TargetPlatformVariant.only(TargetPlatform.macOS),
        );
      }
    }
  }
}
