# Design QA — Linefold compact header

## Scope and source

The selected user attachment is `.product-design/header-redesign/selected-target.png`.
The user's requested changes are a compact sidebar without “Workspace”, “Linefold” beside the native traffic lights, tabs above the document context and mode controls, and a centered document when the editor exceeds its maximum content width. The follow-up attachment `mode-menu-request.png` supersedes the segmented mode control: the user requested a vertically centered icon-and-text dropdown.

The previous unrelated QA report is preserved at `.product-design/header-redesign/previous-design-qa.md`.

## Visual comparison

- Reference: 1556 × 1011 source pixels.
- Native capture: 2400 × 1560 pixels, representing a 1200 × 780 point macOS window at 2×.
- Both are normalized to 1200 × 780 using Lanczos; no application pixels are redrawn.
- Full comparison: `.product-design/header-redesign/comparison-final-full.png`.
- Header comparison: `.product-design/header-redesign/comparison-final-header.png`, identical top 180-point crops.
- The two combined comparisons were opened and inspected together.
- `native-final.png` is a fresh capture after the final mode-menu change and native regression checks. `native-mode-menu-open.png` shows all three choices with icons and the current-mode checkmark. `comparison-mode-menu.png` compares identical 600 × 354-pixel top-right regions of the before and after captures at 1:1 scale.

## Visual findings

No actionable P0–P2 visual discrepancy remains in the requested scope.

- Structure and spacing: the sidebar starts with a 32-point app-name row, followed immediately by the existing project row and search. The redundant “Workspace” caption and 52-point empty spacer are gone. The main header is a 44-point tab strip over a 40-point context row.
- Typography: the existing system font and document styles remain. Active tabs have stronger weight; inactive close buttons appear on hover or keyboard focus. Dirty documents retain their blue indicator.
- Controls: sidebar toggle, tabs, open-document menu, New, and outline toggle occupy the first row. A single icon + current mode label + chevron sits at the right of the second row in a 32-point control. Its icon, text, and arrow share the same vertical center, with equal top/bottom gutters. The menu exposes Live, Source, and Read with icons and a current-mode checkmark. Keyboard navigation, focus restoration, and selected semantics are verified.
- Context: the breadcrumb reflects the real workspace-relative path, external parent directory, or unsaved document state, with middle ellipsis and a full-path tooltip.
- Document placement: all three modes use equal left/right insets within the editor pane, excluding both side panels. The existing 720-point maximum width remains. Narrow panes retain 24- or 48-point minimum gutters.
- Color and assets: existing neutral surfaces, blue selection accents, sidebar colors, and project icons are reused. No decorative imagery or new asset set was needed.
- Responsiveness: tests cover 1600 × 1000 and 840 × 560, all panel combinations, all editor modes, and 200% text. The narrow/large-text screenshots show no header overlap or overflow.
- Expected differences: actual open documents and external paths differ from the reference. Document font metrics, table wrapping, and the existing maximum reading width were retained. Native traffic-light appearance depends on window activation; the purple Computer Use badge seen in some captures is an automation overlay.

## Iteration history

1. The first visual pass put the modes too close to the context-row edges; constrained them to 32 points with gutters.
2. Native titlebar handling consumed top-row clicks and tab drags. AppKit now reserves the app-name area for window dragging and routes the remaining header region to Flutter. Center clicks, sidebar/outline toggles, tab dragging, and native window zoom were exercised.
3. The lazy tab list underestimated its length with many variable-width names. Selection reveal now uses measured tab widths. New and distant selected tabs are fully visible.
4. Dragging a tab with an active tooltip produced a Flutter overlay layout error. Drag feedback now uses an independent visual proxy, with tooltips disabled during reorder.
5. Native testing found a macOS accessibility-bridge crash when a modal document popup closed while the underlying document/scroll semantics changed. Delaying selection and changing semantics visibility did not reliably resolve it. The document menu now uses `MenuAnchor`, matching the project's existing design-system menu approach. The full formerly failing chain (new tab → reorder → close → GLOSSARY → feature-matrix via menu) succeeded in the rebuilt native application. No new crash report was created; the latest remains the earlier `Linefold-2026-09-30-123351.ips`. This verifies the app-level regression path, not a general Flutter engine fix.
6. The user then requested a mode dropdown and flagged vertical text alignment. Replaced the segmented control with a centered icon/text/chevron button and MenuAnchor choices. Layout tests assert the button center matches the context row and that the text/icons share its center; native captures confirm the result.

## Verification

- `flutter test` in `app`: **152 passed, 1 skipped**.
- The full passing suite includes header and editor-affordance checks for centering, breadcrumb updates on save, large text, long variable-width tabs, dragging, closing, mode-menu accessibility/keyboard selection, and read-mode content protection.
- `flutter analyze` in `app`: **no issues**.
- Dart format check for all changed Dart files: **passed, 0 changes**.
- `git diff --check`: **passed**.
- `flutter build macos --debug`: **passed**.
- Native mode selection was exercised through the new menu: Live → Source by mouse, Source → Read by keyboard, and back to Live. Wide Live and both-panels-hidden captures were refreshed with the final implementation. Earlier wide Source/Read captures remain historical layout evidence.
- The normal 1200 × 780-point window was restored with feature-matrix active in Live, both panels visible, and the sidebar scrolled back to the top. The native app-name double-click zoom also passed.
- Dark/narrow/large-text captures were refreshed from the final full test run.
- User document contents were not changed. Only disposable empty tabs were used for creation/close/reorder checks.

## Final review

The final full-view, focused-header, and mode-menu before/after comparisons were reviewed at matched scales. Dark and narrow 200% text captures were inspected. No actionable P0–P2 issue remains in the requested header, centering, or mode-menu scope.

final result: passed
