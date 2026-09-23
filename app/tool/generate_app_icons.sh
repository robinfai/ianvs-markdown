#!/bin/bash
set -euo pipefail

linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linefold_icon_source="$linefold_app_dir/design/linefold-icon-v1.png"
linefold_icon_output="$linefold_app_dir/macos/Runner/Assets.xcassets/AppIcon.appiconset"

# Export every unique size referenced by the macOS asset catalog from the master.
# sips preserves the transparent canvas and the approved icon artwork.
for linefold_icon_size in 16 32 64 128 256 512 1024; do
  sips --resampleHeightWidth "$linefold_icon_size" "$linefold_icon_size" \
    "$linefold_icon_source" \
    --out "$linefold_icon_output/app_icon_${linefold_icon_size}.png" >/dev/null
done

printf 'Generated Linefold macOS icons in %s\n' "$linefold_icon_output"
