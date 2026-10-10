# Component development and validation

Use Flutter 3.44.0 / Dart 3.12.0 or newer, Python 3.10+, and Make. Core widget
tests and examples do not depend on the optional Mermaid or native clipboard
backends. Those adapters retain their native toolchain requirements when a host
chooses them. On Linux, the Flutter test runtime needs `libglu1-mesa`.

## Local checks

```sh
make check-core          # dependency resolution, formatting, analysis, tests
make check-package       # actual publication snapshot and external host
make check-integrations  # macOS: app, native clipboard, Mermaid, Quick Look
make build-examples      # macOS Debug: body, reading, editor, playground
make check               # all three groups
make publish-dry-run     # core + snapshot + workspace Pub validation; no upload
```

Use `FLUTTER=/path/to/flutter/bin/flutter` and `DART=/path/to/flutter/bin/dart`
to select a toolchain. Formatting uses Dart 3.12; when testing newer SDKs, also
set `FORMAT_DART=/path/to/flutter-3.44.0/bin/dart`. The Flutter 3.47/Dart 3.13
formatter makes different layout decisions for some existing callbacks.

`check-integrations` requires macOS, Xcode command-line tools, CocoaPods,
Rust/Cargo, and the Rust target for the current architecture.
Quick Look tests locate the packaged Mermaid library through Pub's resolved
package configuration; they do not require a previous app build or CocoaPods
plugin symlinks.

Profile performance measurements use `make benchmark LABEL=after`. Read
[benchmark/README.md](benchmark/README.md) first: the current macOS SDK
workarounds and incomplete-run handling are separate from widget-test results.
Only a complete, error-free matched pair satisfies the full baseline gate.
Partial diagnostics must identify unfinished phases and their limitations.

Candidate macOS Profile/Release commands, observed native build requirements,
and remaining device checks are recorded in [the platform matrix](doc/PLATFORM_SUPPORT.md).

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
widget integration check; the snapshot also runs all three integration-entry
regressions. Native CI separately builds all four core entries and the Mermaid
host, which opts into the native clipboard adapter.
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
rendering baselines.

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
