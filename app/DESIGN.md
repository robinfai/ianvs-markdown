# Desktop UI contract

The app follows macOS conventions within its existing Flutter shell. The
black, single workspace sidebar is a deliberate user preference. This is a
visual and interaction adaptation, not a claim that every Flutter control is
an AppKit control or that the app implements Liquid Glass.

## References

- [Apple: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Apple: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Apple: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple: Outline views](https://developer.apple.com/design/human-interface-guidelines/outline-views)
- [Apple: Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/)
- [Apple: Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
- [Apple: Menus](https://developer.apple.com/design/human-interface-guidelines/menus)

The app uses the published `ianvs_design: ^0.4.0` package. `IanvsTheme.build`
with compact density supplies Material controls, `IanvsTokens` and code
`IanvsTypography`. `desktop_theme.dart` maps the same semantic colors into
`IanvsMarkdownThemeData`; it does not maintain a second palette or add
`VisualDensity.compact` on top of Ianvs density. The source tree retains its
black background and specialized outline spacing.

Exact sizes below are app design decisions, not Apple-mandated dimensions.

## Shared rules

| Surface | App rule |
| --- | --- |
| Typography | macOS system UI font; 13-point primary controls, 11–12-point supporting labels; regular and semibold weights. |
| Palette | Neutral light/dark surfaces; blue for actions, focus, and links. Sidebar stays black in both appearances. |
| Shapes | Ianvs semantic control/panel/dialog radii; subtle separators. Tree rows keep 5-point corners. |
| Toolbar | At least 52 points with `IanvsToolbar`; sidebar toggle, centered Live/Source/Read control, outline toggle. No repeated filename or overflow action menu. |
| Tabs | At least 32 points, growing with text; filename appears here once, selected background, dirty indicators, close controls, new-document button, horizontal scrolling and reordering. All Documents exposes overflow and shortcut hints; selection scrolls into view. |
| Sidebar | 248 points by default, adjustable from its right edge within 180–560 points and available window space; width is recovered with the session. Native traffic-light space, Workspace root, inline filename/path search, optional favorites, and a virtualized file tree. |
| File tree | At least 28-point rows including margins, growing with text; 14-point hierarchy indents; separate disclosure and document/folder glyphs. Directory paths stay on one line, preserving both ends with `...` in the middle; tooltips show full paths. |
| Inspector | 224 points, right aligned, separator instead of a floating card; heading levels use indentation; empty state explains how to populate it. |
| Document | Maximum 720-point measure, 24/48-point responsive horizontal padding, shared colors for Live/Source/Read. |
| Status | At least 25 points; counts and document status wrap and grow with enlarged text or narrow windows. |
| Menus | Native application menus; in-window menus use neutral surfaces, 28–32-point minimum command rows, shortcut labels, and a checkmark gutter. |
| Dialogs | Bounded desktop width; concise title and explanation; Cancel, Don't Save, Save choices; default Save action and visible cancellation. |
| Feedback | Inline external-change notice with explicit recovery choices; dismissible error message; drag overlay names its action. |

## Interaction contract

- New/Open/Save/Save As/Close share workspace operations between window and
  native menu commands. Native Finder file selection remains system provided.
- Sidebar toggle uses Control-Command-S on macOS, avoiding Command-B (bold).
- Mode controls observe `modeListenable`, including changes from keyboard/menu.
- Command-1 through Command-9 select the first nine tabs in their current visual
  order, including after reordering; a missing tab is a no-op. These bindings
  work from Source, Live Preview, and workspace search, and appear in the native
  Window menu. They never change editor mode. The host disables library mode
  shortcuts using `enableModeShortcuts: false`, including the nested Source editor.
- Window controls have one primary home: workspace selection/search in the
  sidebar, view toggles/modes in the toolbar, new/close/switch in the tab strip.
  Open, Save, Save As and Appearance live in native File/View menus; native
  counterparts to direct controls remain for discoverability and keyboard use.
- Linefold → Settings… (Command-,) owns the default Markdown application
  preference. The startup question appears only while the choice is undecided;
  Escape means keeping the current application. Settings distinguishes the saved
  choice from the current macOS default and reports cancellation or failure.
- File rows expose accessible names and selection; directories expose expanded
  state and an activation action. Do not exclude descendant semantics without
  restoring the corresponding action on the parent.
- Search uses `IanvsTextField` inside the dark sidebar theme; it keeps the
  existing query controller, Escape/Down handling and filename/path results.
  `IanvsSearchField` is not used because its suggestions menu would duplicate
  the existing results tree.
- `IanvsResizeHandle` owns drag, keyboard and accessibility input. Arrow keys
  adjust width by 20 points, Home/End go to its current limits, Enter or a
  double-click resets the preferred width. Width persistence remains in the
  workspace controller.
- macOS Control-click and secondary click open the same context menu without
  opening a file. Command-click toggles selection and Shift-click selects a
  range. Move to Trash is separated and appears last in a destructive color.
- The default appearance follows the system. View → Toggle Appearance overrides
  it for this session; View → Use System Appearance restores live following.
- Keep content scrolling independent from navigation and inspector scrolling.

## Icon contract

- `app_icons.dart` is the single semantic icon vocabulary for the app shell.
  Use existing monochrome outlined/line glyphs; do not mix filled navigation
  symbols, emoji, or unrelated icon families.
- Toolbar glyphs are 16 points, file/folder glyphs 14 points, and close/disclosure
  glyphs 12 points. Glyph size is independent of the surrounding hit area.
- Action buttons use at least 28-point targets; file-tree disclosure controls
  use the compact row's disclosure gutter. Decorative empty/drop-state icons
  may be larger.
- Sidebar glyphs use the sidebar's secondary neutral color. Selection and focus
  use shared state colors, not a different icon family. Icon-only actions have
  tooltips; tree rows expose names and expanded/selected state.
- These are Flutter glyphs, not SF Symbols; native symbol rendering is not claimed.

## Review and verification — 2026-09-05

| Checked state | Result |
| --- | --- |
| Existing main window | Replaced inconsistent chrome, low-contrast tabs, and floating outline treatment. |
| Light/dark app | Observed in the live native window after state-preserving hot reload. |
| Native File menu | Observed New/Open/Open Folder/Save/Save As/Close Document commands. |
| In-window menu | All Documents is the sole overflow menu; file/view action overflow and duplicate controls are removed. |
| Source mode | Observed real source view; found and fixed stale mode-picker selection. |
| Minimum 840 × 560 layout | Widget test with macOS platform and inspector present; no layout exceptions. |
| Unsaved close | Test verifies Cancel preserves the draft and Save writes before closing. |
| File tree | Existing nested expansion regression remains passing. |
| Tab shortcuts | Tested Source and Live editor focus, missing tabs, search focus, ninth-tab visibility, reorder mapping, and native menu bindings. |
| Consolidated window | Observed after state-preserving hot reload: Workspace/search/tree sidebar, centered modes, one new button, no repeated toolbar title. |

Static analysis, all eight app tests, 751 library tests, and the macOS debug build pass. Native checks use the existing
running application; no user document was edited for the verification.
Screenshot inspection and widget semantics do not establish full VoiceOver
compliance. App colors currently use a fixed blue accent; automatically reading
the user's macOS accent color and active/inactive window treatment would require
additional native integration. Icons use the existing Flutter icon library.

## File association verification — 2026-09-23

- 71 Flutter tests and 9 native scenarios pass; static analysis and the macOS
  debug build pass.
- An isolated app copy with its own bundle identifier displayed the first-run
  question, remembered Keep Current App across an actual quit/relaunch, and
  opened Settings using Command-, with the real system default shown.
- Finder Open With delivered a temporary Markdown file into the running app and
  launched the closed app with another file; both opened in the correct tabs.
- Changes to the system association, restoration, cancellation, and rejection
  are covered using a simulated native workspace and isolated UserDefaults.
  The user's actual default Markdown application was left in place.

## Sidebar enhancements

Keep active-document blue separate from multi-selection gray and keyboard-focus
outline, using Ianvs state colors. File rows have a 28 pt minimum including
margins; search rows have a 48 pt minimum with a
parent-path subtitle and match highlights. Dirty state is a small trailing dot.
At 180 pt, reveal moves into the workspace menu and deep indentation is capped
so filenames retain useful space. The root title and empty space below the tree
are root move targets. Dropping on a file row moves into its parent directory;
these targets display the destination name while hovering. Rejected folder drops
never fall through to a surrounding root target.

The tree owns only open-file paths in External Files; a displayed ancestor does
not imply permission to enumerate it. An explicit containing-folder picker
precedes mutations where needed. Rename/new names are inline within the tree,
with a persistent inline validation message. Trash offers Save/Discard/Cancel
for unsaved descendants. Move/rename feedback states that relative Markdown
links have not been rewritten.


## Ianvs integration verification — 2026-09-29

See [the acceptance record](design/ianvs-macos-acceptance/README.md) for the
current checks, real Flutter render captures, ImageGen review board and its
prompt. The image-generated board is a visual presentation of the checked
screens, not evidence of executing the app or passing interaction tests.
