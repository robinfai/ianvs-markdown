# Writing and knowledge workflows: stages 1–3

Requested 2026-10-29. Baseline: `dde9bfe06f9f7fea065082236038a59762b8d080`.
Status: all three stages have UI implementations in stacked draft PRs #56–61.
Validation and review fixes are in progress; no stage is accepted or merged.

Preserve ordinary local Markdown files and the current editing engine. Reuse
workspace indexing, note semantics, command routing, guarded saves and session
persistence. Cloud collaboration, proprietary blocks, plugins, formulas,
relations, rollups and stage-four capture/export work are outside this scope.

## Independently reviewable delivery sequence

- [ ] 1A: quick switcher and command palette. Search title, path and aliases;
  rank recent notes; create from an unmatched query. Reuse editor command
  routing and expose keyboard and visible menu entry points.
- [ ] 1B: template creation/insertion, daily notes and quick append. Supply
  meeting, reading, technical proposal and blog templates; expand title/date/
  time in Markdown and YAML. Reopen an existing daily note. Append to Inbox
  or today's note without replacing existing contents.
- [ ] 1C: slash insertion UI for headings, tasks, quotes, code, images and
  templates. Use the current editor selection and existing image import flow.
- [ ] 2A: link hover preview and persistent incoming/outgoing links panel;
  pin a reference note and expose open-beside actions.
- [ ] 2B: two-note panes and same-note Source/Read panes, independent scroll
  positions and explicit active input target. Preserve unsaved shared content.
- [ ] 2C: outline chapter reordering with descendants, heading promotion and
  demotion, folding and chapter-link copy. Extract selection to a new linked
  note; insert/merge reference content through normal undoable editing.
- [ ] 3A: saved collections with folder/tag/property filtering, list/table
  views, column selection, sorting and editable typed YAML properties.
  Persist view configuration separately from note content and expose it in
  the sidebar. Write property edits through the existing file-save contract.
- [ ] 3B: status-grouped board over the same collection and saved filters.
  Moving a card changes its underlying note status; reopening preserves it.

## Acceptance for every delivery

1. Exercise the actual UI entry points, keyboard operation, cancellation,
   repeated invocation, document/workspace switching and restart persistence.
2. Verify Markdown source fidelity and undo/redo; never overwrite a dirty
   buffer or silently replace a changed on-disk file. Test IME/local input
   routing where commands edit text.
3. Add focused controller/widget/integration coverage for behavior, then run
   the applicable formatting, analysis and tests from CONTRIBUTING.md.
4. Open a draft PR for each deliverable. Record exact commit, test output and
   actual UI evidence. Verify the final PR head's Core required and applicable
   native checks before merging. Never bypass protection or approve own PRs.
5. Record the resulting main commit and remaining limitations below. No
   isolated service API or placeholder UI counts as delivery.

Stage-one scenario: create a meeting note from a template, navigate with the
switcher, insert structured content, and append a capture to today's note.
Stage-two scenario: find references, read beside a draft, cite them, reorder
chapters and extract a reusable note while retaining navigation positions.
Stage-three scenarios: a blog pipeline and a reading list backed by ordinary
Markdown files, editable through table and status board, surviving restart.

## Environment and baseline evidence

- Fresh clone at `/workspace/ianvs-markdown`; main is the baseline above.
- Existing open PRs #27 and #43 are performance work and remain untouched.
- No AGENTS.md or repository-local SKILL.md was found in this checkout.
  CONTRIBUTING.md and Makefile define validation and protected-main PR flow.
- The selected Linux environment initially contains `ianvs-terminal`; it has
  not been modified. No Flutter or Dart executable was found on PATH or in
  the inspected tool locations (`/opt`, `/usr/local`, `/tmp`, `/home`).
- Official Flutter download-host access failed before download with proxy
  `403 Forbidden`, `curl: (56) CONNECT tunnel failed`, both normally and with
  an escalated request. No SDK was installed. Tests run through authorized GitHub Actions instead.
- macOS/Xcode native builds and actual desktop acceptance are unavailable in
  this Linux environment. A suitable validation environment remains required.

Stage 1A adds toolbar entry points and Cmd/Ctrl+P (notes) and
Cmd/Ctrl+Shift+P (commands). Recent open notes persist their activation time
in session recovery. Closed-note recency is retained in the bounded workspace session history. Existing CI is
being used for toolchain validation; no local Flutter tests or actual desktop
UI acceptance have been performed. No stage has merged.

Draft PR: https://github.com/robinfai/ianvs-markdown/pull/56
Initial implementation commit: `b735b6f155fcaf92ab450ab41e46e2273db90dd8`.
Follow-up commits and their exact-head CI remain to be recorded.


## Delivery and verification log (2026-10-29)

| PR | UI entry and implementation | Verification state |
| --- | --- | --- |
| [56](https://github.com/robinfai/ianvs-markdown/pull/56) | Toolbar / Cmd+P switcher, Cmd+Shift+P commands; title/path/alias search, persisted recency, create note | Head `5df6dac746dc599b3ca47de28a91aa374d037969`: Core success, including app formatting/analyze and five focused tests. Native workflow queued. |
| [57](https://github.com/robinfai/ianvs-markdown/pull/57) | Commands: template new/insert, Open today, append today/Inbox | Template UI tests passed in earlier runs; daily capture fix and broader existing regression suites await current-head validation. |
| [58](https://github.com/robinfai/ianvs-markdown/pull/58) | Type `/` on a blank line: heading/task/quote/code/image/template menu | Slash source insertion and cancellation widget tests passed in earlier run; inherited daily failure fixed, rerun pending. |
| [59](https://github.com/robinfai/ianvs-markdown/pull/59) | Toggle references command, pin incoming/outgoing/open note, read alongside primary editor | Persistent independent reading position; app analyzer lint fixes committed, tests pending. |
| [60](https://github.com/robinfai/ianvs-markdown/pull/60) | Outline drag handles and chapter menu; Extract selection command; reference insert button | Extraction now creates a sibling note. Reference insertion rebases Markdown paths and resolves wiki paths; source-fidelity regression tests pending. |
| [61](https://github.com/robinfai/ianvs-markdown/pull/61) | Collections sidebar: saved filters, list/table/board, property edit and status drag | Long-value preservation and YAML flow-map insertion fixed with regression cases. Current CI and table/board screenshot artifacts pending. |

[Successful stage-1A Core run](https://github.com/robinfai/ianvs-markdown/actions/runs/40833862235).
The additional Linux app check supplements, and does not replace, existing Core
and Native integrations jobs. Native jobs have not started at this checkpoint;
no macOS build or manual UI evidence is claimed. Widget screenshot artifacts,
when produced, show the Flutter test harness rather than a native desktop run.

Remaining acceptance: current-head passing app checks for stages 1B–3; native
checks/builds; desktop interaction acceptance; blog/reading scenario review;
main merges and verification of resulting main commits. Template source can be
customized per invocation but a persistent custom-template library is not yet
implemented. The reference pane is read-only; the main pane supplies editing.
