# Component development and validation

Use Flutter 3.44.0 / Dart 3.12.0 or newer, Python 3.10+, and Make. Core widget
tests and examples do not depend on the optional Mermaid or native clipboard
backends. Those adapters retain their native toolchain requirements when a host
chooses them. On Linux, the Flutter test runtime needs `libglu1-mesa`.

## Local checks

```sh
make run-example         # example/lib/main.dart
make run-app             # app/lib/main.dart
make check-local         # default: core/app/native checks + both main Debug builds
make build-local-release # the same two entries, Release
make build-local-performance MODE=profile LABEL=baseline # opt-in diagnostics in both mains
make check-core          # dependency resolution, formatting, analysis, tests
make check-api           # resolved exports and declared public member baseline
make check-package       # actual publication snapshot and external host
make check-processing-budget # independent processes for pathological input
make check-integrations  # macOS: app, native clipboard, Mermaid, Quick Look
make build-examples      # optional focused-example diagnostic builds
make check               # all three groups
make publish-dry-run     # core + snapshot + workspace Pub validation; no upload
```

Use `FLUTTER=/path/to/flutter/bin/flutter` and `DART=/path/to/flutter/bin/dart`
to select a toolchain. Formatting uses Dart 3.12; when testing newer SDKs, also
set `FORMAT_DART=/path/to/flutter-3.44.0/bin/dart`. The Flutter 3.47/Dart 3.13
formatter makes different layout decisions for some existing callbacks.

`check-core` includes `check-api`. The checker is an isolated, locked Dart tool
under `tool/api_check/`, excluded from the Pub archive. API additions, removals,
member signatures, defaults and constants require a reviewed baseline update;
this does not certify behavioral or semantic-version compatibility. Follow
[the API baseline workflow](tool/api_check/README.md) when changing public APIs.

`check-integrations` requires macOS, Xcode command-line tools, CocoaPods,
Rust/Cargo, and the Rust target for the current architecture.
Quick Look tests locate the packaged Mermaid library through Pub's resolved
package configuration; they do not require a previous app build or CocoaPods
plugin symlinks.

Current performance acceptance uses `make build-local-performance MODE=profile
LABEL=baseline`, which builds and freezes diagnostics inside the two existing
main entries. Open the Profile app paths listed in `freeze.json` through Finder, run one entry at a
time, and restart each process for its second complete repetition. Keep the
window active and unchanged; do not build or test concurrently. Collect every
run, including failures, with `tool/local_performance.py collect`, then validate
two complete runs per entry with `tool/analyze_local_performance.py`.
See the [fixed protocol](benchmark/LOCAL-PERFORMANCE-PROTOCOL.md) and
[R4-02 report](benchmark/MAIN-ENTRY-PERFORMANCE-2026-10-13.md) for exact commands,
synthetic-input boundaries, frozen environment, raw data and observation lines.
Ordinary builds keep diagnostics disabled; the public API is unchanged.

For optimization batches, `tool/compare_local_performance.py` takes four
`--baseline` and four `--candidate` run directories, a frozen `--targets` JSON,
an `--output` file and one `--allow-source` per reviewed changed runtime/tool
path. It rejects environment, corpus, typography or undeclared source changes,
then checks both candidate repetitions against targets and every remaining
baseline observation line. A valid measurement that misses a target writes its
failed result before exiting nonzero; keep that evidence and leave the roadmap
item open. See [R4-03](benchmark/LARGE-DOCUMENT-COSTS-2026-10-14.md).
CPU attribution uses `local_performance.py build --attribution` and
`capture_local_cpu.py` inside the same mains. Its extra profiling and native
snapshots use a distinct protocol that formal validation rejects; never include
its VM service address or use its times as acceptance results.

The older `make benchmark LABEL=after` and [benchmark/README.md](benchmark/README.md)
remain historical R0/R2 attribution tools. They are not acceptance entries for
the current roadmap, and their results cannot substitute for actual main runs.

`check-core` includes the processing-budget check on the supported Linux/macOS
validation hosts (the process-group timeout runner requires POSIX). It gives each of 32
preparse/copy cases a separate process group, a 60-second Flutter startup
deadline and a 5-second operation deadline. A timeout kills only that child
group and records partial results under `build/processing-budget/`; both core
CI SDKs upload those logs alongside package evidence. This checks bounded-input
behavior and source preservation, not a profile frame-time target. See
[the R2-05 report](benchmark/PROCESSING-BUDGET-2026-10-10.md).

Current local acceptance uses `example/lib/main.dart` and `app/lib/main.dart`.
See [the local checklist](doc/R3_ACCEPTANCE.md). The standalone AOT reduction and
candidate matrix are retained for diagnostics, not prerequisites for local work.
Historical platform evidence remains in [the platform matrix](doc/PLATFORM_SUPPORT.md).

## Publication snapshot

`tool/check_package.py` reads the archive file list emitted by
`dart pub --verbose publish --dry-run`. It deliberately fails if Pub changes
that log format. It copies only those files into a system temporary directory,
validates the pristine snapshot with **zero warnings**, compares its file list
and SHA-256 hashes, then resolves and tests the included example and a new host.
Resolved package paths must not point into the original workspace or include
either optional native backend. Native clipboard packages leaking into the
core example or external host cause the snapshot check to fail.

The new host imports the public library, renders Markdown, edits source, invokes
the save callback, undoes the change, and switches to reading mode. This is a
widget integration check. It also verifies migration behavior for default plain-text
copy (with a mocked platform channel), independent budgets, bounded/legacy history,
and captured asynchronous saves through cancellation and retry. These checks do
not prove actual UI or durable file behavior. See [the migration guide](doc/MIGRATION.md).
The snapshot also runs the focused example regressions. Native CI builds the
example and app main entries in Debug and Release; app exercises the real
Mermaid, rich clipboard and Quick Look integration. Separate real external
hosts are outside the current local roadmap.
The core archive excludes `app/`, `packages/`, `demos/`, benchmarks and internal
maintenance scripts. Pub's own ignore behavior is described in the
[official publishing guide](https://dart.dev/tools/pub/publishing).

Logs, the exact file/hash manifest and a summary are written to
`build/package-check/`. Use `python3 tool/check_package.py --keep` to inspect a
temporary snapshot after a failure. A dirty source checkout may produce Git
warnings during manifest collection; the independent snapshot never ignores
warnings. Review and commit intended changes before the final workspace
`make publish-dry-run`. Do not discard unrelated work to silence Pub warnings.

## Continuous integration

`Core` runs on every pull request, on `main`, and by manual dispatch. Both
Flutter 3.44.0/Dart 3.12.0 and Flutter 3.47.6/Dart 3.13.5 execute the same Make
checks, using the canonical formatter. Package evidence is retained as an
artifact. Releases are selected from the [Flutter SDK archive](https://docs.flutter.dev/install/archive);
the matrix versions are pinned and should be updated explicitly after validation.

`Native integrations` runs for affected core, example, app, adapter, fixture,
dependency and workflow paths. Manual dispatch forces a complete native run.
It uses Flutter 3.44.8 so a core SDK upgrade does not silently change native
rendering baselines. Its build step is `make build-local build-local-release`;
focused sample entry builds remain available manually through `build-examples`.
The normal local gate is `make check-local`; CI additionally retains automatic
package-snapshot checks for publishing hygiene, without requiring external projects.

`main` requires the **Core required** check from GitHub Actions (app ID 15368),
with the branch up to date. The rule also applies to administrators. Push changes
to a feature branch, open a pull request, and merge after the checks pass. The
workflow aggregates both SDK results and fails if either fails or is cancelled.
Force pushes and branch deletion remain disabled.

The first [core run](https://github.com/robinfai/ianvs-markdown/actions/runs/37605838941)
and [native run](https://github.com/robinfai/ianvs-markdown/actions/runs/37605838983)
passed for `ebe7dd7`. The protection API was read back after configuration on
2026-10-07. [PR #1](https://github.com/robinfai/ianvs-markdown/pull/1) verified that
`Core required` is required and passes. Its core and manually dispatched native
integration runs passed for `11f04ac`; see [R0 acceptance](benchmark/ACCEPTANCE-2026-10-07.md)
for the recorded evidence and performance reproduction commands.
