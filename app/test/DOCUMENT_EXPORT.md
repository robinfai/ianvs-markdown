# P2a basic offline export and print

## Product boundary

macOS File has Export HTML, Export PDF, and Print (Command-P). Each command
first captures the complete current buffer, including unsaved changes, then
shows a confirmation explaining fidelity. Continuing exports that snapshot,
not later edits and not a disk reread. Cancel performs no export or image reads.
Switching the active tab/root/path before native handoff invalidates the job,
even if the user switches back. After native handoff, the native sheet owns the
explicitly requested immutable snapshot; no further document reads happen.
The export does not save, mark saved, normalize or rewrite Markdown.

This is **basic export**, not pixel parity with Flutter or full Obsidian export:

- GFM structure, code text, CJK/emoji and document properties are included.
- Math/TeX and Mermaid are readable source rather than rendered diagrams.
- Raster attachments are the preview's bounded first frame, at most 2048 pixels
  on either side, re-encoded as PNG. Resizing metadata and animation are not
  preserved. Embedded image output is limited to 32 image occurrences / 16 MiB.
- Missing, offline, denied, unsafe and over-budget images are labeled
  placeholders with a reason in Export notes. Remote images are never loaded.
- Local/Wiki links are text, not portable vault links. Note embeds are not
  expanded. Raw HTML is escaped source, not active markup.
- Native share panel and higher-fidelity math/diagram export remain **P2b**.
  This candidate does not upload or send content to another person or service.
- iOS remains a reading-preview app. Shared Dart generation compiles there;
  this candidate does not add mobile editing or mobile export UI.

The fidelity summary appears before Continue and inside the output. Runtime
absolute document paths are not inserted into HTML. User-authored text is not
redacted: exporting a note intentionally includes the note's own contents.

## Safety and output

`DocumentExportService` uses existing core syntax classes plus the already
locked `markdown` dependency, declared directly by the app. It serializes a
small known AST tag set and escapes every text/attribute. No source HTML,
styles, event handlers, custom classes or arbitrary URL protocols survive.
Only HTTP(S), mailto and fragment hyperlinks remain; images are only generated
PNG data URLs. The document has a restrictive CSP. Input uses core's existing
1 MiB/4096-token/4096-character-line preflight; rejection creates no truncated
file. HTML is incrementally capped at 32 MiB of actual UTF-8 output, including
escaping expansion, each repeated image URI, document CSS/envelope and notices.
Fixed envelope/notices are charged before I/O; body/notice overflow stops before
later assets. PNG base64 size is checked before encoding. No completed unbounded
HTML string or UTF-8 byte-array copy is built merely to discover overflow.

Image lookup reuses the P1b repository, native scope, file signatures, codec,
pixel/working-memory limits and serialization. It never falls back to Dart
File or a network request. A scope adapter checks before and after every index,
settings, normalize and image await (also on failure). After invalidation, no new
native read starts; already-issued native I/O cannot be recalled. Generated PNGs
remove source image metadata.

macOS uses NSSavePanel with native existing-name confirmation. The output must
be `.html` or `.pdf`; all open-source document paths, symlink and hard-link aliases are
rejected. A metadata version captured after SavePanel approval is revalidated
inside NSFileCoordinator before replacement; a new target uses exclusive create.
Destination access errors and offline cloud placeholders fail closed. As with
other NSFileCoordinator clients, this protects cooperating writers, not an
adversarial process bypassing file coordination at precisely the commit point.

WKWebView is transient, nonpersistent, has JavaScript disabled, only accepts
the initial about:blank navigation, and installs a fail-closed content rule list
before loading generated HTML with no base URL. No document file URL or website
is loaded. Rendering has a 30-second startup timeout; direct PDF output has a
separate 60-second deadline with Core Printing cancellation. A one-shot gate
ignores late callbacks and releases Flutter/native busy state without committing
the user destination. The print delegate stays alive while AppKit unwinds; if
the OS never returns, its private temporary output is retained until terminal
cleanup (not deleted while still being written), and a subsequent PDF/Print
fails clearly rather than starting
a second active operation. HTML export remains available. These run-loop timers
are not a hard process-kill guarantee if AppKit blocks the main thread entirely.
Interactive print panels have no automatic timeout while the user is choosing.
HTML does not require a WebView. Direct PDF uses WKWebView's NSPrintOperation with A4 pages, print CSS
and a private temporary output, then checks it with PDFKit before committing the
user destination. It does **not** call createPDF to make a single tall page or
wrap a screenshot in PDF. Print uses the same document through the native print
sheet; system PDF destination choices are user controlled.

## Automated evidence

Linux local checks (Flutter 3.44.0 / Dart 3.12.0):

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub test/document_export_service_test.dart test/document_export_flow_test.dart`:
  21 tests cover escaping/protocols, CJK/GFM/front matter, attachment formats and
  budgets, source/output rejection, cancellation, scope invalidation, dirty
  snapshots, later edits, recoverable native failure, incremental Unicode/escape/
  repeated-image budgets, and cancellation at all four native I/O boundaries.
- Full app run after syncing main 5bcdf8e: 763 pass, 4 skipped, 17 fail on Linux. The 17 failure names exactly
  match the established P1h Linux baseline; this is not a full green/native gate.
- Tests use only synthetic source and fixtures. No real notes are enumerated.

The following native gate is implemented but **not run on Linux**:

1. `test-document-export-fixture` (also included in `test-app`) writes `build/export-qa/pagination.html` using the production
   generator: CJK/emoji, 150 rows x 4 columns, repeated header and long code.
2. `make test-native-document-export` compiles the actual native export source,
   produces a real PDF and tests source SHA-256, overwrite/collision, aliases,
   permission failure and offline placeholders. An independent Python watchdog
   enforces a 120-second process deadline even if AppKit blocks the main thread.
   A timeout is a failed gate (exit 124), prints the last flushed phase marker,
   and kills only the isolated synthetic test process group. Portable regressions
   cover success, failure and stopping a blocked test with its child process.
3. Native lifecycle fixtures check loading/output timeouts, cancellation,
   ignored late completion, loading-timeout owner release/terminal cleanup exactly
   once, and an interactive print panel with no time limit.
   Destination tests include a symlink source with a hard-link output alias.
4. PDFKit verifies at least three A4 pages, selectable Chinese, all 600 cells,
   repeated header on each table page, complete long code and no horizontal
   out-of-page character bounds. It retains PDF, extracted text and first/last
   page PNGs in `build/export-qa/native` for visual review.
5. Native integrations CI runs the focused fixture and bounded PDF first, then
   all remaining original host/native gates without repeating the native PDF,
   and uploads the evidence. `check-integrations` still aggregates every gate.
   It also builds the actual macOS app and unsigned iOS reader. Passing Dart
   mocks or source inspection is not evidence that native printing works.
6. All four Debug/Release + Local entitlement files declare app sandbox and
   com.apple.security.print. CI checks both these declarations and the built
   Debug/Release app code-signature entitlements. The standalone Swift harness
   is not sandbox app runtime evidence.

## Manual acceptance still required

In the actual signed, sandboxed macOS Debug and Release app, use synthetic
documents to check Export PDF and Print; compilation, entitlement inspection and
the standalone harness cannot establish sandbox printing success. Any system
permission prompts must be handled explicitly by the user, never auto-approved.
Also check SavePanel Cancel, replacing an
existing export after the native confirmation, changing filename/extension,
Print preview paging, printer cancellation, PDF open/search and rendered CJK,
emoji, dense tables and long code. Recheck sandbox destination access and
placeholder behavior on a real file-provider folder without downloading a vault.
Readability and printer/device behavior must not be claimed from compilation.

Apple API references:

- https://developer.apple.com/documentation/webkit/wkwebview/printoperation(with:)
- https://developer.apple.com/documentation/appkit/nsprintoperation/runmodal(for:delegate:didrun:contextinfo:)
- https://developer.apple.com/documentation/appkit/nsprintinfo/attributekey/jobsavingurl
- https://developer.apple.com/documentation/pdfkit/pdfpage/characterbounds(at:)

- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.print
- https://developer.apple.com/documentation/appkit/nsprintinfo/pmprintsession()
- https://developer.apple.com/documentation/applicationservices/core_printing
