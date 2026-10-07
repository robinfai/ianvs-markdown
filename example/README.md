# ianvs_markdown example

This directory intentionally stays small. It demonstrates how a Flutter host
creates an `IanvsMarkdownController`, embeds `IanvsMarkdownLiveEditor`, handles
the save callback, and supplies a theme. It depends only on Flutter and
`ianvs_markdown`. Images retain the library's safe placeholder; Mermaid uses
the code-block fallback until a host supplies `diagramBuilder`.

The macOS example requires macOS 12 or later. From the repository root, run
`make run example`, or use Flutter directly:

```sh
cd example
flutter pub get
flutter run -d macos
```

The example does not open or write files. The full file-first desktop product,
including workspace navigation, tabs, recovery, and file watching, lives in
[Linefold](https://github.com/robinfai/ianvs-markdown/tree/main/app).

Native Mermaid rendering and explicitly enabled HTTP images are demonstrated in
the separate [adapter example](https://github.com/robinfai/ianvs-markdown/tree/main/packages/ianvs_mermaid/example).
That optional example requires Rust and a supported native platform. The core
package still depends on `super_clipboard`; removing the Mermaid backend does
not remove the clipboard plugin's platform build requirements.
