# Design QA — Editorial Navigator Sidebar Selection Refinement

## Comparison target

- Source visual truth: `/Users/robinfai/.codex/generated_images/01a0256c-cb60-7f53-a4ce-469f867b15bc/exec-42940529-fe16-452e-9d93-3350a4f0971a.png`, refined by the user's request to remove the large tinted selection surfaces and heavy accent rails.
- Before-state evidence: `/var/folders/k2/8qbf3nrs7t1749d198rw0df40000gn/T/codex-clipboard-8c736f73-95d3-44d9-aeb8-e00bdc817544.png`
- Final implementation capture: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/design-qa/implementation-sidebar-refined-preview.png`
- Hover-state capture: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/design-qa/implementation-hover-edit-final.png`
- Active source-edit capture: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/design-qa/implementation-active-block-final.png`
- Full-view before/after comparison: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/design-qa/comparison-sidebar-before-after.png`
- Focused sidebar comparison: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/design-qa/comparison-sidebar-focused.png`

## Viewport and normalization

- Original direction pixels: `1487 × 1058`.
- Before-state pixels: `2360 × 1624` (`2×` density of the same desktop aspect ratio).
- Implementation pixels: `1117 × 768`, captured from the native macOS window including chrome.
- Native macOS window capture: `1117 × 768` points/pixels as reported by the capture surface. A browser CSS viewport and `deviceScaleFactor` do not apply to this Flutter macOS build.
- Density normalization: the before-state capture was downsampled to `1117 × 768`; the implementation remained `1117 × 768`. Both were placed in the same `2234 × 768` comparison input. The focused comparison crops the identical `284 × 430` sidebar region from each normalized capture.
- State: light theme, saved document, Preview selected, YAML front matter collapsed, first outline heading active.

## Findings

No actionable P0, P1, or P2 differences remain.

- Fonts and typography: the implementation uses the macOS/Flutter system sans-serif and SF Mono fallback. Document-title, heading, body, and code hierarchy match the target after reducing Markdown heading scale and preserving the larger front-matter-derived title.
- Spacing and layout rhythm: the mode rows now use a 42-point desktop control height and 6-point radius, removing the oversized capsule treatment. Outline rows use a tighter 34-point rhythm with a short 16-point locator rather than a full-height rail. No clipping or overflow is visible at the captured desktop size.
- Colors and tokens: mode selection is now a neutral, low-opacity blend derived from the theme's text and sidebar surfaces; teal is limited to the selected mode icon and the outline locator. The two kinds of selection no longer share the same tinted-card treatment and remain legible with both light and dark theme tokens.
- Image quality and asset fidelity: the target contains no raster product imagery. Icons use Flutter's Material icon library rather than approximated image assets. Mermaid remains a real generated SVG, not a placeholder.
- Copy and content: mode labels, keyboard shortcuts, document title, YAML disclosure, Markdown body, table, and code sample match the selected direction. Settings, Help, and a drag handle were intentionally not fabricated because the existing product has no corresponding routes or reorder behavior.
- Icons and interactions: Preview, Source, and Read remain full-row targets. The active mode uses neutral surface, icon color, and text weight; outline navigation uses a short locator and text weight without a filled card. Preview/Source switching and moving the active outline marker to Diagram injection were verified in the running app.
- Accessibility and responsiveness: mode controls and rendered blocks expose semantic labels; keyboard shortcuts and visible focus/edit states are present; practical control heights are at least 40–46 points. The navigation pane collapses below its configured breakpoint and the content column remains constrained.

## Comparison history

### Iteration 1 — blocked

- [P1] The first implementation used a centered, effectively full-width document column, making the table and code block substantially wider than the reference.
- [P1] Read mode reverted to the older expanded metadata card, breaking cross-mode information hierarchy.
- [P2] The native title bar and Flutter app bar appeared as separate rows instead of the target's single integrated header.

Fixes made:

- Set the example reading column to 640 points and aligned it to the leading edge of the main canvas.
- Passed compact front matter and document-title settings through Preview and Read modes.
- Enabled a transparent, full-size macOS title bar and moved Saved/overflow into the integrated Flutter header.
- Reduced Markdown heading/body scale to restore the target hierarchy and line wrapping.

### Iteration 2 — passed

- Post-fix evidence: `comparison-live-final.png` and `comparison-hover-final.png`.
- The sidebar/main-column proportions, title hierarchy, collapsed YAML row, hover edit treatment, table width, code block, and top-bar actions now preserve the source design intent.
- Remaining variation is limited to expected native-font rasterization, the source mock's denser non-heading outline entries, and the deliberate omission of non-functional Settings/Help/reorder controls.

### Iteration 3 — sidebar selection refinement, passed

- [P2] User feedback identified the mode selection as an oversized pale-teal capsule with a heavy right rail, and the outline selection repeated the same filled-card language with a heavy left rail.

Fixes made:

- Replaced the mode's teal fill and 3-point edge rail with a neutral low-opacity selection surface, 6-point radius, compact vertical rhythm, and localized icon emphasis.
- Removed the outline selection fill and full-height rail; the active heading now uses a 2 × 16 point locator plus text-weight change.
- Added restrained neutral hover and focus treatments while preserving the full row hit target.
- Post-fix evidence: `comparison-sidebar-before-after.png` and `comparison-sidebar-focused.png`.
- The focused comparison shows distinct hierarchy without duplicated tinted cards; no actionable P0/P1/P2 issue remains.

## Verification

- `flutter analyze`: passed with no issues.
- Root `flutter test`: 22 tests passed.
- Example `flutter test`: 3 tests passed.
- Clean macOS build and launch: passed.
- Primary interactions checked in the running app for this pass: Preview/Source switching and outline navigation to Diagram injection, followed by restoring the top Preview state. The prior full-flow checks for Read, block editing, YAML disclosure, Saved state, and Mermaid rendering remain covered by Iteration 2.
- Runtime log check: no launch, layout, or interaction exceptions on the clean run. `flutter_svg` still reports non-fatal unsupported `<filter>` and `<marker>` elements from the generated Mermaid SVG; the diagram renders, and a browser/resvg-backed diagram surface remains optional follow-up fidelity work outside this selected-screen comparison.

## Follow-up polish

- [P3] If one-row task editing is desired, split contiguous GFM task lists into item-level editor projections while preserving the original source ranges.
- [P3] Replace the example's `flutter_svg` Mermaid surface with a browser-capable or rasterized renderer when complete marker/filter parity is required.

final result: passed
