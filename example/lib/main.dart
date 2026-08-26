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
      title: 'Ianvs Markdown Playground',
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff167b82)),
        scaffoldBackgroundColor: const Color(0xffffffff),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xffffffff),
          foregroundColor: Color(0xff202526),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
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
      home: MarkdownPlayground(
        dark: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }
}

class MarkdownPlayground extends StatefulWidget {
  const MarkdownPlayground({
    super.key,
    required this.dark,
    required this.onToggleTheme,
  });

  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<MarkdownPlayground> createState() => _MarkdownPlaygroundState();
}

class _MarkdownPlaygroundState extends State<MarkdownPlayground> {
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
        toolbarHeight: 56,
        titleSpacing: 78,
        title: const Text(
          'Ianvs Markdown Playground',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        shape: Border(bottom: BorderSide(color: colors.borderSoft)),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _controller.dirtyListenable,
            builder: (context, dirty, _) => Tooltip(
              message: dirty ? '保存' : '已保存',
              child: TextButton.icon(
                onPressed: dirty ? _saveFromHeader : null,
                icon: Icon(
                  dirty ? Icons.edit_outlined : Icons.check_circle_outline,
                  size: 18,
                ),
                label: Text(dirty ? 'Unsaved' : 'Saved'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  disabledForegroundColor: colors.textSecondary,
                  minimumSize: const Size(88, 44),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<_PlaygroundAction>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (action) {
              switch (action) {
                case _PlaygroundAction.reset:
                  _reset();
                case _PlaygroundAction.theme:
                  widget.onToggleTheme();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _PlaygroundAction.reset,
                child: ListTile(
                  leading: Icon(Icons.restart_alt_rounded),
                  title: Text('Reset example'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _PlaygroundAction.theme,
                child: ListTile(
                  leading: Icon(
                    widget.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                  title: Text(
                    widget.dark ? 'Use light theme' : 'Use dark theme',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: IanvsMarkdownLiveEditor(
        controller: _controller,
        showToolbar: false,
        showNavigationPane: true,
        navigationWidth: 300,
        navigationBreakpoint: 860,
        contentMaxWidth: 640,
        padding: const EdgeInsets.fromLTRB(54, 32, 54, 64),
        onChanged: (_) => setState(() {}),
        onSaveRequested: _save,
        onTapLink: _openLink,
        diagramBuilder: (context, source) => _MermaidDemo(source: source),
        wikiEmbedBuilder: _buildWikiEmbed,
        wikiLinkExists: (target) => !target.startsWith('Missing Wiki Note'),
      ),
    );
  }

  Future<void> _saveFromHeader() async {
    await _save(_controller.text);
    _controller.markSaved();
  }

  Future<void> _save(String markdown) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved locally by the host app'),
        duration: Duration(seconds: 1),
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
    setState(() {});
  }

  void _openLink(String text, String? href, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Host handles link: ${href ?? text}')),
    );
  }

  Widget _buildWikiEmbed(
    BuildContext context,
    IanvsMarkdownWikiEmbedReference reference,
  ) {
    final source = switch (reference.subpath) {
      '^next-step' => 'Connect the editor to a host-owned note repository.',
      'Roadmap' =>
        '''
## Roadmap

- Resolve notes in the host app
- Keep Markdown as the source of truth

Connect the editor to a host-owned note repository. ^next-step
''',
      _ => projectNotesMarkdown,
    };
    return IanvsMarkdown(data: source, fitContent: true, onTapLink: _openLink);
  }
}

enum _PlaygroundAction { reset, theme }

class _MermaidDemo extends StatelessWidget {
  const _MermaidDemo({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return Container(
      key: const ValueKey('example-mermaid-renderer'),
      height: 320,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(colors.mediumRadius),
      ),
      child: MermaidView(
        source: source,
        semanticsLabel: 'Mermaid diagram',
        loadingBuilder: (_) => const Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorBuilder: (context, error) => Center(
          child: SelectableText(
            'Mermaid render failed:\n$error',
            style: TextStyle(color: colors.error, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

const exampleMarkdown =
    '''
---
title: Ianvs Markdown
author: Ianvs
tags: [Flutter, GFM, live-preview]
aliases: [Ianvs editor, Markdown playground]
status: editable
enabled: true
archived: false
score: 42
due: 2026-08-24
related: ["[[Project Notes]]", "[[Project Notes#Roadmap]]"]
empty:
settings: {owner: Ianvs}
---
# Render and edit together

Click any rendered block to edit it **without leaving live preview**. Use the
toolbar to switch between live preview, full source, and reading modes.

> The Markdown string remains the only source of truth. The host application
> decides how and when to save it.

## Everyday Markdown

- [x] GitHub-flavored Markdown
- [ ] Click this task block and edit it
- [ ] Try **bold**, *italic*, `inline code`, and [a link](docs/guide.md)

Nested emphasis stays combined in ***bold italic*** text.

Intraword underscores stay asymmetric: foo_single_word remains literal, while
foo__double__word uses Obsidian's intraword strong form.

Select text before using ⌘B, ⌘I, or ⌘K. With no selection, link insertion
starts as `[]()` and keeps the caret inside the label.

Wiki links keep their Obsidian source: [[Project Notes]] or
[[docs/roadmap|the roadmap]]. Tags render as compact chips: #flutter/markdown.
External links keep their destination hidden and show an exit cue:
[Flutter](https://flutter.dev).

Link labels preserve nested formatting: [**bold link** with `inline code`](https://example.com/docs "Rich label").

Bare links keep Obsidian punctuation boundaries: https://example.com/a_(b).,
user@example.com and www.example.com.

Reading mode separates [[Project Notes#Roadmap]] with a chevron, while
[[Missing Wiki Note]] uses the host-resolved missing-link style.

A host-resolved heading embed keeps Obsidian's slim rail and open affordance:

![[Project Notes#Roadmap]]

- Bullets stay visual while editing
- Press Enter to continue the list
- Split at the content start without discarding the empty marker

1. Ordered markers stay visual
2. Numbers continue automatically

## Structure and depth

> A quoted paragraph keeps a slim accent rail.
>
> A second paragraph remains in the same quote.

> An outer quote keeps its first rail.
>
> > A nested quote adds a second rail.
> > - Nested list markers stay readable.
>
> The outer quote resumes without losing its depth.

> A lazy quote continuation starts here.
This unmarked source line remains inside the quote.
> An explicit quoted tail finishes the block.

---

- Parent bullet
  - Nested bullet
    1. Nested ordered item
- Following parent

## Heading hierarchy

# Heading level one

## Heading level two

### Heading level three

#### Heading level four

##### Heading level five

###### Heading level six

Setext level one
================

Setext level two
----------------

## Highlights and callouts

Inactive ==highlight markers disappear== until the caret enters their range.

> [!note] **Live preview** with `inline code`
> Callouts keep their icon, type color, title, and inline **formatting**.
An unmarked lazy continuation remains inside the same callout.
> The explicit quoted tail remains inside it too.
> > [!tip] Nested callout
> > Nested callouts keep their own card color, icon, and body.

> [!warning]- **Folded** source-preserving detail
> Expanding this card does not enter editing; clicking its body does.

## Mathematics

Inline math hides its delimiters: \$E = mc^2\$, and display-style math can
remain in the same line: \$\$x^2 + 1\$\$.

\$\$
\\int_0^1 x^2\\,dx = \\frac{1}{3}
\$\$

## Comments, block IDs, and footnotes

Rendered text keeps %%this editor-only comment%% out of the reading surface.

This paragraph has an Obsidian block identifier. ^example-block

Standard footnotes[^standard] and inline notes
^[Inline footnotes join the same numbered footer.] share one sequence.

[^standard]: Standard footnotes keep **Markdown formatting**.

%%
This multi-line comment stays subdued in Preview and disappears in Read.
%%

| Capability | Detail | Status |
| :--- | :--- | ---: |
| Block live preview | **Rendered + editable** | Yes |
| Source-preserving edits | `Markdown` stays canonical | Yes |
| Empty cells | | Supported |
| Escaped pipe | A \\| B stays in one cell | Yes |
| Sparse row | Missing cells stay editable |
| Extra source cell | Retained instead of truncated | Yes | Obsidian |
| Network image loading | Host-approved builders only | Off |

## Line breaks and whitespace

Obsidian-style soft breaks keep each source line visible:
first source line
second source line

Two trailing spaces also create a hard break:${'  '}
the following line stays separate.

Escaped \\*asterisks\\*, \\#hash, and \\[brackets\\] stay literal.

Several     internal spaces collapse when the document is rendered.

Inline code can cross a soft source break without losing its code style:
`first inline row
second inline row`.

Code spans keep shorter delimiter runs literal: ``code with ` a tick``.
Live Preview preserves `three   internal   spaces`, while Reading collapses
them; `  one padded edge  ` removes one source-space pair in both modes.
Outer formatting composes with code: **`strong code`**, *`italic code`*,
~~`struck code`~~, and ==`highlighted code`==.

## Code blocks

```dart
final controller = IanvsMarkdownController(text: source);

IanvsMarkdownLiveEditor(controller: controller);
```

Code tabs follow four-column stops while copied Markdown keeps the original
tab characters:

```text
root
\tchild
a\tb
```

Indented code stays plain and monospaced without fenced chrome:

    const unfenced = true;

    print(unfenced);

Only the first info token becomes the visible language label:

```python linenums="1"
print("info suffix")
```

Unknown language labels preserve their source casing:

```FoObAr
widget := unknown_token(42)
```

Long fenced lines soft-wrap inside the available code canvas:

```text
This deliberately long code line keeps flowing inside the canvas instead of exposing a horizontal scrollbar at the bottom.
```

An empty fenced block shows an empty canvas until it is activated:

```text

```

## Diagram injection

```mermaid
graph LR
  Source --> Parse
  Parse --> Edit
  Edit --> Render
```

## Safe images

Images are blocked until the host supplies an approved `imageBuilder`.

![Remote example](https://images.example.com/diagram.png)
''';

const projectNotesMarkdown = '''
# Project Notes

The host app supplies embedded Markdown without granting the renderer file
system access.

## Roadmap

- Resolve notes in the host app
- Keep Markdown as the source of truth

Connect the editor to a host-owned note repository. ^next-step
''';
