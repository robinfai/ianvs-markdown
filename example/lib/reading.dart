import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() => runApp(const ReadingExampleApp());

/// Run independently with `flutter run -d macos -t lib/reading.dart`.
class ReadingExampleApp extends StatelessWidget {
  const ReadingExampleApp({
    super.key,
    this.clipboardWriter = writeIanvsMarkdownClipboard,
  });

  final IanvsMarkdownClipboardWriter clipboardWriter;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Markdown reader',
    home: _ReadingPage(clipboardWriter: clipboardWriter),
  );
}

class _ReadingPage extends StatefulWidget {
  const _ReadingPage({required this.clipboardWriter});
  final IanvsMarkdownClipboardWriter clipboardWriter;

  @override
  State<_ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<_ReadingPage> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _heading = ValueNotifier<IanvsMarkdownHeadingNavigation?>(null);
  var _secondDocument = false;
  String _status = 'Select text, or use Ctrl/⌘A and Ctrl/⌘C to copy.';

  String get _source => _secondDocument ? readingNotes : readingGuide;

  @override
  void dispose() {
    _heading.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _copy(IanvsMarkdownClipboardData data) async {
    await widget.clipboardWriter(data);
    if (mounted) setState(() => _status = 'Copied selection');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_secondDocument ? 'notes.md' : 'guide.md'),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _secondDocument = !_secondDocument;
              _status = 'New document: selection and scroll reset.';
            });
            _focus.requestFocus();
          },
          child: const Text('Switch document'),
        ),
      ],
    ),
    body: IanvsMarkdownLocalization(
      strings: const IanvsMarkdownStrings.english(),
      child: Column(
        children: [
          Wrap(
            children: [
              TextButton(
                onPressed: () {
                  _heading.value = IanvsMarkdownHeadingNavigation(
                    _source.indexOf('## Checklist'),
                  );
                  _focus.requestFocus();
                },
                child: const Text('Jump to checklist'),
              ),
              TextButton(
                onPressed: () {
                  _scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                  _focus.requestFocus();
                },
                child: const Text('Back to top'),
              ),
            ],
          ),
          Expanded(
            child: IanvsMarkdownView(
              data: _source,
              controller: _scroll,
              focusNode: _focus,
              autofocus: true,
              headingNavigation: _heading,
              enableHeadingFolding: true,
              clipboardWriter: _copy,
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: Text(_status)),
        ],
      ),
    ),
  );
}

final readingGuide =
    '''
---
title: Reading guide
author: Example host
---
# Reading guide

The View owns document layout. The host owns focus, scrolling and copy output.

${List.generate(12, (index) => '## Section ${index + 1}\n\nRead **Markdown** without an editor. Whole-document copy preserves the original source, including the metadata.\n').join('\n')}
## Checklist

- [x] Navigate to a heading
- [ ] Select and copy text
- [ ] Switch to another document
''';

const readingNotes = '''
---
title: Another document
---
# Another document

Changing data clears the old selection and returns the View to the top.

## Checklist

- [ ] Copy this document without content from the previous one
''';
