# Public API review baseline

Run from the repository root:

```sh
make check-api
```

`check-core` and both Core CI SDKs include this gate. The checker has its own
locked Dart package; it adds no dependencies to the library, example or published
archive. Dependency resolution for the core library runs before API analysis.
`FORMAT_DART` selects the canonical Dart 3.12 formatter when testing a newer SDK.

The baseline records the resolved namespace of `lib/ianvs_markdown.dart`, including
`show` / `hide`, reexports and parts. It contains project declarations and the
explicitly reexported third-party symbols. For each exported declaration it records
its library URI and its own public constructors, fields, accessors and methods,
including type parameters, bounds, supertypes, nullability, named/positional and
required parameters, defaults, modifiers, constant initializers and enum order.
Private declarations and function bodies are excluded. Unresolvable or ambiguous
exports fail instead of producing a partial baseline. Extension types fail until
explicit coverage is added; they are not silently accepted.

Every addition, removal or changed record fails `--check`. This is a review gate,
not a semantic-version compatibility classifier or a 1.0 freeze. It does not
compare inherited members from non-exported bases, implementation behavior,
documentation, arbitrary annotations, platform-specific conditional exports, or
transitively evaluated constants. Types are analyzer display strings, not fully
qualified type identities. Initializers/defaults are normalized source expressions;
a referenced private constant may change without changing the recorded expression.
Behavioral contracts still need the component tests and integration checks.

## Deliberate updates

1. Inspect the reported symbols/members and decide whether the API change is
   intended. Dependency updates can change third-party reexports too.
2. Update `doc/API_CONTRACTS.md`, migration notes and relevant behavioral tests.
3. Generate explicitly from the resolved checkout:

   ```sh
   cd tool/api_check
   dart pub get --enforce-lockfile
   dart run bin/check.dart --write ../..
   ```

4. Review `git diff -- tool/api_check/api_baseline.json` from the repository root,
   then run `make check-core` and `make check-package`. Commit the baseline with
   its change, not as a separate unexplained CI repair.

`--check` never overwrites the baseline. Updating the generator, its schema or its
locked analyzer requires reviewing the regenerated baseline and passing its
fixture tests on both CI SDKs. A successful check alone cannot declare a release
compatible or satisfy the R3 platform and real-host acceptance gates.
