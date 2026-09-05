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
- [Apple: Menus](https://developer.apple.com/design/human-interface-guidelines/menus)

Exact sizes below are app design decisions, not Apple-mandated dimensions.

## Shared rules

| Surface | App rule |
| --- | --- |
| Typography | macOS system UI font; 13-point primary controls, 11–12-point supporting labels; regular and semibold weights. |
| Palette | Neutral light/dark surfaces; blue for actions, focus, and links. Sidebar stays black in both appearances. |
| Shapes | 5–6-point list/control corners, 8-point menus, 12-point dialogs; hairline boundaries. |
| Toolbar | 44 points; sidebar toggle, centered Live/Source/Read control, outline toggle. No repeated filename or overflow action menu. |
| Tabs | 32 points; filename appears here once, selected background, dirty indicators, close controls, new-document button, horizontal scrolling and reordering. All Documents exposes overflow and shortcut hints; selection scrolls into view. |
| Sidebar | 248 points; native traffic-light space, Workspace root, inline filename search, and file tree. No duplicate Notes/Search/Outline navigation or Appearance entry. |
| File tree | 26-point rows plus 1-point vertical margins; 14-point hierarchy indents; separate disclosure and document/folder glyphs. |
| Inspector | 224 points, right aligned, separator instead of a floating card; heading levels use indentation; empty state explains how to populate it. |
| Document | Maximum 720-point measure, 24/48-point responsive horizontal padding, shared colors for Live/Source/Read. |
| Status | 25-point bottom bar with word/character counts, Saved/Edited state, encoding, and line endings. |
| Menus | Native application menus; in-window menus use neutral surfaces, 28-point command rows, shortcut labels, and a checkmark gutter. |
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
- File rows expose accessible names and selection; directories expose expanded
  state and an activation action. Do not exclude descendant semantics without
  restoring the corresponding action on the parent.
- Search controls stay legible against the permanently dark sidebar.
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
