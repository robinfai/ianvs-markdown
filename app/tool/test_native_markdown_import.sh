#!/bin/bash
set -euo pipefail

linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$linefold_app_dir/tool/native_test_timing.sh"
linefold_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/linefold-import-tests.XXXXXX")"
trap 'rm -rf "$linefold_test_dir"' EXIT

linefold_timed compile xcrun swiftc \
  -module-cache-path "${LINEFOLD_SWIFT_MODULE_CACHE:-$linefold_test_dir/module-cache}" \
  "$linefold_app_dir/ios/Runner/MarkdownImporter.swift" \
  "$linefold_app_dir/test/native_markdown_import_test.swift" \
  -o "$linefold_test_dir/markdown_import_tests"
linefold_timed execute "$linefold_test_dir/markdown_import_tests"
