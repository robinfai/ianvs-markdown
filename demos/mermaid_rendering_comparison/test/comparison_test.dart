import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_rendering_comparison/main.dart';

void main() {
  final cases =
      (jsonDecode(File('assets/cases.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();

  testWidgets('capture actual Flutter pictures and rendering stage timings', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final font = FontLoader('Hiragino Sans GB')
        ..addFont(
          File(
            '/System/Library/Fonts/Hiragino Sans GB.ttc',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await font.load();
      final records = <Map<String, dynamic>>[];
      Directory('results').createSync(recursive: true);
      for (final item in cases) {
        final id = item['id'] as String;
        final rust = item['rust'] as Map<String, dynamic>;
        final width = rust['width'] as int;
        final height = rust['height'] as int;
        for (final variant in ['input', 'vector']) {
          final source = File('assets/$id/$variant.svg').readAsStringSync();
          final compileTimes = <double>[];
          PictureInfo? info;
          for (var i = 0; i < 6; i++) {
            info?.picture.dispose();
            svg.cache.clear();
            final watch = Stopwatch()..start();
            info = await vg.loadPicture(SvgStringLoader(source), null);
            compileTimes.add(watch.elapsedMicroseconds / 1000);
          }
          final warm = compileTimes.skip(1).toList()..sort();
          final record = <String, dynamic>{
            'id': id,
            'variant': variant,
            'flutter_compile_median_ms_debug': warm[warm.length ~/ 2],
          };
          for (final ratio in [1, 2, 4]) {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)
              ..drawColor(Colors.white, BlendMode.src);
            canvas.scale(width * ratio / info!.size.width);
            canvas.drawPicture(info.picture);
            final picture = recorder.endRecording();
            final watch = Stopwatch()..start();
            final image = await picture.toImage(width * ratio, height * ratio);
            record['flutter_to_image_${ratio}x_ms_debug'] =
                watch.elapsedMicroseconds / 1000;
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File(
              'results/$id-$variant-${ratio}x.png',
            ).writeAsBytesSync(data!.buffer.asUint8List());
            if (variant == 'vector' && ratio == 2) {
              final codec = await ui.instantiateImageCodec(
                File('assets/$id/raster-2x.png').readAsBytesSync(),
              );
              final reference = (await codec.getNextFrame()).image;
              final a = (await image.toByteData())!.buffer.asUint8List();
              final b = (await reference.toByteData())!.buffer.asUint8List();
              expect(a.length, b.length);
              var error = 0;
              var changed = 0;
              for (var p = 0; p < a.length; p += 4) {
                var pixelError = 0;
                for (var c = 0; c < 3; c++) {
                  pixelError += (a[p + c] - b[p + c]).abs();
                }
                error += pixelError;
                if (pixelError > 60) changed++;
              }
              record['rgb_mean_absolute_error_2x'] = error / (a.length / 4 * 3);
              record['pixels_with_mean_rgb_error_gt20_pct_2x'] =
                  changed / (a.length / 4) * 100;
              reference.dispose();
              codec.dispose();
            }
            image.dispose();
            picture.dispose();
          }
          info!.picture.dispose();
          records.add(record);
        }
      }
      File(
        'results/flutter-metrics.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));
    });
  });

  for (final vector in [true, false]) {
    testWidgets(
      '${vector ? 'vector' : 'raster'} passes wheel and trackpad input to document',
      (tester) async {
        final scroll = ScrollController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    DiagramSurface(
                      id: 'flow',
                      vector: vector,
                      aspect: 640 / 152,
                    ),
                    const SizedBox(
                      height: 2400,
                      child: Text('Document continues'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        final position = tester.getCenter(find.byType(DiagramSurface));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: position,
            scrollDelta: const Offset(0, 80),
          ),
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        scroll.jumpTo(0);
        await tester.pump();
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await gesture.panZoomStart(position);
        await gesture.panZoomUpdate(position, pan: const Offset(0, -80));
        await gesture.panZoomUpdate(position, pan: const Offset(0, -160));
        await gesture.panZoomEnd();
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        scroll.dispose();
      },
    );
  }

  testWidgets(
    'comparison controls load and switch cases without layout errors',
    (tester) async {
      tester.view.physicalSize = const Size(1360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ComparisonApp(cases: cases));
      await tester.pumpAndSettle();
      expect(find.text('A · Flutter 矢量'), findsOneWidget);
      expect(find.text('B · Rust 位图'), findsOneWidget);
      await tester.tap(find.text('未经 usvg 处理的基线'));
      await tester.pumpAndSettle();
      expect(find.text('基线 · 直接 flutter_svg'), findsOneWidget);
      await tester.tap(find.text('长文滚动测试'));
      await tester.pumpAndSettle();
      expect(find.textContaining('阅读测试：'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
