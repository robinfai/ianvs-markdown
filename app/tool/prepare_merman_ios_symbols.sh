#!/bin/bash
set -euo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
out="$app_dir/build/merman-symbols"
source_dir="$out/source"
revision=00a2f291025913d612b6ca1ce9b6df6daf5bef94
plugin="$app_dir/ios/.symlinks/plugins/merman"
template="$plugin/ios/MermanFFI.xcframework/ios-arm64/MermanFFI.framework"
mkdir -p "$out"
if [[ ! -d "$source_dir/.git" ]]; then
  git clone --depth 1 --branch v0.7.0 https://github.com/Latias94/merman.git "$source_dir"
fi
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$revision" ]]
[[ -z "$(git -C "$source_dir" status --porcelain)" ]]
# Fail on dependency upgrades instead of silently replacing a different ABI.
grep -qx 'version: 0.7.0' "$plugin/pubspec.yaml"
cmp "$source_dir/crates/merman-ffi/include/merman.h" "$template/Headers/merman.h"

CARGO_PROFILE_RELEASE_DEBUG=2 CARGO_PROFILE_RELEASE_STRIP=none \
  CARGO_TARGET_DIR="$out/target" cargo +1.95.0 build --locked --release \
  -p merman-ffi --target aarch64-apple-ios --manifest-path "$source_dir/Cargo.toml"

stage="$(mktemp -d "$out/stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$template" "$stage/MermanFFI.framework"
binary="$stage/MermanFFI.framework/MermanFFI"
cp "$out/target/aarch64-apple-ios/release/libmerman_ffi.dylib" "$binary"
install_name_tool -id '@rpath/MermanFFI.framework/MermanFFI' "$binary"
xcrun dsymutil "$binary" -o "$stage/MermanFFI.framework.dSYM"
xcrun strip -x "$binary"
python3 "$app_dir/tool/verify_merman_symbols.py" "$binary" "$stage/MermanFFI.framework.dSYM"
# Verify all exported C ABI entry points remain available.
xcrun nm -gjU "$template/MermanFFI" | sort | sed -n '/^_merman_/p' > "$stage/original.exports"
xcrun nm -gjU "$binary" | sort | sed -n '/^_merman_/p' > "$stage/rebuilt.exports"
diff -u "$stage/original.exports" "$stage/rebuilt.exports"
ditto "$stage/MermanFFI.framework" "$out/MermanFFI.framework"
ditto "$stage/MermanFFI.framework.dSYM" "$out/MermanFFI.framework.dSYM"
printf '%s\n' "$revision" > "$out/source-revision.txt"
