# Markdown Rendering Design Audit

Date: 2026-08-22

## Audit scope

Desktop Markdown editor rendering across live preview, source, reading, rich
content, block activation, and dark theme states.

## User goal and accessibility target

Help writers scan a long Markdown document, understand the current mode, move
between reading and editing with confidence, and read tables, code, diagrams,
metadata, and safety states without excessive visual noise. Target keyboard and
screen-reader clarity with visible focus, named controls, and at least 44 px
primary targets where practical.

## Accepted evidence

1. `01-live-preview-reference.png` — user-provided maximized live preview.
2. `02-live-preview-app.png` — current live preview at a normal desktop window.
3. `03-source-mode.png` — full source editing mode.
4. `04-reading-mode.png` — reading mode with document outline.
5. `05-reading-rich-content.png` — code, Mermaid, and blocked-image area.
6. `06-live-block-edit.png` — attempted block activation; no visible edit state.
7. `07-dark-live-preview.png` — dark theme rendering.

## Strengths

- The three-mode model is coherent and source mode preserves the Markdown
  mental model.
- Reading mode's outline provides useful orientation for longer documents.
- Code blocks, safe-image messaging, metadata parsing, and save state are
  represented consistently.
- The UI is restrained and avoids decorative visual noise.

## UX risks

### P0 — Reading width is uncontrolled

The maximized reference stretches metadata, paragraphs, tables, code, and
diagrams almost edge to edge across a 3456 px window. The reading measure is far
beyond a comfortable long-form line length, and tables become two oversized
50/50 columns. Add a centered document canvas with a maximum reading width
(roughly 760–880 px), while letting diagrams and wide tables opt into a wider
content lane.

### P0 — The promised click-to-edit transition is invisible or unreliable

Two direct attempts to activate rendered heading/body blocks produced no
visible active editor state. Even when activation works, rendered blocks have
no persistent edit cue and the text cursor alone is easy to miss. Add a visible
hover/focus treatment, a small edit affordance, and deterministic activation
for both pointer and keyboard.

### P1 — Toolbar mode and action hierarchy is too implicit

The first three modes are icon-only, the selected state is subtle, and editing,
history, formatting, save, reset, and theme controls are split across two bars.
Use a labeled segmented mode switch, keep document actions together, and group
formatting actions by meaning. Hide or disable formatting controls more clearly
in Reading mode.

### P1 — Metadata dominates the document

Four small fields occupy a large nested-card area before the title. Default to
a compact metadata summary row with an explicit disclosure for details; retain
the full grid for metadata-heavy documents.

### P1 — Mermaid loses directional meaning

The captured flowchart shows connector lines without arrowheads, so a directed
flow reads as an undirected chain. Treat this as a content-fidelity issue, not
only polish: fix the SVG marker path or use a renderer that preserves markers,
then add zoom/reset controls without turning the diagram into another nested
card.

### P2 — Status is duplicated and low-value chrome is persistent

Saved state appears in the header while a disabled cloud action remains in the
formatting bar. Keep one save/status control and surface transient confirmation
near it. The footer mode/character count can become a lighter status strip or
appear only in editing modes.

## Accessibility risks

- Toolbar targets are constrained to 32 px, below a comfortable desktop target
  size for repeated actions.
- The captured accessibility tree exposes most toolbar actions as unnamed
  buttons; tooltips alone are not sufficient evidence of screen-reader labels.
- Source mode exposes an unnamed text field in the captured accessibility tree.
- Dark-mode task checkboxes and disabled toolbar icons are visually too close
  to their surrounding surfaces.
- Mode, save, and block-activation state changes need explicit semantic state
  announcements and visible keyboard focus.

## Opportunity areas

1. Introduce a responsive document shell with a readable center lane and a
   wider escape lane for code, tables, and diagrams.
2. Replace icon-only mode switching with a stable labeled control and make
   editing context obvious.
3. Use spacing and typography before borders; remove the card-inside-card
   metadata treatment.
4. Establish semantic tokens for interactive, focus, success, code, quote,
   table, and diagram states in both themes.
5. Add responsive rules at compact, standard desktop, and ultrawide widths.

## Evidence limits

Screenshots establish visual hierarchy, target size, layout, and visible state
risks. Screen-reader names were observed through the macOS accessibility tree,
but full keyboard order, screen-reader announcements, contrast ratios, zoom
reflow, and reduced-motion behavior still require dedicated testing.
