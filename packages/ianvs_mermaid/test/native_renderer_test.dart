import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';
import 'package:ianvs_mermaid/src/native_svg_bridge.dart';

Future<String> nativeMermanPath() async {
  final config = File('.dart_tool/package_config.json');
  final packages =
      (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
  final merman = packages.cast<Map>().singleWhere((p) => p['name'] == 'merman');
  final root = config.uri.resolve(merman['rootUri'] as String).toFilePath();
  if (Platform.isMacOS) return '$root/macos/Libraries/libmerman_ffi.dylib';
  throw UnsupportedError('Native integration fixtures currently run on macOS');
}

void main() {
  test(
    'standalone SVG preview expands text and markers off the UI isolate',
    () async {
      final result = await renderSvg(
        '''<svg xmlns="http://www.w3.org/2000/svg" width="300" height="100">
      <defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="5" refY="5"><path d="M0 0L10 5L0 10Z"/></marker></defs>
      <text x="10" y="30">中文 English</text><path d="M10 50H200" stroke="black" marker-end="url(#arrow)"/>
      </svg>''',
      );
      expect(result.width, 300);
      expect(result.height, 100);
      expect(result.svg, contains('<path'));
      expect(result.svg, isNot(contains('<text')));
      expect(result.svg, isNot(contains('<marker')));
      await expectLater(
        renderSvg('<svg><foreignObject/></svg>'),
        throwsA(isA<MermaidRenderFailure>()),
      );
    },
  );

  test(
    'production FFI expands all seven demo sources and caches results',
    () async {
      final renderer = NativeMermanRenderer(
        libraryPath: await nativeMermanPath(),
      );
      addTearDown(renderer.dispose);
      final cases =
          jsonDecode(
                File(
                  '../../demos/mermaid_rendering_comparison/assets/cases.json',
                ).readAsStringSync(),
              )
              as List;
      for (final item in cases.cast<Map>()) {
        final source = item['source'] as String;
        final result = await renderer.render(
          source,
          options: const MermaidRenderOptions(fontFamily: 'Hiragino Sans GB'),
        );
        expect(result.svg, contains('<path'), reason: item['id'] as String);
        expect(result.svg, isNot(contains('<text')));
        expect(result.svg, isNot(contains('<marker')));
        expect(result.width, greaterThan(0));
        expect(result.height, greaterThan(0));
        expect(result.preprocessingIdentity, contains('usvg/0.45.1'));
        final cached = await renderer.render(
          source,
          options: const MermaidRenderOptions(fontFamily: 'Hiragino Sans GB'),
        );
        expect(cached.svg, result.svg);
        expect(cached.fromCache, isTrue);
      }
    },
  );

  test('native rendering leaves the caller event loop responsive', () async {
    final renderer = NativeMermanRenderer(
      libraryPath: await nativeMermanPath(),
    );
    addTearDown(renderer.dispose);
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    addTearDown(timer.cancel);
    final source = File(
      '../../demos/mermaid_rendering_comparison/assets/dense/source.mmd',
    ).readAsStringSync();
    final first = renderer.render(source);
    final duplicate = renderer.render(source);
    expect(identical(first, duplicate), isTrue);
    await first;
    expect(ticks, greaterThan(5));
    final themed = await renderer.render(
      source,
      options: const MermaidRenderOptions(theme: 'dark'),
    );
    expect(themed.fromCache, isFalse);
    final validation = await renderer.validate('flowchart LR\nA-->B');
    expect(validation.valid, isTrue);
    expect(validation.raw, isNotNull);
    expect(await renderer.layoutJson('flowchart LR\nA-->B'), contains('{'));
  });

  test('dispose settles pending work and rejects subsequent renders', () async {
    final renderer = NativeMermanRenderer(
      libraryPath: await nativeMermanPath(),
    );
    final pending = renderer.render('flowchart LR\nA-->B');
    final assertion = expectLater(
      pending,
      throwsA(isA<MermaidRendererDisposedException>()),
    );
    renderer.dispose();
    renderer.dispose();
    await assertion;
    await expectLater(
      renderer.render('flowchart LR\nB-->C'),
      throwsA(isA<MermaidRendererDisposedException>()),
    );
  });

  test('FFI exposes unsupported features instead of silently dropping them', () {
    final bridge = NativeSvgBridge();
    for (final tag in ['foreignObject', 'image']) {
      expect(
        () => bridge.preprocess('<svg><$tag/></svg>'),
        throwsA(isA<MermaidRenderFailure>()),
      );
    }
    expect(
      () => bridge.preprocess(
        '<svg width="20" height="20"><defs><filter id="f"><feGaussianBlur stdDeviation="2"/></filter></defs><rect width="20" height="20" filter="url(#f)"/></svg>',
      ),
      throwsA(isA<MermaidRenderFailure>()),
    );
    expect(
      () => bridge.preprocess(
        '<svg width="20" height="20"><defs><mask id="m"><rect width="10" height="10" fill="white"/></mask></defs><rect width="20" height="20" mask="url(#m)"/></svg>',
      ),
      throwsA(isA<MermaidRenderFailure>()),
    );
    expect(
      () => bridge.preprocess('<svg><text>😀</text></svg>'),
      throwsA(isA<MermaidRenderFailure>()),
    );
    expect(
      () => bridge.preprocess('<svg'),
      throwsA(isA<MermaidRenderFailure>()),
    );
    final good = bridge.preprocess(
      '<svg width="10" height="20"><rect width="10" height="20"/></svg>',
    );
    expect(good['width'], 10);
    expect(good['height'], 20);
  });

  test(
    'LRU bounds bytes and entries, including replacement and oversized SVGs',
    () {
      final cache = MermaidSvgCache.memory(maxEntries: 2, maxBytes: 20);
      cache.set('a', '12345');
      cache.set('b', '12345');
      expect(cache.get('a'), '12345');
      cache.set('c', '12345');
      expect(cache.get('b'), isNull);
      cache.set('a', '12');
      expect(cache.sizeBytes, 14);
      cache.set('huge', 'a' * 11);
      expect(cache.get('huge'), isNull);
      expect(cache.length, 2);
      cache.clear();
      expect(cache.sizeBytes, 0);
      expect(cache.length, 0);
      final key = MermaidSvgCache.keyFor(
        source: 's',
        optionsJson: '{}',
        engineVersion: '1',
        preprocessingIdentity: 'font-a',
      );
      expect(
        key,
        isNot(
          MermaidSvgCache.keyFor(
            source: 's',
            optionsJson: '{}',
            engineVersion: '1',
            preprocessingIdentity: 'font-b',
          ),
        ),
      );
    },
  );
}
