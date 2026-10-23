# Synthetic system-font PDF diagnostic (WIP only)

This branch investigates a real PDF Unicode-copy defect. It does not restore PDF/Print product actions, change application entitlements, claim HTML-rendering parity, or replace the parked multi-page PDF acceptance gate. The existing product remains HTML and Markdown copy export only.

## Purpose and evidence

The preserved native output mapped original 文 (U+6587) to ⽂ (U+2F42) and original code 长 (U+957F) to ⻓ (U+2ED3) in PDF ToUnicode tables. Visual similarity is not exact copy fidelity. NFKC changes the first pair but not the second; normalizing the fixture or globally rewriting CMaps would hide meaningful input distinctions.

`make test-native-pdf-font-diagnostic` runs a test-only version of the previously reviewed offline WK/AppKit renderer. There is no NSSavePanel, user document read, external input URL, network font, new package dependency, font installation, registration, activation request, or system-setting change. Its input is a fixed synthetic corpus.

The current CI Mac supports the diagnostic's macOS 13 minimum. The app's macOS 12 target is unchanged. `preventAutoDownload` is publicly available from macOS 13; the fixture does not guess its numeric value or claim equivalent macOS 12 coverage.

## Selection and limits

- Census uses public available-font APIs and an auto-activation-disallowed collection. It does not probe unknown names with CTFontCreateWithName.
- At most three allowlisted families (PingFang SC, Heiti SC, Songti SC), with at most six distinct preflight non-bold/bold reference faces (selected by symbolic traits, with weight used only as a deterministic preference). Each family gets an independent census process, and each render process rechecks only its own family. Each process constructs at most two reference faces; the six-face limit is not a claim of only six constructor calls across all processes. These are not a prediction of WK's CSS 400/700 face choice; actual PDF resources/runs remain separate evidence. Only known enabled, explicitly non-downloadable, already available files resolving under `/System/Library/Fonts/` qualify. Missing/unknown attributes or unavailable families are recorded, not repaired. The combined manifest retains all three family statuses. An unavailable, missing, failed, or unstarted family prevents a green matrix, even if other families' cases pass. Remaining eligible families still collect evidence.
- Parse an existing file's data into unregistered descriptors, select the exact inventoried PostScript face, and construct with preventAutoActivation + preventAutoDownload. Verify resulting identity and required glyph coverage. File reads remain bounded to 64 MiB each / 128 MiB aggregate per process. Canonical-URL caching already deduplicates the regular/bold faces when they share one TTC; per-family isolation does not remove this cache or increase either cap. The manifest records distinct input-file count and input bytes per process. No font Data is retained across family processes. Data-created descriptors are intentionally not registered.
- These options constrain the fixture's CoreText calls, not WebKit's own lookup or cascading. Current upstream WK has a missing-family auto-activation path; content-rule/CSP blocking is not proof that system font services can never activate/download. No such absolute guarantee is claimed.
- Nine cases maximum: separate forward, pair-reversed and repeated/mixed PDFs for each family. Separate processes isolate process-local print contexts and callbacks; they do not reset every OS font cache or launchd-managed WebKit service. A slow or failed case stays failed while remaining independent cases collect evidence.
- Each case has a 100-second process watchdog; native loading/output timers are 20/60 seconds. Each of the at most three censuses is bounded to 30 seconds. A single 18-minute monotonic matrix deadline covers all censuses and cases; no new process starts unless its full watchdog plus five-second reap allowance fits. The deadline is not reset per family. Compile remains bounded to 120 seconds, CI job to 25 minutes (including two separately bounded compilations and artifact upload). On timeout/exception, the established watchdog cleans only its spawned process group, including when that leader has already exited. It does not promise descendant cleanup following normal leader completion, nor control launchd-managed WebKit services. Original worker callback marshaling, lease-before-factory exclusion ordering, one-shot completion and retain-until-terminal cleanup are preserved.
- Input PDF ≤4 MiB; accepted evidence ≤16 MiB per PDF and 128 MiB aggregate. Before each case, the runner reserves 40 MiB for its worst-case accepted files/log; before each census it reserves 10 MiB for its manifest/log. Both also reserve 1 MiB for the outer acceptance transcript and 2 MiB for the final summary. The total budget includes all families and the complete uploaded attempt directory, not only the matrix subdirectory. Child logs are replayed only as bounded tails; the acceptance capture itself fails on overflow rather than silently truncating a success. Each spawned watchdog/native process also inherits a lowered 8 MiB per-file resource limit; it affects only explicitly inheriting test processes, not the system, launchd services or other jobs. A file-limit failure is a failed case, not a truncated success. Resource traversal, text/runs, page count, decoded streams and images have additional caps. Framework decode/render allocations occur before some size checks and are not a hard peak-memory guarantee; this helper is only for these synthetic files in supervised processes, not untrusted PDFs.
- Every evidence directory is new-only. No prior artifact is removed or replaced. CI uploads only the current attempt path emitted by the script, never all preserved local attempts. File writes are confined to the test output directory; cleanup removes only the script's own temporary compiler directory.

## Assertions and review

The four distinct scalars 文⽂长⻓ are tested in body, heading, code and table contexts, along with the original Chinese title and the exact original long-code line `长代码 ABCDEFGHIJKLMNOPQRSTUVWXYZ ` repeated 35 times, including all 70 spaces and every “代码”. The payload is checked against the original production Dart fixture, not a shortened reconstruction. Each literal radical remains meaningful input. Any changed, missing, duplicated or reordered marker/payload fails the case. Only renderer-added LF/CR in the explicitly unbroken long-code probe may be removed; no other whitespace or Unicode normalization is permitted.

Python independently rechecks PDFKit's raw text against committed expected strings, not a native success flag. A failed native assertion, timeout, geometry error or Unicode mismatch makes the diagnostic job fail. There is no continue-on-error or “any font passed” conversion to success.

Actual font dictionaries, BaseFont/Subtype, ToUnicode streams, raw page/Form content streams, PDFKit-inferred font runs, raw UTF-8/scalars, original PDFs and PNG pages are retained. Resource presence and PDFKit inferred fonts do not by themselves prove a particular glyph's font. The helper does not implement a speculative Tf/Tj/TJ interpreter or correct the content. An independent extractor and visual page review remain required; the summary explicitly marks them pending even if machine checks pass.

The original full-document cells, repeated table headers, long-code content, source/destination safety and Print paper-size gates remain requirements for a future product feature. A small font-matrix pass cannot satisfy them. The original parked PDF/Print branch and its failing gate remain intact; it is not a merge candidate.

## CI isolation

Only exact branch `diag/p2-offline-pdf-system-fonts` gets the separate `Synthetic PDF font investigation` workflow, via its explicit push trigger or workflow_dispatch. It runs the diagnostic's Python budget/corpus tests, process-watchdog regressions, actual Swift evidence/lifecycle harness, and strict PDF matrix, preserving failure and current-attempt artifact behavior. Its independent concurrency group does not cancel active Native integrations runs.

The original Native integrations main/PR/manual triggers and all existing macOS host/native/build/signature and iOS jobs remain unchanged. Pure diagnostic-branch pushes no longer repeat those unrelated product builds. This is not a removal of production required checks, and a diagnostic pass cannot establish product readiness. No wildcard branch trigger, new credentials or third-party automation is added. These WIP-only workflow changes are not intended for main; this branch must never be merged.

## Official API references

- [Available font collection](https://developer.apple.com/documentation/coretext/ctfontcollectioncreatefromavailablefonts(_:))
- [Available font URLs](https://developer.apple.com/documentation/coretext/ctfontmanagercopyavailablefonturls())
- [Data-backed unregistered font descriptors](https://developer.apple.com/documentation/coretext/ctfontmanagercreatefontdescriptorsfromdata(_:))
- [CoreText creation options](https://developer.apple.com/documentation/coretext/ctfontoptions)
- [preventAutoDownload availability](https://developer.apple.com/tutorials/data/documentation/coretext/ctfontoptions/preventautodownload.json)
- [Enabled font attribute](https://developer.apple.com/documentation/coretext/kctfontenabledattribute)
- [Downloadable attribute](https://developer.apple.com/documentation/coretext/kctfontdownloadableattribute)
- [Basic glyph mapping](https://developer.apple.com/documentation/coretext/ctfontgetglyphsforcharacters(_:_:_:_:))
- [Current upstream WK lookup/fallback implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/graphics/cocoa/FontCacheCoreText.cpp)
