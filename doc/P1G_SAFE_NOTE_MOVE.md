# Safe note rename and move: staged implementation

## P1g1: read-only plan, not completed reference maintenance

The first stage adds renderer-aligned table source mapping and a bounded,
source-preserving proposal for moving one note inside the selected workspace.
It does not execute the proposed reference changes. No journal, multi-file CAS,
recovery or atomic multi-file transaction is claimed in this stage.

The existing Rename, Move to Folder and drag-and-drop flows now show a cancellable
preview. The only affirmative button explicitly says **Move without updating
links**. It retains the existing file-operation behavior, with a warning that
incoming links and the moved note's relative outgoing links/images may break.
Folders and multiple items are explicitly outside automatic maintenance, rather
than silently being described as safe. Cancel, dismissal, a late preview failure,
and a workspace switch never approve a move. Starting a preview never writes.

`WorkspaceNoteMovePlanner` consumes an immutable `WorkspaceReferenceSnapshot`
and the host's dirty-session set. It has no filesystem or write API. It keeps
canonical catalog paths distinct from display/case-normalization keys. Current
scope, content and catalog revisions must still match when planning ends.

- Inline Markdown, images and effective first-wins reference definitions use
  exact UTF-16 destination spans. Shared definitions are deduplicated; labels,
  shadow definitions, aliases, titles, queries and fragments are not replaced.
- Replacement paths are serialized according to Markdown URI or Wiki grammar,
  then the entire proposed source is reparsed. Reference kind, occurrence span,
  target, destination span, alias, title, query, fragment, tags and YAML aliases
  must match the expected transformed source. Unchanged source, BOM and line
  endings are copied verbatim. Percent escapes are decoded once only.
- Incoming links and the moved note's relative outgoing links are handled. All
  Wiki occurrences are resolved against a simulated candidate catalog. A new
  basename collision is disambiguated with an explicit workspace path, including
  links to a different pre-existing note. Previously missing Markdown or Wiki links changing
  resolution block automatic maintenance instead of silently acquiring a target.
- Moved image targets use the image resolver's own fallback and relative-path
  rules with optional scoped attachment metadata. They produce explicit stable
  metadata requirements for later native preflight, not proof of local bytes.
  Unsupported local assets, missing metadata or ambiguous assets are blockers.
- Incomplete scans, unsupported syntax, unknown/ambiguous edges, offline notes,
  dirty/conflicted affected buffers, invalid scope, occupied destinations,
  unavailable normalization, missing parent folders, extension conversions,
  open-buffer destination identities and case/NFC-only moves are
  explicit blockers. Clean buffers do not override offline affected-file metadata.
  Case-only rename needs a separate exclusive-move protocol.
- One proposal retains at most 128 affected files and 32 MiB of combined original
  and replacement UTF-8 bytes. A limit marks the proposal incomplete, never a
  successful truncated transaction. The existing index/parser have independent
  coverage budgets. These are storage/input limits, not UI-latency guarantees.

A complete proposal means supported-source coverage, not permission to execute,
not a durable identity check, and not an assertion that attachments are local.
The UI does not apply the displayed proposal in P1g1. The requested end-to-end
rename/reference feature remains unfinished until P1g2 below is implemented,
reviewed and independently verified.

## P1g2: required executor and recovery contract

The next stage must replace the manual-only single-note path with an explicitly
confirmed, recoverable executor. The preview's exact content/revisions, source,
destination and affected set form the consent boundary. No new affected file may
be added after confirmation. Rebuild and reconfirm when the plan materially changes.

Planned file boundaries:

- `workspace_note_transaction.dart`: bounded serialized request/result DTOs and
  app/session reconciliation. Recheck dirty/conflicted buffers and scope before
  invoking native operations; never advance a save baseline before disk evidence.
- `app/apple/WorkspaceNoteTransaction.swift`: descriptor-rooted local preflight,
  coordinated per-file compare-and-swap, exclusive destination and bounded journal.
  Shared by macOS/iOS and compiled in both platform CI jobs.
- A recovery UI in the existing preview flow: exact applied/pending/uncertain
  file states, restore-original-as-copy and safe retry. No silent rollback.

The native scope must pin the authorized directory object, not merely reopen a
path string under a later grant. Verify the root path still identifies that
object before/after each coordinated action. Walk directory components with
`openat`/`O_NOFOLLOW`, pin parent descriptors, reject symlinks, offline/dataless
providers and unverified identities. Check stable file identity plus exact
expected UTF-8 bytes/revision. Native coordination is advisory cooperation, not
protection against arbitrary non-cooperating writers. A root/parent externally
renamed after a check remains a residual race: never misreport successful scope
or delete a concurrently created file when detecting it afterward.

Durable states:

1. `prepared`: complete bounded manifest and original/replacement bytes synced
   before the first user-file mutation; all paths local and preflighted.
2. `applying`: an intent receipt is synced before each individual CAS. A success
   receipt records the resulting identity/revision after it. Files are independent,
   not a cross-file ACID transaction.
3. `moving`: after reference writes, move the one note exclusively, without
   overwriting the destination. Source identity must still match its expected
   current receipt; record identity at the destination. The source must not be
   unlinked on evidence of an unrelated concurrent writer.
4. `completed`: every write and final move is positively verified and receipted.
5. `partial` / `uncertain`: record exact last known state after any failure.
   Restart reconciliation compares identity and bytes to both baselines. Equality
   alone is not permission to overwrite a changed identity. Do not automatically
   roll back a file over another writer, nor infer unexecuted after a lost reply.

Recovery copies use exclusive new names in an authorized destination and retain
original bytes; they never replace current files or permanently delete notes.
Safe retry is allowed only for not-yet-applied entries still matching the original
identity and contents, under the same confirmed scope/plan. Anything else is
reported for a new preview/decision. Fault injection must exercise every boundary,
including before/after a user-file write but before the durable success receipt.

Journal privacy and retention: app-private storage only, transaction-touched
paths and before/after bytes only, no unrelated vault contents or global graph.
Use bounded metadata and checksums, no credentials. Cap each transaction at the
same 128 files / 32 MiB and cap total retained bytes/records. Never silently delete
unrecovered records to make room; stop before mutation and offer export-as-copy or
user-reviewed cleanup. A journal is not proof of power-loss durability until the
file and directory fsync guarantees and fault tests are verified on supported
filesystems. Do not claim provider-side rollback or cross-file atomicity.

## Validation

All fixtures are synthetic. Focused core renderer-oracle tests and app planner /
warning / cancel tests run locally with `flutter test --no-pub`. Package publication,
publish dry-run, cloud metadata and user vaults are not used. Native Mac/iOS CI and
real-device acceptance are separate gates; Linux tests do not establish them.
