#!/bin/bash
# Repeatable acceptance of all three sidebar phases, including the macOS bridge.
set -euo pipefail
linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$linefold_app_dir"
mkdir -p build/sidebar-acceptance
dart format --output=none --set-exit-if-changed lib test 2>&1 | tee build/sidebar-acceptance/format.log
flutter analyze 2>&1 | tee build/sidebar-acceptance/analyze.log
flutter test 2>&1 | tee build/sidebar-acceptance/flutter-tests.log
bash tool/test_native_workspace_files.sh 2>&1 | tee build/sidebar-acceptance/native-files.log
flutter build macos --debug 2>&1 | tee build/sidebar-acceptance/macos-build.log
