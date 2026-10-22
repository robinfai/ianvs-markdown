# P1b: read-only Obsidian image attachments

This phase connects the Linefold desktop editor and iOS reader to the same
scoped image loader. It does not change the reusable renderer's zero-I/O default
or its public API. Importing/pasting new files is a later phase.

## Supported behavior

- Open a vault/folder explicitly. The current document must be inside that
  workspace. Opening an individual document never grants its parent directory.
  An iOS single-file import does not import attachments or search the original
  file's parent. The placeholder explains that a folder/vault must be opened.
- Standard Markdown image destinations resolve relative to the current note,
  then from the vault root if the unqualified relative destination is absent.
  A leading `/` means the vault root, not the OS root.
- Block Wiki embeds resolve a unique basename or path suffix across the vault.
  A complete vault-relative path disambiguates duplicates. Exact full paths win;
  a case/NFC fallback must be unique. Wiki percent characters are literal, not
  URI-decoded: `![[literal%20.png]]` selects that exact filename. No real-app
  round-trip claim is made for unusual percent names. Indexes retain actual names.
- The current `imageBuilder` receives a Dart `Uri`, which may already normalize
  `./` and encoded dot segments. The app does not rewrite source to recover that
  spelling. It decodes remaining percent sequences once, verifies the resulting
  path remains inside the vault, and passes only an indexed, normalized relative
  path to native code. Native code never URL-decodes a filename. Double-encoded
  names therefore cannot become a second traversal.
- Root, fixed attachment folder, note folder, and note-subfolder fixtures work.
  `.obsidian/app.json` is read-only, at most 64 KiB, and only
  `attachmentFolderPath` is retained. This is a new-file destination preference,
  not a restriction on where old attachments can be found. Missing, invalid,
  oversized or refused settings do not hide existing images. The raw settings
  spellings `/`, empty, `./` and `./assets` are adapter fixtures, not a claimed
  stable Obsidian configuration API or a verified real-app round trip.
- PNG, JPEG, GIF, WebP and BMP are decoded, not accepted solely by extension.
  Allowed content signatures and successful real decoding are both required;
  other codec formats disguised with an allowed suffix are refused. Animated
  formats show their first frame only when the original sides are at most 2,048
  pixels; oversized animations return a memory-limit placeholder before taking
  the first frame because Flutter's multi-frame codec ignores target sizing. The existing core size wrappers
  support `![[image.png|250]]`, `![[image.png|100x145]]`, and Markdown image sizes.
- Standalone/block `![[...]]` is supported. Inline Wiki images remain outside
  this phase and do not load. SVG, AVIF, PDFs and note embeds are not handled by
  this automatic raster loader. Remote URLs, `file:`, and other schemes do not
  trigger automatic access. Explicit user-opened image dialogs remain separate.
- Rendering and switching source/live/reading modes do not edit the text, change
  line endings, mark the document dirty, or change notes/settings/attachments.
  The authorized iCloud provider may download a selected existing attachment,
  as described below; this is not a general remote-image network loader.

## Scope and resource limits

The app has no portable `File` fallback for automatic attachments. Native
`CloudWorkspace` exposes a separate `listAttachments` index and
`readAttachmentBytes` capability, each with an explicit root. This does not add
attachments to the Markdown sidebar or the iOS document list.

Native reads pin a directory descriptor, reject a symlink root, open descendants
with `openat`/`O_NOFOLLOW`, reject symlink files/configs/directories, and verify
root identity and the coordinated URL. OS ancestor aliases such as `/var` are
allowed; no links below the selected root are followed. Special files are not
read. Only the exact `.obsidian/app.json` hidden path is permitted for bytes;
other hidden entries are not indexed or read. Names with unsupported control
characters, backslashes or colons are skipped individually during enumeration;
they cannot invalidate the entire index and are refused by byte reads.

Enumeration reads metadata only, with 10,000 images, 50,000 filesystem entries
and 64 directory levels as hard ceilings. An incomplete index is rejected,
never used to guess that a basename is unique. Native revisions include inode,
device, size, nanosecond modification and change times, including for placeholders.

Image reads are capped at 32 MiB. Decoded headers are checked against 32 MiPixels;
preview output is capped at 2,048 pixels per side. A document has a 64 MiB decoded
cache with explicit image leases, serialized encoded reads/decodes, and no use of
Flutter's global image cache. Visible pinned entries cannot be evicted to exceed
the budget. A separate 256 MiB conservative decode-admission budget covers the
existing cache, two encoded-input copies, three source-sized RGBA decode/staging
copies and the target frame. Unpinned entries may be evicted to fit; real output
size is checked and charged again before caching. This is not a claim that total
process RSS stays under either budget; codec/platform overhead is not measurable
through this API. Source-pixel and working-memory ceilings can reject an image
even when its compressed bytes are small.

Visible documents refresh metadata every five seconds and on app resume or
workspace revisions. Slow enumerations do not overlap. Switching document/vault
or disposing a view invalidates old requests; stale results cannot update the new
view. Cache revisions distinguish timestamp-preserving atomic replacement.

The native adapter prevents implicit dataless-file materialization, requests
only a selected cloud attachment, and reports it offline while downloading.
Materialized reads use file coordination with cancellation after five seconds
and a separate attachment queue. Missing, offline, permission, invalid path,
index limit and decode/resource failures have distinct recoverable UI states.

## Verification and remaining platform checks

Synthetic Dart tests cover four directory fixtures, old attachments in other
folders, Chinese/spaces/URL encoding, case and NFC/NFD, duplicate names, dimensions,
settings errors, permission/offline errors, bounded decode/cache, replacement,
retry, pending work cancellation, both real app builder connections, and source
preservation. Small generated fixtures really decode PNG/JPEG/GIF/WebP/BMP; the
PNG dimension-bomb fixture is rejected before pixel decoding. Tests also lock
in the block-only Wiki boundary and single-file import scope.

`app/test/native_attachment_test.swift` uses only temporary synthetic directories
and is wired to `make test-native-attachments` and `make check-integrations`.
It covers byte fidelity, symlinks, redirects/root replacement, bounded indexing,
settings scope, permissions, offline stubs, coordination cancellation, cache
identity, and the unchanged document BOM contract.

Linux can run Flutter tests but cannot run these Swift/macOS checks. The native
CI must pass on the final commit before merge. The Native integrations workflow
also compiles the actual iOS simulator Debug entry and shared Swift bridge via
`make build-ios-preview` in a separate 30-minute job. It uses `--no-codesign`,
boots no simulator, and does not replace runtime/device testing. Its first run
is pending; a macOS build alone does not establish iOS compilation.
Real signed macOS/iOS sandbox,
Files-provider behavior, actual iCloud eviction/download and a real Obsidian
settings round trip remain manual acceptance tasks; no access to a real user
vault or installed Obsidian is needed for the synthetic tests.

### Local verification on 2026-10-22

- Flutter 3.44.0 / Dart 3.12.0, using existing offline dependencies and
  `flutter test --no-pub`.
- Initial attachment and explicit-image-viewer tests: **35 passed**. Review
  reproduced a 4,096² animated-GIF target-sizing bypass and a WBMP disguised as
  PNG. Regression fixes add content-signature checks, pre-frame animation
  rejection, source/actual-frame accounting, literal Wiki percent names and
  unsupported-native-name filtering. The expanded targeted set has **42 passed**.
- Initial full app suite: **462 passed, 4 skipped, 17 failed**. The failed test-name set
  is identical to the established Linux baseline (macOS native menus, Finder,
  window appearance/layout); this is not an all-green platform claim.
- `dart analyze --fatal-infos app`, changed Dart formatting, shell syntax,
  and `git diff --check` passed. Native tests remain not run on Linux.

- After the review fixes and the final P1a read-only Tab fix were integrated,
  the independently rerun full app suite was **469 passed, 4 skipped, 17 failed**,
  again with exactly the established Linux baseline failure-name set.
