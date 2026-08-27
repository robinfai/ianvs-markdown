## Unreleased

- Keep pipe-less GFM body rows inside tables until a blank line or real block
  opener, including exact Live Preview cell editing and missing-cell writes.
- Keep irregular-table projection active after fenced code nested in list
  containers, while leaving table-shaped lines inside that code byte-exact.
- Preserve footnote, comment, and block-ID-shaped text inside code blocks that
  begin in ordered, unordered, empty, nested, quoted, or tab-separated list
  items, with container prefixes excluded from exact UTF-16 source ranges.
- Preserve footnote, comment, and block-ID-shaped text inside fenced or
  indented code nested in one or more block-quote containers, with original
  UTF-16 source ranges shared by Reading, Live Preview, and source styling.
- Keep inline and standard footnote-shaped text literal inside true indented
  code blocks, excluding it from Reading expansion, shared ordinal collection,
  Live Preview presentation ranges, and source metadata styling.
- Keep trailing and table-cell-shaped `^block-id` text literal inside inline,
  fenced, and true indented code blocks across Reading, source styling, and
  Live Preview.
- Prevent comment-shaped text inside inline, fenced, or indented code from
  prematurely closing an outer Obsidian comment; source styling and Reading
  now consume the complete outer range.
- Preserve literal `%%comment-shaped%%` text inside true four-space or tab
  indented code blocks in Reading and source styling, without treating an
  indented paragraph continuation as code.
- Keep a line-ending `^block-id` candidate literal when a soft line below
  continues the same Markdown block; only a true block-ending marker is
  consumed or styled as Obsidian metadata, while table-cell IDs stay intact.
- Resolve empty ordinary-link destinations to Obsidian's current-note URI in
  link callbacks, including both `()` and `(<>)` source forms.
- Render defined standard and inline footnotes as shared `[N]` / `[N-k]`
  ordinals in inactive Live Preview, while undefined references remain literal,
  definition blocks keep document-wide numbering, and activation restores the
  exact Markdown source; single- and multi-line code spans retain literal
  footnote-shaped text in Reading and Live Preview.
- Keep an isolated `==before / blank line / after==` attempt fully literal in
  Reading and inactive Live Preview instead of projecting both sides as
  independent unclosed highlights; exact source and higher-priority literal
  contexts remain unchanged.
- Parse Obsidian angle scheme and email autolinks before the safe raw-HTML
  fallback, preserving `<https:…>`, `<user@example.com>`, `mailto`, `ftp`, and
  `obsidian` targets in Reading and exact-source Live Preview.
- Match Obsidian's non-standard `<www…>` fallback by preserving the leading
  `<` as literal text while including the trailing `>` in the bare-link label
  and percent-encoded destination; ordinary `www` links remain unchanged.
- Preserve Obsidian inline-link destination backslash parity: odd runs that
  escape a parenthesis now retain one encoded literal backslash per preceding
  pair in Reading and inactive Live Preview, while exact source, code,
  comments, images, angle destinations, titles, and malformed links stay
  unchanged.
- Keep ordinary full-reference labels case-insensitive while matching
  Obsidian's measured non-normalizing whitespace boundary: a secondary label
  combining surrounding whitespace with a repeated internal run remains
  literal in Reading and block-local Live Preview instead of resolving.
- Add Obsidian-style Live Preview property editing for text fields and boolean
  controls: Enter or focus loss commits one undoable source edit, Escape
  cancels pending text, and a committed text field canonicalizes top-level
  inline scalar lists to the block-list form emitted by Obsidian Properties.
- Add finite numeric property input with focus-loss submission, invalid-input
  recovery, numeric YAML type preservation, and the same observed top-level
  flow-list canonicalization as an Obsidian number-field commit.
- Add safe in-place tag editing for complete string lists: chip removal writes
  immediately, removing the last item preserves an empty `tags:` property,
  and Tab/Enter adds a block-list value from either populated or empty state.
  Typed, nested, truncated, or oversized lists remain source-only.
- Add neutral editable alias chips for complete string sequences. Removing an
  alias immediately rewrites safe flow lists, removing the last item preserves
  `aliases:`, and Tab/Return add block-list aliases from empty or populated
  properties while retaining existing item order. Focus loss and Escape commit
  pending aliases, surrounding spaces are trimmed, and exact duplicates are
  not appended.
- Add in-place property-key renaming with Tab, Enter, and focus-loss commits,
  Escape cancellation, exact source-order and value-type preservation, YAML
  quoting for ambiguous names, and empty/case-insensitive duplicate/lossy-key
  rejection, including Obsidian's refusal of case-only renames.
- Add a segmented year/month/day property editor with a date-picker surface.
  Return commits an exact valid date as one undoable edit and canonicalizes
  top-level flow lists; Tab moves focus while retaining the pending UI value.
- Match Obsidian properties for source-order keys, an ordinary `title` row,
  default-expanded panels, triple-dash-only closing markers, distinct aliases,
  tags, and `cssclasses`, linked Wiki/URL scalar values, and invisible empty
  mappings across Reading and Live Preview without turning their delimiters
  into thematic rules.
- Lock Obsidian list editing semantics for multi-level empty-item exits,
  quote-contained soft continuations, four-space and tab-indented list-like
  lines, standalone comment wrappers, and tab-separated dash markers that
  render as lists while retaining native newline input behavior.
- Match Obsidian ordinary-link source recognition for empty and angle-wrapped
  destinations, balanced and escaped parentheses, double-, single-, and
  parenthesis-delimited titles, soft-line title whitespace, malformed-link
  fallback, nested labels, and parser-compatible full-reference labels; share
  the same scanner with block-local reference-definition injection.
- Match Obsidian Callout headers for case-insensitive non-empty types up to
  `]`, Unicode and punctuation fallback cards, strict zero-or-one-space quote
  markers, real-blank block boundaries, exact active source markers, and
  spaced nested block-quote rails.
- Match Obsidian emphasis and strong delimiter stacks for flanking, asymmetric
  and long runs, Reading/Live Preview-specific surplus presentation, intraword
  asterisks, literal intraword underscores, escapes, nesting, and source-range
  selection.
- Match Obsidian strikethrough parsing for double-tilde-only syntax, odd and
  even delimiter runs, asymmetric and adjacent surplus, whitespace and escape
  boundaries, soft-line and unclosed scopes, nested links/Wiki aliases, code
  priority, inactive marker hiding, and source-range selection.
- Match Obsidian highlight parsing for whitespace boundaries, surplus and
  adjacent `=` runs, escape parity, closed soft-line spans, unclosed line
  scope, nested links, Reading/Live Preview presentation, and source-range
  selection.
- Match Obsidian tag tokenization for Unicode and emoji, numeric rejection,
  slash paths, adjacent tags, punctuation boundaries including a confirmed
  fullwidth-colon start, and backslash parity with code, comment, and link
  precedence across Reading, Live Preview, and source styling.
- Match Obsidian block-ID boundaries for standalone markers, underscores,
  table cells, ASCII spaces after valid IDs, multiple candidates, escape
  parity, blank-separated ownership by the preceding supported block, and code
  precedence across Reading, Live Preview, and source styling.
- Match Obsidian comment pairing, backslash escape parity, adjacent-percent
  residue, literal unclosed delimiters, code precedence, and standalone
  comments that remain one editable Live Preview block across blank lines.
- Match Obsidian case-insensitive standard-footnote definitions by making the
  last duplicate authoritative in Reading while preserving exact Live Preview
  and source bytes, shared first-reference numbering, `[N-k]` repeat labels,
  in-page link callbacks, and every backlink.
- Match Obsidian's Live Preview inline-source boundaries: reveal delimiters at
  their opening edge, hide them immediately after the closing edge, select the
  complete formatted source on double click, edit ordinary links without
  navigating, and route Wiki-link clicks through the host navigation callback.
- Keep Live Preview selection document-wide: Command+A selects the complete
  Markdown source, while desktop mouse drags extend forward or backward across
  rendered block boundaries without marking the document dirty.
- Match Border's one-pixel nested-list indentation guides and 28 px marker
  steps in Reading and Live Preview, including active and split list items.
- Match Obsidian image dimensions for standard Markdown images, external
  images, and host-resolved Wiki image embeds while preserving safe default
  image blocking and exact Live Preview source editing.
- Add Obsidian-style desktop image resize handles in Live Preview with
  aspect-ratio preservation, editor-width clamping, width-only source
  writeback, double-click reset, and independent undo steps.
- Match Obsidian table row and column drag handles, 27 px Live Preview rows,
  point-accurate first-click caret placement, selection and drop feedback, RTL
  geometry, mobile active-handle visibility, structural source normalization,
  and the minimum-width alignment markers it emits.
- Match the active Border theme's fenced-code dot texture, dashed frame,
  dimensions, light and dark syntax palettes, persistent copyable Live Preview
  flair, desktop and mobile reading controls, and one-second copy feedback.
- Match Border blockquotes across reading, Live Preview, and source modes with
  the 4x4 dot texture, 4px radius, inset 3px accent rail, exact outer padding,
  and Obsidian's 2px horizontal-rule weight.
- Match Border's ordinary task checkboxes with 16px geometry, 6px corners,
  exact light and dark colors, a two-pixel hover/focus ring, thick check mark,
  keyboard and semantic toggling, and muted completed text in Live Preview.
- Render Obsidian's full single-character task-state model, including Border's
  progress, cancelled, forwarding, scheduling, question, importance, star,
  info, idea, location, bookmark, note, sentiment, quote, savings, and trend
  icons; preserve every original marker and toggle it with Obsidian semantics.

## 0.1.0

- Add `IanvsMarkdownController` with selection, dirty state, formatting
  commands, and document-wide undo/redo history.
- Add `IanvsMarkdownEditor` for complete source editing with syntax styling and
  Markdown-aware list continuation.
- Add `IanvsMarkdownLiveEditor` with live-preview, source, and reading modes.
- Add source-preserving block parsing, editor toolbar, and keyboard shortcuts.
- Refine live preview to keep active blocks in the rendered typography flow,
  reveal inline Markdown delimiters only around the caret, and collapse link
  targets and inline-code delimiters outside full-source mode.
- Edit contiguous lists one item at a time, toggle task checkboxes in place,
  edit GFM table cells without exposing pipe syntax, append rows and columns
  from contextual table-edge controls, and focus the newly created cell.
- Navigate table cells with Tab, Shift+Tab, arrow keys, and boundary-aware
  left/right movement; Enter or Tab from the last cell appends a row, while
  Shift+Tab from the first cell inserts a row above the table header.
- Render completed task text with a strike-through and continue completed
  tasks as fresh unchecked items when Enter is pressed.
- Keep task markers concealed while an item is active, retaining an interactive
  checkbox beside the editable text without changing the underlying source.
- Keep bullets, ordered numbers, and quote rails rendered while their blocks
  are active, concealing the corresponding Markdown prefixes on every line.
- Preserve the original caret or selection through Tab/Shift+Tab indentation
  instead of selecting the entire transformed line.
- Use a unified active surface for fenced code blocks and apply language-aware
  highlighting while preserving editable fences and exact source offsets.
- Render Obsidian Wiki links, tags, highlights, typed/foldable callouts,
  comments, block identifiers, and inline footnotes while preserving their
  exact source in editing modes.
- Make outline navigation reach distant headings that have not yet been built
  by the lazily rendered live-preview list.

- Extract the reusable Markdown renderer from `ianvs-acp`.
- Add safe image placeholders, fenced-code tools, front matter, and outline navigation.
- Add rendering budgets and custom builder injection points.
