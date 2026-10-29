# Writing and knowledge workflows: stages 1–3

Requested 2026-10-29. Baseline: `dde9bfe06f9f7fea065082236038a59762b8d080`.
All six functional deliveries in stages 1–3 are merged through PRs 56–61.

The product remains a local Markdown editor: linked reference reuse,
discoverable operations and structured views over existing YAML properties.
Notes remain ordinary files; view configuration lives in workspace session
data. Cloud collaboration, proprietary blocks, plugins, relations, rollups,
formulas and stage-four mobile capture/export themes are outside this delivery.

## Feature entry points

| Step | Entry | Behavior |
| --- | --- | --- |
| 1A | Toolbar or Cmd/Ctrl+P | Search title, path and aliases, rank recent notes, create an unmatched name. Arrow keys/Enter navigate; Escape cancels. |
| 1A | Toolbar or Cmd/Ctrl+Shift+P | Command palette reuses editing, navigation, save/export, template and capture actions. |
| 1B | New note from template / Insert template | Meeting, reading, technical proposal and blog templates; editable source and title/date/time variables in body and YAML. |
| 1B | Open today’s note / Append to today / Append to Inbox | Reuses the existing daily note and appends captures through guarded saves. |
| 1C | Type a single slash on an otherwise empty line | Heading/task/quote/code/image/template insertion. Cancel leaves the slash and selection. Pasted paths/prose do not trigger it. |
| 2A–2B | Toggle reference pane | Incoming/outgoing links and open-note choices, pinned read-only note beside the editor, including same-note Source+Read; independent reading positions. |
| 2A | Hover a local link in rendered Markdown | Local excerpt with stale-hover/document results discarded. |
| 2C | Outline drag handle and chapter menu | Reorder chapters with descendants, promote/demote headings, fold/expand, copy chapter links and undo changes. |
| 2C | Extract selection / reference insert button | Save a sibling note before leaving a link; insert reference content with relative destinations rebased. |
| 3 | Collections in sidebar | Folder/tag/property filters, saved views, list/table/status board, selected columns, sorting, property editing and status dragging. |

Template variables: `{{title}}`, `{{title_yaml}}`, `{{date}}`, `{{time}}`.
Use the YAML-safe title variable for arbitrary titles in front matter.
Template source is customizable per invocation; there is no persistent custom
template library. The reference pane is read-only; editing stays in the primary
pane. It can display that note's unsaved content without activating another note.

## Markdown fidelity

- Extraction stays beside the original note and carries effective reference
  definitions from outside the selection, preserving relative link/image bases.
- Fragment links to headings/blocks left in the original gain the original-note
  target. Migrated targets remain local; duplicate heading slugs are remapped.
  Standalone block IDs move with preceding content. Unknown HTML anchors,
  unresolved/ambiguous or partially selected targets produce an explicit error
  before creating a file.
- Reference insertion rebases Markdown destinations and resolves wiki targets
  before changing the destination; unsaved/ambiguous references require correction.
- Collection edits use complete YAML values, never truncated display text.
  No-op edits preserve source exactly. New fields support block and flow maps;
  YAML must parse and the Markdown body must remain unchanged before saving.
- Captured text edits validate document/selection state; writes retain the
  existing save/conflict flow and undo behavior.

## Repeatable acceptance scenarios

These recipes are not a claim of manual native testing.

1. Create a meeting note from a template, find it by title/alias, cancel and
   reopen commands, insert a slash task, append two captures to today, then
   reopen today and confirm both remain.
2. Pin a linked reference beside a draft in Source mode; scroll separately,
   insert a citation, reorder a parent chapter with children, change its level
   and undo. Extract a nested-folder selection and verify images, reference
   definitions and links to original/migrated headings.
3. Blog pipeline: notes under `blog/` with `status`, `date`, `category`. Choose
   Folder `blog`, Property `status`, Equals `draft`, columns
   `title,status,date,category`, sort by date and Save view. Edit a cell, switch
   to board, drag a card and inspect the .md. Cards leaving the status filter
   disappear from the filtered view.
4. Reading list: notes under `reading/` with a `reading` tag, `status` and
   numeric `rank`. Save a list/table sorted by rank, restart and reopen the view.
   Verify the configuration survives and metadata remains ordinary YAML.
5. Cancel property/filename dialogs, repeat commands and switch workspaces.
   Incomplete indexes are reported; views from another workspace must be reopened.

## Delivery ledger

Normal protected-branch PR merges are used without self-approval, force-push,
protection bypass or skipped existing gates.

| PR | Delivery | Main commit |
| --- | --- | --- |
| [56](https://github.com/robinfai/ianvs-markdown/pull/56) | Switcher/commands | `44f88174a0410b31c6d224a4d54dd606d0b936ca` |
| [57](https://github.com/robinfai/ianvs-markdown/pull/57) | Templates/daily/capture | `747867ff5a91c638e1fed0a42988565f48ea5223` |
| [58](https://github.com/robinfai/ianvs-markdown/pull/58) | Slash insertion | `50f5287b975f8e79a17150b046b203723c593078` |
| [59](https://github.com/robinfai/ianvs-markdown/pull/59) | Reference reading | `d8f17ab23bf0282e0d41dfca4af0ed8190fafb26` |
| [60](https://github.com/robinfai/ianvs-markdown/pull/60) | Chapters/extraction | `f7dff6a01bb39c96e0f665bdfcef5779e7d72b62` |
| [61](https://github.com/robinfai/ianvs-markdown/pull/61) | Collections/board | `46662f26eacc1241ef6e8ab8923f6aea523ccc50` |

PRs 56–59 passed complete Core and Native integrations before merging. Tested
heads: `5df6dac746dc599b3ca47de28a91aa374d037969`,
`9d97f629023a8914aa43b0264e81e1f775df9afa`,
`7d4a23eae3352961ae5216e02d7c1faddbd5503c`,
`cdd37300fd63d5007b33b643985bcce18414d0aa` respectively.
Main `d8f17ab` passed [Core](https://github.com/robinfai/ianvs-markdown/actions/runs/40842739729)
and [Native integrations](https://github.com/robinfai/ianvs-markdown/actions/runs/40842739773).

PR 60 head `7bbecca2c8f0df730ee699d623570a519f668144` passed
[Core](https://github.com/robinfai/ianvs-markdown/actions/runs/40849060108),
including canonical formatting, full app analysis and 73 app tests.
PR 61 head `797b61270414c4f3ab80b087ec23ee05c8ae740d` passed
[Core](https://github.com/robinfai/ianvs-markdown/actions/runs/40849065962),
including formatting, full app analysis and 79 app tests.
Their [stage-2 native](https://github.com/robinfai/ianvs-markdown/actions/runs/40849060157)
and [stage-3 native](https://github.com/robinfai/ianvs-markdown/actions/runs/40849066019)
checks also passed before merging. The complete macOS app suites passed
1173 tests (stage 2C) and 1179 tests (stage 3), with one existing skip each.
An initial tab-visibility test failure was corrected by scoping its finder
to TitleTabsBar after the outline introduced another ReorderableListView;
all existing visibility/reordering assertions remain and the full suites
were rerun successfully.

The final functional main revision is
`46662f26eacc1241ef6e8ab8923f6aea523ccc50`. Its post-merge verification is
[Core](https://github.com/robinfai/ianvs-markdown/actions/runs/40851129941)
and [Native integrations](https://github.com/robinfai/ianvs-markdown/actions/runs/40851130091).
Later documentation-only revisions retain this application/test/workflow tree;
their own required Core checks are linked from the documentation PR.

The focused suite exercises actual switcher/command/slash dialogs, repeated
daily capture, hover/pinned reading, outline drag/menu/undo, nested extraction,
long YAML prefill/no-op/edit, board dragging and saved-view persistence.
Service tests cover typed metadata, flow maps, filters/sorts and content transfer.
Existing Core checks on Flutter 3.44/3.47 and macOS regression/build/iOS simulator
gates remain intact. The extra Linux app job supplements the full macOS suite.

[Collection table/board screenshots](https://github.com/robinfai/ianvs-markdown/actions/runs/40849065962/artifacts/12886476658)
come from the successful widget harness at PR 61's tested head, with seven-day
artifact retention. They are not native desktop captures.

## Environment and remaining boundaries

- Only ianvs-markdown worktrees were changed; ianvs-terminal and unrelated PRs
  were untouched. No repository AGENTS.md or local SKILL.md was present.
  CONTRIBUTING.md and Makefile define toolchain/check requirements.
- Linux has no Flutter/Dart SDK. Official SDK download failed with proxy HTTP
  403; no workaround was used. Tests ran through authorized GitHub Actions.
- No manual macOS/iOS device acceptance was performed. Available evidence is
  native CI builds, simulator compilation and automated tests. Artifact download
  also returned 403, so local visual inspection of screenshots is not claimed.
- Collections offer one property-equality filter plus folder/tag filters, not
  arbitrary boolean queries. The board groups by status. Relations, rollups,
  formulas, calendar and card layouts are outside scope.
- The reference pane is read-only; custom template changes are per-use.
  Preserving Wiki heading/block syntax does not add renderer support for
  previously unsupported Wiki-anchor navigation.
- No planned stage 1–3 functional item remains unimplemented. Manual native
  desktop/device acceptance remains outstanding; the automated evidence above
  must not be described as manual acceptance.
