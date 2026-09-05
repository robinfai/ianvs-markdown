import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'mermaid/mermaid_view.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  var _dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ianvs Markdown Example',
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff167b82)),
        extensions: const <ThemeExtension<dynamic>>[
          IanvsMarkdownThemeData.light,
        ],
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff68c5ca),
          brightness: Brightness.dark,
        ),
        extensions: const <ThemeExtension<dynamic>>[
          IanvsMarkdownThemeData.dark,
        ],
      ),
      home: MarkdownExample(
        dark: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }
}

class MarkdownExample extends StatefulWidget {
  const MarkdownExample({
    super.key,
    required this.dark,
    required this.onToggleTheme,
  });

  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<MarkdownExample> createState() => _MarkdownExampleState();
}

class _MarkdownExampleState extends State<MarkdownExample> {
  late final IanvsMarkdownController _controller = IanvsMarkdownController(
    text: exampleMarkdown,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ianvs_markdown example',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        shape: Border(bottom: BorderSide(color: colors.borderSoft)),
        actions: [
          IconButton(
            tooltip: widget.dark ? 'Use light theme' : 'Use dark theme',
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Reset example',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: IanvsMarkdownLiveEditor(
        controller: _controller,
        showToolbar: true,
        showNavigationPane: false,
        showFrontMatter: true,
        enableHeadingFolding: true,
        imageBuilder: buildExampleNetworkImage,
        diagramBuilder: (context, source) => MermaidView(source: source),
        onSaveRequested: (_) {
          _controller.markSaved();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Host save callback invoked')),
          );
        },
      ),
    );
  }

  void _reset() {
    _controller.value = const TextEditingValue(
      text: exampleMarkdown,
      selection: TextSelection.collapsed(offset: 0),
    );
    _controller
      ..mode = IanvsMarkdownEditorMode.livePreview
      ..clearHistory()
      ..markSaved();
  }
}

Widget buildExampleNetworkImage(Uri uri, String? title, String? alt) {
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    return Text(alt?.isNotEmpty == true ? alt! : uri.toString());
  }
  return Image.network(
    uri.toString(),
    semanticLabel: alt,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      final total = progress.expectedTotalBytes;
      return SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: total == null
                ? null
                : progress.cumulativeBytesLoaded / total,
          ),
        ),
      );
    },
    errorBuilder: (context, error, stackTrace) => SizedBox(
      height: 120,
      child: Center(
        child: Text(
          alt?.isNotEmpty == true
              ? 'Unable to load $alt'
              : 'Unable to load image',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

const exampleMarkdown =
    '''
---
title: Ianvs Markdown Playground
author: Ianvs
tags: [Flutter, Markdown, live-preview]
aliases: [Ianvs editor, Markdown playground]
status: editable
enabled: true
archived: false
score: 42
due: 2026-09-03
related: ["[[Project Notes]]", "https://flutter.dev"]
empty:
settings: {owner: Ianvs, autosave: true}
---
# Render and edit together

Click any rendered block to edit its exact **Markdown source** without leaving
Live Preview. Use the toolbar to switch between Live Preview, Source, and Read.

> Markdown remains the only source of truth. The host application decides how
> files, links, images, and persistence are handled.

## Text and inline formatting

A normal paragraph can contain **bold**, *italic*, ***bold italic***,
~~strikethrough~~, ==highlighted text==, and `inline code`.

Escaped characters stay literal: ${r'\*asterisks\*'}, ${r'\#hash'}, and
${r'\[brackets\]'}.
Two spaces at the end of this line create a hard break:${'  '}
this sentence starts on the next visual line.

Links support [relative destinations](docs/guide.md),
[titles](https://example.com "Example title"), and bare URLs such as
https://flutter.dev. Email addresses like hello@example.com remain readable.

Wiki links keep their source: [[Project Notes]], [[Project Notes#Roadmap]], and
[[docs/roadmap|a custom label]]. Hierarchical tags render compactly:
#flutter/markdown.

## Lists and tasks

- Unordered item
- A second item with nested content
  - Nested bullet
  - Another nested bullet
    1. Ordered item at a deeper level
    2. Another ordered item
- Final parent item

1. First ordered item
2. Second ordered item
3. Third ordered item

- [x] Completed task
- [ ] Open task
- [ ] Task containing **formatted text** and a [link](https://dart.dev)

## Quotes and callouts

> A blockquote can span multiple lines.
>
> It can contain **formatting**, lists, and a second paragraph.
> - Quoted list item

> An outer quote keeps its first rail.
>
> > A nested quote adds another level.

> [!note] Live Preview
> Callouts keep their title, accent, and Markdown **formatting**.

> [!warning]- Collapsible detail
> This warning starts folded and preserves its exact source.

---

## Headings

### Heading level three

#### Heading level four

##### Heading level five

###### Heading level six

Setext level one
================

Setext level two
----------------

## Tables

| Capability | Example | Supported |
| :--- | :--- | ---: |
| Inline styles | **Bold** and `code` | Yes |
| Alignment | Left and right columns | Yes |
| Empty cell | | Yes |
| Escaped pipe | ${r'A \| B'} | Yes |

## Code

Inline code preserves symbols such as `final value = <String>[];`.

```dart
final controller = IanvsMarkdownController(
  text: '# Hello Markdown',
);

IanvsMarkdownLiveEditor(controller: controller);
```

Indented code is also supported:

    const unfenced = true;
    print(unfenced);

## Mermaid diagram

The example app injects its Mermaid renderer through `diagramBuilder`.

```mermaid
flowchart LR
  Markdown --> Parse
  Parse --> Edit
  Edit --> Render
```

## Math

Inline math uses delimiters such as ${r'$E = mc^2$'}.

${r'$$'}
${r'\int_0^1 x^2\,dx = \frac{1}{3}'}
${r'$$'}

## Images and embeds

Standard image syntax remains host-controlled for safe loading:

![Frame diff principle advantages](https://robinfai.github.io/ianvs-terminal/assets/images/frame-diff/principle-advantages.png "Frame diff principle advantages")

Obsidian-style embeds retain their exact source:

![[Project Notes#Roadmap]]

## Footnotes, comments, and block IDs

A statement can reference a standard footnote[^source] and an inline footnote
^[Inline notes share the same reading-mode sequence.].

[^source]: Footnote definitions can contain **Markdown formatting** and links.

This text is visible, while %%this editor-only comment is hidden in Read mode%%.

This paragraph has a reusable block identifier. ^example-block

%%
A multi-line Markdown comment remains editable in Live Preview and disappears
from the reading surface.
%%

## Host integration

| API | Responsibility |
| --- | --- |
| `IanvsMarkdownController` | source, selection, history, dirty state |
| `IanvsMarkdownLiveEditor` | editing and rendering surfaces |
| `diagramBuilder` | host-approved Mermaid rendering |
| `onSaveRequested` | host-owned persistence callback |

The reset button restores this entire document, so every supported element can
be edited repeatedly without changing files on disk.
''';
