# G5: bounded batch reference maintenance

Supports **2–8 disjoint top-level notes and/or directories** moved to one existing
folder, preserving each basename. Existing multi-selection / Move to flows show
one global proposal. No sequential per-root planner or v1/v2 executor loop is used.

All mapping uses original addresses once. One final catalog, alias environment
and image index resolve references across all roots, including cross-root links.
An external note that references several roots is edited once. Exact-source
serialization, reparse proof, cancellation and conservative complexity limits
remain in use. Existing single-note v1 and directory v2 protocols remain valid.

Directory roots carry complete native member evidence. Individual notes use the
catalog/effective-source baseline; no dummy directory or fake text entry is used.
The whole proposal shares limits of 256 members (including top-level notes),
64 directory members, 128 affected texts and 32 MiB original + replacement text.
Unknown, offline, symlink, hidden/retained-artifact, dirty dependency, incomplete,
unsupported, case/NFC-equivalent and overlapping inputs remain blocked. Target
parents must already be in the local catalog. Arbitrary filesystem vacancy is
not established by preview: native preflight must establish it before mutation.

## v3 contract

`prepareWorkspaceBatchMove` receives `path`, `transactionId`, `roots`, and shared
`files`, `catalog`, `assets`. Every root has `sourcePath`, `destinationPath`,
`kind` (`note` or `directory`), and `tree` only for directories. Native sorts roots
canonically. Existing execute/cancel/list/reconcile/recover methods accept v3.

A v3 record has `namespaces` (2–8), no singular `namespace`, and shared file
receipts. Each root receipt includes kind, original identity, memberCount,
source/destination paths, moved/synced/verified, and optional observed actualPath.
A note root has memberCount 1; its original prepared inode is not confused with
the new inode created by a body swap. Directory identity is checked against its
approved inspection. File receipts retain exact current revisions and intended
final destination paths, with actual paths at source or destination as observed.

`completed` requires all root moves durably synced and verified at destination,
plus all affected files verified at intended destinations. Missing, duplicate,
mismatched or malformed evidence cannot qualify. The controller independently
checks the approved root set and file manifest, then rereads affected texts before
updating buffers. Bookmarks for all selected roots are invalidated before execute;
only independently verified destinations are remapped. Keystrokes made during
native work remain unsaved rather than being overwritten.

## Partial results and recovery

Global text updates precede individual root moves. This is **not an atomic batch**:
a failure may leave some roots at source after links have changed, temporarily
breaking references. Stop on failure, retain originals, and never automatically
retry/replay or roll back a partial/uncertain result. A lost reply is reconciled,
not re-executed. The UI shows each root as verified destination, verified source,
or uncertain and offers original-copy recovery rather than a blind retry.

Recovery storage inspection remains read-only and never calls reconciliation.
v2 namespace / v3 namespaces summaries are explicitly historical, not current
observations. Empty and image-only directory transactions with zero text entries
are valid only with versioned namespace evidence. Recovery copies consume space
and may sync; they do not complete a partially moved namespace.

## Verification

Planner tests cover simultaneous note/directory/image/alias mapping, BOM/CRLF and
exact source spans, shared budgets, overlap and normalized collisions, empty and
image-only roots, dirty dependencies, cancellation and hypothetical vacancy.
Adapter/DTO/controller/UI tests cover v3-only dispatch, strict schema validation,
all-success and mixed partial roots, mismatched prepared evidence, lost replies,
unsaved input preservation, sync-proof gates, explicit approval/cancellation,
and historical recovery summaries. Existing v1/v2 tests remain required.

Native macOS fault-injection and iOS build validation must pass before merging or releasing
this combined increment; Dart fake tests do not establish filesystem guarantees.
