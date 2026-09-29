#!/bin/bash
set -euo pipefail
linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linefold_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/linefold-files-tests.XXXXXX")"
trap 'rm -rf "$linefold_test_dir"' EXIT
xcrun swiftc "$linefold_app_dir/macos/Runner/DesktopIntegration.swift" \
  "$linefold_app_dir/test/native_workspace_files_test.swift" \
  -o "$linefold_test_dir/workspace_files_tests"
"$linefold_test_dir/workspace_files_tests"
