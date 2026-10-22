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

## P1g2: recoverable single-note executor

The same preview now offers **Move and update links** only for a complete plan.
Every affected file can be expanded to inspect the exact old/new destination
spelling. Explicit confirmation fixes the scope, source/destination, affected
manifest and original/replacement bytes. There is no automatic execution when a
preview opens and no automatic fallback to a manual move after any attempt.
Folders, multi-selection, extension conversion and case/NFC-only moves still
require the clearly warned, unmaintained legacy path; this is not the completed
folder/batch reference-maintenance feature.

Implementation boundaries:

- `workspace_note_transaction.dart`: bounded platform DTOs, exact UTF-8 payloads
  (including BOM/CRLF), native catalog revisions, receipts and recovery listing.
- `WorkspaceController`: serialize mutations, reject stale/dirty/conflicted plans,
  and freeze queued-save snapshots across move generations. A save captured before
  a reference rewrite cannot silently write old links back afterward. Lost replies
  trigger observation only, never replay `execute`. Open buffers advance only after
  a verified receipt plus a fresh, non-materializing text/revision read. Keystrokes
  during execution are retained and marked conflicted, not replaced. A failed fresh
  read, revision mismatch or changed workspace downgrades the client result to
  partial/current-state-unverified; native completion alone is not a UI success.
  Before execution, obsolete inode-bound document/favorite bookmarks are removed
  from the persisted session. A definitely unexecuted cancellation restores them;
  verified resulting identities receive new bookmarks, including closed favorites
  in other workspaces. A stale restored bookmark cannot redirect an old note tab
  to a retained hidden artifact. Bookmark renewal failures preserve the verified
  file result but explicitly report unavailable persistent access. Every asynchronous
  renewal checks the original workspace, epoch, document membership and path.
  An affected active document's previous cloud observation is invalidated before
  execution and refreshed after the scoped result, including same-path backlinks.
  This checks only the current active document and does not turn cloud metadata
  into a receipt for the rewritten revision.
- `app/apple/WorkspaceNoteTransaction.swift`: shared macOS/iOS descriptor-rooted
  preflight, durable private journal, coordinated atomic swaps, exclusive final move.
- The existing preview shows per-file and artifact states. **Workspace actions →
  Note Move Recovery** remains available after restart, with a notice for unfinished,
  unverifiable or storage-blocked journals. Original recovery is copy-only, explicitly
  confirmed, and does not repair/finish a partial move by itself.

### Native authorization, read set and atomic replacement

The live prepared token retains the authorized root directory object and parent
file descriptors. Root/path identities are checked before and after coordinated
actions, with no-symlink `openat` walking. A restarted process cannot regain the
old execution token by reopening the same path. Offline/dataless files, multiple
hard links, unverifiable identities or provider materialization are rejected.
Native revision, inode/device and exact expected bytes must agree. Unrelated
catalog metadata and attachment requirements form a bounded dependency digest.
The restart-reconstructible walk includes at most 50,000 relevant metadata entries
(notes, assets and directories), including logical iCloud-placeholder notes rather
than excluding every dot name; its deadline is bounded.
New notes or changed link sources invalidate execution without retaining their
bodies/paths in the journal. Metadata comparison remains a snapshot check, not a
lock on arbitrary non-cooperating writers.

Each changed file is fully written and synced to an exclusive hidden sibling
`.linefold-note-move-<transaction UUID>-<index>.md`. It does not disclose the original
filename. Ordinary permissions/uid/gid are preserved; unsupported ACLs, xattrs,
special flags or metadata queries block replacement rather than silently dropping
access semantics. A synced intent precedes `renameatx_np(RENAME_SWAP)`. The original
(or concurrently displaced version) survives at the hidden sibling. The target is
replaced atomically as a complete file, never an in-place truncated body. Durability
claims cover process interruption with successful file/directory `fsync` calls;
they do not guarantee OS-crash, power-loss or device-cache ordering. Unsupported
swap/provider rejection fails closed, without an unbacked replace or in-place
fallback. Final rename is exclusive and never overwrites a destination. Source and
destination parents must be local, writable/searchable and on the same volume
before any swap; those checks are not a reservation or a guarantee against races.
The visible final move balances `NSFileCoordinator` will/did-move notifications
when the namespace move actually succeeds, even if a later durability check fails.

Coordination is advisory and this is not a cross-file ACID transaction or a stronger
platform CAS guarantee than P0. Coordination covers individual changed files and
the final move, not a transaction-wide lock or a globally consistent read-set
snapshot. Even a cooperating writer can change an uncoordinated dependency between
the final scan and receipt. A non-cooperating writer can race check → swap; its
displaced inode is retained and the result becomes uncertain instead of being
silently deleted or swapped back. External root/parent rename retains a residual
check-to-system-call window; later detection must not claim successful authorized
scope or delete a concurrently created file.

### Durable states and recovery

1. `prepared`: bounded exact manifest, payloads and identities durably synced before
   any vault mutation. A live token is required to execute.
2. `applying`: durable staging/swap intents, then observed identity/revision receipts.
   An artifact may be staged, retained or uncertain. Files change independently.
3. `moving`: durable intent before the one exclusive final move. Reconciliation
   checks both locations; a move whose receipt was lost must not be performed again.
4. `completed`: every change and final location positively verified, with a durable
   final dependency-verification proof written by the successful execution path.
   A record missing that proof stays `partial` / `completion_unverified` even if
   reconciliation verifies the final location and repairs its sync receipt. A live
   token is not a completion proof, and reconciliation never creates one.
5. `partial` / `uncertain` / `blocked`: observations for each exact entry. Restart
   reconciliation checks real inode plus bytes and the dependency digest, not just
   durable phase labels. Missing durability evidence requires real resynchronization
   of the verified file and parent objects, followed by revalidation, before a
   receipt can be accepted. An inode/bytes read is not proof of a successful sync.
   Any failed final semantic verification, including an unavailable scan or new
   offline placeholder, remains a sticky conflict rather than being replaced by a
   weaker digest or the presence of an in-memory execution token.

No failure automatically rolls back, reverses a swap, unlinks a file, retries an
uncertain mutation or discards a concurrent version. Execution failure invalidates
its live token; an in-memory invalidation remains effective even when a failed
journal write prevents saving the latest conflict. UI recovery only creates new
exclusive copies of the journal's originals in the explicitly selected original
workspace. Its complete copy-name plan is durable first; each copy has its own
intent/identity/bytes receipt. Existing or uncertain copies are never replaced or
blindly duplicated. After another explicit recovery choice, a planned path still
verified absent can continue using exclusive creation; no fresh duplicate name is
allocated to hide an uncertain result. Missing old parents or an unverifiable
original transaction do not prevent copying verified journal originals into a safe
current destination under the same authorized root identity. Verified completed
copies are listed. Copies may introduce aliases and affect link resolution; the
confirmation discloses this rather than presenting them as a semantic rollback.
The current UI does not offer
execution retry after a restart: use recovery copies and a newly reviewed preview.
Only its specifically planned, identity/bytes-verified recovery copies are excluded
from that transaction's dependency digest, never arbitrary similarly named files.
A historical completed record can conservatively show `partial` with
`dependency_conflict` when later, unrelated visible metadata changes. This is a
current-state verification limitation, not a claim that its previously verified
move was undone: the per-file observed locations/states remain available.

### Privacy, storage and remaining work

Private journals live in app Application Support, excluded from backup, not in the
vault or ubiquity container. They contain only touched paths, before/after bytes and
required receipts/checksums, not unrelated note contents, graph or credentials.
The transaction cap is 128 files / 32 MiB combined UTF-8 payload. Private retention
is at most 32 records / 192 MiB, with a separate 192 MiB artifact reservation and
pre-mutation free-space checks. Durable temporary journal remnants are accounted
for, not silently pruned. Concurrent external growth of retained artifacts is not
claimed to be bounded by the app. Capacity checks aggregate allocations sharing a
volume: two generations of actual JSON/base64 journal bytes, 512 KiB receipt
headroom, pending stages/copies and a 1 MiB per-volume margin. Capacity is rechecked
before creation, not reserved; a provider quota or concurrent writer can still
exhaust space. Recovery copies consume additional checked space. New private
journal directories and their ancestors are synchronized, and unsupported inherited
ACLs fail closed instead of silently broadening access.

Successful and unsuccessful swaps retain originals. The confirmation discloses
hidden files, space usage and possible vault synchronization; private journal data
is not additionally synchronized. No automatic permanent delete is implemented.
Explicit recoverable Trash cleanup is still a separate follow-on task; a full
journal stops new operations rather than disposing of recovery data. Directory and
multi-item maintained transactions, case-only rename and real-device/provider
acceptance also remain open. This stage must not be described as completing all
rename/move scope requested by the user.

## Validation

All fixtures are synthetic. Focused core renderer-oracle tests and app planner /
warning / cancel tests run locally with `flutter test --no-pub`. Package publication,
publish dry-run, cloud metadata and user vaults are not used. Native Mac/iOS CI and
real-device acceptance are separate gates; Linux tests do not establish them.
