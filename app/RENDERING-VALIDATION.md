# LLM principles corpus: macOS app validation

Verified on 2026-09-26, macOS 27 / Apple Silicon. Corpus:
`/Users/robinfai/Downloads/llm-principles-series/`.

Current implementation: Mermaid and supported standalone SVGs use native usvg
preprocessing and Flutter vectors. The WebView implementation described in the
earlier entries below is historical; it has been removed. Unsupported standalone
SVGs offer an explicit action to open the file in the system's default viewer.

## Fixes

- Connected the app's Mermaid callback to the shared native renderer. A local
  WKWebView displays SVG markers and Chinese labels, including HTML labels in
  linked SVG assets. The page disables scripts, navigation, and remote resources.
- Reused the example's dylib normalization in both macOS builds. Bundled Merman
  no longer refers to an absolute path on its publisher's build machine.
- Fixed Read-mode multiline links being clipped by table rows. Live editing
  retains the span representation needed for source projection.
- Connected relative Markdown links, heading fragments, local image previews,
  and external links. Existing dirty tabs are preserved. Sandbox denial now
  explains how to grant access with File → Open Folder….
- Escaped two probability-formula pipes on line 17 of the corpus's
  `MATH-NOTES.md`, restoring its table to three columns. Updated that file's
  `MANIFEST.sha256` entry. Original files are backed up at
  `/private/tmp/linefold-series-original/`.

## Automated evidence

- Root library: **896 tests passed**, including the table-height regression and
  Live link/source-editing regressions.
- App with `LLM_SERIES_DIR`: **208 tests passed**. The acceptance suite scrolls
  all **57 Markdown documents** in both Read and Live modes, checks for render
  exceptions and table-link overflow, and verifies source remains unchanged.
- All **25 Mermaid sources** render through the bundled native engine and
  decode in the Flutter test renderer. WebView fidelity is checked separately
  in the running app because widget tests do not instantiate native WebViews.
- Example: **5 tests passed**, including native Mermaid rendering.
- Repository static analysis, formatting, and `git diff --check`: passed.
- Release build and installed app's deep code-signature verification: passed.

Reproduce the corpus checks from `app/`:

```sh
flutter test --dart-define=LLM_SERIES_DIR=/absolute/path/to/llm-principles-series
```

## Actual app checks

The installed Release app at `/Applications/Linefold.app` was relaunched and
restored its document tabs and selected corpus workspace.

- `INDEX.md`: wrapped article titles remain within their table rows.
- `MATH-NOTES.md`: three columns and a complete conditional-probability formula.
- `articles/04-attention.md`: arrows, curved connectors and Chinese text render
  in Read and Live. Clicking the Live diagram exposes its editable source.
- Its SVG and PNG links open complete images inside the app.
- The directory link opens `articles/01-request-lifecycle.md`; the installed
  Release app also displays that chapter's branching Mermaid diagram.
- A file-only permission failure was reproduced before opening the corpus
  folder. Folder access allows sibling chapters and image assets to load.

Ordinary links are editable in Live and followed in Read. Embedded image syntax
and Wiki embeds remain outside the shell's current integration; this corpus
contains no embedded Markdown images.

## Mermaid scrolling follow-up (2026-09-26)

- Reproduced in the installed app: scrolling over body text moved the document,
  while the same scroll over the Mermaid surface did nothing. The embedded
  WKWebView consumed native AppKit input before Flutter received it.
- Added a display-only macOS WebKit surface with native input hit-test
  passthrough and a transparent Flutter `AppKitView`. Rendering still uses
  WebKit with JavaScript, navigation, and remote resources disabled.
- Native AppKit regression test demonstrates ordinary WKWebView input capture
  and verifies passthrough after resize/removal. Flutter tests cover wheel and
  trackpad scrolling in both directions, enclosing editor clicks, and SVG updates.
- App suite: **95 passed**, with the optional corpus test skipped. Static
  analysis, Release build, and deep code-signature verification passed.
- In the new Release app, `01-request-lifecycle.md` scrolls up and down with the
  pointer inside the diagram in both Read and Live. Chinese labels and arrows
  remain visible, and a Live diagram click still exposes its editable source.

## Production vector pipeline follow-up (2026-09-26)

This supersedes WebKit rendering for Mermaid blocks described above. Local SVG
image previews still use WebKit because linked files include HTML labels.

- The shared package now renders real source through merman `resvg-safe`, CSS
  normalization, and an FFI usvg 0.45.1 bridge. usvg expands markers and outlines
  system font glyphs; Flutter `SvgPicture` displays the resulting vectors.
  Mermaid blocks contain no WebView and disable pan/zoom by default.
- Rendering and font discovery run on a persistent worker isolate. Requests
  are deduplicated, edits debounced, stale completions ignored, and disposal
  settles pending futures. The worker LRU is bounded by both entry count and
  byte size, with preprocessing/font identities included in cache keys.
- **3 Rust tests**, **6 shared-package tests**, **213 app tests** with the
  corpus enabled, and **5 example tests** passed. All **25 Mermaid sources**
  used the new native pipeline; all **57 Markdown documents** were scrolled
  in Read and Live using the production document widget and those actual results.
- Seven production FFI/Flutter screenshots were compared to the demo vector
  references. Five matched exactly; state differed by less than 0.001% of pixels
  and Attention by 0.2042%, within the 1% tolerance. Outputs and metrics are in
  `packages/ianvs_mermaid/build/visual-regression/`. The demo was not modified.
- Regression checks cover wheel/trackpad movement across a diagram boundary,
  Live click-to-edit, late results, errors, disposal/reopening, cache limits,
  native errors for unsupported SVG features, and caller event-loop progress.
  These checks do not claim a measured end-to-end frame-time improvement.
- Root, app, example, and shared-package static analysis passed. Rust formatting,
  Clippy with warnings denied, Dart formatting, and `git diff --check` passed.
- A clean macOS arm64 Release build includes the signed
  `ianvs_svg.framework` and the corresponding native-asset mapping. The build
  hook explicitly discovers the macOS SDK because Flutter filters `SDKROOT`
  from hook environments. Deep code-signature verification passed.
- Actual Release app: `01-request-lifecycle.md` scrolls in both directions with
  the pointer inside the Mermaid surface in Read and Live. Live clicking still
  exposes the unchanged source. `04-attention.md` displays Chinese, arrows and
  curves correctly; its separate SVG file link still opens a complete image.
- Updated and relaunched `/Applications/Linefold.app`. The installed native
  framework matches the validated build's SHA-256, passes deep signature
  verification, and loads the Attention diagram with working in-diagram scroll.

Font discovery/fallback, cache bounds, unsupported features, platform status,
and build instructions are documented in
[`packages/ianvs_mermaid/README.md`](../packages/ianvs_mermaid/README.md).
There is no automatic bitmap fallback. System fonts are discovered, not bundled.

## Complete embedded-browser removal (2026-09-26)

- Removed `webview_flutter` and all three platform/interface dependencies from
  the resolved package graph. Regenerated the macOS plugin registrant and
  CocoaPods lockfile without the WebView plugin.
- Removed `ReadOnlySvgView`, its factory/project entries, native input test and
  test script, HTML wrapper, platform-view code, and the network-client
  entitlement. The debug network-server entitlement remains for Flutter tooling.
- Standard local SVGs now use background usvg preprocessing and Flutter vectors.
  Native integration verifies Chinese glyphs and markers become visible paths.
  HTML labels, active filters and other unsupported features show a clear message
  with an explicit **Open in default app** action. This changes the previous
  in-app support for those complex SVG files; Mermaid blocks are unaffected.
- **214 app tests** (including all 57 corpus documents and 25 diagrams) and
  **7 shared-package tests** passed. SVG tests verify source updates, stale
  results, disposal, input propagation, and the external-open callback/channel.
  App/shared-package analysis, Dart formatting and `git diff --check` passed.
- Clean macOS arm64 Release build and deep code-signature verification passed.
  Inspected all **12 Mach-O binaries**: no WebView/WebKit load commands or bundled
  WebView frameworks. Signed app entitlements have no network-client capability.
- Installed and relaunched `/Applications/Linefold.app`. A standard SVG preview
  displays Chinese/Latin text, color and an arrow; an HTML-label SVG displays the
  unsupported-content message and external-open button. Temporary test tabs were
  closed and the original corpus workspace and Attention article restored.

## Separate corpus packaging observation

The original manifest lists both `preview/INDEX.html` and `preview/index.html`
with different hashes. On this case-insensitive volume they resolve to one
file, so the latter hash check fails. This pre-existing HTML-preview packaging
issue does not affect the Markdown app checks. The previews and those manifest
entries were not changed; the repaired `MATH-NOTES.md` checksum matches.
