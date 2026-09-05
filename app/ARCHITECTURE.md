# Desktop app architecture

The `app` package turns `ianvs_markdown` into a file-first desktop editor. It
borrows MarkText's product shape—documents remain ordinary files, while the app
adds workspace navigation and window-level document state—but keeps the editor
engine and storage layer independent. The window shell follows macOS desktop
conventions with a user-selected black workspace sidebar.

## MarkText comparison

| MarkText concept | Ianvs desktop implementation | Design choice |
| --- | --- | --- |
| Main process and renderer shell | Flutter macOS runner + `EditorShell` | Native file access stays behind services instead of entering editor widgets. |
| Open-file tabs | `WorkspaceController` + `DocumentSession` | Every tab owns source, selection, history, mode, and scroll state. |
| Folder sidebar | `WorkspaceSidebar` + lazy `MarkdownFileService.listDirectory` | Directories are read when expanded; the app does not require a vault or database. |
| Outline sidebar | `FloatingOutline` | A toggleable right-hand inspector participates in layout so it cannot cover document content. The existing class name is retained. |
| Editor modes | `IanvsMarkdownEditorMode` | Live Preview, Source, and Read all share one exact Markdown source string. |
| Window/session state | `WorkspaceSessionStore` | Open tabs, active tab, layout visibility, and unsaved source are recovered after restart. |
| macOS file permission recovery | security-scoped bookmarks over a platform channel | User-approved file and folder access survives an app restart without disabling the sandbox. |
| File watching | per-document directory subscriptions | External edits are surfaced explicitly; recovered local edits are never silently overwritten. |
| Safe persistence | `writeMarkdownFileAtomic` | A same-directory temporary file is flushed and renamed over the target. |

## Dependency direction

```text
macOS runner
    ↓
EditorShell / sidebar / outline / tabs
    ↓
WorkspaceController
    ↓                         ↓
MarkdownFileService      WorkspaceSessionStore
    ↓                         ↓
ordinary .md files       recovery snapshot

IanvsMarkdownLiveEditor ← DocumentSession
```

The root package never imports `app`. This keeps `ianvs_markdown` reusable as a
widget library, and keeps `example` small enough to demonstrate package
integration without duplicating product-level file and session behavior.

## App-shell visual contract

The shell uses one 248-point black workspace sidebar, a 44-point document
toolbar, a 32-point tab strip, and an optional 224-point outline inspector.
`desktop_theme.dart` owns neutral surfaces, system typography, blue action
accents, compact controls, menus, dialogs, and scrollbars. `DesktopMenuBar`
exposes the same document commands through the native macOS menu bar.
The document canvas adapts its padding to available width; word counts,
saved/edited state, encoding, and line endings live in a quiet bottom status bar.
`app_icons.dart` owns the shell's semantic icon vocabulary. The sidebar owns
workspace selection and inline file search; the toolbar owns modes/view toggles;
the tab strip owns new/close/switch. Command-1–9 follows visual tab order using
`tab_shortcuts.dart` in both the shell and native Window menu. The app disables
the library's optional mode shortcuts, including the nested Source editor, so
focused text editing does not intercept those tab bindings.

Markdown rendering remains owned by the reusable root package. The app supplies
theme overrides for neutral emphasis, code, and link colors without changing
the library's defaults. See [DESIGN.md](DESIGN.md) for the full visual contract.

## Source-of-truth rules

1. `DocumentSession.controller.text` is the current source shown by the editor.
2. `persistedText` is the last version successfully saved to the document path.
3. A dirty recovered document wins over the disk copy, but a changed disk copy
   raises an explicit conflict banner.
4. A clean recovered document is refreshed from disk during launch.
5. Workspace metadata is recovery state, never a replacement for Markdown
   files.
