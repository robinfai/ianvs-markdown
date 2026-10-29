# Writing and knowledge workflows: stages 1–3

Requested 2026-10-29. Baseline: `dde9bfe06f9f7fea065082236038a59762b8d080`.
Status: all three stages have UI implementations in stacked draft PRs #56–61.
Validation and review fixes are in progress. Stage 1A merged through PR #56;
the remaining deliveries are still draft PRs.

Preserve ordinary local Markdown files and the current editing engine. Reuse
workspace indexing, note semantics, command routing, guarded saves and session
persistence. Cloud collaboration, proprietary blocks, plugins, formulas,
relations, rollups and stage-four capture/export work are outside this scope.

## Independently reviewable delivery sequence

- [x] 1A: quick switcher and command palette. Search title, path and aliases;
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
UI acceptance have been performed. Stage 1A merged through PR #56.

Draft PR: https://github.com/robinfai/ianvs-markdown/pull/56
Initial implementation commit: `b735b6f155fcaf92ab450ab41e46e2273db90dd8`.
Follow-up commits and their exact-head CI remain to be recorded.


## Delivery and verification log (2026-10-29)

| PR | UI entry and implementation | Verification state |
| --- | --- | --- |
| [56](https://github.com/robinfai/ianvs-markdown/pull/56) | Toolbar / Cmd+P switcher, Cmd+Shift+P commands; title/path/alias search, persisted recency, create note | Head `5df6dac746dc599b3ca47de28a91aa374d037969`: Core success, including app formatting/analyze and five focused tests. All PR Core/macOS/iOS checks passed; merged as `44f88174a0410b31c6d224a4d54dd606d0b936ca`. |
| [57](https://github.com/robinfai/ianvs-markdown/pull/57) | Commands: template new/insert, Open today, append today/Inbox | Head `1c9b2d6`: Core success; app formatting/analyze and 55 tests passed. Native checks pending. |
| [58](https://github.com/robinfai/ianvs-markdown/pull/58) | Type `/` on a blank line: heading/task/quote/code/image/template menu | Head `6cf9b22`: Core success, including app checks and slash insertion/cancellation UI tests. Native checks pending. |
| [59](https://github.com/robinfai/ianvs-markdown/pull/59) | Toggle references command, pin incoming/outgoing/open note, read alongside primary editor | Head `cee2b28`: Core success; app formatting/analyze and 59 tests passed, including actual hover preview and pinned reading. Native checks pending. |
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


### First main delivery and review regressions

PR #56 merged as `44f88174a0410b31c6d224a4d54dd606d0b936ca` after all
Core, macOS regressions/builds and iOS simulator build checks passed on its
head. Its main-commit checks are [Core](https://github.com/robinfai/ianvs-markdown/actions/runs/40837040670)
and [Native integrations](https://github.com/robinfai/ianvs-markdown/actions/runs/40837040607),
currently running/queued. PR #57 is now based on main.

Collection review fixes include complete original YAML editing values,
unchanged-source no-op commits, valid flow-map additions, full status values
for grouping/dragging and full scalar values for filtering/sorting. Display
ellipsis never supplies a property write. The source body must remain unchanged
and resulting YAML must still parse before a write proceeds.

[Widget screenshot artifact](https://github.com/robinfai/ianvs-markdown/actions/runs/40836827021/artifacts/12880634097)
contains collection-table.png and collection-board.png. This run exercised
long-value prefill/no-op save, property editing, status drag and saved-view UI;
the overall run still failed on a malformed reference fixture, nested-folder
fixture and lint issues, subsequently corrected. Downloading the artifact into
this environment returned HTTP 403, so visual inspection is not claimed.

Extracted notes now remain beside their original; reference definitions outside
the selection are copied into the extracted note. Reference insertion rebases
Markdown destinations and resolves wiki note paths before replacement. Unknown
or ambiguous wiki references stop insertion without changing the destination.


Latest portable acceptance checkpoint: stage 2C head `0ae6a79382d790460d484df8cf32545160187842`
passed app formatting, analysis and all 66 focused/regression tests in
[App feature checks](https://github.com/robinfai/ianvs-markdown/actions/runs/40837253304/job/123324989041).
Stage 3 head `4c0dfd4ec5efbf57edc104028a1b15d4f993c306` passed app analysis
and all 72 tests in [the next run](https://github.com/robinfai/ianvs-markdown/actions/runs/40837257528/job/123325003294);
that run failed only canonical formatting, whose exact diff is now applied.
All active branches were then merged with the new main commit to meet the
up-to-date branch requirement; their new heads must pass CI before further merges.

Fragment extraction review: preflight now preserves the original note target
for heading/block links left outside the selection, keeps migrated targets
local, remaps duplicate Markdown heading slugs, and retains literal Wiki
heading names. Unknown HTML anchors and partially selected target structures
produce an explicit error before any file is created. Tests cover these cases
and reference definitions with fragment destinations. At `c490872` (stage 2C)
all 72 app tests passed; at `c31ad4e` (stage 3) all 78 passed. Their formatter
and one control-flow lint correction are applied in the following commit;
new-head CI remains required before merge.
