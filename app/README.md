# Linefold

`app/` is the file-first desktop editor built on top of the reusable
`ianvs_markdown` package. Its file-first product structure keeps the useful
parts of MarkText, with app chrome adapted to macOS toolbar, source-list,
inspector, menu, typography, and selection conventions.

Implemented application-shell capabilities:

- document toolbar with editing modes and a compact, reorderable tab strip
- Command-1–9 switches the first nine tabs in their current order, not editor modes
- shared monochrome icons and one primary window location per action
- black workspace sidebar, neutral light/dark chrome, and blue action accents
- native File, Edit, View, and Window menus and an all-open-documents menu
- new/open/save/save-as and Finder file drop
- folder workspace with lazy Markdown file tree and filename search
- collapsible left sidebar and docked document outline inspector
- per-document mode, cursor, scroll, dirty state, encoding and line-ending UI
- atomic UTF-8 writes and external file-change notifications
- debounced crash recovery for open files and unsaved drafts
- macOS security-scoped bookmarks for restoring user-approved files and folders

Integration boundaries in the current desktop shell:

- Link navigation, local/remote images, Wiki embed resolution, and Mermaid
  rendering need host callbacks that this app has not yet connected. Links have
  their rendered appearance, images show a blocked placeholder, Wiki embeds show
  a reference, and Mermaid falls back to its source.
- YAML is editable in Source and hidden in Live/Read. The package's optional
  Properties editor and heading-fold controls are not enabled in this app.
- Search filters filenames across the workspace; it is not a document-content
  search. Find/replace, export, and an encoding or line-ending selector are not
  currently exposed.
- Open-document text, modes, and workspace visibility are recovered. Appearance,
  caret positions, and scroll offsets are not serialized across app launches.

Run from the repository root:

```sh
cd app
flutter pub get
flutter run -d macos
```

`example/` remains the small package-integration example. Product features
belong here instead of in the example application.

See [DESIGN.md](DESIGN.md) for the macOS visual contract and verification notes,
and [ARCHITECTURE.md](ARCHITECTURE.md) for dependency and recovery rules.
