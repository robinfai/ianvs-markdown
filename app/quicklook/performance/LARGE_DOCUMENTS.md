# Large-document validation — 2026-11-04

This change raises the **Linefold host policy**, not the package defaults. It
also removes avoidable work and changes layout; a higher limit alone was not
accepted as validation. See [machine-readable measurements](2026-11-04-large-documents.json).

## Policy

| Input bound | Previous host policy | New shared app / Finder policy |
| --- | ---: | ---: |
| Source UTF-16 code units | 1,048,576 | 8,388,608 |
| Physical line UTF-16 code units | 4,096 | 16,384 |
| Charged syntax units in document | 4,096 | 262,144 |
| Nonblank run syntax units | — | 8,192 |
| Dense nonblank run syntax units (>1 per 4 UTF-16 units) | — | 4,096 |
| Nonblank run UTF-16 units | — | 262,144 |
| Native Finder file bytes | 2 MiB | 32 MiB |
| Mobile preview-library file bytes | 5 MiB | 32 MiB |

These are independent input guards, not an 8 MiB guarantee for arbitrary syntax.
UTF-16 length is not UTF-8 file size. Rejected render input still produces the
existing bounded plain-text prefix, while full source remains editable/saveable
and whole-document clipboard plain text remains exact. Image, diagram, export,
undo and workspace-index limits are unchanged.

## Implementation

- Accepted preflight no longer allocates a 64 KiB fallback prefix; rejected input
  stops scanning immediately and creates only the bounded UTF-8 fallback.
- Reference preprocessing skips documents without the required `]:` marker.
  Live reuses its controller's decision when source and budget match.
- Protected highlight intervals use an ordered disjoint union instead of
  comparing each link with every previously seen protected range. Footnote
  scanning avoids ordinary caret characters without `[^` / `^[` syntax.
- Finder builds viewport blocks on demand, disposing their gesture recognizers
  when unmounted. Full AST/reference resolution remains shared. Custom builders
  and source-region rendering retain document-order widget construction.
- Read documents over 64 Ki UTF-16 units use viewport-only layout. Source/heading
  navigation materializes offscreen targets before revealing them, following the
  existing Live proportional-jump/bisection approach. Front matter, fallback
  scrolling and whole-source copy remain available.
- Recovery saves containing only a scroll-anchor change no longer notify/rebuild
  the whole workspace. Changed recovery content and failure/recovery transitions
  still notify. This was found by native measurement, not a build/test failure.

## Corpus and reproduction

Three genuine public release histories were downloaded without repeating content:

| File | Bytes | Git blob |
| --- | ---: | --- |
| Angular `CHANGELOG.md` | 1,072,599 | `702e04743f60782dcd563a5ff93bb2f52d311134` |
| Angular `CHANGELOG_ARCHIVE.md` | 1,104,183 | `af4c6fb7ff5669cfba1aa0c7fc6bf6688213f176` |
| Deno `Releases.md` | 669,209 | `eeb01e899bfe745f13d24208dac54f1c4474e945` |

Sources: [Angular](https://github.com/angular/angular),
[Deno](https://github.com/denoland/deno). Immutable bytes can be fetched using the
GitHub Git Blobs API with the repository and blob ID above; verify the SHA-256
values in the JSON. `release-histories.md` joins these files in table order using
two LF separators (2,845,995 bytes). It is explicitly a combined real-content
stress document, not a single upstream file. `plain-8m.md` is a separate synthetic
8,329,288-byte ordinary-paragraph stress input, not evidence of real-world syntax.

From the repository root, after placing the files locally:

```sh
python3 tool/measure_large_documents.py \
  /tmp/linefold-large-documents/angular.md \
  /tmp/linefold-large-documents/release-histories.md \
  --flutter /path/to/flutter --output /tmp/large-document-phases
```

The runner uses a fresh, externally killable `flutter_tester` per mode/document.
Its phase times and RSS include debug/test overhead; **do not treat those as
native release first-open latency**. The 30 s timeout is a safety ceiling, not a
performance target. `--expect-fallback --modes finder` measures adversarial inputs.

For native runs build the app with `--release --dart-define=LINEFOLD_SCROLL_PROBE=true`.
Use isolated signed test copies, register the copied extension only for a test
suffix, then open the byte-identical document in actual Finder and Linefold.
The diagnostic **Measure scroll** control runs 0 → 2400 → 0 logical pixels, six
seconds per leg. Do not compile or run tests during accepted scroll sampling.
The control and file logging are absent from ordinary release builds.

## Native findings and limits

- Baseline means the previous renderer with only the larger input budgets, so
  both sides actually render the same full document rather than comparing a
  truncated fallback with Markdown.
- Baseline Angular Read reached an observed RSS of 2,988,784 KiB and stayed busy;
  the isolated process was sampled and terminated. No completed baseline Read
  scroll measurement exists. The sample reported a 3.0G peak physical footprint;
  footprint and RSS are distinct OS metrics.
- The optimized Angular Read run completed with 370.3 MiB peak RSS and 2.244 ms
  P95 total frame span. This is a separate fresh process, not a percentage claim
  derived from mixing footprint with RSS.
- Angular Finder P95 stayed near 1.3 ms while peak RSS went from 187.5 to 173.6
  MiB. Lazy widget creation has a tradeoff: the largest observed frame increased
  from 9.491 to 28.827 ms. Do not claim every frame became faster.
- The 2.85 MB combined file opens as Markdown in actual Finder, Live and Read.
  Finder P95 was 1.257 ms with 191.3 MiB peak RSS. Live still has a large first
  table-layout frame (220.099 ms) even though P95 was 6.240 ms; editable table
  layout is not fully virtualized within a single table.
- A scroll-anchor recovery save triggered an unnecessary workspace rebuild and
  an observed 4,055.590 ms frame in combined-file Read. After suppressing
  unchanged-status notifications, the fresh-process repeat had per-leg P95
  2.086 / 2.277 ms and maxima 96.206 / 21.866 ms, with 469.0 MiB process peak
  RSS. The JSON keeps the before-fix and after-fix runs separately; this is one
  controlled repeat, not proof that every long frame is eliminated.
- The synthetic 8,329,288-byte paragraph document also opened fully in actual
  Finder and application Live mode. Finder P95/max were 1.384/7.136 ms, with
  191.3 MiB process peak RSS; application Live P95/max were 1.826/35.483 ms,
  with 654.7 MiB process peak RSS (other test tabs retained). This is a ceiling
  stress check, not a substitute for the real release-history corpus.
- Native Angular Finder Select All/Copy was byte-for-byte equal to the full
  1,072,599-byte source, including offscreen content, verified by SHA-256.
- Continuous dense links timed out before input protection; a soft-wrapped
  unmatched-bracket paragraph took ~9.4 s in the test harness. With run guards
  both reach plain fallback in ~0.2 s in that same diagnostic harness. A separate
  dense-emphasis case motivated the stricter density guard; real long tables
  remain accepted.

The app viewport was 671 logical pixels high, Finder 900, both on a 120 Hz display.
FrameTiming is Flutter pipeline timing, **not** end-to-end WindowServer or input
latency. RSS includes the entire process and its native frameworks; app sessions
retain other opened test documents. Process peak RSS accumulates across mode
switches. Full AST parsing remains synchronous, and large individual tables/code
blocks can still create long frames. This validates larger supported inputs and
specific improvements, not unlimited documents or uniformly perfect scrolling.
