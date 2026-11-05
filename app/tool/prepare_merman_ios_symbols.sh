#!/bin/bash
set -euo pipefail
app_dir="$(cd "$(dirname "$0")/.." && pwd)"
out="$app_dir/build/merman-symbols-0.9.3"
source_dir="$out/source"
revision=3b915f69c02d55b873d252cf6c8a6048e7f3427d
mkdir -p "$out"
if [[ ! -d "$source_dir/.git" ]]; then
  git clone --depth 1 --branch v0.9.3 https://github.com/Latias94/merman.git "$source_dir"
fi
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$revision" ]]
[[ -z "$(git -C "$source_dir" status --porcelain)" ]]
# Match the official flutter-ios-native feature recipe, retaining source symbols.
CARGO_PROFILE_NATIVE_DISTRIBUTION_DEBUG=2 CARGO_PROFILE_NATIVE_DISTRIBUTION_STRIP=none \
  CARGO_TARGET_DIR="$out/target" cargo +1.95.0 build --locked --profile native-distribution \
  -p merman-ffi --lib --no-default-features \
  --features all-diagrams,analysis,ascii,layout-cytoscape,layout-elk,svg \
  --target aarch64-apple-ios --manifest-path "$source_dir/Cargo.toml"
cp "$out/target/aarch64-apple-ios/native-distribution/libmerman_ffi.dylib" "$out/libmerman_ffi.dylib"
xcrun dsymutil "$out/libmerman_ffi.dylib" -o "$out/libmerman_ffi.dylib.dSYM"
xcrun strip -x "$out/libmerman_ffi.dylib"
python3 "$app_dir/tool/verify_merman_symbols.py" "$out/libmerman_ffi.dylib" "$out/libmerman_ffi.dylib.dSYM"
printf '%s\n' "$revision" > "$out/source-revision.txt"
