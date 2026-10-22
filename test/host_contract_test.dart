import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Future<void> requestSave(WidgetTester tester, {required bool toolbar}) async {
  if (toolbar) {
    await tester.tap(find.byTooltip('保存'));
  } else {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  }
  await tester.pump();
}

Widget editorHost(
  IanvsMarkdownController controller,
  IanvsMarkdownSaveCallback save,
) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: IanvsMarkdownLiveEditor(
      controller: controller,
      autofocus: true,
      onSaveRequested: save,
    ),
  ),
);

void main() {
  test('late save acknowledgment is harmless after controller disposal', () {
    final controller = IanvsMarkdownController(text: 'initial');
    controller.text = 'persisted';
    final captured = controller.text;
    controller.dispose();
    expect(() => controller.markSaved(savedText: captured), returnsNormally);
  });

  for (final toolbar in [true, false]) {
    final path = toolbar ? 'toolbar' : 'keyboard';
    testWidgets(
      '$path save preserves edits made while persistence is pending',
      (tester) async {
        final controller = IanvsMarkdownController(
          text: '# Initial',
          mode: IanvsMarkdownEditorMode.source,
        );
        addTearDown(controller.dispose);
        controller.text = '# Captured';
        final gate = Completer<void>();
        String? persisted;
        await tester.pumpWidget(
          editorHost(controller, (source) {
            persisted = source;
            return gate.future;
          }),
        );
        await tester.pumpAndSettle();
        await requestSave(tester, toolbar: toolbar);
        expect(persisted, '# Captured');
        controller.text = '# Newer edit';
        gate.complete();
        await tester.pump();
        expect(controller.isDirty, isTrue);
        expect(controller.text, '# Newer edit');
        controller.undo();
        await tester.pump();
        expect(controller.text, '# Captured');
        expect(controller.isDirty, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$path save may complete after the document has been closed', (
      tester,
    ) async {
      final controller = IanvsMarkdownController(
        text: '# Initial',
        mode: IanvsMarkdownEditorMode.source,
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) controller.dispose();
      });
      controller.text = '# Persisted';
      final gate = Completer<void>();
      await tester.pumpWidget(editorHost(controller, (_) => gate.future));
      await tester.pumpAndSettle();
      await requestSave(tester, toolbar: toolbar);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      disposed = true;
      gate.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  for (final live in [false, true]) {
    testWidgets(
      '${live ? 'Live' : 'Source'} replaces borrowed objects without disposing them',
      (tester) async {
        final first = IanvsMarkdownController(
          text: 'first',
          mode: IanvsMarkdownEditorMode.source,
        );
        final second = IanvsMarkdownController(
          text: 'second',
          mode: IanvsMarkdownEditorMode.source,
        );
        final focusA = _TrackedFocusNode();
        final focusB = _TrackedFocusNode();
        final scrollA = _TrackedScrollController();
        final scrollB = _TrackedScrollController();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        addTearDown(focusA.dispose);
        addTearDown(focusB.dispose);
        addTearDown(scrollA.dispose);
        addTearDown(scrollB.dispose);
        final changes = <String>[];
        Widget host(
          IanvsMarkdownController controller,
          FocusNode focus,
          ScrollController scroll,
        ) => MaterialApp(
          home: Scaffold(
            body: live
                ? IanvsMarkdownLiveEditor(
                    controller: controller,
                    focusNode: focus,
                    scrollController: scroll,
                    showToolbar: false,
                    onChanged: changes.add,
                  )
                : IanvsMarkdownEditor(
                    controller: controller,
                    focusNode: focus,
                    scrollController: scroll,
                    showToolbar: false,
                    onChanged: changes.add,
                  ),
          ),
        );
        await tester.pumpWidget(host(first, focusA, scrollA));
        await tester.pumpAndSettle();
        await tester.pumpWidget(host(second, focusB, scrollB));
        await tester.pumpAndSettle();
        first.text = 'detached change';
        first.commitHistoryGroup();
        second.text = 'current change';
        second.commitHistoryGroup();
        await tester.pump();
        expect(changes, ['current change']);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller,
          same(second),
        );
        expect(scrollA.hasClients, isFalse);
        expect(scrollB.hasClients, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        expect([
          focusA.disposals,
          focusB.disposals,
          scrollA.disposals,
          scrollB.disposals,
        ], everyElement(0));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'View source updates reset scroll and borrowed controllers remain host-owned',
    (tester) async {
      final scrollA = _TrackedScrollController();
      final scrollB = _TrackedScrollController();
      addTearDown(scrollA.dispose);
      addTearDown(scrollB.dispose);
      final source = List.generate(
        40,
        (index) => '# Heading $index\n\nParagraph $index',
      ).join('\n\n');
      Widget host(String data, ScrollController scroll) => MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: data,
            controller: scroll,
            showOutline: false,
          ),
        ),
      );
      await tester.pumpWidget(host(source, scrollA));
      await tester.pumpAndSettle();
      scrollA.jumpTo(200);
      await tester.pump();
      expect(scrollA.offset, 200);
      await tester.pumpWidget(host('$source\n\nAppended', scrollA));
      await tester.pumpAndSettle();
      expect(scrollA.offset, 0);
      await tester.pumpWidget(host(source, scrollB));
      await tester.pumpAndSettle();
      expect(scrollA.hasClients, isFalse);
      expect(scrollB.hasClients, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect([scrollA.disposals, scrollB.disposals], everyElement(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'View preserves current position only when opted in and clamps shorter source',
    (tester) async {
      final scroll = _TrackedScrollController();
      addTearDown(scroll.dispose);
      final source = List.generate(
        60,
        (i) => '# Section $i\n\nParagraph $i.',
      ).join('\n\n');
      Widget host(String data) => MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: data,
            controller: scroll,
            preserveScrollOnUpdate: true,
            showOutline: false,
          ),
        ),
      );
      await tester.pumpWidget(host(source));
      await tester.pumpAndSettle();
      scroll.jumpTo(1200);
      await tester.pump();
      await tester.pumpWidget(host('$source\n\nAppended text.'));
      await tester.pumpAndSettle();
      expect(scroll.offset, 1200);
      await tester.pumpWidget(host('# Short\n\nOnly this.'));
      await tester.pumpAndSettle();
      expect(scroll.offset, scroll.position.maxScrollExtent);
      expect(scroll.offset, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(scroll.disposals, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preserving View scroll retains existing matching heading folds',
    (tester) async {
      const source =
          '# Folded\n\nHidden paragraph.\n\n# Visible\n\nVisible paragraph.';
      final folds = IanvsMarkdownHeadingFoldController();
      addTearDown(folds.dispose);
      final folded = IanvsMarkdownHeadingFoldModel.parse(
        source,
      ).sections.first.identity;
      folds.toggleIdentity(folded);
      Widget host(String data) => MaterialApp(
        home: Scaffold(
          body: IanvsMarkdownView(
            data: data,
            preserveScrollOnUpdate: true,
            headingFoldController: folds,
            enableHeadingFolding: true,
            showOutline: false,
          ),
        ),
      );
      await tester.pumpWidget(host(source));
      await tester.pumpAndSettle();
      expect(folds.isCollapsed(folded), isTrue);
      expect(find.text('Hidden paragraph.', findRichText: true), findsNothing);
      await tester.pumpWidget(
        host('Intro inserted before headings.\n\n$source\n\nAppended text.'),
      );
      await tester.pumpAndSettle();
      expect(folds.isCollapsed(folded), isTrue);
      expect(find.text('Hidden paragraph.', findRichText: true), findsNothing);
      await tester.pumpWidget(host('# Visible\n\nVisible paragraph.'));
      await tester.pumpAndSettle();
      expect(folds.isCollapsed(folded), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _TrackedFocusNode extends FocusNode {
  int disposals = 0;
  @override
  void dispose() {
    disposals += 1;
    super.dispose();
  }
}

class _TrackedScrollController extends ScrollController {
  int disposals = 0;
  @override
  void dispose() {
    disposals += 1;
    super.dispose();
  }
}
