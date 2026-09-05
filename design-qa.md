# Design QA — Ianvs Markdown Native macOS Editor Redesign

## Comparison target

- Source visual truth: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/redesign/visual-target-native-primary.png`
- Drag/dirty interaction target: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/redesign/visual-target-native-drag-unsaved.png`
- Final native implementation capture: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/redesign/implementation-native-final.jpeg`
- Full-view comparison: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/redesign/qa-reference-vs-implementation-final.png`
- Focused chrome/document comparison: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/redesign/qa-focused-chrome-and-document-final.png`
- Annotated before/target comparison: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/redesign/annotated-current-vs-native-target.png`

## Viewport and normalization

- Source pixels: `1536 × 1024`.
- Native implementation pixels: `1225 × 768`, captured from the running Flutter macOS application including integrated window chrome.
- Native viewport: `1225 × 768` capture surface; browser CSS size and `deviceScaleFactor` do not apply.
- Normalization: the source was centered-cropped to the native implementation's `1225 × 768` aspect ratio and downsampled with Lanczos. Both normalized images were placed at equal size in the `2450 × 812` full-view comparison.
- Focused comparison: identical `1225 × 390` top regions from the normalized source and implementation, combined into `2450 × 432`.
- State: light theme, saved `Playground.md`, Preview selected, three visible tabs, first outline heading active, native title bar visible.

## Findings

No actionable P0, P1, or P2 differences remain.

- Fonts and typography: both directions use macOS system sans-serif with compact system labels and an editorial document hierarchy. The implementation's 31-point title, 21.5-point section heading, 15-point body, 1.62 body line height, and SF Mono-compatible code treatment preserve the reference hierarchy and wrapping. Native rasterization and the implementation's slightly stronger title weight are acceptable platform variation.
- Spacing and layout rhythm: the 372-point navigation pane, 760-point document measure, 112/96-point horizontal document padding, 62-point toolbar, 44-point tabs, hairline separators, and 32-point status bar reproduce the reference region proportions at the native capture size. The navigation pane collapses below 1040 points. No overlap, clipping, or overflow is visible.
- Colors and visual tokens: warm white content, cool neutral chrome, charcoal text, muted gray labels, and restrained `#167B82` teal accents align with the reference. Teal is limited to active indicators, links, and state feedback; selected rows do not use large tinted capsules.
- Image quality and asset fidelity: the design contains no raster product imagery or decorative illustration. Controls use the project's existing Flutter icon library with consistent optical sizes; no inline SVG, emoji, CSS-art equivalent, gradient, or placeholder asset was introduced.
- Copy and content: the standalone editor now opens with “Ianvs Markdown Playground,” a concise product introduction, and realistic Markdown examples. New/Open/Save/Saved, mode labels, drag instructions, word/character counts, line-ending metadata, and tab names are coherent in context.
- Icons and controls: New, Open, Save/Saved, overflow, close, dirty-dot, mode, and file icons share a flat native-toolbar treatment. Filled tonal/pill actions were removed; hover and pressed feedback uses quiet neutral surfaces and six-point control radii.
- Interaction states: multi-tab creation/selection/close, open, edit, dirty state, save/save-as, and close confirmation remain functional. The canvas-only drag target keeps the navigation pane visible, uses a thin dashed outline, and exposes explicit supported extensions. The drag overlay and dirty indicator have widget-test coverage.
- Accessibility and responsiveness: buttons retain tooltips and semantic labels, keyboard shortcuts remain available, tab close controls appear for active/hovered tabs, and the navigation pane collapses before it can crowd the editor. Text and controls remain readable at the minimum window size.

## Comparison history

### Iteration 1 — blocked

- [P2] Default expanded YAML properties pushed the first document heading substantially below the source's above-the-fold position.
- [P2] The implementation sidebar and document inset were visibly narrower than the normalized source, weakening the intended editorial hierarchy.

Fixes made:

- Switched the default example to a clean document opening while retaining Markdown editing behavior.
- Increased navigation width from 300 to 372 points, moved its collapse breakpoint from 860 to 1040 points, and increased document insets to 112/96 points.
- Added the target's document title and introductory paragraph to realistic example content.

Evidence: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/redesign/qa-reference-vs-implementation-iteration-1.png` and `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/redesign/implementation-native-iteration-1b.jpeg`.

### Iteration 2 — blocked

- [P1] Hiding the front-matter card while leaving the demo YAML source active exposed the metadata block as oversized editable source text, materially changing the first screen.

Fix made:

- Removed the synthetic YAML header from the default playground document. Front-matter support remains in the package; the editor example now opens in the clean, reference-matched authoring state.

Evidence: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/redesign/implementation-native-iteration-2.jpeg`.

### Iteration 3 — passed

- The final same-size full-view and focused comparisons show aligned sidebar/content proportions, first-screen content order, toolbar density, tabs, type hierarchy, canvas width, accent restraint, and status-bar placement.
- Remaining differences are expected: the source includes a synthetic `README.md` tab/files group while the live capture shows two newly created untitled documents; the native implementation renders real system glyph/font metrics; Computer Use contributes a small purple focus indicator outside the product UI at the upper-left edge.
- No actionable P0/P1/P2 issue remains.

## Verification

- Target and implementation images were opened and judged together in both full-view and focused same-size comparison inputs.
- `flutter analyze example/lib/main.dart example/test/widget_test.dart`: passed with no issues.
- Root test suite: 742 passed.
- Example test suite: 5 passed, including open/tab/save, dirty-state, and drag-overlay coverage.
- macOS debug build: passed and launched successfully.
- Native interaction checks: created multiple tabs, returned to the first tab, and verified toolbar/tab/status/editor layout in the running app.
- No browser console applies to this native Flutter build; no launch or layout exception was observed.

## Follow-up polish

- [P3] A future native menu pass could mirror New/Open/Save actions in the macOS menu bar and expose recent files without changing the current visual system.

final result: passed
