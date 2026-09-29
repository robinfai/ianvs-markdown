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
- virtualized Markdown file tree with cancellable filename/path search, ranked
  highlights, result counts, natural/modified sorting and directory-local refresh
- reveal active file, optional follow mode, keyboard navigation and per-workspace
  expansion, scroll, sort and favorites recovery
- inline new Markdown/folder and rename, duplicate saved copy, move picker,
  multi-selection, folder drop targets and native Trash with unsaved-edit protection
- External Files tree for individually opened files outside the workspace,
  with shared directory paths merged into expanded branches and synced with
  open tabs; paths stay on one line with middle ellipsis and full-path tooltips
- collapsible left sidebar with a draggable right edge and remembered width,
  plus a docked document outline inspector
- per-document mode, cursor, scroll, dirty state, encoding and line-ending UI
- atomic UTF-8 writes and external file-change notifications
- debounced crash recovery for open files and unsaved drafts
- macOS security-scoped bookmarks for restoring user-approved files and folders
- a one-time choice of Linefold as the default Markdown application, with a
  persistent preference in Linefold → Settings… (Command-,)
- Finder open requests, including files received before workspace recovery finishes
- native Mermaid diagrams in Live/Read, including SVG arrowheads and Chinese labels
- Read-mode links to local Markdown and headings, local image previews, and
  external web, HTML, and PDF links

Integration boundaries in the current desktop shell:

- Embedded local/remote images and Wiki embeds still need host resolution:
  images show a blocked placeholder and Wiki embeds show a reference. Ordinary
  image links open a preview. Open the document's containing folder as a workspace
  to grant sandbox access to sibling documents and assets. In Live mode, ordinary
  links retain their source-editing behavior; use Read mode to follow them.
- YAML is editable in Source and hidden in Live/Read. The package's optional
  Properties editor and heading-fold controls are not enabled in this app.
- Search matches names and relative paths in the workspace, and full paths for
  external files. It returns the best 200 matches with the total count; it is not
  a document-content search. Rename and move do not rewrite Markdown links.
  Find/replace, export, and an encoding or line-ending selector are not currently
  exposed.
- Open-document text, modes, and workspace visibility are recovered. Appearance,
  caret positions, and scroll offsets are not serialized across app launches.

The desktop shell integrates the published `ianvs_design: ^0.4.1` package.
Shared themes and controls use compact density and macOS system fonts.
Appearance follows the system by default; View → Use System Appearance restores
following after a manual override. Sidebar resize supports arrow keys, Home/End,
and double-click or Enter to reset. Its single divider sits at the sidebar's
right edge while retaining an 8-point drag target inside the sidebar.
Control-click opens the file context menu;
Command-click remains additive selection.

Specialized outline/tab typography is defined in `lib/src/desktop_typography.dart`.
It maps Apple's macOS text styles to system-font controls: 13/16 pt for primary
interface text, 12/15 pt for tabs, and 11/14 pt for secondary information. Use
these shared styles for app chrome so font family, leading, and tracking remain
consistent. The Markdown canvas keeps its own reading and monospace styles.

The app icon uses the folded-paper L mark. Its master artwork and generation
prompt are in [design/linefold-icon-v1.md](design/linefold-icon-v1.md). Regenerate
all macOS icon sizes from the repository root with
`bash app/tool/generate_app_icons.sh`.

The first-launch association prompt remembers both acceptance and refusal.
Settings shows the saved preference alongside the actual macOS default. Changing
the preference off restores the previous application when available, or asks for
a replacement. Linefold respects later changes made in Finder and does not
reapply its preference on launch. If macOS cancels or rejects a change, the choice
is still remembered and Settings offers a retry and Finder instructions.

Native association tests use an isolated preference domain and a simulated
workspace; run `bash app/tool/test_native_file_association.sh` from the repository
root. They do not change the machine's default applications. Run the Flutter
controller, settings, and Finder-delivery tests with `cd app && flutter test`.

Mermaid blocks use the shared [native vector pipeline](../packages/ianvs_mermaid/README.md):
merman renders in a background isolate, usvg expands markers and outlines system
font glyphs, and Flutter displays the result. Document diagrams have no embedded
WebView or pan/zoom gesture handler. Run `flutter test test/document_diagram_test.dart`
from `app/` for wheel, trackpad, Live editing, and async lifecycle regressions.

Local SVG previews use the same native text/marker expansion and Flutter vectors.
Run `flutter test test/svg_document_scroll_test.dart` from `app/` for input,
source-update, stale-result, error and disposal regressions. SVGs with unsupported
features such as HTML labels, filters or embedded images offer **Open in default
app**. The app has no embedded browser dependency or native SVG platform view.

To validate a local copy of the LLM principles corpus in both Live and Read modes,
run `flutter test test/llm_series_render_test.dart
--dart-define=LLM_SERIES_DIR=/absolute/path/to/llm-principles-series` from `app/`.
This optional test scrolls every Markdown document, checks table-link bounds,
and renders every Mermaid source through the bundled native vector pipeline.
Native library loading and external link navigation also require a macOS app
smoke test.

The desktop app requires macOS 12 or later. From the repository root, run
`make run` (or `make run-app`), or use Flutter directly:

```sh
cd app
flutter pub get
flutter run -d macos
```

To build a Release version for your Mac's architecture and install it into
`/Applications/Linefold.app`, run `make install` from the repository root.
Run it again to update the installed app,
then launch Linefold from Finder's Applications folder. To choose another
destination, use `make install INSTALL_DIR="$HOME/Applications"`. Installation
replaces the app bundle after verifying the new copy and preserves user data.

`example/` remains the small package-integration example. Product features
belong here instead of in the example application.

See [DESIGN.md](DESIGN.md) for the macOS visual contract and verification notes,
and [ARCHITECTURE.md](ARCHITECTURE.md) for dependency and recovery rules.

## Sidebar file management

Use the workspace **…** menu for new files/folders, reveal/follow, collapse,
refresh and sorting. Right-click a row for file operations, favorites and path
copying. A new item uses the selected folder (or selected file's parent); names
are edited inline. Return commits and Escape cancels. New Markdown names receive
`.md` when no extension is supplied. External-folder creation uses a dialog
because the external tree contains only open files, never a directory listing.

Arrow keys navigate the tree independently of the active document. Return opens;
Escape clears search and restores the previous tree position. Command-click
(or Control-click) toggles selection; Shift-click extends a range. Use **Move
selected** / **Trash selected**, or right-click for batch actions. Drop onto a
folder to move into it. To move back to the workspace root, drop onto its title,
a root-level file row, or the empty space below the tree. File-row and empty-space
targets show the destination folder while hovering. Touch/trackpad scrolling
continues to scroll the list. Favorites appear only after the first item is added.

Moves and copies refuse collisions. Trash uses the macOS Trash and checks all
open descendants for unsaved changes. Copies use saved bytes. Editing during a
pending Trash operation preserves the new text as a recoverable untitled draft.
Operations outside the workspace request a containing-folder grant; they do not
silently enumerate an individually opened file's parent. External directory rows
are synthetic groups: bulk commands affect only their opened files, and whole-folder
rename/move/Trash requires opening that folder as a workspace. Partial batch failures
report the number completed and identify each failed item.

Run all sidebar acceptance gates with `bash app/tool/verify_sidebar.sh` from the
repository root. Logs and rendered normal/narrow/search screenshots are written
to `app/build/sidebar-acceptance/`. See
[the acceptance matrix](design/sidebar-enhancement-acceptance.md) for coverage.


The Ianvs/macOS design integration and visual acceptance artifacts are documented
in [the acceptance record](design/ianvs-macos-acceptance/README.md). Run
`bash tool/verify_sidebar.sh` from `app/` for static analysis, all app tests,
native file-operation checks, and a macOS debug build. The visual fixture also
covers system-style light/dark surfaces, 840 × 560, 200% text, context menus,
and root-directory drop feedback.
