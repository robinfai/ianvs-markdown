#!/bin/bash
set -euo pipefail
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:$PATH"
linefold_macos_dir="${PROJECT_DIR:?}"
linefold_client="$linefold_macos_dir/../quicklook"
linefold_native_dir="${BUILT_PRODUCTS_DIR:?}/LinefoldQuickLookNative"
linefold_frameworks="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}"
mkdir -p "$linefold_native_dir" "$linefold_frameworks"
bash "$linefold_macos_dir/../tool/prepare_quicklook.sh" --offline
(
  cd "$linefold_client"
  "$FLUTTER_ROOT/bin/flutter" assemble --output=build/native \
    -dTargetPlatform=darwin -dBuildMode=release -dTargetFile=lib/main.dart \
    "-dDarwinArchs=${ARCHS:?}" "--DartDefines=${DART_DEFINES:-}" -dTreeShakeIcons=true release_macos_bundle_flutter_assets
)
for framework in FlutterMacOS App; do
  rm -rf "$linefold_native_dir/$framework.framework" "$linefold_frameworks/$framework.framework"
  ditto "$linefold_client/build/native/$framework.framework" "$linefold_native_dir/$framework.framework"
  ditto "$linefold_native_dir/$framework.framework" "$linefold_frameworks/$framework.framework"
done
# Remove the obsolete CocoaPods library from incremental extension builds.
rm -f "$linefold_frameworks/libmerman_ffi.dylib"
# Flutter's native-asset frameworks must be adjacent to App.framework.
if [[ -d "$linefold_client/build/native/native_assets" ]]; then
  for asset in "$linefold_client/build/native/native_assets/"*.framework; do
    ditto "$asset" "$linefold_frameworks/$(basename "$asset")"
  done
fi
mkdir -p "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
ditto "$linefold_macos_dir/QuickLook/ThirdPartyNotices.txt" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/ThirdPartyNotices.txt"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
  while IFS= read -r -d '' code; do
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$code"
  done < <(find "$linefold_frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0)
fi
