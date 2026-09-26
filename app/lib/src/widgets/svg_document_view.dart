import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';

/// A Flutter vector preview with background text/marker expansion.
class SvgDocumentView extends StatefulWidget {
  const SvgDocumentView({
    super.key,
    required this.svg,
    this.render = renderSvg,
    this.onOpenExternal,
  });

  final String svg;
  final Future<SvgRenderResult> Function(String) render;
  final VoidCallback? onOpenExternal;

  @override
  State<SvgDocumentView> createState() => _SvgDocumentViewState();
}

class _SvgDocumentViewState extends State<SvgDocumentView> {
  late Future<SvgRenderResult> _result = _render();
  int _generation = 0;

  Future<SvgRenderResult> _render() async {
    final generation = ++_generation;
    final source = widget.svg;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted || generation != _generation) {
      throw StateError('Superseded SVG preview');
    }
    return widget.render(source);
  }

  @override
  void didUpdateWidget(covariant SvgDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.svg != widget.svg || oldWidget.render != widget.render) {
      _result = _render();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SvgRenderResult>(
    future: _result,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This SVG cannot be displayed in the built-in preview.',
              ),
              const SizedBox(height: 8),
              const Text(
                'It may be invalid or use unsupported features such as HTML labels, filters, or embedded images.',
                textAlign: TextAlign.center,
              ),
              if (widget.onOpenExternal != null) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: widget.onOpenExternal,
                  child: const Text('Open in default app'),
                ),
              ],
            ],
          ),
        );
      }
      final result = snapshot.requireData;
      return AspectRatio(
        aspectRatio: result.width / result.height,
        child: SvgPicture.string(result.svg, semanticsLabel: 'SVG image'),
      );
    },
  );
}
