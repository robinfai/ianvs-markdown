# P2C: iPhone and iPad quick notes

## Deliberately small surface

The mobile main still starts in Reading. An explicit **编辑源码** enters a
multiline Source field, not the desktop editor shell. Save/Cancel are explicit;
leaving dirty Source confirms. There is no Live editor, rich task-toggle claim,
automatic camera/photo permission, clipboard-image collection, or hidden write
back to a sending app. Edit `[ ]` to `[x]` in Source for quick task completion.
Existing Markdown image paths and text are preserved as source.

The library offers safe-basename `.md` creation in its current folder and
metadata-only filename/path filtering. Relative Markdown links resolve against
the current note; Wiki names resolve inside the current root, with explicit
selection for duplicate basenames. No parent scan or grant is inferred from a
single-file import. Wiki aliases from YAML and block references are out of scope.

## Write and recovery boundaries

- Entering Source reads exact UTF-8 bytes, preserving BOM, CRLF, combining
  characters and emoji. Preview-only BOM stripping is not reused as a baseline.
- iOS native workspace activation returns a session-only root token. New and
  Save require that token and a root-relative path. Generic unscoped native
  writes and attachment creation are blocked on iOS; desktop behavior is unchanged.
- The native lease starts before enqueue and ends only when native I/O settles.
  A root change is refused while a write is pending. Dart never treats a timeout
  as proof of cancellation, unlocks an unresolved write, or starts a second save.
- Save compares exact bounded source bytes in one file-coordination claim. It
  walks from a pinned root through no-follow descriptors, does not recursively
  create directories, and revalidates parent and leaf identities at commit.
- Overwrite approves only the conflict's observed bytes. A newer version prompts
  again. Keep Both exclusively creates a new `.md`, then guarded-saves its empty
  baseline. A write failure can leave a new file, so failures are reported as
  unconfirmed and no automatic retry or cleanup deletes somebody else's file.
- New uses the existing complete-listing case/NFC collision policy and O_EXCL.
  Missing parents, placeholders, revoked access, invalid UTF-8 and >5 MiB bodies
  fail closed. No cloud library download is initiated for a new/save operation.
- Preview metadata/list refresh may continue during editing, but body refresh
  never replaces Source or its baseline. Scope generation protects A→B→A.
- Recovery is an isolated `LinefoldMobileDraft` namespace, reusing the verified
  atomic primary/backup store. Writes are serialized and snapshots captured
  before enqueue; no desktop tabs, bookmarks or tokens are loaded. Background
  flushing is recovery only, never an original-file save. OS force-kill can still
  interrupt an in-flight flush; the last complete backup is retained.
- Restore is explicit and only within the same freshly authorized root. It keeps
  the original source baseline so a changed external note still conflicts.
  Failed recovery I/O preserves damaged originals and visible dirty content.

No file API can exclude a malicious, uncoordinated filesystem writer changing
an object after the last check. Atomic replacement relies on cooperating
NSFileCoordinator writers, matching the existing P0 boundary.

## Synthetic validation

`make test-ios-preview` runs import and scoped native-save fixtures, plus mobile
controller, bridge, link and widget suites. `make check-integrations` includes
all app tests and the native guarded-save target. The native fixture compiles
production CloudWorkspace.swift with FlutterMacOS, not a stubbed module.

The Dart/widget suites cover byte preservation, conflict Cancel/Keep Both,
observed-version overwrite plus a third version, copy-name racing, permission
failure, pending writes/navigation, scope ABA, background recovery, broken draft
storage, explicit create/search/links, and iOS-target keyboard/undo/IME behavior.
Synthetic viewports include 375×812, 390×844, 768×1024, 1024×768,
812×375 and 844×390, with keyboard insets. Assertions check live field size,
controller/focus identity, composing range and selection, not static max-lines.

The native fixture covers root-token leases/ABA, root replacement, symlinks,
parent replacement, byte-exact BOM/NFC, limits, conflict and concurrent commit.
It uses temporary synthetic files only, not user iCloud or photos.

## Required Apple gates and honest limits

Linux tests do not prove Swift/UIKit compilation or file-provider integration.
Before merge, required CI must compile/run native fixtures and build the actual
unsigned iOS simulator main (`make build-ios-preview`). No new Runner project
file reference is required; the existing shared Swift source remains registered.

A physical iPhone/iPad smoke check remains necessary for Files/iCloud delayed
materialization and revoked folder grants, external keyboard input/undo, CJK IME
composition across rotation, app background/termination recovery, and unavailable
network states. Simulator build success alone is not that device validation.

If the original folder cannot be reauthorized (including an old app container
path), **恢复为新笔记** explicitly copies recovered source into a fresh exclusive
file in the current granted root. It does not copy attachments or change the old
file. The new Source still requires Save. Lifecycle events before recovery load
finishes cannot clear an unseen draft.

## Review regressions

Save rechecks Source after asynchronous recovery cleanup, so input delivered
before the busy frame paints cannot be hidden by closing the editor. New-note
and recovery-copy dialogs bind their initiating root epoch, and incoming imports
do not change that root while a dialog is pending. Cancel Source refreshes the
reader after discarding, without writing the draft to disk.

Error, recovery and Source-caption areas use scrollable budgets based on actual
remaining layout constraints. They do not clamp accessibility text or replace
sizing tests with static line limits. A 3.2× text scale, landscape keyboard,
save error and long recoverable filenames have explicit interaction regressions.

Every exclusive create uses a full bounded filename scan, including symlink and
special-file names, before O_EXCL. A display index that filters those entries
cannot be used as evidence that a case/NFC/placeholder alias is absent.
