# Native Mermaid integration example

This optional host injects `MermaidView` through the Markdown editor's
`diagramBuilder`, while preserving Controller, mode, save, and theme examples.
Its `imageBuilder` explicitly enables HTTP/HTTPS images. These are host choices;
the [minimal core example](../../../example/) keeps the safe resource defaults.
It also explicitly selects `ianvs_markdown_clipboard` for native Markdown/HTML
copy; the core renderer now defaults to Markdown plain text without that plugin.

Install Flutter, Rust/Cargo, and the Rust target for your Mac architecture. See
the [adapter requirements](../README.md) for other platforms and font support.
From this directory:

```sh
flutter pub get
flutter test
flutter run -d macos
```

The macOS host requires macOS 12 or later. Its Xcode build phases normalize the
packaged merman library using `../../tool/normalize_macos.sh`. It does not open
or save user files; the save callback only marks the document clean.

Native view and FFI coverage moved from the core example into
[`../test/mermaid_view_integration_test.dart`](../test/mermaid_view_integration_test.dart).
Run `make test-mermaid` from the repository root to include it.
