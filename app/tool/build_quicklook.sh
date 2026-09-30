#!/bin/bash
set -euo pipefail

export PATH="${HOME}/.cargo/bin:/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
linefold_macos_dir="${PROJECT_DIR:?PROJECT_DIR is required}"
export MERMAN_LIB_DIR="$linefold_macos_dir/Flutter/ephemeral/.symlinks/plugins/merman/macos/Libraries"
export CARGO_TARGET_DIR="$linefold_macos_dir/../build/quicklook-native"
linefold_native_dir="${BUILT_PRODUCTS_DIR:?}/LinefoldQuickLookNative"
linefold_frameworks="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}"
mkdir -p "$linefold_native_dir" "$linefold_frameworks"

if [[ ! -f "$MERMAN_LIB_DIR/libmerman_ffi.dylib" ]]; then
  printf 'error: Missing merman native library. Run flutter pub get in app/.\n' >&2
  exit 1
fi

linefold_archives=()
linefold_arch_flags=()
for linefold_arch in ${ARCHS:?ARCHS is required}; do
  case "$linefold_arch" in
    arm64) linefold_rust_target=aarch64-apple-darwin ;;
    x86_64) linefold_rust_target=x86_64-apple-darwin ;;
    *) printf 'error: Unsupported Quick Look architecture: %s\n' "$linefold_arch" >&2; exit 1 ;;
  esac
  cargo build --locked --release \
    --manifest-path "$linefold_macos_dir/QuickLook/renderer/Cargo.toml" \
    --target "$linefold_rust_target"
  linefold_archives+=("$CARGO_TARGET_DIR/$linefold_rust_target/release/liblinefold_quicklook.a")
  linefold_arch_flags+=(-extract "$linefold_arch")
done
/usr/bin/lipo -create "${linefold_archives[@]}" -output "$linefold_native_dir/liblinefold_quicklook.a"
/usr/bin/lipo "$MERMAN_LIB_DIR/libmerman_ffi.dylib" "${linefold_arch_flags[@]}" \
  -output "$linefold_native_dir/libmerman_ffi.dylib"
/usr/bin/install_name_tool -id '@rpath/libmerman_ffi.dylib' "$linefold_native_dir/libmerman_ffi.dylib"
/usr/bin/ditto "$linefold_native_dir/libmerman_ffi.dylib" "$linefold_frameworks/libmerman_ffi.dylib"
mkdir -p "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
/usr/bin/ditto "$linefold_macos_dir/QuickLook/ThirdPartyNotices.txt" \
  "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/ThirdPartyNotices.txt"

if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
  linefold_signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  /usr/bin/codesign --force --sign "${linefold_signing_identity:--}" \
    --timestamp=none "$linefold_frameworks/libmerman_ffi.dylib"
fi
