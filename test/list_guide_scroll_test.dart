import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/list_guide.dart';

void main() {
  testWidgets(
    'live list guides repaint with every scroll frame and stay clipped',
    (tester) async {
      final controller = IanvsMarkdownController(
        text: List.generate(
          30,
          (index) => '- Parent $index\n  - Child $index\n    - Deep $index\n',
        ).join('\n'),
      );
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);
      const captureKey = ValueKey('capture');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: captureKey,
              child: Material(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: SizedBox(
                    width: 320,
                    height: 240,
                    child: IanvsMarkdownLiveEditor(
                      controller: controller,
                      scrollController: scrollController,
                      showToolbar: false,
                      showNavigationPane: false,
                      theme: IanvsMarkdownThemeData.light.copyWith(
                        listGuideColor: const Color(0xffff00ff),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final surface = tester
          .renderObject<IanvsMarkdownSliverListGuideRenderObject>(
            find.byKey(const ValueKey('ianvs-markdown-live-list-guides')),
          );

      Future<void> expectPaintMatchesMarkers() async {
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        addTearDown(image.dispose);
        final data = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        final pixels = data.buffer.asUint8List();
        final origin = MatrixUtils.transformPoint(
          surface.getTransformTo(boundary),
          Offset.zero,
        );
        final segments = surface.debugGuideSegments();
        expect(segments, isNotEmpty);
        var checkedPixels = 0;
        for (final level in <int>[0, 1]) {
          final guides = segments.where((segment) => segment.level == level);
          final x = (origin.dx + guides.first.start.dx).floor();
          for (var y = 0; y < image.height; y += 1) {
            final localY = y + .5 - origin.dy;
            final inside =
                localY >= 0 && localY < surface.geometry!.paintExtent;
            // Ignore antialiasing at the ends of guide segments.
            if (guides.any(
              (segment) =>
                  (localY - segment.start.dy).abs() < 2 ||
                  (localY - segment.end.dy).abs() < 2,
            )) {
              continue;
            }
            final expected =
                inside &&
                guides.any(
                  (segment) =>
                      localY > segment.start.dy && localY < segment.end.dy,
                );
            final pixel = (y * image.width + x) * 4;
            final painted =
                pixels[pixel] > 240 &&
                pixels[pixel + 1] < 200 &&
                pixels[pixel + 2] > 240;
            expect(
              painted,
              expected,
              reason:
                  'scroll=${scrollController.offset}, level=$level, y=$localY',
            );
            checkedPixels += 1;
          }
        }
        expect(checkedPixels, greaterThan(100));
      }

      await expectPaintMatchesMarkers();
      for (final offset in <double>[9, 21, 47, 105, 350, 810, 795, 340, 0]) {
        scrollController.jumpTo(offset);
        await tester.pump();
        await expectPaintMatchesMarkers();
      }
      // A focused list item can remain alive after scrolling out of view.
      await tester.tap(find.text('Child 0'));
      await tester.pumpAndSettle();
      await expectPaintMatchesMarkers();
      final animation = scrollController.animateTo(
        900,
        duration: const Duration(milliseconds: 160),
        curve: Curves.linear,
      );
      await tester.pump();
      for (var frame = 0; frame < 12; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
        await expectPaintMatchesMarkers();
      }
      await animation;
      expect(tester.takeException(), isNull);
    },
  );
}
