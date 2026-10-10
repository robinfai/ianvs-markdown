import 'package:flutter/material.dart';

/// Host-owned identity: revisions belong to a document, source to a resource.
typedef ExampleDiagramRequest = ({
  String documentId,
  int revision,
  String source,
});

typedef ExampleDiagramLoader = Future<String> Function(ExampleDiagramRequest);

/// Demonstrates stale-result isolation without a network or native backend.
/// This is example code, not a core component API or a Mermaid renderer.
class ExampleAsyncDiagram extends StatefulWidget {
  const ExampleAsyncDiagram({
    super.key,
    required this.request,
    required this.load,
  });

  final ExampleDiagramRequest request;
  final ExampleDiagramLoader load;

  @override
  State<ExampleAsyncDiagram> createState() => _ExampleAsyncDiagramState();
}

class _ExampleAsyncDiagramState extends State<ExampleAsyncDiagram> {
  var _generation = 0;
  String? _result;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ExampleAsyncDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request || oldWidget.load != widget.load) {
      _load();
    }
  }

  void _load() {
    final generation = ++_generation;
    final request = widget.request;
    final load = widget.load;
    // Clear the previous result immediately, including while a new request waits.
    _result = null;
    _failed = false;
    Future<String>.sync(() => load(request)).then(
      (result) {
        if (!mounted || generation != _generation) return;
        setState(() => _result = result);
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || generation != _generation) return;
        setState(() => _failed = true);
      },
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: _failed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Diagram preview unavailable'),
                TextButton(
                  onPressed: () => setState(_load),
                  child: const Text('Retry diagram'),
                ),
              ],
            )
          : Text(_result ?? 'Loading diagram preview…'),
    ),
  );
}
