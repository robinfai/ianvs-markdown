import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/widgets/middle_ellipsis_text.dart';

void main() {
  const path =
      'flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/fixtures';

  testWidgets('resizing retains both path ends on one line', (tester) async {
    tester.view.physicalSize = const Size(1400, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLabel(tester, path, width: 220);
    final narrow = _displayedText(tester).data!;
    _expectMiddleEllipsis(path, narrow);
    expect(_displayedText(tester).maxLines, 1);
    expect(_displayedText(tester).softWrap, isFalse);
    expect(_displayedText(tester).semanticsLabel, path);
    expect(tester.getSize(find.byType(MiddleEllipsisText)).height, 14);

    await _pumpLabel(tester, path, width: 400);
    final wider = _displayedText(tester).data!;
    _expectMiddleEllipsis(path, wider);
    expect(wider.length, greaterThan(narrow.length));
    final paragraph = _paragraph(tester);
    expect(paragraph.didExceedMaxLines, isFalse);

    await _pumpLabel(tester, path, width: 1200);
    expect(find.text(path), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('middle ellipsis preserves Unicode graphemes and text scaling', (
    tester,
  ) async {
    const unicodePath =
        '👩🏽‍💻/研究资料/e\u0301criture/long directory/家庭👨‍👩‍👧‍👦';
    await _pumpLabel(tester, unicodePath, width: 280);
    final originalScale = _displayedText(tester).data!;
    _expectMiddleEllipsis(unicodePath, originalScale);
    await _pumpLabel(tester, unicodePath, width: 280, scale: 1.8);
    final scaled = _displayedText(tester).data!;
    _expectMiddleEllipsis(unicodePath, scaled);
    expect(scaled.characters.length, lessThan(originalScale.characters.length));
    expect(_paragraph(tester).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('very narrow paths clip without wrapping or overflowing', (
    tester,
  ) async {
    await _pumpLabel(tester, path, width: 12);
    expect(_displayedText(tester).data, '...');
    expect(tester.getSize(find.byType(MiddleEllipsisText)).height, 14);
    expect(tester.takeException(), isNull);
  });
}

void _expectMiddleEllipsis(String original, String displayed) {
  final pieces = displayed.split('...');
  expect(pieces, hasLength(2));
  expect(pieces.first, isNotEmpty);
  expect(pieces.last, isNotEmpty);
  final graphemes = original.characters.toList();
  expect(graphemes.take(pieces.first.characters.length).join(), pieces.first);
  expect(
    graphemes.skip(graphemes.length - pieces.last.characters.length).join(),
    pieces.last,
  );
}

Text _displayedText(WidgetTester tester) => tester.widget<Text>(
  find.descendant(
    of: find.byType(MiddleEllipsisText),
    matching: find.byType(Text),
  ),
);

RenderParagraph _paragraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(MiddleEllipsisText),
        matching: find.byType(RichText),
      ),
    );

Future<void> _pumpLabel(
  WidgetTester tester,
  String text, {
  required double width,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: MiddleEllipsisText(
              text,
              style: const TextStyle(fontSize: 14, height: 1),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
