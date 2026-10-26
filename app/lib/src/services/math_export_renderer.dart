import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// A bounded, independent render tree: no editor focus, scroll or selection.
class MathExportImage {
  const MathExportImage(this.png, this.width, this.height);
  final Uint8List png;
  final double width;
  final double height;
}

Future<MathExportImage> renderExportMath(
  String expression,
  bool displayMode,
) async {
  if (expression.length > 8192) {
    throw const FormatException('Formula exceeds rendering limit.');
  }
  final view = ui.PlatformDispatcher.instance.implicitView;
  if (view == null) throw StateError('No rendering view available.');
  final boundary = RenderRepaintBoundary();
  final position = RenderPositionedBox(
    alignment: Alignment.topLeft,
    child: boundary,
  );
  final renderView = RenderView(
    view: view,
    configuration: const ViewConfiguration(
      logicalConstraints: BoxConstraints.tightFor(width: 1024, height: 512),
      physicalConstraints: BoxConstraints.tightFor(width: 1024, height: 512),
    ),
    child: position,
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  final focus = FocusManager();
  final owner = BuildOwner(focusManager: focus);
  RenderObjectToWidgetElement<RenderBox>? element;
  Object? renderingError;
  ui.Image? image;
  try {
    renderView.prepareInitialFrame();
    element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Math.tex(
            expression,
            mathStyle: displayMode ? MathStyle.display : MathStyle.text,
            textStyle: const TextStyle(fontSize: 18, color: Color(0xff171717)),
            onErrorFallback: (error) {
              renderingError = error;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ).attachToRenderTree(owner);
    owner.buildScope(element);
    owner.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
    if (renderingError != null) throw FormatException('$renderingError');
    final size = boundary.size;
    if (size.width <= 8 ||
        size.height <= 8 ||
        size.width >= 1024 ||
        size.height >= 512) {
      throw const FormatException('Formula exceeds image dimensions.');
    }
    image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Formula image encoding failed.');
    return MathExportImage(data.buffer.asUint8List(), size.width, size.height);
  } finally {
    image?.dispose();
    if (element != null) {
      RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
      ).attachToRenderTree(owner, element);
      owner.buildScope(element);
      owner.finalizeTree();
    }
    pipeline.rootNode = null;
    renderView.child = null;
    position.child = null;
    boundary.dispose();
    position.dispose();
    renderView.dispose();
    pipeline.dispose();
    focus.dispose();
  }
}
