import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';
import 'package:linefold/src/widgets/document_diagram.dart';

// Optional corpus acceptance test; source documents are never changed here.
// flutter test test/llm_series_render_test.dart --dart-define=LLM_SERIES_DIR=/path/to/series
void main() {
  const corpusPath = String.fromEnvironment('LLM_SERIES_DIR');
  if (corpusPath.isEmpty) {
    test('LLM series acceptance requires LLM_SERIES_DIR', () {}, skip: true);
    return;
  }
  final root = Directory(corpusPath);
  final documents =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final diagrams = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.mmd'))
      .toList();
  final svgs = <String, String>{};
  final rendered = <String, MermaidRenderResult>{};
  late NativeMermanRenderer renderer;
  setUpAll(() async {
    final config = File('.dart_tool/package_config.json');
    final packages =
        (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
    final package = packages.cast<Map>().singleWhere(
      (p) => p['name'] == 'merman',
    );
    final packageRoot = config.uri
        .resolve(package['rootUri'] as String)
        .toFilePath();
    renderer = NativeMermanRenderer(
      libraryPath: '$packageRoot/macos/Libraries/libmerman_ffi.dylib',
    );
    for (final file in diagrams) {
      final source = file.readAsStringSync().trim();
      final result = await renderer.render(source);
      expect(result.svg, contains('<svg'), reason: file.path);
      svgs[source] = result.svg;
      rendered[source] = result;
    }
  });
  tearDownAll(() => renderer.dispose());

  testWidgets('all native diagrams decode and lay out in Flutter', (
    tester,
  ) async {
    expect(diagrams, hasLength(25));
    for (final entry in svgs.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 720,
              height: 600,
              child: SvgPicture.string(entry.value),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: entry.key);
    }
  });

  for (final file in documents) {
    final source = file.readAsStringSync();
    final name = file.path.substring(root.path.length + 1);
    for (final mode in [
      IanvsMarkdownEditorMode.preview,
      IanvsMarkdownEditorMode.livePreview,
    ]) {
      testWidgets('$name renders in ${mode.name}', (tester) async {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = IanvsMarkdownController(text: source, mode: mode);
        final scroll = ScrollController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IanvsMarkdownLiveEditor(
                controller: controller,
                scrollController: scroll,
                showToolbar: false,
                showNavigationPane: false,
                contentMaxWidth: 720,
                onTapLink: (_, _, _) {},
                diagramBuilder: (_, code) {
                  final svg = svgs[code.trim()];
                  expect(
                    svg,
                    isNotNull,
                    reason:
                        'Every article diagram must use the tested native renderer.',
                  );
                  return DocumentDiagram(
                    source: code.trim(),
                    renderer: _CorpusRenderer(rendered),
                  );
                },
              ),
            ),
          ),
        );
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        if (name == 'MATH-NOTES.md' &&
            mode == IanvsMarkdownEditorMode.preview) {
          final table = tester.renderObject<RenderTable>(
            find.byType(Table).first,
          );
          expect(
            table.columns,
            3,
            reason: 'Probability pipes must stay in one cell.',
          );
        }
        for (var page = 0; page < 100; page++) {
          expect(tester.takeException(), isNull, reason: '$name page $page');
          expect(
            find.byKey(const ValueKey('ianvs-markdown-plain-fallback')),
            findsNothing,
          );
          if (mode == IanvsMarkdownEditorMode.preview) _checkTableLinks(tester);
          if (!scroll.hasClients ||
              scroll.offset >= scroll.position.maxScrollExtent) {
            break;
          }
          scroll.jumpTo(
            (scroll.offset + 600).clamp(0, scroll.position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
        }
        if (scroll.hasClients) {
          expect(
            scroll.offset,
            scroll.position.maxScrollExtent,
            reason: 'The complete document must be checked.',
          );
        }
        expect(controller.text, source);
        expect(controller.isDirty, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        controller.dispose();
        scroll.dispose();
      });
    }
  }
}

// Native rendering is exercised above for every source. Use those completed
// results with the production widget while Flutter controls the test clock.
class _CorpusRenderer implements MermaidRenderer {
  const _CorpusRenderer(this.results);
  final Map<String, MermaidRenderResult> results;
  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
    bool includeLayout = false,
  }) async => results[source]!;
  @override
  void dispose() {}
  @override
  Future<String> layoutJson(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
  }) => throw UnimplementedError();
  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
  }) => throw UnimplementedError();
}

void _checkTableLinks(WidgetTester tester) {
  for (final element
      in find
          .byKey(const ValueKey('ianvs-markdown-ordinary-link'))
          .evaluate()) {
    final link = element.renderObject! as RenderBox;
    RenderObject child = link;
    while (child.parent != null && child.parent is! RenderTable) {
      child = child.parent!;
    }
    if (child.parent case final RenderTable table) {
      final data = child.parentData! as TableCellParentData;
      final row = table.getRowBox(data.y!);
      final offset = link.localToGlobal(Offset.zero, ancestor: table);
      expect(
        offset.dy + link.size.height,
        lessThanOrEqualTo(row.bottom + 0.01),
      );
    }
  }
}
