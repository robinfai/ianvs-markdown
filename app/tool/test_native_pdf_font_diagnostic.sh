#!/bin/bash
set -euo pipefail
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/linefold-font-diagnostic.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$app_dir/build/pdf-font-qa"
evidence="$(mktemp -d "$app_dir/build/pdf-font-qa/attempt.XXXXXX")"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'evidence-path=%s\n' "$evidence" >> "$GITHUB_OUTPUT"
fi
{
echo "PHASE: diagnostic toolchain and SDK font option provenance"
git -C "$app_dir" rev-parse HEAD
sw_vers
xcodebuild -version
sdk="$(xcrun --sdk macosx --show-sdk-path)"
grep -n -A 5 -B 5 'kCTFontOptionsPreventAutoDownload\|kCTFontCollectionDisallowAutoActivationOption' \
  "$sdk/System/Library/Frameworks/CoreText.framework/Headers/CTFont.h" \
  "$sdk/System/Library/Frameworks/CoreText.framework/Headers/CTFontCollection.h"
python3 -m unittest discover -s "$app_dir/tool" -p 'test_pdf_font_diagnostic.py'
python3 -m unittest discover -s "$app_dir/tool" -p 'test_native_test_watchdog.py'
echo "PHASE: compile and run evidence/lifetime boundary tests"
python3 "$app_dir/tool/native_test_watchdog.py" --timeout-seconds 120 -- \
  xcrun swiftc -target "$(uname -m)-apple-macos12.0" \
  "$app_dir/test/support/offline_pdf_diagnostic_job.swift" \
  "$app_dir/test/support/pdf_font_evidence.swift" \
  "$app_dir/test/native_pdf_font_evidence_test.swift" \
  -o "$test_dir/pdf_font_evidence_tests"
python3 "$app_dir/tool/native_test_watchdog.py" --timeout-seconds 30 -- \
  "$test_dir/pdf_font_evidence_tests"
echo "PHASE: compile synthetic-only PDF font diagnostic"
python3 "$app_dir/tool/native_test_watchdog.py" --timeout-seconds 120 -- \
  xcrun swiftc -target "$(uname -m)-apple-macos12.0" \
  "$app_dir/test/support/offline_pdf_diagnostic_job.swift" \
  "$app_dir/test/support/pdf_font_evidence.swift" \
  "$app_dir/test/native_pdf_font_diagnostic.swift" \
  -o "$test_dir/pdf_font_diagnostic"
python3 "$app_dir/tool/run_pdf_font_diagnostic.py" \
  --executable "$test_dir/pdf_font_diagnostic" --output "$evidence/matrix" --artifact-root "$evidence"
} 2>&1 | python3 "$app_dir/tool/run_pdf_font_diagnostic.py" --capture-log "$evidence/acceptance.log"
