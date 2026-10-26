import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  for (final selectable in [true, false]) {
    for (final newline in ['\n', '\r\n', '\r']) {
      testWidgets(
        'plain fallback navigation and anchors $selectable ${newline.codeUnits}',
        (tester) async {
          final source =
              '---${newline}title: hidden$newline---$newline'
              '${List.generate(180, (i) => 'Line $i 中文 content').join(newline)}';
          final controller = IanvsMarkdownController(text: source);
          final scroll = ScrollController();
          IanvsMarkdownViewportAnchor? anchor;
          addTearDown(controller.dispose);
          addTearDown(scroll.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: IanvsMarkdownView(
                  data: source,
                  controller: scroll,
                  selectable: selectable,
                  sourceNavigation: controller.sourceNavigation,
                  showOutline: false,
                  onViewportChanged: (value) => anchor = value,
                  renderBudget: const IanvsMarkdownRenderBudget(
                    maxSourceCodeUnits: 1,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final before = controller.value;
          final target = source.indexOf('Line 120');
          controller.revealSourceRange(TextRange.collapsed(target));
          await tester.pumpAndSettle();
          expect(scroll.offset, greaterThan(1000));
          expect(controller.value, before);
          expect(anchor, isNotNull);
          expect(anchor!.sourceOffset, greaterThan(source.indexOf('Line 100')));
          expect(anchor!.sourceOffset, lessThan(target + 30));
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(const ValueKey('ianvs-markdown-plain-fallback')),
              matching: find.byType(RichText),
            ),
          );
          final bodyStart = source.indexOf('Line 0');
          final caret = paragraph.getOffsetForCaret(
            TextPosition(offset: target - bodyStart),
            Rect.zero,
          );
          expect(paragraph.localToGlobal(caret).dy, inInclusiveRange(0, 600));
          // A stale request never scrolls the new document or alters selection.
          final position = scroll.offset;
          controller.text = 'other';
          await tester.pump(const Duration(milliseconds: 600));
          controller.revealSourceRange(const TextRange.collapsed(0));
          await tester.pumpAndSettle();
          expect(scroll.offset, position);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'truncated plain fallback clamps and restores its visible anchor',
    (tester) async {
      final source = List.generate(400, (i) => 'Line $i content 中文\n').join();
      final controller = IanvsMarkdownController(text: source);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      IanvsMarkdownViewportAnchor? anchor;
      Widget view({IanvsMarkdownViewportAnchor? initial}) => MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: source,
            controller: scroll,
            showOutline: false,
            sourceNavigation: controller.sourceNavigation,
            initialViewportAnchor: initial,
            onViewportChanged: (value) => anchor = value,
            renderBudget: const IanvsMarkdownRenderBudget(
              maxSourceCodeUnits: 1,
              maxFallbackBytes: 2200,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      controller.revealSourceRange(TextRange.collapsed(source.length));
      await tester.pumpAndSettle();
      expect(scroll.offset, scroll.position.maxScrollExtent);
      expect(anchor, isNotNull);
      expect(anchor!.sourceOffset, lessThan(source.indexOf('Line 100')));
      final saved = anchor!;
      final pixels = scroll.offset;
      await tester.pumpWidget(const SizedBox.shrink());
      // A fresh controller has no pending navigation overriding restoration.
      final restoredScroll = ScrollController();
      addTearDown(restoredScroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IanvsMarkdownView(
              data: source,
              controller: restoredScroll,
              showOutline: false,
              initialViewportAnchor: saved,
              renderBudget: const IanvsMarkdownRenderBudget(
                maxSourceCodeUnits: 1,
                maxFallbackBytes: 2200,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(restoredScroll.offset, closeTo(pixels, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Read retains bare CR line positions through hidden comments', (
    tester,
  ) async {
    final source =
        '%%hidden\rcomment%%\r\r${List.generate(50, (i) => 'Before $i\r\r').join()}'
        'BARE CR TARGET\r\r${List.generate(25, (i) => 'After $i\r\r').join()}';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: source,
            sourceNavigation: controller.sourceNavigation,
            showOutline: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.revealSourceRange(
      TextRange.collapsed(source.indexOf('BARE CR TARGET')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('BARE CR TARGET', findRichText: true).hitTestable(),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final preset in IanvsMarkdownSyntaxPreset.values) {
    testWidgets(
      'Read maps $preset across metadata, references, comments and CRLF',
      (tester) async {
        final source = [
          '---',
          'title: demo',
          '---',
          '',
          '%% hidden',
          'comment %%',
          '',
          for (var i = 0; i < 50; i++) ...[
            'Paragraph $i [link][ref] ^[note $i]',
            '',
          ],
          '# Target',
          '',
          'UNIQUE TARGET TEXT',
          '',
          '| A | B |',
          '|---|---|',
          '| one | two | extra |',
          '',
          '[ref]: https://example.test',
          '',
          for (var i = 0; i < 25; i++) ...['After $i', ''],
        ].join('\r\n');
        final controller = IanvsMarkdownController(text: source);
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IanvsMarkdownView(
                data: source,
                syntaxPreset: preset,
                controller: scroll,
                sourceNavigation: controller.sourceNavigation,
                showOutline: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        controller.revealSourceRange(
          TextRange.collapsed(source.indexOf('UNIQUE TARGET TEXT')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('UNIQUE TARGET TEXT', findRichText: true).hitTestable(),
          findsOneWidget,
        );
        expect(controller.isDirty, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Read unfolds target ancestors while retaining earlier folds', (
    tester,
  ) async {
    final source =
        '# First\n\n${List.generate(30, (i) => 'Hidden $i\n\n').join()}'
        '# Middle\n\n${List.generate(30, (i) => 'Visible $i\n\n').join()}'
        '# Last\n\nTARGET IN FOLD\n\n${List.generate(25, (i) => 'After $i\n\n').join()}';
    final controller = IanvsMarkdownController(text: source);
    final folds = IanvsMarkdownHeadingFoldController();
    final model = IanvsMarkdownHeadingFoldModel.parse(source);
    final first = model.sections.first.identity;
    final last = model.sections.last.identity;
    folds.toggleIdentity(first);
    folds.toggleIdentity(last);
    addTearDown(controller.dispose);
    addTearDown(folds.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: source,
            sourceNavigation: controller.sourceNavigation,
            enableHeadingFolding: true,
            headingFoldController: folds,
            showOutline: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TARGET IN FOLD', findRichText: true), findsNothing);
    controller.revealSourceRange(
      TextRange.collapsed(source.indexOf('TARGET IN FOLD')),
    );
    await tester.pumpAndSettle();
    expect(folds.isCollapsed(first), isTrue);
    expect(folds.isCollapsed(last), isFalse);
    expect(
      find.text('TARGET IN FOLD', findRichText: true).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
