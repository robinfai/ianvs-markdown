import '../app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';

class DocumentDiagram extends StatelessWidget {
  const DocumentDiagram({
    super.key,
    required this.source,
    required this.renderer,
  });
  final String source;
  final MermaidRenderer renderer;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: MermaidView(
      source: source,
      renderer: renderer,
      enablePanZoom: false,
      semanticsLabel: 'Mermaid diagram',
      errorBuilder: (context, error) => SelectableText(
        appText(context, "Unable to render diagram: {0}\n\n{1}", [
          error,
          source,
        ]),
      ),
    ),
  );
}
