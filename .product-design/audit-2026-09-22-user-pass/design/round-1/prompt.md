# Round 1 imagegen prompt

Mode: built-in image_gen; one generated `ui-mockup` design review sheet, using the existing screenshot as a reference image. This is a proposal, not a screenshot of implemented behavior.

Input reference image: `/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22-user-pass/screenshots/01-initial.png`

```text
Use case: ui-mockup
Asset type: a high-fidelity design review sheet for an existing macOS Markdown editor, landscape, clean and precisely legible.
Primary request: use the reference screenshot to illustrate three conservative usability refinements, retaining almost all existing design. Show a large main app window above and three small clearly separated detail panels below. The main app remains recognizably the exact existing app; this is not a redesign.
Input images: Image 1 is a reference image showing the real current application, not a background to blindly copy and not an edit target.
Style/medium: realistic crisp macOS software UI mockup, system UI font, fine neutral separators, 5–6 point corners, no decorative artwork.
Color palette: preserve the black workspace sidebar; white document canvas; very light neutral gray toolbar, tabs, and right outline; blue action, selection, focus and link accents only. Do not introduce any additional palette.
Composition/framing: the large app window preserves left black workspace sidebar with search and file tree, 44 point toolbar, 32 point horizontal document tabs, central Markdown document, 224 point right outline and slim status bar. Preserve the reference's visible Markdown headings, inline formatting, lists, checkbox list, quotation, fenced code, indented code and table. Keep the existing three centered modes Live / Source / Read. Keep the existing sidebar and outline icon buttons in the toolbar and one plus new-document button plus all-documents chevron in the tab strip. No duplicated title or filename in the toolbar. No new navigation, no floating cards over the main document.
Main refinements: make each mode segment have at least a 28 point hit area without increasing the toolbar height; preserve selected neutral segment and show one restrained blue keyboard focus ring on Source in its detail panel only. Give the Chinese document tab enough width to show Markdown体验.md completely while retaining the 12 point close glyph inside a 28 point target. Other tabs may remain ellipsized as in the source. Do not increase every tab to the same large width.
Detail panel 1: caption “1  Clear modes”. Show only the three modes Live / Source / Read, with a subtle example tooltip underneath Source reading “Source — edit Markdown”. A small supporting line reads “28 pt target · explicit selected state”.
Detail panel 2: caption “2  Readable document tabs”. Show one selected tab with exact filename “Markdown体验.md” and a close glyph, plus one longer ellipsized tab “Project notes…”. A small supporting line reads “Measure text · preserve full-path tooltip”.
Detail panel 3: caption “3  Empty document — proposal”. Show a small empty white editor area with a caret and a subtle non-interactive hint at its text origin reading “Start writing Markdown…”. It must not look like actual inserted document content. A supporting line reads “Only while empty · disappears on input”. Label this explicitly as a proposed state, because the supplied reference contains an existing document, not an empty document.
Constraints: black sidebar, three modes, tabs, right outline and all existing document formatting are invariant. Keep understated macOS appearance and the current compact density. This review sheet must never claim keyboard, VoiceOver, hit areas, or empty-state behavior has been verified by a screenshot. Do not add action buttons, duplicate New/Open shortcuts, marketing headings, colored gradients, illustrations, new icon family, oversized text, floating toolbar, emoji, shadows around content blocks, or an entirely new layout.
```
