# Report: optimized-away NativeCallable retains a Struct with illegal cid in AOT

Published with user authorization on 2026-10-11 as a
[comment on flutter/flutter#191575](https://github.com/flutter/flutter/issues/191575#issuecomment-6110222678).
The published body was read back and verified against the approved report;
[exact text and receipt](results/2026-10-11-aot-upstream/) are archived.
This report contains no project source dependency. Maintainer assessment of the
proposed cause and experimental patch is still pending.

## Reproduction

On macOS 27.0.1 arm64, stock Dart 3.12.2 and stock Dart 3.13.5 both fail to compile
this standalone file (no pub dependencies):

```dart
import 'dart:ffi';

final class Rect extends Struct {
  @Double()
  external double x;
}

Pointer<Rect> position(Pointer<Rect> rect) => rect;
void main() {
  if (<int>[1].length > 1) {
    final callback =
        NativeCallable<Pointer<Rect> Function(Pointer<Rect>)>.isolateLocal(
          position,
        );
    callback.close();
  }
}
```

Save as `repro.dart`, then run:

```sh
dart --version
dart compile aot-snapshot repro.dart -o repro.aot
```

Expected: successful compilation. The callback branch is never executed.
Actual: compiler wrapper exits 254:

```text
Unexpected object (Class with illegal cid, full-aot): ... Class: Rect
```

Tested revisions:

- Dart 3.12.2: `d684a576a6aa954ae107a03b2b4e1d61c3bebe93`, from stock Flutter 3.44.8.
- Dart 3.13.5: `04bcd1036cdc799ac6564988f159ee454d42c822`, official macOS arm64 archive with SHA-256 verified.

Replacing the condition with literal `false` compiled successfully in a separate
control. The list-length condition matters to this reproduction.

## Debug snapshot backtrace

A Debug gen_snapshot built from the same Dart 3.12.2 revision reports this chain
(addresses removed; arrows mean “referenced by”):

```text
Class: Rect
→ Type: Rect → TypeArguments: [Type: Rect] → Type: Pointer<Rect>
→ (Pointer<Rect>) => Pointer<Rect>
→ Function 'position': static.
→ TrampolineData: c_signature=(Pointer<Rect>) => Pointer<Rect>
→ Function '_FfiCallbackposition': static ffi-trampoline-function.
→ _List len:11
```

The original Flutter failure also references `_window_macos.dart`'s `_Rect`
through a trampoline signature and an `_List len:11`.

## Experimental observation, not a validated fix

In `Precompiler::DropFunctions()`, immediately after clearing the closure
functions table, we tried:

```cpp
IG->object_store()->set_ffi_callback_functions(Object::null_array());
```

Using identical kernels and otherwise matching Debug builds/link settings:

| Input | Original Debug | Experimental Debug |
| --- | --- | --- |
| Standalone reproduction above | exits -6 | exits 0, AOT ELF generated |
| Live callback compile control | exits 0 | exits 0, AOT ELF generated |
| Original Flutter View product kernel | exits -6 | exits 0, assembly generated |

This suggests the deduplication table retains a trampoline referencing a dropped
Struct after its call site is optimized away. We have **not** run the VM FFI suite
or executed the experimental AOT outputs. The live callback control was executed
only with the stock JIT. This is not evidence that clearing this table is safe for
all callbacks, snapshot modes, or targets.

Build environment: DebugSIMARM64; dependency and compiler revisions, GN arguments,
and linker command are archived. Xcode 27's linker was used for **both** Debug
builds because the pinned LLVM linker could not read the host SDK's TAPI format.
No installed Flutter SDK was patched.

Raw logs, source variants, the experimental diff and hash records:
[local evidence](results/2026-10-11-aot-callback/).
Detailed diagnosis and limitations:
[local report](AOT-CALLBACK-2026-10-11.md).
The published comment includes the minimal source inline and links evidence at
merged revision `e567ba3cacde1bed8529500a8449c0296dfd0a74`. Posting this report
does not mean the experimental patch is accepted or the platform gates pass.
