import 'dart:isolate';

import 'native_svg_bridge.dart';

class SvgRenderResult {
  const SvgRenderResult({
    required this.svg,
    required this.width,
    required this.height,
  });

  final String svg;
  final double width;
  final double height;
}

/// Expands a standalone SVG's text and markers on a background isolate.
/// Uses the same feature and size limits as the Mermaid vector pipeline.
Future<SvgRenderResult> renderSvg(String source) => Isolate.run(() {
  final result = NativeSvgBridge().preprocess(source);
  return SvgRenderResult(
    svg: result['svg'] as String,
    width: (result['width'] as num).toDouble(),
    height: (result['height'] as num).toDouble(),
  );
});
