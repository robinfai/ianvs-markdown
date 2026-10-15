import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/code_surface.dart';
import 'package:ianvs_markdown/src/editor/editor_controller.dart'
    show ianvsMarkdownControllerReferences;

IanvsMarkdownSyntaxTheme _theme({Color color = Colors.red}) =>
    IanvsMarkdownSyntaxTheme(
      heading: TextStyle(color: color),
      marker: const TextStyle(color: Colors.grey),
      link: const TextStyle(color: Colors.blue),
      code: const TextStyle(color: Colors.green),
      comment: const TextStyle(color: Colors.grey),
    );

void main() {
  testWidgets(
    'save and host rebuild reuse source spans without stale styles or composing',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: '# Title\n\n[link][ref]\n\n[ref]: /one',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                controller.syntaxTheme = _theme();
                TextSpan span({
                  TextStyle style = const TextStyle(fontSize: 14),
                  bool composing = true,
                }) => controller.buildTextSpan(
                  context: context,
                  style: style,
                  withComposing: composing,
                );
                final initial = span();
                controller.markSaved();
                controller.syntaxTheme =
                    _theme(); // Equal styles, new theme instance.
                expect(identical(span(), initial), isTrue);
                var previous = initial;
                for (final next in [
                  controller.value.copyWith(
                    selection: const TextSelection.collapsed(offset: 2),
                  ),
                  controller.value.copyWith(
                    composing: const TextRange(start: 2, end: 4),
                  ),
                  const TextEditingValue(
                    text: '# Changed\n\n[link][ref]\n\n[ref]: /two',
                  ),
                ]) {
                  controller.value = next;
                  final updated = span();
                  expect(identical(updated, previous), isFalse);
                  expect(updated.toPlainText(), next.text);
                  expect(
                    updated,
                    buildMarkdownSourceTextSpan(
                      next,
                      style: const TextStyle(fontSize: 14),
                      syntaxTheme: controller.syntaxTheme!,
                      withComposing: true,
                    ),
                  );
                  previous = updated;
                }
                expect(identical(span(composing: false), previous), isFalse);
                controller.commitHistoryGroup();
                final beforeTheme = span();
                controller.syntaxTheme = _theme(color: Colors.purple);
                expect(span(), isNot(beforeTheme));
                final beforeSize = span();
                expect(
                  span(style: const TextStyle(fontSize: 18)),
                  isNot(beforeSize),
                );
                controller.syntaxTheme = null;
                expect(span().toPlainText(), controller.text);
                controller.syntaxTheme = _theme();
                expect(identical(span(), initial), isFalse);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    },
  );

  test(
    'reference snapshot tracks edits and undo; stricter controller budget declines reuse',
    () {
      final controller = IanvsMarkdownController(
        text: '[ref]: /old\n\n[link][ref]',
      );
      addTearDown(controller.dispose);
      final first = ianvsMarkdownControllerReferences(
        controller,
        controller.text,
      )!;
      expect(first.references['ref']!.destination, '/old');
      expect(
        ianvsMarkdownControllerReferences(controller, 'stale source'),
        isNull,
      );
      controller.text = '[ref]: /new\n\n[link][ref]';
      expect(
        ianvsMarkdownControllerReferences(
          controller,
          controller.text,
        )!.references['ref']!.destination,
        '/new',
      );
      expect(first.references['ref']!.destination, '/old');
      controller.undo();
      expect(
        ianvsMarkdownControllerReferences(
          controller,
          controller.text,
        )!.references['ref']!.destination,
        '/old',
      );
      final strict = IanvsMarkdownController(
        text: '[ref]: /old',
        parseBudget: const IanvsMarkdownRenderBudget(maxSourceCodeUnits: 1),
      );
      addTearDown(strict.dispose);
      expect(ianvsMarkdownControllerReferences(strict, strict.text), isNull);
    },
  );

  test(
    'cached vector dots match original pixels with clipping, scale and custom overlap',
    () async {
      for (final scale in [1.0, 1.25, 2.0]) {
        for (final dots in [1.0, 1.5, 3.0]) {
          for (final origin in [Offset.zero, const Offset(-3.5, 2.25)]) {
            Future<List<int>> render(bool batch) async {
              final recorder = ui.PictureRecorder();
              final canvas = Canvas(recorder)
                ..scale(scale)
                ..translate(origin.dx, origin.dy)
                ..clipRect(const Rect.fromLTWH(2.5, 1.5, 26, 23));
              const rect = Rect.fromLTWH(-2, -3, 38, 37);
              if (batch) {
                paintIanvsMarkdownCodePattern(
                  canvas,
                  rect,
                  color: const Color(0x7f123456),
                  dotSize: dots,
                );
              } else {
                final visible = rect.intersect(canvas.getLocalClipBounds());
                final path = Path();
                for (
                  var y = rect.top + ((visible.top - rect.top) / 4).floor() * 4;
                  y < visible.bottom;
                  y += 4
                ) {
                  for (
                    var x =
                        rect.left +
                        ((visible.left - rect.left) / 4).floor() * 4;
                    x < visible.right;
                    x += 4
                  ) {
                    path
                      ..addRect(
                        Rect.fromLTWH(x + dots, y + 4 - dots, dots, dots),
                      )
                      ..addRect(
                        Rect.fromLTWH(x + 4 - dots, y + dots, dots, dots),
                      );
                  }
                }
                canvas
                  ..save()
                  ..clipRect(visible)
                  ..drawPath(
                    path,
                    Paint()
                      ..color = const Color(0x7f123456)
                      ..isAntiAlias = false,
                  )
                  ..restore();
              }
              final picture = recorder.endRecording();
              final image = await picture.toImage(80, 80);
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List().toList();
              image.dispose();
              picture.dispose();
              return bytes;
            }

            expect(
              await render(true),
              await render(false),
              reason: '$scale / $dots / $origin',
            );
          }
        }
      }
    },
  );
}
