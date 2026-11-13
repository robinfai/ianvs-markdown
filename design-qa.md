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

---

# Design QA — directory rename overview (2026-11-12)

This section records the current rename-dialog work; the earlier header review above is preserved as historical evidence.

## Source and implementation evidence

- Source concept: `/Users/robinfai/.codex/generated_images/01a1cd5d-67dc-7171-afd1-8db1113de8dc/exec-4a924f4f-31ad-4a80-899b-8df01f1da97e.png` (1351 × 1164 pixels).
- Generated transparent icon atlas: `app/assets/icons/move-preview-atlas.png` (1774 × 887 pixels, four columns by two rows).
- Implementation: `app/build/workflow-ui/rename-blocked-zh.png`, `rename-partial-zh.png`, and `rename-partial-dark-zh.png`.
- Flutter widget-harness viewport: 1000 × 900 logical pixels, device pixel ratio 1, screenshots 1000 × 900. These are real Flutter component renders with synthetic workspace data, not captures of the installed macOS application.
- The concept has no declared device density. Compare hierarchy and the modal component, not the outside canvas or an inferred exact pixel scale. No images were stretched to claim a pixel match.
- Shared blocked state: one folder renamed in its current parent, two directory entries, one involved note, zero text replacements, a visible disabled update action, details initially collapsed.
- Additional states: partial external coverage with an enabled, explicitly labeled confirmed-links action; dark mode; expanded diagnostics; completed partial update.

## Comparison and iteration history

The source concept and rendered blocked dialog were opened together in the same comparison input. Full-resolution captures were readable enough to inspect headings, labels, action text, and icon shapes without a separate crop.

1. Initial capture exposed missing CJK fonts in the harness and a purple caution surface. Loaded local CJK test fonts and used the existing Ianvs warning token. Follow-up captures show legible Chinese and an amber/brown warning treatment.
2. Replaced the dialog's folder, document, link, warning, location, close and disclosure glyphs with the generated transparent atlas, as requested. Disclosure arrows rotate with expansion. Fixed harness capture timing by decoding the asset before capturing, so first-frame image loading is not mistaken for a missing icon.
3. Dark capture exposed low-contrast old-name and overview-heading text (P2). Set those foregrounds explicitly to the theme's `onSurface`; the final dark capture was reopened and checked after the fix.

## Required visual surfaces

- Typography: a 20-point heading, compact application body typography, clear secondary captions, wrapping action labels at narrow sizes. The harness uses local Heiti for reproducible Chinese glyphs; installed-app system font rasterization is outside this review.
- Spacing/layout: one white/dark modal, aligned before/after names, a single impact overview, one caution region, collapsed details and footer actions. No clipped default controls in the desktop captures. Existing 320-point-wide tests pass at text scales 1, 2 and 3.
- Colors/tokens: existing app surfaces and blue actions; warning uses the Ianvs warning token. Icons use an alpha tint, including dark and disabled colors. Dark text contrast was fixed and visually rechecked.
- Image quality/assets: the original generated PNG is bundled in the app. Eight separate atlas cells preserve transparent backgrounds; no hand-drawn replacement glyphs. Actual folder, note, link, warning, location, close and arrow renders were inspected.
- Copy: overview is Chinese; full paths and raw diagnostics appear only on expansion. Partial coverage says only confirmed links will be updated and repeats possible omissions on completion. Blocking explanations distinguish offline sources, destination collisions, dirty notes and unparseable dependencies.

## Intentional product adaptations

The implementation uses existing compact native typography and button styling rather than reproducing the enlarged concept canvas literally. A separate collapsed link-changes row keeps source diffs reachable without expanding diagnostic logs. Recovery-copy disclosure remains visible before execution. These preserve existing application behavior and were retained intentionally.

## Verification and limits

- 201 related Dart regression tests passed before icon integration; 88 affected UI/execution regression tests passed after integration.
- Final Chinese overview checks pass in light partial, light blocked and dark partial states (3 tests), including detail expansion and explicit execution of the displayed plan.
- Real production Swift transaction suite passed, including external offline placeholders, changed-placeholder rejection, source-placeholder rejection, cross-parent behavior and restart reconciliation.
- `flutter analyze --no-pub`: no issues. `git diff --check`: passed.
- This review does not claim a fresh installed-app launch or an end-to-end test against the user's real iCloud workspace.

No actionable P0/P1/P2 issue remains in the reviewed rename-dialog scope. Minor P3 follow-up: native system font appearance can differ slightly from the deterministic test fonts.

final result: passed

---

# Rename confirmation refinement — 2026-11-12

The user's follow-up replaces routine preview confirmation with a decision only when a rename carries uncertainty. Source: `/var/folders/k2/8qbf3nrs7t1749d198rw0df40000gn/T/codex-clipboard-ca40e3db-d3fe-4ce8-9b2a-0d5e9c7018e9.png` and the approved follow-up rules. This is a deliberate simplification of the earlier mock, not a pixel reproduction of the large screenshot.

- A submitted same-parent rename with complete coverage executes through the existing native preflight, including zero-edit and confirmed-link-update cases. The sidebar reports the result and offers optional receipt details.
- Incomplete coverage shows a short warning with Back / Rename anyway. Zero replacement counts, relocated-but-unchanged notes, directory manifests and technical coverage counts are absent from this prompt; diagnostics remain collapsed.
- Known blockers explain the issue without offering automatic or raw rename bypass. Returning preserves the original path and any unsaved contents.
- Moves and batch operations retain their explicit review. Execution failures remain single shot, with receipts/recovery available and no fallback rename.

Final Flutter harness captures (1000 × 900 pixels, DPR 1): `app/build/workflow-ui/rename-risk-partial-zh.png`, `rename-risk-blocked-zh.png`, `rename-risk-partial-dark-zh.png`. The light and dark partial-risk captures were opened together and checked at full resolution. Text, icon contrast, compact layout, collapsed details and button labels are legible and unclipped. No density normalization or claim of native installed-app capture is made.

Verification: 170 related widget, sidebar, planner and execution tests passed; static analysis reports no issues; `git diff --check` passed. Added coverage for automatic zero-edit and inbound-link renames, explicit partial-risk choice, known blockers, cancelled/stale intent, mismatched destinations, execution failure, on-demand completed receipts and retained cross-parent confirmation. The sidebar progress indicator hides while a decision dialog is current, so it does not animate indefinitely behind the prompt.

No actionable P0/P1/P2 issue remains in this refinement's reviewed scope.

final result: passed

---

# Rename/move result dialog design QA

- Date: 2026-11-13.
- Scope: implement the approved path presentation direction in the existing Flutter app.
- Source visual truth: `/Users/robinfai/.codex/generated_images/01a1d3d3-b933-72e3-8126-f80e70bb53e5/exec-f836b324-e28c-4a7b-81a1-168aa2eb911e.png`.
- Implementation screenshot: `app/build/workflow-ui/move-result-zh.png`.
- Full-view comparison: `app/build/workflow-ui/move-result-comparison.png`.
- Focused path comparison: `app/build/workflow-ui/move-result-paths-comparison.png`.
- Additional screenshots: `app/build/workflow-ui/move-result-dark-zh.png`, `app/build/workflow-ui/move-result-narrow-zh.png`.
- State: completed directory rename, operation details and full paths expanded; updated files and technical details collapsed. Data matches the supplied historical folder names and long Markdown filename.
- Viewport: 1000 × 1000 logical pixels, density 1; narrow case 390 × 1000, density 1, text scale 2.
- Normalization: source 1184 × 1328 pixels; source modal cropped to 1156 × 1298 and proportionally resized to 528 × 593. Implementation modal cropped from (236, 178)–(764, 822), 528 × 644. No aspect-ratio stretching.
- Rendering: real Flutter widgets in the repository's widget harness, using the desktop theme, local Chinese font and Menlo for path text. This is component visual evidence, not native desktop acceptance; browser console checks do not apply.

## Findings

No remaining actionable P0/P1/P2 findings within the requested direction.

- Typography: paths use readable 13-point monospace text with 1.6 line height, wrap without truncation, and highlight the changed suffix. Names use the existing body hierarchy rather than large heavy text. Chinese font fallback and exact raw clipboard values were checked.
- Layout: original and new paths are separate rows on a muted surface with aligned copy controls. Narrow screens and enlarged text stack labels above paths. Dialog content scrolls while actions remain reachable.
- Tokens: path surface uses the existing Ianvs chrome token for both light and dark themes; text, dividers, accent and success indicators use theme colors.
- Assets: existing folder, document, location and disclosure atlas retained; copy, success and settings controls use Material icons. No new raster assets or approximated icons.
- Content: raw execution logs and journal IDs remain available under technical details, separately from the updated-file disclosure. Failed operations retain their high-level warning and selectable diagnostic message. The summary, names and recovery action preserve existing behavior.
- Intentional differences from the generated mock: native typography/tokens and existing control dimensions are retained; counts remain in disclosure titles rather than decorative pills; helper text occupies a subtitle for reliable localization. The mock's decorative gradients and label pills are not required by the requested direction.

## Comparison history

1. Initial rendered inspection found insufficient surface separation and overly narrow path columns at 390 pixels with 2× text. Fixed by using the Ianvs chrome surface and switching to a stacked path layout at narrow widths or larger text scales.
2. Re-captured both themes and the narrow state. Full-view and focused combined comparisons confirm clear path grouping, changed-suffix emphasis, copy alignment and collapsed logs. Directory icon fallback now also reads the initial result receipt when no preview plan is supplied.

## Validation

- 67 tests passed across result layout, move preview, rename confirmation, rename overview, recovery and directory-move flow suites.
- Interactions: original/new copy returns exact unmodified paths; disclosure toggles independently; filenames and logs stay hidden until requested; recovery still requires its existing confirmation.
- Flutter analyzer: no issues in the five changed Dart files.
- `git diff --check`: passed.
- Widget framework exceptions: none in final runs.

## Implementation checklist

- [x] Separate original/new paths and add exact copying.
- [x] Highlight changes and allow full wrapping.
- [x] Fold updated files and technical logs independently.
- [x] Check Chinese light/dark and narrow enlarged-text layouts.
- [x] Preserve rename, failure and recovery flows.

## Follow-up polish

Native macOS/iOS font rendering and clipboard integration were not exercised in a running app; clipboard calls were verified at the platform-channel boundary.

final result: passed
