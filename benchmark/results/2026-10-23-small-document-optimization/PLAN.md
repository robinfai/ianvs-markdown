# Small-document optimization validation

Base: main 72eefd59449e9adb2e3c1098b264311c89d5647d.
Candidate: extract source-span reuse, controller reference reuse and bounded vector-path reuse from b62c389; retain current main behavior elsewhere.

Before any candidate timing, collect two fresh processes per actual main using the unchanged LOCAL-PERFORMANCE-PROTOCOL.md. Repeat the same four runs after the change. No attribution build or historical run substitutes for acceptance. Keep failed/invalid attempts.

Target the 10 KiB example sourceToRead and app save paths: both candidate repetitions must improve P95 by at least 10% against the faster baseline repetition. All other cases must remain within the protocol's baseline-derived observation lines. Report input, RSS and frame distributions, including failures. This is a scoped optimization check, not closure of the historical R4-03 large-document targets.

Regression gates: core/API/processing-budget checks; example and app tests; source theme/value/composition invalidation; reference updates, undo/redo and stricter budgets; repeated cached-paint pixel equivalence. Profile builds must use an unmodified SDK. Merge only if correctness and paired performance checks pass.
