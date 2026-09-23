# ianvs_markdown example

This directory intentionally stays small. It demonstrates how a Flutter host
creates an `IanvsMarkdownController`, embeds `IanvsMarkdownLiveEditor`, handles
the save callback, supplies a theme, and injects a Mermaid renderer.

The macOS example requires macOS 12 or later. From the repository root, run
`make run`, or use Flutter directly:

```sh
cd example
flutter pub get --offline
flutter run -d macos
```

The example does not open or write files. The full file-first desktop product,
including workspace navigation, tabs, recovery, and file watching, lives in
[`../app`](../app/).
