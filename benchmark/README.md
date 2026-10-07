# Live editor performance baseline

Run this benchmark on an idle Mac. It opens the minimal example host, performs
the workload automatically, writes evidence to `build/benchmark/`, and exits.
It uses profile mode; debug widget-test timings are not performance evidence.

```sh
python3 tool/run_benchmark.py --label after
```

To reproduce the pre-cache behavior with the same harness, use
`--label before --force-document-parse`. This internal diagnostic switch forces
the Live document refresh on every controller notification; it keeps the public
callbacks and editing behavior unchanged. Do not enable it in a product build.

The deterministic generator in `corpus.dart` produces exactly 10,240, 102,400,
and 1,048,576 UTF-8 bytes. It combines Chinese/English paragraphs, a long physical
line, headings, lists, tasks, code fences and tables. Corpus version, generator
hash, byte/unit/line/block counts, SDK, OS, CPU, actual view size, editor hash,
and raw measurements are retained in each JSON result.

Each operation has 5 warmups and 20 measured samples by default. Use `--warmup`
and `--samples` to change them; compare runs with the same values. Run both
default budgets and `renderBudget: null` against only this controlled corpus.
The result identifies whether Reading mode uses Markdown or the bounded plain
text fallback. Live Preview budgets apply per rendered block. Those workloads
must not be combined into one performance claim.

## Measurements

- `initialDisplay`: create a new controller/editor, mount, and complete the
  autofocus projection. The Dart/Flutter process is already warm; this is not
  cold application startup or disk loading.
- `selection`: move `IanvsMarkdownController.selection` within the first active
  paragraph, including the resulting focused-field projection and frame. This
  measures host-driven selection, not the entire OS keyboard event path.
- `typing`: send one character through the focused `EditableTextState` input
  update path, including the editor formatter. This is synthetic input, not a
  claim about physical keyboard or IME latency.
- `modeSwitch`: cycle Source → Reading → Live. The distribution mixes those
  transitions; use raw samples for further attribution.
- `scroll`: jump between the top and offsets up to 1,200 logical pixels in Live
  Preview; it measures a viewport update, not a full-document animated scroll.

Latency runs from the action through the next completed UI frame; initial
display includes its extra mount/focus frames. Frame build/raster durations
come from `FrameTiming`. Its callbacks are batched, so each phase drains them
for 1.1 seconds before and after sampling. Frame distributions can include
settling/caret frames and have their own sample count.

`documentParses` counts the Live editor's `_refreshBlocks` operation, which
refreshes references, highlight spans, footnotes, block structure and heading
folds. It does not count every inline renderer, Reading parser, or controller
reference scan. `rssMiB` is total process resident memory, including Flutter,
native code, caches and history; it is not isolated Dart heap usage. Results
include P50, P95, maximum and every raw sample. Do not set absolute regression
thresholds from one pair of runs; repeat fresh-process runs to establish noise.

## macOS AOT prerequisite

During the 2026-10-07 run, stock Flutter 3.44.0, 3.44.8 and 3.47.6 all failed
profile AOT compilation in `_window_macos.dart`'s `_Rect`, matching
[Flutter issue #191575](https://github.com/flutter/flutter/issues/191575).
No performance result is inferred from these failed builds.

For a controlled single-window measurement, the runner can apply the included
one-line patch to a **disposable SDK in a system temporary directory**. This
disables the unused experimental windowing path. It refuses to patch a normal
SDK installation. Both comparison runs must use the same patched SDK:

```sh
git clone --branch 3.47.6 https://github.com/flutter/flutter.git /tmp/ianvs-bench-sdk
python3 tool/run_benchmark.py --label after \
  --flutter /tmp/ianvs-bench-sdk/bin/flutter --windowing-workaround
```

The exact SDK patch and feature-file hash are stored in the result. These are
controlled component measurements, not validation of an unmodified Flutter
release build. The runner also uses the repository's existing macOS native
build workaround `CARGO_PROFILE_RELEASE_STRIP=none` and the host architecture
for `FLUTTER_XCODE_ARCHS`. Default library builds contain no diagnostic counter
updates unless debug mode or `IANVS_MARKDOWN_DIAGNOSTICS=true` is enabled.

The runner always resolves example dependencies with the selected Flutter
binary, then verifies that `package:flutter` points to that SDK before building.
This prevents `flutter run` from reusing a different SDK's `package_config.json`.
The same editor, harness, corpus and framework hashes should match between the
forced-parse baseline and optimized run; only the diagnostic parse switch differs.

## Failed and incomplete runs

The runner writes `LABEL.partial.json` at each operation boundary. An operation
has a 180-second deadline, including its warmups and frame-delivery drains;
`--operation-timeout` can explicitly change it. Build/startup has a 600-second
deadline. The watchdog terminates only the benchmark process group it created.
The first rendering exception also stops the run and prints its stack trace.
Reusing a label clears its old JSON results before starting, so a failed build
cannot leave a previous success in place. Use distinct labels to keep runs.

`LABEL.json` includes `complete`, `errors` and the last active operation. A
failure retains diagnostic results but returns a failing exit status. Require
`complete: true`, no errors, all six cases and all five operations before accepting
the complete baseline. Individually completed operations from matched runs may
be reported as **partial diagnostic evidence** only if they finished before any
runtime error; identify every unfinished phase and do not infer its result.
Checkpoint files alone are not accepted baselines. The latest investigation is recorded in
[the R0-04 validation report](VALIDATION-2026-10-07.md).
