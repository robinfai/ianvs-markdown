import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:ianvs_markdown_example/mermaid/mermaid_render_options.dart';
import 'package:ianvs_markdown_example/mermaid/mermaid_render_result.dart';
import 'package:ianvs_markdown_example/mermaid/mermaid_renderer.dart';
import 'package:ianvs_markdown_example/mermaid/mermaid_view.dart';
import 'package:ianvs_markdown_example/mermaid/native_merman_renderer.dart';

void main() {
  testWidgets('renders generated SVG in the Mermaid view', (tester) async {
    final renderer = _FakeRenderer();
    addTearDown(renderer.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 500,
          height: 320,
          child: MermaidView(
            source: 'flowchart LR\nA --> B',
            renderer: renderer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(renderer.renderedSource, 'flowchart LR\nA --> B');
  });

  test('renders a flowchart with the packaged native engine', () async {
    final libraryPath = await _nativeLibraryPath();
    expect(libraryPath, isNotNull);

    final renderer = NativeMermanRenderer(
      openEngine: () => BundledMermanEngine.openPath(libraryPath!),
    );
    addTearDown(renderer.dispose);

    final result = await renderer.render(
      'flowchart LR\nSource --> Parse\nParse --> Render',
    );

    expect(result.svg, contains('<svg'));
    expect(result.svg, contains('Source'));
    expect(result.svg, contains('Render'));
    expect(result.svg, isNot(contains('<style')));
  });
}

class _FakeRenderer implements MermaidRenderer {
  String? renderedSource;

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
    bool includeLayout = false,
  }) async {
    renderedSource = source;
    return MermaidRenderResult(
      source: source,
      svg: '<svg viewBox="0 0 100 40"><text x="5" y="20">OK</text></svg>',
      optionsJson: options.toOptionsJson(),
    );
  }

  @override
  void dispose() {}

  @override
  Future<String> layoutJson(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
  }) async => '{}';

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
  }) async {
    return const MermaidValidationResult(valid: true);
  }
}

Future<String?> _nativeLibraryPath() async {
  final packageDir = await _packageRoot('merman');
  if (packageDir == null) return null;
  final path = switch (Abi.current()) {
    Abi.macosArm64 ||
    Abi.macosX64 => '$packageDir/macos/Libraries/libmerman_ffi.dylib',
    Abi.linuxX64 => '$packageDir/linux/lib/x86_64/libmerman_ffi.so',
    Abi.linuxArm64 => '$packageDir/linux/lib/aarch64/libmerman_ffi.so',
    Abi.windowsX64 => '$packageDir/windows/merman_ffi.dll',
    _ => null,
  };
  if (path == null || !File(path).existsSync()) return null;
  return path;
}

Future<String?> _packageRoot(String packageName) async {
  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) return null;

  final decoded =
      jsonDecode(await configFile.readAsString()) as Map<String, Object?>;
  final packages = decoded['packages'];
  if (packages is! List<Object?>) return null;

  for (final package in packages) {
    if (package is! Map<String, Object?> || package['name'] != packageName) {
      continue;
    }
    final rootUri = package['rootUri'];
    if (rootUri is! String) return null;
    return configFile.uri.resolve(rootUri).toFilePath();
  }
  return null;
}
