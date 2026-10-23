# Small-document optimization: validation in progress

Base: `72eefd59449e9adb2e3c1098b264311c89d5647d` (current main at start).
Candidate code: `da4de94` on `codex/small-document-optimization`.
Source branch retained: `codex/small-document-latency` (`b62c389`).

## Extracted scope

- Reuse the current source TextSpan only when the editing value, base style, composing flag and every syntax-theme input match.
- Reuse the controller's already-current immutable reference context in Live; fall back to Live parsing when the controller's stricter budget disallows reuse.
- Retain at most eight vector pattern geometries, each at most 32,768 cells; oversized geometry is still drawn completely without retaining it.
- Retain CPU-tool fixes for deferred all-sample extraction, invalid-run rejection, recursive-stack counting and zero-CPU intervals. No diagnostic changes to the production performance protocol were imported.
- Extend the extracted regression coverage with repeated cache-hit pixel comparisons and listener/undo/redo reference consistency.

The historical branch's 552-file diagnostic payload is not imported. The results here are new attempts on current main.

## Performance status: NOT PASSED

The unchanged real-main protocol and merge criteria are in PLAN.md. No complete valid baseline or paired candidate result exists yet. Do not merge or claim measured improvement from these attempts.

1. `small-main-before-20261023`: initial example build failed because its generated package configuration referenced a removed temporary SDK. App built successfully. Refreshed example dependencies with `flutter pub get --enforce-lockfile`; no tracked lockfile change.
2. `small-main-before-fixed-20261023`: both actual Profile mains built with the clean installed SDK.
3. `before-example-invalid-focus`: background launch was rejected (`active=false`), zero samples.
4. `before-example-invalid-selection`: launched via Finder and remained foreground; failed at 10 KiB `livePaste`, formal sample 17, with `Input position changed`. This is the unoptimized main; preserve the failure and investigate if it recurs.
5. `before-example-invalid-focus-later`: fresh process passed the prior failing stage, then lost foreground later. The window generation changed and the validator rejected the entire run.

All invalid records and initial build logs are preserved; none are accepted, stitched together or substituted for complete runs. Foreground availability was requested before resuming full paired sampling. Candidate compilation and regression checks can proceed independently.

## Remaining acceptance

Collect two fresh complete processes per actual main before and after on the same SDK/window configuration. Rebuild main for new baseline collection (candidate builds overwrite the standard output paths). Use the unchanged collector/validator and declared source-difference allowlist: `lib/ianvs_markdown.dart`, `lib/src/code_surface.dart`, `lib/src/editor/editor_controller.dart`, `lib/src/editor/live_editor.dart`. Tool-only CPU capture changes do not enter the runtime input manifest.

If the input-position failure repeats while the foreground is stable, diagnose it before claiming a valid baseline; do not remove or relax that assertion. Preserve all failed attempts. Only merge after the complete correctness and paired performance gates pass.

## Regression results

`make check-core` passed (API, format, analysis, 1,144 core tests, 35 example tests, 30 Python tests and all killable-process budget checks). API checker tests: 8 passed. Targeted cache/reference/pixel tests: 4 passed. App: 993 passed, 1 pre-existing optional LLM-fixture test skipped; app analysis passed. Logs are in `checks/`. These do not substitute for paired performance acceptance.

Candidate Profile builds for both actual mains passed; the clean SDK and binary/input hashes are recorded in `builds/small-candidate-20261023/freeze.json`.
