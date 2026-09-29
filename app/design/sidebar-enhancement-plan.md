# Sidebar enhancement acceptance plan

Scope: all three phases of the agreed file-first sidebar design. Full-text search and automatic Markdown link rewriting remain explicitly separate follow-ups.

## Phase 1
- Reveal active file (including external files), optional follow, transient emphasis.
- Per-workspace expansion, scroll and sorting recovery; refresh preserves location.
- Independent keyboard focus/active document, arrows/Enter/Escape.
- Filename/path search, ranked matches, highlights, parent paths, count/200 limit,
  cancellation, reveal result and return to previous tree position.
- Natural name / modification-time sorting, directories first.
- Dirty status, retryable directory errors, empty states, minimum-width layout.

## Phase 2
- Inline new Markdown/folder and rename with validation and collision handling.
- Duplicate, move picker, Trash, relative-path copying.
- No overwrite; no move into self/descendant; coherent sessions/watchers/recovery.
- Dirty documents protected on Trash, including descendants; save/discard/cancel.
- External branches never enumerate unauthorized parents; grant folder access when needed.
- Explicit feedback that move/rename does not rewrite relative Markdown links.

## Phase 3
- Persistent file/folder favorites, only shown once used.
- Command/Shift selection and batch operations with accurate partial-failure feedback.
- Drag selected files/folders into folders, including workspace root.
- Virtualized visible rows, cancellable incremental directory index and local refresh.
- External filesystem events update cached directories and search without losing state.

## Verification
Controller/service tests, widget interaction tests, native filesystem tests,
Flutter analysis/full app tests and macOS build. Audit each requirement against
current implementation and recorded test evidence before marking complete.

## Completion

All three phases implemented and accepted on 2026-09-29. See
[requirement-by-requirement evidence](sidebar-enhancement-acceptance.md).
The repeatable gate is `bash app/tool/verify_sidebar.sh`.
