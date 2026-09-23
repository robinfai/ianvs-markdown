# Round 2 imagegen prompt

Mode: built-in `image_gen`; one generated `ui-mockup` convergence proposal. No CLI or external API runner.

Reference images, both inspected with `view_image` before generation:

- Primary: `../../screenshots/04-empty-source.png`
- Supporting: `../round-1/mockup.png`

```text
Use case: ui-mockup
Asset type: second-round convergence mockup for an existing macOS Markdown editor. This is a review proposal, not proof of an implemented UI.
Primary request: produce one precise, understated desktop application mockup illustrating only the approved minimal usability refinements from round one. Keep the current product layout and visual identity.
Input images: Image 1 (04-empty-source.png) is the PRIMARY reference image: a fresh real empty Source-mode screenshot. Preserve its black workspace sidebar, toolbar, tabs, blank white document surface, fixed right outline and bottom status bar. Image 2 (round-1/mockup.png) is a SUPPORTING reference image showing the previous review proposal only; do not copy its blue tab underline, review cards, shadows, heading colors, or changed document typography. Neither image is an edit target.
Style/medium: high-fidelity raster UI mockup with crisp macOS system typography and neutral hairline separators. Landscape composition, readable at desktop size. Flat application window; no perspective and no decorative surrounding scene.
Composition/framing: one large application window, plus a narrow separate annotation band beneath it labeled "Round 2 — proposed refinements". Keep the app's existing proportions and hierarchy: black left sidebar with Workspace, fixtures root, Search Files, existing file names; compact 44 pt toolbar with the existing sidebar toggle, centered Live / Source / Read modes and outline toggle; compact 32 pt tabs with one new-document plus and one all-documents chevron; white editor; fixed 224 pt right outline; compact bottom status. The dimensions are the product design contract, not measurements from the supplied screenshots.
Application state: Source is selected. Empty active document is "Untitled-9.md". Preserve the neutral selected mode and neutral active tab underline; do not introduce a blue tab underline. Preserve the right outline's existing empty state exactly: "Outline", "No Headings", "Add headings to navigate your document." Preserve "0 words", "0 characters", "Saved", "UTF-8", "LF" in the status bar.
Only visible refinements: keep the visible mode labels exactly "Live", "Source", "Read", with at least a 28 pt segment target within the existing toolbar. Show a small normal tooltip below Source reading exactly "Source — edit Markdown source". At the document's existing first-line text origin, add a single understated non-interactive placeholder in a secondary neutral text color reading exactly "Start writing Markdown…". Keep the rest of the editor completely blank, without cards, buttons or instructional paragraphs.
Annotation band: three concise plain columns separated by hairlines, not rounded cards. Column 1: "1  Clear mode names" then "Button role · selected state · 28 pt target". Column 2: "2  Measured tab labels" with a small two-tab crop: "Markdown体验.md" fully readable, and "A very long filename…" naturally ellipsized. Keep original close glyph and neutral selection. Supporting text: "Actual font width · existing full-path tooltip". Column 3: "3  Empty Source hint" then "Visual hint only · never saved as content". Do not show new empty-state designs for Live or Read.
Color palette: same black sidebar, white canvas, soft neutral chrome and restrained existing blue accent. No new palette.
Constraints: preserve black sidebar, three modes, tabs, fixed right outline, current monochrome line icon family, compact density and all existing action placement. No UI redesign. Do not enlarge every icon or tab, do not duplicate New/Open actions, do not add a logo, content panel, floating cards, illustrations, gradients or invented navigation. Do not imply accessibility has been verified by the generated image. Any invisible semantics behavior is a proposal described in the annotation band. Retain readable mixed Chinese and English filenames without claiming a fixed final pixel width.
```
