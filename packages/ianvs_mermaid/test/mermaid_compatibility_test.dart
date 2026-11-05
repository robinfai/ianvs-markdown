import 'dart:convert';
import 'dart:io';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Native Assets renders unquoted ER names and Unicode node IDs', () async {
    final renderer = NativePeleRenderer();
    addTearDown(renderer.dispose);
    for (final source in [
      'erDiagram\nUser ||--o{ Token : owns\nUser {\nstring username PK\n}\nToken {\nuint id PK\n}',
      'flowchart TD\nMetrics -.-> 蓝鲸监控\nTracing -.-> 蓝鲸监控',
    ]) {
      expect((await renderer.validate(source)).valid, isTrue);
      final result = await renderer.render(source, includeLayout: true);
      expect(result.engineVersion, NativePeleRenderer.engineVersion);
      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
      expect(jsonDecode(result.layoutJson!), isA<Map>());
      final picture = await vg.loadPicture(SvgStringLoader(result.svg), null);
      picture.picture.dispose();
    }
    // Do not turn malformed input into a success by guessing line breaks.
    expect(
      (await renderer.validate(
        'sequenceDiagram\nautonumber participant A',
      )).valid,
      isFalse,
    );
  });

  const localDocument = String.fromEnvironment('MERMAN_DOCUMENT');
  if (localDocument.isNotEmpty) {
    test('local document diagrams through production SVG pipeline', () async {
      final renderer = NativePeleRenderer();
      addTearDown(renderer.dispose);
      final source = File(localDocument).readAsStringSync();
      final fences = RegExp(
        r'^```mermaid[^\n]*\n(.*?)^```[^\n]*$',
        multiLine: true,
        dotAll: true,
      ).allMatches(source);
      var count = 0;
      for (final fence in fences) {
        final line =
            '\n'.allMatches(source.substring(0, fence.start)).length + 1;
        final timing = Stopwatch()..start();
        final result = await renderer.render(fence.group(1)!);
        final renderMs = timing.elapsedMicroseconds / 1000;
        final picture = await vg.loadPicture(SvgStringLoader(result.svg), null);
        final totalMs = timing.elapsedMicroseconds / 1000;
        picture.picture.dispose();
        expect(result.width, greaterThan(0), reason: 'Document line $line');
        count++;
        // Includes first-worker startup; excludes screen raster/presentation.
        // ignore: avoid_print
        print(
          'Diagram $count line $line: render=${renderMs.toStringAsFixed(2)}ms '
          'picture=${(totalMs - renderMs).toStringAsFixed(2)}ms '
          'total=${totalMs.toStringAsFixed(2)}ms cache=${result.fromCache}',
        );
      }
      expect(count, greaterThan(0));
      // ignore: avoid_print
      print('Validated $count local diagrams with Pele 1.13.0');
    });
  }
}
