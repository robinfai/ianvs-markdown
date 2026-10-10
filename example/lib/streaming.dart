import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'async_diagram.dart';

void main() => runApp(const StreamingExampleApp());

Future<String> _preview(ExampleDiagramRequest request) async {
  await Future<void>.delayed(const Duration(milliseconds: 600));
  return 'Diagram preview for ${request.documentId}\n${request.source}';
}

/// A host that merges fragments, follows new content, and isolates async work.
class StreamingExampleApp extends StatelessWidget {
  const StreamingExampleApp({super.key, this.loadDiagram = _preview});

  final ExampleDiagramLoader loadDiagram;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Streaming Markdown',
    home: _StreamingPage(loadDiagram: loadDiagram),
  );
}

class _StreamingPage extends StatefulWidget {
  const _StreamingPage({required this.loadDiagram});
  final ExampleDiagramLoader loadDiagram;

  @override
  State<_StreamingPage> createState() => _StreamingPageState();
}

class _StreamingPageState extends State<_StreamingPage> {
  final _scroll = ScrollController();
  var _document = 0;
  var _revision = 0;
  var _follow = true;
  var _scrollGeneration = 0;
  String get _documentId => _document.isEven ? 'response-A' : 'response-B';
  String get _source =>
      '# $_documentId\n\n'
      '${List.generate(12, (index) => 'Context paragraph ${index + 1}.\n\n').join()}'
      '${streamingFragments.take(_revision).join()}';

  @override
  void initState() {
    super.initState();
    _followAfterLayout();
  }

  void _followAfterLayout() {
    final generation = ++_scrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _scrollGeneration || !_follow) return;
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_documentId),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _document += 1;
              _revision = 0;
              _follow = false;
              _scrollGeneration += 1;
            });
            if (_scroll.hasClients) _scroll.jumpTo(0);
          },
          child: const Text('Switch document'),
        ),
      ],
    ),
    body: Column(
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            TextButton(
              onPressed: _revision == streamingFragments.length
                  ? null
                  : () {
                      setState(() => _revision += 1);
                      _followAfterLayout();
                    },
              child: const Text('Append fragment'),
            ),
            const Text('Follow new content'),
            Switch(
              value: _follow,
              onChanged: (value) {
                setState(() => _follow = value);
                _followAfterLayout();
              },
            ),
            Text('Fragment $_revision / ${streamingFragments.length}'),
          ],
        ),
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              if (notification.depth != 0) return false;
              // Async builder size changes can also extend the content.
              _followAfterLayout();
              WidgetsBinding.instance.ensureVisualUpdate();
              return false;
            },
            child: NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0 &&
                    _follow &&
                    notification.direction == ScrollDirection.forward) {
                  setState(() => _follow = false);
                  _scrollGeneration += 1;
                }
                return false;
              },
              child: SingleChildScrollView(
                key: const ValueKey('streaming-scroll'),
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                child: IanvsMarkdown(
                  // New identity clears component-owned selection and local state,
                  // even when two documents happen to contain identical source.
                  key: ValueKey(_documentId),
                  data: _source,
                  diagramBuilder: (_, source) => ExampleAsyncDiagram(
                    request: (
                      documentId: _documentId,
                      revision: _revision,
                      source: source,
                    ),
                    load: widget.loadDiagram,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

const streamingFragments = [
  '```mermaid\ngraph TD\n',
  '  A --> B\n',
  '```\n\n| Name | State |\n',
  '| --- | --- |\n| Alpha | loading',
  ' |\n| Beta | ready |\n\n[Open the guide',
  '][guide]\n\n[guide]: docs/guide.md\n\nComplete.',
];
