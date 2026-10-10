# ianvs_markdown example

Each entry below runs independently and imports only public APIs. The example
package depends only on Flutter and `ianvs_markdown`; it does not depend on
Linefold or the optional Mermaid backend.

| Entry | Demonstrates | Host responsibilities |
| --- | --- | --- |
| `lib/body.dart` | A content-sized `IanvsMarkdown` inside a card; GFM/Obsidian switching | Scrolling, approved image widgets and link handling |
| `lib/reading.dart` | `IanvsMarkdownView`, heading navigation/folding, document replacement and selection/copy | FocusNode, ScrollController, navigation notifier and clipboard writer |
| `lib/editor.dart` | Three-mode Live editor with an independent toolbar, English/Chinese messages and custom shortcuts | Document identity, controller lifetime, captured/ordered asynchronous saves and persistence errors |
| `lib/main.dart` | Existing full-syntax playground with light/dark themes | Controller, reset and save callback; resources use the safe fallback |

All examples leave Mermaid as a code block unless the host supplies
`diagramBuilder`. The body example resolves exactly `asset:approved-logo` to a
local Flutter widget. It blocks every other image URI and displays requested
links instead of opening them. It does not fetch network resources.

The macOS project declares macOS 12 or later; actual build and interaction
evidence is tracked in [the platform matrix](../doc/PLATFORM_SUPPORT.md).
From this directory:

```sh
flutter pub get
flutter run -d macos -t lib/body.dart
flutter run -d macos -t lib/reading.dart
flutter run -d macos -t lib/editor.dart
# Existing playground; also available as `make run example` from the root.
flutter run -d macos -t lib/main.dart
```

Launch one entry at a time. In the reader, use the heading button to navigate,
select text or press Ctrl/⌘A then Ctrl/⌘C, and switch documents to observe the
selection/scroll reset. Whole-document copy includes the exact original YAML
and Markdown. The default writer puts Markdown plain text on the clipboard;
HTML remains available to an injected writer.

The editor stores snapshots **in memory only**. Closing the app loses them.
`EditorExampleApp.write` is the replacement point for a real file/database
writer; `ExampleDocumentSession` serializes captured saves under `draft.md`.
The component acknowledges only that saved snapshot, so edits made during a
pending save remain dirty. Both the toolbar and editor use the same callback
and host-owned FocusNode. F5 saves; Ctrl/⌘L changes the UI language. Failed
writes remain errors rather than being acknowledged as saved.

Run all example regressions with `flutter test`. From the repository root,
`make build-examples` builds all four macOS Debug entries. `make check-package`
runs the same example tests in a Pub-selected snapshot outside the repository,
then checks a separately created host. This automated check does not replace
real IME, cross-application clipboard or external-product acceptance.

The examples do not open or write files. The full file-first desktop product,
including workspace navigation, tabs, recovery, and file watching, lives in
[Linefold](https://github.com/robinfai/ianvs-markdown/tree/main/app).

Native Mermaid rendering and explicitly enabled HTTP images are demonstrated in
the separate [adapter example](https://github.com/robinfai/ianvs-markdown/tree/main/packages/ianvs_mermaid/example).
That optional example requires Rust and a supported native platform, and opts
into `ianvs_markdown_clipboard` to keep native Markdown + HTML copy. These core
examples resolve neither native backend. Existing hosts that need rich copy
must follow the [clipboard migration](../doc/INTEGRATION_GUIDE.md#剪贴板迁移r1-04).

R2-05: the editor entry observes `onRenderDecision` and shows a host-owned notice
when large content uses simplified display. Full source is retained for editing,
saving and history. The controller, renderer and Reading clipboard budgets are
independent; see the [integration guide](../doc/INTEGRATION_GUIDE.md).
