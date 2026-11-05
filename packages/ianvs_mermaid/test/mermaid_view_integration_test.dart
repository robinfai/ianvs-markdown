import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';

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
    final renderer = NativePeleRenderer();
    addTearDown(renderer.dispose);

    final result = await renderer.render(
      'flowchart LR\nSource --> Parse\nParse --> Render',
    );

    expect(result.svg, contains('<svg'));
    expect(result.svg, contains('<path'));
    expect(result.svg, isNot(contains('<text')));
    expect(result.svg, isNot(contains('<marker')));
    expect(result.preprocessingIdentity, contains('usvg/0.45.1'));
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
