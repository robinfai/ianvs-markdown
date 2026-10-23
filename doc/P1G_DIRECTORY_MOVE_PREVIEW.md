# Directory reference-maintenance preview and execution (G4a/G4b)

## Scope

G4a provides a read-only directory impact preview. G4b adds an explicitly
confirmed, single-directory transaction through the separate v2 namespace
protocol. It does not change the v1 single-note protocol or add recovery cleanup.
A complete proposal means supported-source coverage, not authority or durable
move proof. Native prepare rechecks the tree, exact bytes and all-object target
vacancy before any note mutation.

The explicitly confirmed **Move without updating links** action remains. It does
not apply proposed edits. Multi-selection still uses the warned manual flow.
Opening, cancelling or dismissing a preview never moves anything. A maintained
move requires **Move and update links** on the exact current proposal.
A PDF, hidden entry or unsupported object does not make its directory nonexistent:
the observed directory and specific blocking reasons remain visible.

## Independent complete-member manifest

`inspectWorkspaceDirectoryMoveTree` uses the selected workspace grant and real
member metadata, not the intentionally filtered Markdown/image catalogs. It
includes the source, nested directories, notes, images, unsupported regular
files, hidden entries, symlinks and special objects. Physical `.icloud` names are
not remapped into invented logical members. Unknown locality stays unknown.

Package/bundle blockers use a directory-constrained, registered filename-extension
type lookup. This recognizes supported system type declarations without opening
bundle contents for classification, but does not prove the absence of custom
packages with unrecognized extensions. Complete enumeration is not a complete
filesystem type-identification or execution-safety proof.

The descriptor-rooted implementation pins/rechecks root, parents and members,
does not follow descendant symlinks, and requires exact stored directory spelling.
All inspection filesystem access disables materialization. This endpoint reads no
note/image body, import settings, journal or other workspace. It never writes,
creates, repairs, downloads or calls mutation/reconciliation methods.

The result separates source state (`directory`, `missing`, `notDirectory`,
`unavailable`), enumeration completeness and issues. A discovered directory remains
a directory after cancellation, budget exhaustion or a race. Complete enumeration
does not waive unsupported members. The limits are 256 records, 64 directories,
1 MiB of encoded metadata and a 10-second cooperative scan deadline. Two admitted
inspections use the existing bounded directory lane. Cancellation is lock-only,
not queued behind the scan; a blocked call retains its slot until returning.
Cancel/deadline cannot interrupt an arbitrary filesystem call.

Dart checks envelope bounds and exact root/source/request correlation. Root/epoch
changes, disposal and dialog dismissal invalidate pending results. Late replies
cannot approve a move. There is no filesystem fallback or new permission grant.

## One simultaneous namespace

`WorkspaceMoveNamespace` maps path components for the entire subtree at once,
not by repeatedly planning individual note moves. One transformed catalog, Wiki
candidate/alias set and image metadata index is used for every occurrence's
before/after origin context. The original spelling is kept when it still resolves
to the same mapped identity. Otherwise a grammar-specific replacement is resolved
again, the source is reparsed, and all resulting references are checked.

This covers outside-to-inside links, moved notes' outgoing links, internal
relative links, basename/YAML-alias Wiki collisions and renderer-aligned Markdown
images/Wiki image embeds. Effective first-definition-wins shared target spans are
deduplicated. Labels, aliases, titles, fragments, queries, BOM, line endings and
unchanged text are preserved. There is no replace-all. Missing references that
would acquire a target block the plan rather than being silently repaired.

Moved notes remain in the proposal even when their text needs no change. Proposal
limits are 128 files and 32 MiB of original-plus-replacement UTF-8 text. Directory
comparison/resolver work is additionally bounded at 200,000 operations and a
20-second cooperative deadline, yielding between batches; neither limit can
interrupt a pending native call. Scope/content/catalog revisions must remain
current. Every mapped directory/note/image path is validated again: directory
paths allow at most 64 components (files 65), 4096 UTF-8 bytes overall and 255
UTF-8 bytes per component. These are conservative preview limits, not a claim
about every provider's filename capacity. Missing Wiki resolution does not compute
unused note-creation suggestions; each actual query/alias normalization is charged
and checked for cancellation. Ordinary Wiki navigation retains its creation flow.
Image metadata never claims that image bytes were read or verified.

Unchanged text reuses its existing complete parser evidence; it still undergoes
all before/after target-identity checks and, for moved notes, disk/local/dirty
checks. Changed text must pass directory-only reparse complexity limits: original
and proposed text each at most 16 Ki UTF-16 code units, at most 128 semantic
reference occurrences (unused definitions included), and no line longer than
512 UTF-16 code units. The original and projected sizes are checked before any
replacement-string construction; proposed line length is checked before parsing.
Exceeding these bounds gives an explicit incomplete complexity reason, never an
unverified complete proposal. Allowed reparses yield/check cancellation before
and after the synchronous parser. Ordinary single-note v1 behavior is unchanged.

These conservative input limits are based on synthetic measurements, not a
performance or hard-deadline guarantee. The pre-existing reference index's first
parse has its own budgets; it is not included in the new directory-planning
stopwatch. Blocking provider calls cannot be forcibly interrupted either.

## Visible conservative blockers

Execution requires a complete current preview and successful native preflight.
Coverage is incomplete for unknown syntax or ambiguous targets;
incomplete/changed catalogs, aliases or member evidence; unsupported files (PDFs
included); hidden/recovery artifacts, recognized packages/bundles, symlinks, special objects, hard
links or offline members; unsupported assets or missing stable image metadata;
dirty/conflicted moved or reference/alias-bearing dependencies; ghost buffers;
catalog-visible occupied/reserved destinations; unavailable parents; case/NFC collisions;
overlapping/equivalent paths; root moves; cross-device members; and any budget
exhaustion. These mean maintained movement is unproven, not that manual movement
of the item itself is categorically unsafe.

The source manifest covers every observed object in the moved subtree. Destination
collision checks cover only the note/directory catalog, image metadata and open
buffers. They do not prove filesystem-wide destination vacancy: an unsupported
regular file outside the source may be absent from those catalogs. The preview is not an all-object absence/conflict proof. The v2 native prepare
checks actual destination objects and same-volume parents; it never overwrites,
merges folders or creates missing target parents. Manual movement still uses its
existing collision checks.

## Separate v2 execution and receipts

V1 assumes one note namespace move. G4b does not loop that executor over members.
It sends the complete inspected tree, every moved note (even unchanged), changed
external notes, catalog and attachment dependencies to dedicated native prepare.
Empty and image-only directories have a namespace receipt with zero text entries;
no fake text record is used to represent a directory.

The result carries version 2 plus a directory namespace receipt. Successful UI
completion requires phase `completed`, `moved`, `synced`, `verified`, the exact
approved destination, source identity and member count, and verified destination
receipts for all note entries. Prepared evidence must instead identify the
original directory. Missing or mismatched evidence is uncertain, never success.
A lost reply is reconciled read-only, not replayed. Verified namespace movement
can remap the browser, selected paths and favorites. Each open note additionally
requires a fresh exact content/revision read; typing during native work is kept
as dirty text rather than replaced. Old affected bookmarks are invalidated and
persisted before mutation; new bookmarks are only renewed for verified paths.

Original text and displaced versions are retained for explicit recovery. New
artifacts follow the namespace only with a corresponding move receipt. Existing
recovery artifacts in the source remain blockers; no cleanup or relocation of
older journals is performed. Shared capacity limits still apply.

Failures expose actual partial state. No automatic rollback may overwrite other
writers; uncertain operations cannot be replayed merely from journal phase.
Text recovery copies are not an attachment backup. Per-file coordination and
repeated dependency scans are not a global lock or cross-file ACID snapshot.
Cross-volume moves, merging, multiple selected roots and batch path chains/cycles
remain unsupported. Recovery Trash cleanup remains a separate unfinished item.

Apple reference contracts:
- [WritingOptions.forMoving](https://developer.apple.com/documentation/foundation/nsfilecoordinator/writingoptions/formoving)
- [item(at:didMoveTo:)](https://developer.apple.com/documentation/foundation/nsfilecoordinator/item(at:didmoveto:))

## Validation boundaries

All fixtures are synthetic. Native tests cover ordinary/empty/image-only trees,
unsupported/hidden/recovery members, symlinks, exact spelling, budgets,
cancellation and observation races. Darwin execution and iOS compilation require
actual Apple CI; Linux syntax checks do not substitute for them. Dart tests cover
the unified graph and renderer image behavior, source-preserving edits, strict
DTOs, dirty/ghost/collision blockers, budgets, cancellation and root changes.
Compact enlarged-text UI tests use real taps and require explicit execution approval.
Existing v1 and mobile scope tests remain regression gates. Batch reference maintenance and recovery garbage collection remain unfinished.
Native execution claims require actual macOS CI; these source contracts do not
substitute for that acceptance.
