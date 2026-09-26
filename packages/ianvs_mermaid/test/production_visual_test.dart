import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';

import 'native_renderer_test.dart' show nativeMermanPath;

void main() {
  testWidgets(
    'live production FFI matches the seven vector reference pictures',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = NativeMermanRenderer(
          libraryPath: await nativeMermanPath(),
        );
        final root = Directory('../../demos/mermaid_rendering_comparison');
        final cases =
            (jsonDecode(
                      File('${root.path}/assets/cases.json').readAsStringSync(),
                    )
                    as List)
                .cast<Map>();
        final output = Directory('build/visual-regression')
          ..createSync(recursive: true);
        final metrics = <Map<String, Object>>[];
        try {
          for (final item in cases) {
            final id = item['id'] as String;
            final result = await renderer.render(
              item['source'] as String,
              options: const MermaidRenderOptions(
                fontFamily: 'Hiragino Sans GB',
              ),
            );
            final codec = await ui.instantiateImageCodec(
              File('${root.path}/results/$id-vector-2x.png').readAsBytesSync(),
            );
            final reference = (await codec.getNextFrame()).image;
            final info = await vg.loadPicture(
              SvgStringLoader(result.svg),
              null,
            );
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)
              ..drawColor(Colors.white, BlendMode.src);
            canvas.scale(reference.width / info.size.width);
            canvas.drawPicture(info.picture);
            final picture = recorder.endRecording();
            final actual = await picture.toImage(
              reference.width,
              reference.height,
            );
            final png = await actual.toByteData(format: ui.ImageByteFormat.png);
            File(
              '${output.path}/$id.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
            final a = (await actual.toByteData())!.buffer.asUint8List();
            final b = (await reference.toByteData())!.buffer.asUint8List();
            var total = 0;
            var changed = 0;
            for (var p = 0; p < a.length; p += 4) {
              var delta = 0;
              for (var c = 0; c < 3; c++) {
                delta += (a[p + c] - b[p + c]).abs();
              }
              total += delta;
              if (delta > 60) changed++;
            }
            final error = total / (a.length / 4 * 3);
            final changedPercent = changed * 100 / (a.length / 4);
            metrics.add({
              'id': id,
              'meanRgbError': error,
              'changedPixelPercent': changedPercent,
            });
            expect(
              error,
              lessThan(1),
              reason: '$id: compare build/visual-regression/$id.png',
            );
            expect(changedPercent, lessThan(1), reason: id);
            actual.dispose();
            reference.dispose();
            codec.dispose();
            picture.dispose();
            info.picture.dispose();
          }
          File('${output.path}/metrics.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(metrics),
          );
        } finally {
          renderer.dispose();
        }
      });
    },
  );
}
