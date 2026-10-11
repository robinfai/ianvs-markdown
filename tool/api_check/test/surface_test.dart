import 'dart:convert';
import 'dart:io';

import 'package:ianvs_api_check/surface.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory fixture;
  late String entry;

  void write(String name, String source) {
    final file = File(p.join(fixture.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(source);
  }

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('ianvs-api-test-');
    entry = p.join(fixture.path, 'lib/ianvs_markdown.dart');
    write('pubspec.yaml', 'name: fixture\nenvironment:\n  sdk: ^3.12.0\n');
  });
  tearDown(() => fixture.deleteSync(recursive: true));

  test('resolved exports respect show/hide, reexports, and parts', () async {
    write(
      'lib/ianvs_markdown.dart',
      "export 'barrel.dart' show Public, fromPart;\n",
    );
    write('lib/barrel.dart', "export 'impl.dart' hide Hidden;\n");
    write(
      'lib/impl.dart',
      "part 'part.dart'; class Public {} class Hidden {} class _Private {}\n",
    );
    write('lib/part.dart', "part of 'impl.dart'; int fromPart() => 1;\n");
    final api = await readSurface(entry);
    expect((api['symbols'] as Map).keys, ['Public', 'fromPart']);
    expect(
      (api['declarations'] as Map).keys,
      contains('Public/constructor:new'),
    );
  });

  test(
    'private bodies, comments, and formatting do not change the API',
    () async {
      const original =
          'class Public { int f({int count = 1 + 2}) => _value(); int _value() => 3; }';
      write('lib/ianvs_markdown.dart', original);
      final before = await readSurface(entry);
      write(
        'lib/ianvs_markdown.dart',
        original
            .replaceAll('1 + 2', '1+2')
            .replaceAll('=> 3;', '=> 4;')
            .replaceAll('class Public', '/// New docs\nclass Public'),
      );
      expect(compareSurface(before, await readSurface(entry)), isEmpty);
    },
  );

  test('named parameters, nullable types, and defaults produce drift', () async {
    write(
      'lib/ianvs_markdown.dart',
      'class Public { const Public({String? label, int count = 2}); }',
    );
    final before = await readSurface(entry);
    write(
      'lib/ianvs_markdown.dart',
      'class Public { const Public({required String title, int count = 3}); }',
    );
    expect(
      compareSurface(before, await readSurface(entry)),
      contains('Changed declarations: Public/constructor:new'),
    );
  });

  test('constant values, public setters and enum order are observable', () async {
    write(
      'lib/ianvs_markdown.dart',
      'const limit = 2; enum Mode { first, second } class Public { int value = 0; static const maximum = 4; }',
    );
    final before = await readSurface(entry);
    write(
      'lib/ianvs_markdown.dart',
      'const limit = 3; enum Mode { second, first } class Public { final int value = 0; static const maximum = 5; }',
    );
    final diff = compareSurface(before, await readSurface(entry));
    expect(
      diff,
      containsAll([
        'Changed declarations: limit',
        'Changed declarations: Mode',
        'Changed declarations: Public/field:value',
        'Changed declarations: Public/field:maximum',
      ]),
    );
  });

  test('adding and hiding a public declaration both require review', () async {
    write('lib/ianvs_markdown.dart', 'class Original {}');
    final before = await readSurface(entry);
    write('lib/ianvs_markdown.dart', 'class Replacement {}');
    final diff = compareSurface(before, await readSurface(entry));
    expect(
      diff,
      containsAll(['Removed symbols: Original', 'Added symbols: Replacement']),
    );
  });

  test('invalid exported library is rejected instead of baselined', () async {
    write('lib/ianvs_markdown.dart', "export 'broken.dart';");
    write('lib/broken.dart', 'MissingType broken() => throw 0;');
    await expectLater(readSurface(entry), throwsStateError);
  });

  test('ambiguous export is rejected', () async {
    write('lib/ianvs_markdown.dart', "export 'a.dart'; export 'b.dart';");
    write('lib/a.dart', 'class Collision {}');
    write('lib/b.dart', 'class Collision {}');
    await expectLater(readSurface(entry), throwsStateError);
  });

  test(
    'check exits nonzero on drift and never overwrites the baseline',
    () async {
      write('lib/ianvs_markdown.dart', 'class Public {}');
      write(
        'tool/api_check/api_baseline.json',
        encodeSurface(await readSurface(entry)),
      );
      final baseline = File(
        p.join(fixture.path, 'tool/api_check/api_baseline.json'),
      );
      final original = baseline.readAsStringSync();
      write('lib/ianvs_markdown.dart', 'class Public { void added() {} }');
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/check.dart',
        '--check',
        fixture.path,
      ]);
      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stderr,
        contains('Added declarations: Public/method:added'),
      );
      expect(baseline.readAsStringSync(), original);
      expect(jsonDecode(original)['schemaVersion'], 1);
    },
  );
}
