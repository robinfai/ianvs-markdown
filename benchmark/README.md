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
default budgets and disabled processing/rendering/copy budgets against only
this controlled corpus. Since R2-05 the harness passes the selected policy to
Controller `parseBudget`, widget `renderBudget` and `clipboardBudget` explicitly.
Results identify whether Controller/Live/Reading can process full Markdown:
over-budget Live edits complete plain source, while Reading shows a bounded
prefix. `processingBudgetPolicy: full-document-preflight-v1` marks this behavior.
The pre-R2-05 default workload used per-block Live budgets; its archived timings
are historical and cannot substitute for a new baseline. The comparison tool
already requires matching source and harness hashes. This change has not rerun
the profile baseline; R2-01 performs the new matched measurements.

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
- `liveToSource`, `sourceToReading`, `readingToLive`: measure each direction
  independently. A sample cycle follows Live → Source → Reading → Live; every
  selected direction gets the configured warmups and measured sample count.
  Unselected directions still run as unmeasured preparation for the next cycle.
- `scroll`: jump between the top and offsets up to 1,200 logical pixels in Live
  Preview; it measures a viewport update, not a full-document animated scroll.

Latency runs from the action through the next completed UI frame; initial
display includes its extra mount/focus frames. Frame build/raster durations
come from `FrameTiming`. Its callbacks are batched, so each phase drains them
for 1.1 seconds before and after sampling. Raw engine vsync timestamps assign
frames to each action's completed frame interval, excluding unmeasured mode
preparation and frames outside the action. Frame distributions retain their
own sample counts; an operation with no frame evidence fails validation.
Schema version 2 has seven operations (the former mixed `modeSwitch` is now
three separate directions). Do not merge version 1 and 2 timing distributions.

`documentParses` counts the Live editor's `_refreshBlocks` operation, which
refreshes references, highlight spans, footnotes, block structure and heading
folds. It does not count every inline renderer, Reading parser, or controller
reference scan. `rssMiB` is total process resident memory, including Flutter,
native code, caches and history; it is not isolated Dart heap usage. Results
include P50, P95, maximum and every raw sample. Do not set absolute regression
thresholds from one pair of runs; repeat fresh-process runs to establish noise.

## Focused diagnostics

```sh
python3 tool/run_benchmark.py --label mode-diagnostic \
  --sizes 1048576 --budgets unlimited \
  --operations liveToSource,sourceToReading,readingToLive --warmup 1 --samples 2
```

`--sizes`, `--budgets` and `--operations` accept comma-separated values. A
filtered run can have `complete: true`, but always has `fullBaseline: false`.
It is diagnostic evidence, never a replacement for a complete baseline.

For CPU attribution, start this companion while that diagnostic is running:

```sh
python3 tool/capture_benchmark_cpu.py --label mode-diagnostic \
  --operation liveToSource --size 1048576 --budget unlimited --index 0
```

The companion connects only to the local VM service reported by that runner.
It uses the action's `dart:developer` timeline timestamps to request CPU
samples for the matching interval and saves the raw profile plus top inclusive
and exclusive functions. CPU diagnostic runs are kept separate from baseline
latency runs; do not run this companion during accepted timing comparisons.

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

The runner writes `LABEL.partial.json` at each operation boundary and flushes
`LABEL.samples.jsonl` for every action start/end, including warmup and unmeasured
preparation. `LABEL.progress.json` identifies the current action and index.
The default operation-group deadline is 900 seconds (`--operation-timeout`),
including all three mode directions, warmups and frame-delivery drains. Each
individual action also has a 120-second deadline (`--sample-timeout`), so a
stalled sample is not hidden by the longer group limit. These are watchdogs,
not performance acceptance thresholds. Build/startup retains its 600-second
deadline. The watchdog terminates only the benchmark process group it created.
The first rendering exception also stops the run and prints its stack trace.
Reusing a label clears its old JSON results before starting, so a failed build
cannot leave a previous success in place. Use distinct labels to keep runs.

`LABEL.json` includes `complete`, `errors` and the last active operation. A
failure retains diagnostic results but returns a failing exit status. Require
`complete: true`, `fullBaseline: true`, no errors, all six cases and all seven
operations with the expected sample counts before accepting the complete
baseline. Paired runs must also match SDK/framework, all library source hashes,
harness/runner/corpus hashes, window size, sampling and watchdog settings. Individually completed operations from matched runs may
be reported as **partial diagnostic evidence** only if they finished before any
runtime error; identify every unfinished phase and do not infer its result.
Checkpoint files alone are not accepted baselines. The latest investigation is recorded in
[the completed R0 acceptance report](ACCEPTANCE-2026-10-07.md); the
[earlier partial investigation](VALIDATION-2026-10-07.md) remains as historical evidence.

## Repeated comparisons

Keep one complete before/after pair. Repeat it in fresh processes, or repeat
all six selection cases in fresh processes with `--operations selection` to
measure the variation of R0's selection optimization. Such focused repetitions
supplement the full pair; they never replace its other operations.

```sh
python3 tool/compare_benchmarks.py \
  --before build/benchmark/before.json --after build/benchmark/after.json \
  --selection-before build/benchmark/selection-before-1.json \
  --selection-after build/benchmark/selection-after-1.json \
  --selection-before build/benchmark/selection-before-2.json \
  --selection-after build/benchmark/selection-after-2.json \
  --output build/benchmark/comparison.json
```

The validator requires at least 5 warmups and 20 measured samples per operation,
a complete matched pair, independent repetitions, exact scenario/operation coverage, unchanged source/SDK/harness inputs and valid raw
sample counts and percentiles. It also checks the deterministic parse gates:
selection 1 → 0, text changes 1 → 1. A partial/filtered file cannot fill the
complete-pair role. Duplicate files/timestamps do not count as another run.

Use at least two complete pairs, or one complete pair plus two focused selection
pairs. The full suite and selection-only suite have different preceding actions
and cache histories, so their P95 ranges and observation lines are kept separate.
P95 values remain separate per process. For operations with repetitions, the
summary proposes an investigation line for the same machine/SDK/workload:
maximum observed optimized P95 × max(1.25, 1 + 2 × relative spread). This is a
conservative initial observation rule, not a statistical confidence interval
or a portable CI performance limit. Unrepeated operations get no such line.
The deterministic parse-count gates remain the automated regression contract.
