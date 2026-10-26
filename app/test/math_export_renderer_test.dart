import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/math_export_renderer.dart';
import 'package:linefold/src/services/document_export_service.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';

void main() {
  testWidgets(
    'formula export paints a bounded PNG without mounting an editor',
    (tester) async {
      await tester.runAsync(() async {
        final fonts =
            jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List;
        for (final entry in fonts) {
          final family = entry['family'] as String;
          if (!family.startsWith('packages/flutter_math_fork/')) continue;
          final loader = FontLoader(family);
          for (final font in entry['fonts'] as List) {
            loader.addFont(rootBundle.load(font['asset'] as String));
          }
          await loader.load();
        }
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final display in [false, true]) {
          final result = await renderExportMath(
            r'\frac{x^2 + 1}{\sqrt{y}}',
            display,
          );
          expect(result.width, greaterThan(8));
          expect(result.height, greaterThan(8));
          if (display) {
            final file = File('build/export-qa/math-rendered.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(result.png);
          }
          final codec = await ui.instantiateImageCodec(result.png);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, closeTo(result.width * 2, 1));
          final pixels = await frame.image.toByteData();
          expect(
            pixels!.buffer.asUint8List().any((value) => value != 0),
            isTrue,
          );
          frame.image.dispose();
          codec.dispose();
        }
        if (Platform.isMacOS) {
          final config = File('.dart_tool/package_config.json');
          final packages =
              (jsonDecode(await config.readAsString()) as Map)['packages']
                  as List;
          final merman = packages.cast<Map>().singleWhere(
            (p) => p['name'] == 'merman',
          );
          final root = config.uri
              .resolve(merman['rootUri'] as String)
              .toFilePath();
          final renderer = NativeMermanRenderer(
            libraryPath: '$root/macos/Libraries/libmerman_ffi.dylib',
          );
          try {
            final dimensions = <Map<String, int>>[];
            final output =
                await DocumentExportService(
                  renderMath: (source, display) async {
                    final result = await renderExportMath(source, display);
                    final codec = await ui.instantiateImageCodec(result.png);
                    final image = (await codec.getNextFrame()).image;
                    dimensions.add({
                      'width': image.width,
                      'height': image.height,
                    });
                    image.dispose();
                    codec.dispose();
                    return result;
                  },
                  renderMermaid: (source) async =>
                      (await renderer.render(source)).svg,
                ).build(
                  const DocumentExportSnapshot(
                    documentId: 'rendered',
                    title: 'Rendered export',
                    source:
                        r'Inline $x^2$ FORMULA_INLINE'
                        '\n\n'
                        r'$$\frac{x^2+1}{\sqrt{y}}$$'
                        '\n\nFORMULA_DISPLAY\n\n'
                        '```mermaid\nflowchart LR\nA[Export] --> B[Complete]\n'
                        '```\n\nDIAGRAM_END',
                  ),
                  isCurrent: () => true,
                  forPdf: true,
                );
            expect(output.content, contains('data:image/svg+xml;base64,'));
            expect(
              'data:image/png;base64,'.allMatches(output.content).length,
              2,
            );
            expect(
              output.notices.any(
                (value) =>
                    value.startsWith('Math:') || value.startsWith('Mermaid:'),
              ),
              isFalse,
            );
            await File(
              'build/export-qa/rendered.html',
            ).writeAsString(output.content);
            await File(
              'build/export-qa/rendered-math.json',
            ).writeAsString(jsonEncode(dimensions));
          } finally {
            renderer.dispose();
          }
        }
        await expectLater(
          renderExportMath(r'\notAValidCommand{x}', true),
          throwsFormatException,
        );
        await expectLater(
          renderExportMath('x' * 8193, true),
          throwsFormatException,
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
}
