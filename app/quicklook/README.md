# Finder preview client

The macOS Quick Look extension hosts this release-AOT Flutter entry point directly.
It uses the same Markdown package, Mermaid renderer, theme and default reading
styles as the application. It has no desktop editor plugins or browser runtime.

`../tool/prepare_quicklook.sh` resolves dependencies and generates style copies
from `../lib/src`; generated files must not be edited. The Xcode extension build
runs `../tool/build_quicklook.sh`, including both requested CPU architectures,
Flutter/App frameworks, SVG native assets and the offline Mermaid library.
CI signs all nested code inside-out before notarization.

The view follows system appearance and supports Chinese/English (English fallback).
It uses default reading preferences; per-workspace settings are not available to
the isolated extension. Document loading supports UTF-8/BOM and UTF-16/BOM up to
2 MiB. Images are bounded to 8 MiB, confined to the document directory and remain
subject to Finder's sandbox grant. Remote images are never fetched. Unavailable
images get text placeholders. Unsupported/oversized document errors return to
Quick Look's system fallback rather than leaving a spinner indefinitely.

Run `flutter test` here after preparing sources, and run
`bash app/tool/test_native_quicklook.sh` from the repository root for encoding,
size and image-access boundary tests. `verify_quicklook_bundle.sh` verifies the
packaged architectures, sandbox, metadata and nested signatures.

## Scrolling and native edit commands

The preview opts into `IanvsMarkdown(scrollable: true)`. It retains full-document
parsing for references/footnotes, but lays out and paints blocks through
`ListView.builder` (the same SliverList lazy layout and repaint-boundary mechanism
used by Live Preview). It does not mount the editable Live surface in Finder.
The default non-scrolling `IanvsMarkdown` API is unchanged.

The embedded Flutter controller terminates AppKit `copy:` and `selectAll:` actions
and invokes the shared Markdown command dispatcher. On macOS 27.0.1, clicking
preview text then pressing Cmd-C without a selection previously caused recursive
`QLUIServiceBaseViewController copy:` forwarding and stack overflow. This was
reproduced in Finder before the fix. Repeating the same steps after the fix kept
the preview alive; Cmd-A/C copied all 69,857 fixture bytes exactly.

## Local frame measurements (2026-11-04)

Build with `--dart-define=LINEFOLD_SCROLL_PROBE=true` to expose a temporary
**Measure scroll** control in both clients. The flag is off in normal builds.
It scrolls the actual mounted document from 0 to 2400 logical pixels and back,
6 seconds per leg, and records Flutter FrameTiming after each leg. JSONL files
are written to the host sandbox's temporary directory, with no document content
or network transmission. Keep the application foreground and avoid building
or running tests during measurement.

Measured in actual Finder Quick Look and the desktop application's Live mode,
Release AOT, Flutter 3.44.8, Mac16,7, macOS 27.0.1, 120 Hz display. All documents
had identical bytes (SHA-256 and full summary in
[performance/2026-11-04.json](performance/2026-11-04.json)). Finder used a temporary
host registering only `.lfnativeprobe`; the native extension and Flutter renderer
were copied from the built production bundle. The before case used the prior
SingleChildScrollView entry point with the same diagnostic wrapper.

| Actual surface | Frames | Build P95 | Raster P95 | Total span P95 | Total span max |
|---|---:|---:|---:|---:|---:|
| Finder before | 1446 | 3.874 ms | 0.716 ms | 4.545 ms | 74.487 ms |
| Finder after | 1470 | 0.708 ms | 1.200 ms | 2.001 ms | 8.371 ms |
| Application Live | 1440 | 1.353 ms | 1.705 ms | 4.672 ms | 17.780 ms |

Finder before/after used the same 900-point viewport; the application retained
its 671-point editor viewport and app chrome. The application numbers are a real
product comparison, not a controlled claim that one host is universally faster.
These are Flutter engine timings, not input-to-photon or WindowServer presentation
latency. The fixture contains 100 sections of Chinese/English paragraphs and
20 tables; this does not establish performance for every Mermaid/image-heavy
file. Raw captures from this session are in `/tmp/linefold-scroll-results/`.
