#!/bin/bash
set -euo pipefail

linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$linefold_app_dir/tool/native_test_timing.sh"
linefold_output="$linefold_app_dir/build/quicklook-tests"
mkdir -p "$linefold_output"
linefold_timed compile xcrun swiftc -D QUICKLOOK_READER_TEST \
  -module-cache-path "${LINEFOLD_SWIFT_MODULE_CACHE:-$linefold_output/ModuleCache}" \
  "$linefold_app_dir/macos/QuickLook/PreviewProvider.swift" \
  "$linefold_app_dir/test/native_quicklook_test.swift" \
  -o "$linefold_output/native_quicklook_tests"
linefold_timed execute "$linefold_output/native_quicklook_tests" "$@"
