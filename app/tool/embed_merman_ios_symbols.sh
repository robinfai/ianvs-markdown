#!/bin/bash
set -euo pipefail

# Simulator/debug builds keep the upstream package. Device archives must use
# the matching rebuilt framework and dSYM prepared before starting Xcode.
[[ "${PLATFORM_NAME:-}" == iphoneos && "${CONFIGURATION:-}" == Release && "${ACTION:-}" == install ]] || exit 0
app_dir="$(cd "$(dirname "$0")/.." && pwd)"
prepared="$app_dir/build/merman-symbols"
if [[ ! -f "$prepared/MermanFFI.framework/MermanFFI" ]]; then
  echo 'error: Run bash tool/prepare_merman_ios_symbols.sh in app/ before archiving.' >&2
  exit 1
fi
grep -qx 'version: 0.7.0' "$app_dir/ios/.symlinks/plugins/merman/pubspec.yaml"
grep -qx '00a2f291025913d612b6ca1ce9b6df6daf5bef94' "$prepared/source-revision.txt"
python3 "$app_dir/tool/verify_merman_symbols.py" \
  "$prepared/MermanFFI.framework/MermanFFI" "$prepared/MermanFFI.framework.dSYM"
destination="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/MermanFFI.framework"
ditto "$prepared/MermanFFI.framework" "$destination"
ditto "$prepared/MermanFFI.framework.dSYM" "$DWARF_DSYM_FOLDER_PATH/MermanFFI.framework.dSYM"
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == YES ]]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$destination"
fi
python3 "$app_dir/tool/verify_merman_symbols.py" \
  "$destination/MermanFFI" "$DWARF_DSYM_FOLDER_PATH/MermanFFI.framework.dSYM"
