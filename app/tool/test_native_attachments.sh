#!/bin/bash
set -euo pipefail

linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linefold_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/linefold-attachment-tests.XXXXXX")"
trap 'rm -rf "$linefold_test_dir"' EXIT

# Compile the production channel bridge as well as its coordinated file code.
# Use the SDK's actual FlutterMacOS module instead of test-only native stubs.
flutter_binary="$(command -v "${FLUTTER:-flutter}")"
"$flutter_binary" precache --macos
framework_dir="$("${PYTHON:-python3}" - "$flutter_binary" <<'PY'
from pathlib import Path
import sys

sdk = Path(sys.argv[1]).resolve().parent.parent
engine = sdk / 'bin/cache/artifacts/engine/darwin-x64'
frameworks = sorted(engine.glob('FlutterMacOS.xcframework/macos-*/FlutterMacOS.framework'))
if len(frameworks) != 1:
    raise RuntimeError(f'Expected one macOS Flutter framework in {engine}, found {len(frameworks)}')
print(frameworks[0].parent)
PY
)"

xcrun swiftc \
  -swift-version 5 -target "$(uname -m)-apple-macosx12.0" \
  -module-cache-path "$linefold_test_dir/module-cache" \
  -F "$framework_dir" -framework FlutterMacOS \
  -Xlinker -rpath -Xlinker "$framework_dir" \
  "$linefold_app_dir/apple/CloudWorkspace.swift" \
  "$linefold_app_dir/test/native_attachment_test.swift" \
  -o "$linefold_test_dir/attachment_tests"
"$linefold_test_dir/attachment_tests"
