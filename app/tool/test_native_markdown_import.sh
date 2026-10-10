#!/bin/bash
set -euo pipefail

linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linefold_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/linefold-import-tests.XXXXXX")"
trap 'rm -rf "$linefold_test_dir"' EXIT

xcrun swiftc \
  -module-cache-path "$linefold_test_dir/module-cache" \
  "$linefold_app_dir/ios/Runner/MarkdownImporter.swift" \
  "$linefold_app_dir/test/native_markdown_import_test.swift" \
  -o "$linefold_test_dir/markdown_import_tests"
"$linefold_test_dir/markdown_import_tests"
