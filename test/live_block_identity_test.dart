import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  testWidgets(
    'inserting before an unchanged block retains its element and semantics',
    (tester) async {
      final handle = tester.ensureSemantics();

      final controller = IanvsMarkdownController(
        text: '# Heading\n\nUntouched paragraph.\n\nLast paragraph.',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: IanvsMarkdownLiveEditor(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final untouched = find.byWidgetPredicate(
        (w) => w is IanvsMarkdown && w.data == 'Untouched paragraph.',
      );
      final element = tester.element(untouched);
      final semanticsId = tester.getSemantics(untouched).id;
      controller.value = TextEditingValue(
        text: '# Heading edited\n\nUntouched paragraph.\n\nLast paragraph.',
        selection: const TextSelection.collapsed(offset: 3),
      );
      await tester.pumpAndSettle();
      expect(
        identical(tester.element(untouched), element),
        isTrue,
        reason: 'An offset shift is not a new Markdown block',
      );
      expect(tester.getSemantics(untouched).id, semanticsId);
      expect(controller.text.endsWith('Last paragraph.'), isTrue);
      expect(tester.takeException(), isNull);
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'unchanged duplicate blocks survive insertion, removal and undo',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: 'First\n\nSame\n\nSame\n\nLast',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: IanvsMarkdownLiveEditor(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final duplicates = find.byWidgetPredicate(
        (w) => w is IanvsMarkdown && w.data == 'Same',
      );
      final original = tester.elementList(duplicates).toList();
      final inserted = 'Inserted\n\n${controller.text}';
      controller.value = TextEditingValue(
        text: inserted,
        selection: const TextSelection.collapsed(offset: 0),
      );
      controller.commitHistoryGroup();
      await tester.pumpAndSettle();
      expect(tester.elementList(duplicates).toList(), original);
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, 'First\n\nSame\n\nSame\n\nLast');
      expect(tester.elementList(duplicates).toList(), original);
      controller.value = TextEditingValue(
        text: 'First\n\nSame\n\nLast',
        selection: const TextSelection.collapsed(offset: 0),
      );
      await tester.pumpAndSettle();
      expect(duplicates, findsOneWidget);
      expect(tester.element(duplicates), original.first);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('replacing the document does not retain the old block subtree', (
    tester,
  ) async {
    final a = IanvsMarkdownController(text: 'Same');
    final b = IanvsMarkdownController(text: 'Same');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    Widget host(IanvsMarkdownController controller) => MaterialApp(
      home: Scaffold(body: IanvsMarkdownLiveEditor(controller: controller)),
    );
    final block = find.byWidgetPredicate(
      (w) => w is IanvsMarkdown && w.data == 'Same',
    );
    await tester.pumpWidget(host(a));
    await tester.pumpAndSettle();
    final old = tester.element(block);
    await tester.pumpWidget(host(b));
    await tester.pumpAndSettle();
    expect(identical(tester.element(block), old), isFalse);
    expect(old.mounted, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
