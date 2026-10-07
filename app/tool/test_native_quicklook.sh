#!/bin/bash
set -euo pipefail

linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linefold_output="$linefold_app_dir/build/quicklook-tests"
# Pub resolution is sufficient for these native tests. A clean checkout has
# not run CocoaPods yet, so its generated plugin symlink need not exist.
MERMAN_LIB_DIR="$("${PYTHON:-python3}" - "$linefold_app_dir" <<'PY'
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urljoin, urlparse

config = Path(sys.argv[1]) / '.dart_tool/package_config.json'
packages = json.loads(config.read_text())['packages']
package = next(item for item in packages if item['name'] == 'merman')
uri = urlparse(urljoin(config.as_uri(), package['rootUri']))
if uri.scheme != 'file':
    raise RuntimeError(f'Expected a local merman package, got {uri.scheme}')
print(Path(unquote(uri.path)).resolve() / 'macos/Libraries')
PY
)"
export MERMAN_LIB_DIR
export CARGO_TARGET_DIR="$linefold_app_dir/build/quicklook-native"
mkdir -p "$linefold_output"

# Use a copied library so native tests never edit the pub cache's install name.
ditto "$MERMAN_LIB_DIR/libmerman_ffi.dylib" "$linefold_output/libmerman_ffi.dylib"
install_name_tool -id '@rpath/libmerman_ffi.dylib' "$linefold_output/libmerman_ffi.dylib"
codesign --force --sign - --timestamp=none "$linefold_output/libmerman_ffi.dylib"
export MERMAN_LIB_DIR="$linefold_output"
cargo test --locked --manifest-path "$linefold_app_dir/macos/QuickLook/renderer/Cargo.toml"
cargo build --locked --manifest-path "$linefold_app_dir/macos/QuickLook/renderer/Cargo.toml"
xcrun swiftc \
  -module-cache-path "$linefold_output/ModuleCache" \
  -import-objc-header "$linefold_app_dir/macos/QuickLook/PreviewBridge.h" \
  "$linefold_app_dir/macos/QuickLook/PreviewProvider.swift" \
  "$linefold_app_dir/test/native_quicklook_test.swift" \
  -L "$CARGO_TARGET_DIR/debug" -L "$linefold_output" \
  -llinefold_quicklook -lmerman_ffi -liconv \
  -Xlinker -rpath -Xlinker "$linefold_output" \
  -o "$linefold_output/native_quicklook_tests"
"$linefold_output/native_quicklook_tests" "$@"
