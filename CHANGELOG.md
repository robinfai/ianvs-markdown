## Unreleased

- Match Obsidian image dimensions for standard Markdown images, external
  images, and host-resolved Wiki image embeds while preserving safe default
  image blocking and exact Live Preview source editing.
- Add Obsidian-style desktop image resize handles in Live Preview with
  aspect-ratio preservation, editor-width clamping, width-only source
  writeback, double-click reset, and independent undo steps.
- Match Obsidian table row and column drag handles, selection and drop
  feedback, RTL geometry, mobile active-handle visibility, structural source
  normalization, and the minimum-width alignment markers it emits.
- Match the active Border theme's fenced-code dot texture, dashed frame,
  dimensions, light and dark syntax palettes, persistent copyable Live Preview
  flair, desktop and mobile reading controls, and one-second copy feedback.
- Match Border blockquotes across reading, Live Preview, and source modes with
  the 4x4 dot texture, 4px radius, inset 3px accent rail, exact outer padding,
  and Obsidian's 2px horizontal-rule weight.
- Match Border's ordinary task checkboxes with 16px geometry, 6px corners,
  exact light and dark colors, a two-pixel hover/focus ring, thick check mark,
  keyboard and semantic toggling, and muted completed text in Live Preview.

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
