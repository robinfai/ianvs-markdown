# P2a: HTML and Markdown copy export

## Delivered scope

macOS File exposes **Export HTML…** and **Export Markdown Copy…** only. Both
capture the complete current editor buffer when the confirmation dialog opens,
including unsaved changes. Later edits do not enter the snapshot. Export never
saves the source, changes its dirty state, switches its file association, uploads
content through an app service, shares it with another application, or reads a
cloud vault in bulk. A destination chosen in a system file-provider folder may
sync according to that provider and the user's existing settings.

- HTML is one self-contained UTF-8 file. The visible confirmation and exported
  notes explicitly explain basic fidelity: math and Mermaid are readable source,
  not rendered diagrams; images use their first frame and at most 2048 pixels per
  side; unavailable images get placeholders; local note links become text.
- Markdown is an exact UTF-8 copy of the **current buffer**, not a reread or
  byte-for-byte copy of an older disk version. It preserves buffer line endings,
  BOM and valid Unicode, including empty content. It does not parse Markdown,
  read images, copy attachments, rewrite relative links, or execute source HTML.
  The confirmation explicitly warns that relative image/note links remain
  unchanged and may not resolve at the new destination. Invalid Unicode and
  over-budget output fail instead of silently replacing or truncating content.
- This stage adds no mobile export interface. It preserves main's separately
  delivered reader-first iOS quick notes and guarded source editing; this export
  work does not expand them. The shared service compiles on iOS. Sharing and
  high-fidelity rendering are not part of this stage.

**PDF and Print are not delivered and have no menu, shortcut or native success
route here.** Their complete implementation and original failing acceptance
remain on `feat/p2-offline-pdf-print-wip` at
`6a571f906d40a496ccb96c940b57d41831735068`. That branch actually produced six A4
pages containing 600 cells, but failed acceptance: WebKit omitted later-page
table headers and Quartz text extraction mapped some CJK characters to radical
code points. NFKC fixes the title's compatibility form, not all code text. These
are unresolved requirements, not tests waived to claim PDF completion. No PDF,
WebKit print API or printing entitlement is needed by the copy-only stage.

## Safety and resource boundaries

HTML uses a Markdown AST allowlist, escaped text/attributes, a restricted link
protocol set, generated CSS and CSP. No source HTML, script, external stylesheet,
remote image fetch, file URL, source absolute path or user-supplied CSS is emitted
as active content. Ordinary links require a user's later click in their browser.
The generator does not promise to remove private text the author actually wrote.

The rendering preflight bounds source/tokens/line length. At most 32 local images
and 16 MiB of normalized PNG payload are admitted. HTML's **32 MiB UTF-8** output
budget is incremental: document headers, escaped Unicode, notices and every
repeated data URI are charged before append; overflow prevents later asset I/O.
Markdown copies bypass rendering limits but have the same incremental 32 MiB
UTF-8 output ceiling. Native output independently enforces that ceiling.

Image lookup reuses P1b's authorized root, Obsidian attachment settings, allowed
formats/signatures, decoder and memory budgets. It never falls back to Dart File
or network I/O. A scope adapter checks before and after every index, settings,
normalization and image await, including failure. Invalidation prevents new I/O;
an already-issued native read cannot be recalled. Generated PNGs remove original
image metadata. Only synthetic documents and attachments are used in tests.

NSSavePanel supplies the destination and its normal existing-file confirmation.
The extension must be `.html` or `.md`. All open-source paths and their symlink
and hard-link aliases are rejected independently of the replacement prompt.
A newly appearing destination fails exclusive create. A previously approved
file's metadata is rechecked inside NSFileCoordinator before atomic replacement.
This protects cooperating writers, not an adversarial process bypassing file
coordination at the exact commit point. Recognized legacy `.name.icloud`
placeholder name collisions and permission errors fail closed without reading
their data. This does not identify every provider placeholder representation.

Tab/root/source-identity changes permanently invalidate a snapshot before its
final approval. While the SavePanel is open, invalidation or flow disposal sends
an operation-ID-bound cancel. IDs include a fresh per-isolate random prefix so a
Dart restart cannot approve an old native panel with a reused counter.
**Cancellation messaging alone is not the commit guard:** after selection,
native retains the exact authorized URL and destination version, then asks Dart
for final `isCurrent` approval for that same operation. Before that approval, a
missing/false reply, cancellation or five-second approval timeout writes nothing
and releases scope. The user choosing a SavePanel destination has no timeout.

**Final Dart approval is the commit authorization/linearization point.** The
protected source set covers all documents open at that point, including paths
and aliases; any newly opened path before approval makes the request stale.
After approval, the native commit is synchronous. Subsequent cross-bridge
cancellations or tab/root changes cannot be guaranteed to arrive before its
write, and cannot undo it. Native no longer reports cancellation once committing.
The confirmation UI states that after Save is confirmed, switching tabs may not
prevent the copy. Source protection does not retroactively extend to documents
opened after this authorization point. Native's identity rechecks guard already
observed invalidation, not an imaginary continuously refreshed Dart state.

A 15-second deadline cancels a still-waiting NSFileCoordinator using Apple's
thread-safe `cancel()` API. A locked waiting/accessor/expired transition prevents
late accessors from writing; timeout is a failure, never success. Once the write
accessor starts, the deadline cannot cancel it or report that no write occurred.
Actual filesystem I/O remains synchronous and can stall the platform thread;
there is no claimed hard timeout or safe cancellation of an in-flight atomic
write. Duplicate/late selections, approvals and old cancellations cannot commit
or unlock a newer operation. Scope is retained until the commit returns.
See [Apple's cancellation contract](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel()).

## Automated gates and evidence

- Focused Dart service/flow tests cover injection, link protocols, CJK/emoji/GFM,
  front matter, attachments and all I/O invalidation boundaries, incremental
  escape/Unicode/repeated-image budgets, raw Markdown bytes, empty content,
  no attachment reads for Markdown, visible caveats, immutable dirty snapshots,
  cancellation, final cross-bridge approval and recoverable native errors.
- `test-document-export-fixture` writes synthetic `build/export-qa/document.html`
  using the actual HTML builder, plus its Markdown source. The corpus contains
  150 rows × 4 columns, CJK/emoji and long code. It is not a PDF assertion.
- `test-native-document-export` compiles the production Swift adapter. It checks
  exact output hashes, unchanged source SHA-256, empty Markdown, explicit
  replacement, collisions, permission errors, aliases (including a source
  symlink plus destination hard link), cancel/once-only completion, refused
  PDF/Print commands, final approval, old cancellation identity, racing target
  changes during approval, approval timeout and late callbacks.
- A 120-second process watchdog fails closed and kills only its synthetic test
  process group. Its three regressions cover normal result propagation and
  cleanup even if the leader exits before a surviving child. No timeout is a pass.
- Native CI keeps all pre-existing Host/native and transaction gates and all
  four macOS example/app Debug/Release builds. It also checks the actual signed
  app entitlements retain sandboxing without an unneeded print permission, and
  compiles the unsigned iOS reader. Export fixtures/logs are retained as artifacts.

Local Dart results are not evidence of Swift compilation or native UI behavior.
The new narrowed commit must pass its own native CI; previous PDF-branch build
success cannot stand in for it.

## Manual acceptance still required

In the real signed sandboxed macOS app, use synthetic notes to check both SavePanel
cancellation and native replacement confirmation, alternate directories and
extensions, unsaved/empty Markdown copies, tab/root invalidation and actual
file-provider permission behavior without downloading a vault. Open HTML in an
offline browser and inspect CJK, emoji, tables, source math/Mermaid, normalized
images and visible notices. Check that both exports leave the original and dirty
buffer unchanged. Compilation and injected destination tests do not prove that
these native UI/device interactions have been exercised.
