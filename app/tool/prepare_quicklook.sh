#!/bin/bash
set -euo pipefail
linefold_app_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$linefold_app_dir/quicklook/lib/shared/models"
# Generated copies ensure both isolated entry points use exactly the same styles.
for source in desktop_theme.dart desktop_typography.dart reading_typography.dart models/reading_preferences.dart models/workspace_layout.dart; do
  cp "$linefold_app_dir/lib/src/$source" "$linefold_app_dir/quicklook/lib/shared/$source"
done
cd "$linefold_app_dir/quicklook"
linefold_flutter="${FLUTTER:-${FLUTTER_ROOT:+$FLUTTER_ROOT/bin/}flutter}"
"$linefold_flutter" pub get "$@"
