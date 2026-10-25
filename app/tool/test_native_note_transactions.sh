#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Native note transaction tests require macOS, Xcode and the real FlutterMacOS framework." >&2
  exit 1
fi

linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$linefold_app_dir/tool/native_test_timing.sh"
linefold_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/linefold-note-transaction-tests.XXXXXX")"
trap 'rm -rf "$linefold_test_dir"' EXIT

# Compile the real production bridge and executor, not replacement native stubs.
# Tests create their own local vault and private journal under a temporary root.
# They never access a real workspace, provider account, clipboard or app journal.
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

linefold_timed compile xcrun swiftc \
  -swift-version 5 -target "$(uname -m)-apple-macosx12.0" \
  -module-cache-path "${LINEFOLD_SWIFT_MODULE_CACHE:-$linefold_test_dir/module-cache}" \
  -F "$framework_dir" -framework FlutterMacOS \
  -Xlinker -rpath -Xlinker "$framework_dir" \
  "$linefold_app_dir/apple/CloudWorkspace.swift" \
  "$linefold_app_dir/apple/WorkspaceNoteTransaction.swift" \
  "$linefold_app_dir/test/native_note_transaction_test.swift" \
  -o "$linefold_test_dir/note_transaction_tests"
linefold_timed execute "$linefold_test_dir/note_transaction_tests"
