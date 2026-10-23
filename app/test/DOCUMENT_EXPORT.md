# P2a: practical HTML, Markdown copy and PDF export

## Delivered scope and fidelity contract

macOS File exposes **Export HTML…**, **Export Markdown Copy…** and **Export PDF…**.
Each captures the complete current editor buffer when its confirmation opens,
including unsaved changes. Later edits do not enter the snapshot. Export never
saves the source, changes its dirty state or file association, uploads through an
app service, shares with another application, or reads a cloud vault in bulk.
A destination in a system file-provider folder may sync according to that
provider and the user's existing settings. **Print and Share are not exposed.**

The user explicitly changed the PDF/HTML goal on 2026-10-23 to roughly 90%
fidelity. This is implemented as a practical acceptance contract, **not a measured
percentage**: readable body and major structures, recognizable authorized images,
complete table cells and code content, bounded multipage layout, and no obvious
horizontal text clipping. It does not relax source protection, authorization,
resource limits, cancellation, offline behavior or data integrity.

- HTML is one self-contained UTF-8 file. The visible confirmation and exported
  notes explain basic fidelity: math and Mermaid are readable source, not
  rendered diagrams; images use their first frame and at most 2048 pixels per
  side; unavailable images get placeholders; local note links become text.
- PDF renders that same safe HTML into real A4 pages using the system offline
  WebKit/AppKit print backend, then saves a separate `.pdf`. It is not a screenshot
  or a pixel-identical Flutter rendering. The confirmation and PDF notes also
  disclose viewer-dependent copy/search text and reading order (including
  punctuation), Chinese characters mapping to visually similar CJK radicals,
  first-page-only table headers and an occasional blank trailing page. Font metrics,
  line breaks and page breaks can differ from the editor. Native PDF paper size
  is selected by NSPrintInfo; standalone HTML does not force A4 when the user
  later prints it from a browser. Production accepts
  at most 256 pages and 32 MiB, rejecting rather than truncating larger output.
- Markdown is an exact UTF-8 copy of the **current buffer**, not a reread or
  byte-for-byte copy of an older disk version. It preserves buffer line endings,
  BOM and valid Unicode, including empty content. It does not parse Markdown,
  read images, copy attachments, rewrite relative links, or execute source HTML.
  The confirmation warns that relative image/note links remain unchanged and
  may not resolve at the new destination. Invalid Unicode and over-budget output
  fail instead of silently replacing or truncating content.
- There is no new mobile export interface. The shared service compiles on iOS;
  main's reader-first quick notes and guarded source editing remain unchanged.
  The internal macOS printing entitlement supports PDF generation only; it does
  not mean a user-facing Print command has shipped.

### Deliberately changed acceptance, with the old evidence preserved

The earlier strict implementation remains at `feat/p2-offline-pdf-print-wip`,
`6a571f906d40a496ccb96c940b57d41831735068`. It produced six A4 pages with all 600
table cells, but failed the old repeated-header and exact CJK extraction checks.
The separate `diag/p2-offline-pdf-system-fonts` history, including
`9786ff9f8ae7ffb0b0fe3a3eb7d5cd9ba0b317c7`, records strict font diagnostics: even a
local Songti/Heiti combination did not distinguish 文 from the literal radical
⽂ in extracted text. Those findings are **known limitations**, not repaired
Unicode or evidence of perfect copying. The practical gate records raw CJK text
and header counts without normalizing/replacing them to manufacture a pass.
It does not import the diagnostic font matrix or its PNG helper into production.

The first practical run (`b62a29e`) generated seven A4 pages, with the final page
blank. Poppler, pypdf and MuPDF independently found all 600 cells exactly once,
all 35 code runs and image boundary markers; all seven pages were visually
reviewed. Body/Chinese/emoji/code/image text was readable, the colored image was
present and the simple inset restored the right border. Native geometry/images/
safety and signed builds passed, but the first content fixture failed because
PDFKit reordered underscores: for example `CELL_0_A` became
`CELL\n0\n_\n_\nA`, and `IMAGE_START` became `IMAGE\nSTART\n_`.
Its page-one header diagnostic was likewise a false absence. These are
reader-dependent extraction observations, not evidence that manual Preview copy
was exercised. The test-only pinned pypdf gate checks the unchanged actual PDF;
it does not repair the PDF's semantics or promise identical search/copy in every
viewer. The blank tail page is a disclosed minor pagination imperfection.

## Safety and resource boundaries

HTML uses a Markdown AST allowlist, escaped text/attributes, a restricted link
protocol set, generated CSS and CSP. No source HTML, script, external stylesheet,
remote image fetch, file URL, source absolute path or user-supplied CSS is emitted
as active content. Ordinary links require a user's later click in a browser.
The generator does not remove private text the author actually wrote.

Rendering preflight bounds source/tokens/line length. At most 32 local images
and 16 MiB of normalized PNG payload are admitted. HTML's **32 MiB UTF-8** output
budget is incremental: document headers, escaped Unicode, notices (including PDF
limitations) and every repeated data URI are charged before append; overflow
prevents later asset I/O. Markdown bypasses rendering limits but keeps the same
incremental 32 MiB UTF-8 ceiling. The native writer keeps that ceiling for all
three formats; adding PDF does not enlarge the HTML/Markdown allowance.

Image lookup reuses P1b's authorized root, Obsidian attachment settings, allowed
formats/signatures, decoder and memory budgets. It never falls back to Dart File
or network I/O. A scope adapter checks before and after every index, settings,
normalization and image await, including failure. Invalidation prevents new I/O;
an already-issued native read cannot be recalled. Generated PNGs remove original
image metadata. Tests use only synthetic documents and attachments.

The transient PDF WebView uses a nonpersistent data store, disables content
JavaScript, loads HTML with no file/base URL, blocks navigation, and installs
resource rules permitting only the initial blank page and embedded PNG data.
No new fonts, remote JavaScript or rendering dependencies are downloaded. This
is an app resource policy, not a claim to control all OS font-service behavior.
A loading deadline (30 seconds) and output deadline (60 seconds) return failure,
not partial success. Cancellation is a request: the AppKit job, its lease and its
UUID-private temporary directory stay alive until the actual terminal callback.
If the system never returns, a later PDF attempt fails busy rather than reusing
an active print context; restarting the app may be necessary. A bounded process
watchdog separately protects the automated fixture, not a production OS worker.

A completed private PDF is checked for regular-file identity, single link and
size before parsing. `O_NOFOLLOW` opens one descriptor, metadata is rechecked,
and bounded reads reject growth; PDFKit receives only the checked bytes. Output
must be readable and within the page limit. The bytes are retained before the
renderer removes its temporary directory, so asynchronous approval never depends
on a deleted URL. No final destination is written during PDF preparation.

NSSavePanel supplies the destination and normal existing-file confirmation. The
extension must match `.html`, `.md` or `.pdf`. All open-source paths and their
symlink/hard-link aliases are rejected independently of that prompt. The exact
chosen URL and destination version are captured at selection and retained across
PDF rendering and final approval; they are **not refreshed after rendering**.
A newly appearing destination fails exclusive create; replacement metadata is
rechecked inside NSFileCoordinator before atomic write. This protects cooperating
writers, not an adversarial process bypassing coordination at the exact commit
point. Recognized legacy `.name.icloud` placeholder collisions and permission
errors fail closed without reading their data; not all provider placeholders
have that representation.

Tab/root/source-identity changes permanently invalidate a snapshot before final
approval. During the SavePanel or PDF preparation, invalidation/disposal sends
an operation-ID-bound cancel. IDs have a per-isolate random prefix. Cancellation
messages alone are not the commit guard: only after selection, and after PDF
preparation if needed, does native request final Dart `isCurrent` approval for
that same operation. Missing/false approval, cancellation or a five-second
approval timeout writes nothing. Choosing a SavePanel destination has no timeout.
Late results or approval cannot revive a cancelled request or affect a new one.

**Final Dart approval is the commit authorization/linearization point.** The
protected source set covers documents open at that point; any newly opened path
before approval makes the request stale. After approval the commit is synchronous.
Later cross-bridge cancellations/tab changes cannot be guaranteed to arrive
before its write or undo it. Native no longer reports cancellation once committing.
The confirmation explains this boundary. Protection does not retroactively
extend to documents opened after authorization.

A 15-second deadline cancels a still-waiting NSFileCoordinator using Apple's
thread-safe `cancel()` API. A locked waiting/accessor/expired transition prevents
late accessors from writing. Once the write accessor starts, the deadline cannot
cancel it or report that no write occurred. Actual filesystem I/O is synchronous
and can stall the platform thread; no hard deadline for an in-flight atomic write
is claimed. Scope is retained until commit returns.
See [Apple's cancellation contract](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel()).

## Automated gates and evidence

- Focused Dart tests cover injection/link protocols, CJK/emoji/GFM, front matter,
  authorized attachments and all I/O invalidation boundaries, incremental escape/
  Unicode/repeated-image budgets, raw/empty Markdown, no Markdown attachment I/O,
  visible limitations, dirty immutable snapshots, cancellation and final approval.
- `test-document-export-fixture` uses the actual production HTML builder. The
  original corpus keeps 150 rows × 4 columns, Chinese/emoji and the full original
  long code. A recognizable synthetic color PNG is loaded through AttachmentSource.
- `test-native-document-export` preserves every HTML/Markdown roundtrip, identity,
  collision, cancellation and blocked-presenter test. Added PDF safety tests cover
  rendering cancel/late result, approval cancel/timeout/late true, changed targets
  during rendering and approval, aliases, byte/page limits, lease ownership and
  terminal-only cleanup. Render/callback races use an injected renderer; the real
  job also exercises cancellation/timeout before loading completes. These do not
  prove a real in-flight AppKit worker cancellation followed by its terminal
  delegate callback. That combined path remains a manual native coverage boundary.
  The real rendered-PDF fixture is an uncancelled successful job. Print/Share
  commands remain refused.
- The real PDF gate requires all 600 cell markers exactly once and code/CJK/image
  boundary markers through a mandatory independently implemented pypdf content
  checker, pinned to pypdf 6.21.2 by version and official PyPI wheel hash in a
  temporary CI-only venv (Python 3.11 or newer; no product dependency). Missing/
  duplicate markers, fewer than three table pages or missing code/image tails
  fail; PDFKit raw
  marker/header observations remain diagnostic and are not silently reordered.
  Native tests still require reasonable multi-page A4 geometry, text character
  bounds and actual image resources. A fixture outside 3…30 pages saves a failure
  report and raw text before stopping, without generating unbounded screenshots. A valid fixture
  emits raw text, diagnostics and **all-page PDFKit thumbnails**
  for visual review of CJK glyphs, body/code/table readability, the color image and
  clipping. CJK copy mappings and repeated table heads are observations, not hard
  fidelity gates under the user's revised contract. No global normalization is used.
- A 120-second process watchdog fails closed and cleans only its own process group
  on timeout/error. The separate independent-content regressions and extraction
  each have a 60-second watchdog; neither stage may be skipped. Five watchdog regressions cover results, leader-exit cleanup and cleanup
  errors; a timeout is never a pass. This is not an OS-wide resource guarantee.
- Native CI keeps all pre-existing Host/native and transaction gates, four macOS
  example/app Debug/Release builds and the unsigned iOS build. Source and actual
  signed app checks require sandboxing and the minimal print entitlement used by
  the PDF backend. Export fixtures/logs are retained as artifacts.
- Before those longer builds, an attempt-named early export-only artifact is
  admitted only if its checkout-anchored sequential metadata check rejects symbolic
  links in every path component below the trusted checkout and finds regular files,
  no symbolic links/special files, at most 64 files/128 entries, 32 MiB per file and 64 MiB total
  including logs/reports. Oversize evidence fails the check and is not uploaded by
  that early step; it is not truncated into a pass. This is not an adversarial
  filesystem snapshot. The original final rendering artifact and every gate remain.

Local Dart/static checks are not evidence of Swift compilation, rendered PDF
quality or native UI behavior. Each new head requires its own native CI and
artifact review; old PDF/font diagnostics cannot stand in for practical acceptance.

## Manual acceptance still required

In the signed sandboxed macOS app, use synthetic notes to check SavePanel cancel
and replacement confirmation, alternate directories/extensions, unsaved and empty
Markdown, tab/root invalidation, and file-provider permissions without downloading
a vault. Open HTML offline and PDF in Preview; inspect Chinese/emoji, tables,
long code, math/Mermaid source, images, pagination and visible notices. Verify all
exports leave the original and dirty buffer unchanged. Injected destinations,
PDF artifacts and signed compilation do not prove these native UI/device actions
were exercised. Print and Share are explicitly deferred to another stage.
