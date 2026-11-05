# Native Mermaid vectors (Pele)

Pipeline on macOS/iOS: Mermaid source → pinned Pele 1.13.0 JavaScript → system
JavaScriptCore public C API → CSS-variable resolution → Rust usvg 0.45.1 →
Flutter `SvgPicture` / `vector_graphics`. No Node, browser, WebView, WASM or
third-party JavaScript engine runs in the application. Node is only a build-time
tool for rebuilding the checked-in Pele bundle. The migration ships with Linefold 0.1.10.

## Build and provenance

The Dart Native Assets hook compiles `native/pele_jsc.c`, links the system
JavaScriptCore framework and builds the locked Rust SVG crate. Flutter packages
and signs both native assets. Rust/Cargo is needed on the build machine. Pele is
pinned in `tool/pele/package-lock.json`; rebuild with `npm ci && npm run build`
from that directory. `vendor/pele/provenance.json` records the version and
instrumentation details. The upstream MIT license is included alongside the
runtime. The generated bundle is a package Flutter asset.

The JSC renderer supports macOS and iOS only. Existing Rust SVG preprocessing
has other target mappings; this does not imply Pele support on those platforms.
After changing dependencies, run `flutter pub get` in each host. Remove stale
native asset build output before evaluating a distributable bundle.

## Execution, cancellation and explicit boundaries

Each `NativePeleRenderer` owns one serial background isolate and one JSC context.
The UI isolate never evaluates JS or touches the context. Disposal sets an atomic
cancellation watermark, settles pending futures, and requests worker shutdown.
The worker releases its context only after evaluation returns. There is no
cross-thread context destruction or isolate-kill shortcut.

The build transform inserts checks at every JS function entry and loop body.
Every 128 such steps, the public JS callback checks the monotonic deadline and
cancellation watermark. Catch handlers check immediately so internal catches
cannot swallow cancellation. A stopped evaluation destroys its context; the
next request creates a fresh one. Contexts are also recycled every 64 attempts,
including invalid parses, to release engine caches.

**This is cooperative interruption, not a hard execution or memory sandbox.**

- The default evaluation budget is 5 seconds for each runtime-load or render/
  parse evaluation. It is not an end-to-end document deadline. Queue wait,
  JSC garbage collection, font discovery, XML normalization, Rust usvg and Flutter
  picture decoding are outside it.
- A single JSC builtin (RegExp, sort, JSON serialization, etc.) cannot be
  interrupted through this public API mechanism. Cancellation/timeout is checked
  at the next checkpoint or after evaluation returns. A late result is rejected,
  but the builtin may already have exceeded the budget. There is no guaranteed
  wall-clock upper bound and no hard per-context heap cap.
- Recursive JS can exhaust the stack before the next check; it returns an engine
  error. Input/output bounds reduce exposure but do not prove bounded CPU or peak
  memory. Do not use this bridge to execute arbitrary user-supplied JavaScript.
- There are no private watchdog symbols, including
  `JSContextGroupSetExecutionTimeLimit`. The native regression checks an explicit
  allowlist of linked public JSC functions.

Default Mermaid input budget is 512 KiB UTF-8. Pele receives input/output budgets;
Rust SVG input is independently bounded at 8 MiB and expanded output at 16 MiB.
Pele's `maxEdges` is an edge limit for supported graph parsers, not a universal
model-item limit. At most 32 requests are pending. Identical in-flight renders
share one future. The worker LRU holds up to 64 entries / 16 MiB of string data;
this excludes transient JS/native trees, font data, Flutter/GPU caches and keys.
Cache identity includes source, options, engine/instrumentation version and fonts.

## Rendering and compatibility

Pele supplies deterministic built-in text metrics, without DOM or Canvas. usvg
outlines actual fonts; estimated layout and glyph bounds can differ. macOS uses
installed fonts. iOS embeds licensed Noto Sans CJK SC Regular, avoiding optional
system font dependencies. Fonts without outline tables and LastResort are excluded;
missing glyphs fail explicitly. No system fonts are redistributed.

Pele CSS variables are expanded before usvg. `--pele-*` overrides and a dark
palette are supported. Legacy Merman theme names/options are not equivalent to
Pele themes. `layoutJson` currently returns dimensions/type/link metadata, not
Merman's full layout graph; consumers requiring the old graph need adaptation.

Pan/zoom remains off by default so the document owns scrolling. Outlined text is
not directly selectable; `MermaidView` retains an accessibility label. Active
filters/masks/patterns, images, foreignObject, scripts, animation and unsupported
emoji remain explicit errors; there is no bitmap fallback. Standalone SVG preview
continues using the existing Rust pipeline.

## Validation

Run on macOS:

```sh
python3 test/native/pele_interrupt_test.py
flutter analyze
flutter test
flutter test test/mermaid_compatibility_test.dart \
  --dart-define=MERMAN_DOCUMENT=/absolute/path/private-document.md
```

The historical `MERMAN_DOCUMENT` test flag is retained for existing local scripts;
it now exercises Pele. Private document bodies are never committed. The supplied
AIGW compatibility copy (17 fences, not the malformed original) passes Pele → usvg
→ Flutter picture decoding without further source rewriting. ER names and Chinese
node IDs have dedicated public regression cases.

The interruption regression uses the exact production transform on nested infinite
loops with a catch handler. It checks actual native return, cross-thread atomic
cancellation, repeated context recovery and Chinese-node rendering afterwards.
A subprocess deadline protects the test runner if instrumentation breaks. The C
simulator probe uses the same bridge and fixture. These tests do not establish a
hard bound on uninstrumented builtins or constitute app/Finder UI acceptance.

Pele picture references live in `test/fixtures/pele-1.13.0/`. Regenerate deliberately
with `--dart-define=UPDATE_PELE_REFERENCES=true` and review the images before
accepting them. Historical Merman references are retained for comparison.
