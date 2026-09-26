import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'mermaid_render_options.dart';
import 'mermaid_render_result.dart';
import 'mermaid_renderer.dart';
import 'native_merman_renderer.dart';

class MermaidView extends StatefulWidget {
  const MermaidView({
    super.key,
    required this.source,
    this.renderer,
    this.options = MermaidRenderOptions.flutterSvgDefault,
    this.enablePanZoom = false,
    this.fit = BoxFit.contain,
    this.minScale = 0.25,
    this.maxScale = 4,
    this.boundaryMargin = const EdgeInsets.all(256),
    this.semanticsLabel,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String source;
  final MermaidRenderer? renderer;
  final MermaidRenderOptions options;
  final bool enablePanZoom;
  final BoxFit fit;
  final double minScale;
  final double maxScale;
  final EdgeInsets boundaryMargin;
  final String? semanticsLabel;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final WidgetBuilder? loadingBuilder;

  @override
  State<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends State<MermaidView> {
  late MermaidRenderer _renderer;
  late bool _ownsRenderer;
  late Future<MermaidRenderResult> _svgFuture;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _configureRenderer();
    _svgFuture = _render();
  }

  @override
  void didUpdateWidget(covariant MermaidView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rendererChanged = oldWidget.renderer != widget.renderer;
    if (rendererChanged) {
      if (_ownsRenderer) _renderer.dispose();
      _configureRenderer();
    }
    final optionsChanged =
        oldWidget.options.toOptionsJson() != widget.options.toOptionsJson();
    if (rendererChanged ||
        oldWidget.source != widget.source ||
        optionsChanged) {
      _svgFuture = _render();
    }
  }

  @override
  void dispose() {
    _generation++;
    if (_ownsRenderer) _renderer.dispose();
    super.dispose();
  }

  void _configureRenderer() {
    _renderer = widget.renderer ?? NativeMermanRenderer();
    _ownsRenderer = widget.renderer == null;
  }

  Future<MermaidRenderResult> _render() async {
    final generation = ++_generation;
    final source = widget.source;
    final options = widget.options;
    // Coalesce rapid source edits before they enter the native worker queue.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted || generation != _generation) {
      throw StateError('Superseded Mermaid render');
    }
    return _renderer.render(source, options: options);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MermaidRenderResult>(
      future: _svgFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.loadingBuilder?.call(context) ??
              const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
        }
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context, snapshot.error!) ??
              SelectableText(
                'Mermaid render failed:\n${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              );
        }

        final result = snapshot.requireData;
        Widget child = SvgPicture.string(
          result.svg,
          fit: widget.fit,
          semanticsLabel: widget.semanticsLabel ?? 'Mermaid diagram',
          placeholderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
        );
        if (result.width case final width? when width > 0) {
          if (result.height case final height? when height > 0) {
            child = AspectRatio(aspectRatio: width / height, child: child);
          }
        }
        if (!widget.enablePanZoom) return child;
        return InteractiveViewer(
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          boundaryMargin: widget.boundaryMargin,
          child: child,
        );
      },
    );
  }
}
