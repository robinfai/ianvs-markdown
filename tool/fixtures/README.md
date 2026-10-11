# AOT diagnostic inputs

These fixtures isolate compiler failures. They are outside the published package
and are not ordinary passing application tests.

- `macos_view_aot.dart`: public `IanvsMarkdownView` input for
  `tool/reproduce_macos_aot.py --component`.
- `ffi_callback_aot.dart`: standalone 17-line `dart:ffi` reproduction. On macOS
  arm64, unmodified Dart 3.12.2 and 3.13.5 fail with
  `Class with illegal cid, full-aot` for `Rect` (compiler wrapper exit 254).

Run the standalone fixture from the repository root with a stock Dart SDK:

```sh
mkdir -p build/aot-manual
/path/to/dart compile aot-snapshot tool/fixtures/ffi_callback_aot.dart \
  -o build/aot-manual/callback.aot
```

Record the Dart version, host architecture, exit status and complete output.
The failure is currently expected; a file at the output path alone is not a
successful compilation. Do not replace the optimized-away branch with `false`:
that is a different compiler path and passed in the recorded controls.

The diagnosis, experimental compiler patch, raw evidence and remaining platform
gates are in [the callback report](../../benchmark/AOT-CALLBACK-2026-10-11.md).
A diagnostic snapshot success does not count as platform acceptance.
