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
