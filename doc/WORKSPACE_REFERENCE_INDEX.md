# Workspace references, backlinks, tags and aliases

This phase is read-only. It introduces source-preserving reference analysis and
an affected-set preview API, not a file rename or multi-file replacement system.
No user note is rewritten when the index, backlinks or tag panel is opened.
Future rename work still requires a journal, per-file compare-and-swap, recovery
and explicit handling of dirty sessions. A preview is not permission to write.

## One effective source

`WorkspaceController.references` owns one `WorkspaceReferenceIndex` alongside
its existing `WorkspaceIndex`. It consumes only `catalog()`, `read()` and the
index's effective buffer snapshots. It has no filesystem or provider client.
Metadata remains local-only and source reads remain no-materialize. Dirty and
clean-but-conflicted open buffers take precedence over disk. A verified native
path identity, not a lowercased string, coalesces an open supported Markdown path alias with
its actual catalog entry.

Each semantic projection is cached by source key, source revision and an explicit
parser version. Source changes replace the note's whole semantic
projection; selection/mode changes do not parse. The graph is published atomically
only if scope epoch, source revision counter and catalog revision still match.
An old asynchronous read/parse/normalization cannot overwrite newer buffer
results. Scope switches drop the semantic cache. Closed buffers fall back to the
existing index's disk snapshot. Catalog changes re-resolve references while
unchanged note semantics are reused.

The aggregate semantic scan permits at most 32 MiB of UTF-16 source storage,
10,000 documents and 100,000 reference/tag occurrences. These are explicit input
and retained-source limits, not latency or heap guarantees. Parser preprocessing
has its own bounds described in [note semantics](NOTE_SEMANTICS.md). Cache bytes
are bounded independently of the shared `WorkspaceIndex` source cache. Metadata
continues to use the existing 50,000-entry catalog limit. Displaying only the first
500 results does not truncate the bounded scan. Cancellation stops publication
and further work after the current native read returns; it does not cancel a
provider operation already in progress. Refresh explicitly retries. A forced metadata refresh arriving during a scan is
coalesced but cannot reuse that scan's captured catalog: another metadata scan
must finish before any joined caller receives the result.

## Resolution and coverage

Occurrences retain original UTF-16 ranges, raw destinations, once-decoded
Markdown targets, fragments, queries, display aliases, syntax kind and effective
reference-definition identity. Wiki targets are not URI-decoded. Definition uses
point to their authoritative definition's destination span, not their label.
The source parser, including unsupported contexts, is documented separately.
Table bodies currently have unknown coverage and contribute no references or
tags. Whole-table inline parsing is not renderer-equivalent and would create
false or missing links across cells. Source-mapped, per-cell table parsing is a
required follow-up before safe rename can cover notes containing tables; this
phase does not claim full reference coverage.

- Wiki note lookup reuses `WikiNoteResolver`, including root-relative, explicit
  relative and bare-basename `.md` policy and real case/NFC collision choices.
- Bounded YAML aliases supplement bare-name candidates. They never overwrite a
  real filename or another file's alias. A bare name that matches multiple real
  identities requires a choice, including a filename/alias collision. Explicit
  paths do not match YAML aliases. The insertion picker still inserts actual
  root-relative file identities, not an alias that could later become ambiguous.
- Alias coverage is independent of body syntax coverage. An offline, unreadable,
  unsupported or over-budget alias source cannot prove a bare name unique or
  missing. Explicit paths remain usable if metadata is complete. No note is
  created from an incomplete bare-name lookup.
- Ordinary Markdown links resolve their already-decoded path relative to the
  source note. `%2520` is not decoded a second time; encoded `#` and `?` remain
  filename characters. Queries/fragments do not alter the target file identity.
  Targets outside the selected workspace, file-URI/authority syntax and
  unavailable normalization are unknown, not safely absent. HTTP(S), mail and
  data destinations are external. Non-note asset destinations are not note edges.
- Image Wiki embeds retain parser source spans but are not mistaken for
  similarly named `.png.md` notes. Wiki heading/block fragments identify the
  target note for backlinks; clicking a Wiki fragment still follows the existing
  explicit unsupported-navigation behavior. This phase does not implement
  heading/block navigation or embed rendering.

The snapshot records per-source/catalog issues. Offline, rejected, changed,
unsupported or budget-limited sources are never presented as zero references.
Unknown and ambiguous target candidates are retained where known. The UI shows
coverage limitations alongside confirmed results. A complete snapshot only
claims the documented supported syntax, not every extensible Markdown dialect.

`previewImpact(relativePath)` returns confirmed and possible references with a
completeness flag. A stale snapshot returns an incomplete preview. Fragment-only
self references have no affected filename span and are excluded. Reference uses
share their definition span: consumers must deduplicate by source key, revision,
and definition identity/destination range before preparing any future edits.
The returned occurrence is evidence for a future serializer, not authorization
for a string replace or proof that every spelling can be rewritten losslessly.

## User surfaces

The current note's Backlinks action and a rendered tag click in Read mode open
the same index panel. The renderer emits `tag:#name`; the host removes the
protocol and one leading `#` before lookup. Live Preview preserves its existing
tag-click source-editing/caret behavior, rather than navigating away. Bare-link alias resolution shows a cancellable status if a local scan
takes longer than half a second. Tag matching is case-insensitive exact tag identity; `project` does not
implicitly include `project/sub`. Repeated occurrences are shown, with a unique
note count. Body tags and supported YAML tags share the same posting list.

Clicking a result reuses workspace source-search navigation. The exact source
revision is checked again before selecting/opening a session, then the opened
buffer must match the captured source. Dirty tabs are reused, modes are preserved,
IME blocks navigation and stale offsets are rejected. A panel from a previous
scope cannot navigate results in a newly selected workspace.

Tests use synthetic sources and fake file services only. Linux tests cannot
establish real Apple sandbox/iCloud behavior, Swift compilation or actual device
interaction; final platform CI remains required.
