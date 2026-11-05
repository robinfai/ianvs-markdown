# Native Mermaid vectors

Production pipeline: Mermaid source → Rust merman (`resvg-safe`) → existing CSS
normalizer → Rust usvg 0.45.1 → Flutter `SvgPicture` / `vector_graphics`.
The runtime uses FFI, with no CLI subprocess, generated fixture, browser, or
bitmap fallback. `MermaidView` defaults to `enablePanZoom: false` so a document's
scroll container owns wheel and trackpad input. Opt in to pan/zoom only for a
dedicated diagram viewer. Outlined text is not directly selectable; the widget
keeps its `Mermaid diagram` semantics label (customizable by the caller).

## Building

Install Rust/Cargo and the Rust target for the build architecture. The Dart
`hook/build.dart` compiles the locked Rust crate and declares a bundled code asset.
Flutter handles copying and signing both it and the pinned Merman 0.9.3 Native
Assets library. The old CocoaPods install-name build phases are removed.
The application, Finder client and test host all use the same ABI 3 package. End users do not need Cargo or separately installed fonts on iOS.

After adding this build hook to an existing checkout, run `flutter clean` and
`flutter pub get` once in `app/` and `packages/ianvs_mermaid/example/` to discard old native-asset
manifests. Normal subsequent builds are incremental. Do not run a clean/build
concurrently with another Flutter command against the same application.

macOS arm64 is verified in a signed Release build. The hook also maps macOS x64,
Linux arm64/x64, and Windows x64 Rust targets; those platforms require their
matching build toolchain, merman packaging and integration validation before
release. iOS arm64 devices and arm64/x64 simulators are supported; Android and web
targets are unsupported by this bridge.

## Worker, cache and fonts

Each `NativeMermanRenderer` owns a persistent isolate. It loads both FFI engines
there and runs merman, CSS normalization, font discovery and usvg there. Identical
in-flight requests share one future. There are at most 32 pending render requests;
overflow is reported, not queued without limit. The view debounces edits for
80 ms and checks its generation before scheduling work. FutureBuilder discards
late completions; a pending update displays its loader, not the old source's SVG.
Disposal settles pending futures and lets the current FFI call free its buffers
before the worker exits. A synchronous native call cannot be interrupted midway.

The worker's LRU retains at most 64 entries and 16 MiB of UTF-16 string payloads,
including SVG/dimension envelopes. Oversized results are not cached. This bound
excludes transient native trees, keys/objects, Flutter's separate picture cache
and GPU memory. Input SVG is limited to 8 MiB; expanded output to 16 MiB.
Keys include source, full render options, merman version, preprocessing version
and the selected family/system font inventory fingerprint. Fonts are a process
snapshot; restart after installing/changing system fonts. `cache:` configures
the worker cache limits; it does not share a mutable cache across isolates.

`fontdb` discovers installed fonts on the target OS. iOS embeds an unmodified
Noto Sans CJK SC Regular under the SIL Open Font License (see `rust/fonts/` and
the package LICENSE), adding about 16 MB to the native library. It is the first
iOS family and fallback candidate, so Chinese diagrams work offline without
depending on optional system fonts. Desktop retains its existing font preference.

Fonts lacking `glyf`, `CFF ` or `CFF2` outline tables are excluded. For example,
iOS 27's PingFangUI can be located with CoreText and accepted by fontdb, but lacks
these tables; selecting it makes usvg silently omit the text. LastResort is also
excluded because its boxes must not count as real Unicode coverage. Missing
families and glyphs fail explicitly. No proprietary system fonts are copied or
redistributed. Other non-macOS deployments must provision suitable
licensed Latin/CJK fonts and validate the resulting metrics and glyph coverage.
Custom engine openers must be isolate-sendable; use `libraryPath` in native tests
rather than capturing a pre-opened FFI engine.

## Verified scope

Seven live FFI examples match the reviewed Merman 0.9.3 references in
`test/fixtures/merman-0.9.3/` (the demo retains its historical 0.7.0 images):
Chinese flowchart and line breaks, sequence/dashes/activation bars, class hollow
arrowheads and diamonds, state transitions, 64 nodes, and two real article
diagrams. Actual Flutter output is exported to `build/visual-regression/`.
Native tests also exercise gradients and clipping. This is not proof of complete
SVG or Mermaid.js compatibility, nor an end-to-end performance benchmark.

Active filters, masks, patterns, embedded images, HTML `foreignObject`, script
and animation nodes, and color emoji/emoji sequences are rejected with a visible
error. Unused merman filter definitions are removed by usvg before this check.
There is no automatic raster fallback. The public `renderSvg` function uses the
same bridge on a background isolate for standalone SVG previews. In Linefold,
unsupported local SVG files show an external-open action; no embedded browser
is used. Mermaid source rendering is unchanged by that preview fallback.

Run `make test-mermaid` from the repository root on macOS. To validate the
production document widget, run `flutter test test/document_diagram_test.dart`
from `app/`. The optional LLM corpus test reads all 57 documents in Read/Live and
preprocesses all 25 Mermaid sources through the same native pipeline.

The [optional adapter example](example/) demonstrates `diagramBuilder`
integration. The repository's root `example/` is independent of this backend.


## Merman 0.9.3 migration

The official stable release fixes unquoted ER entity names and Unicode flowchart
node IDs; no parser fork is needed. Regression tests exercise both through
Native Assets, layout, SVG preprocessing and Flutter picture loading. Options
use schema 2, operation-specific resource limits and deterministic measurement.
Classic/Dagre is selected explicitly to retain a vector-compatible layout without
active ELK shadow filters. Only generated HTML-label fallback viewports allow
font overflow, avoiding clipped glyphs when outlined fonts exceed estimated widths.

The unpublished Flutter hosts override `meta` to 1.19.0 because upstream hooks
2.2 require it while Flutter 3.44 pins 1.18.0. This is an explicit, tested SDK
compatibility override; remove it once the supported Flutter SDK pin catches up.
iOS archive symbol preparation now builds the matching 0.9.3 official feature
recipe and verifies the ABI 3 entry point and UUID against its dSYM.

For a private document, keep it outside the repository and run:

```sh
flutter test test/mermaid_compatibility_test.dart \
  --dart-define=MERMAN_DOCUMENT=/absolute/path/document.md
```

The supplied AIGW document is 25,416 bytes with 17 Mermaid fences. On 0.9.3 its
original ER block works; other malformed blocks still fail. A local copy with
statement newlines restored, mixed-quoted subgraph labels quoted as a whole, and
Go `interface{}` represented as `any` passes all 17 through the production chain.
ER entity names remain unquoted and the Chinese node ID remains unchanged.
Neither the original document nor private diagram bodies are committed here.
The ER and Chinese-node diagrams were also inspected in the macOS application
and Finder Quick Look using isolated test hosts. macOS Release bundle validation,
iOS simulator compilation, and an unsigned iOS archive were checked; this does
not substitute for a signed device or TestFlight acceptance run.
