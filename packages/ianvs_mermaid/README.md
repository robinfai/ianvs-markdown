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
Flutter handles copying and signing it. The existing macOS merman library
normalization remains in `tool/normalize_macos.sh`; merman is still the diagram
engine. End users do not need Cargo or separately installed fonts on iOS.

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

Seven live FFI examples match the demo's Flutter vector reference images:
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
