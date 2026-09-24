#!/bin/bash
set -euo pipefail

linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linefold_source="$linefold_app_dir/build/macos/Build/Products/Release/Linefold.app"
linefold_install_dir="${1:-/Applications}"

if [[ "$(uname -s)" != Darwin ]]; then
  printf 'Linefold installation requires macOS.\n' >&2
  exit 1
fi

if [[ ! -d "$linefold_source" ]]; then
  printf 'Release app not found. Run make install from the repository root.\n' >&2
  exit 1
fi

mkdir -p "$linefold_install_dir"
linefold_install_dir="$(cd "$linefold_install_dir" && pwd -P)"
linefold_target="$linefold_install_dir/Linefold.app"

# Only replace an existing Linefold bundle, never an unrelated file or symlink.
if [[ -e "$linefold_target" || -L "$linefold_target" ]]; then
  if [[ -L "$linefold_target" || ! -d "$linefold_target" ]] ||
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
      "$linefold_target/Contents/Info.plist" 2>/dev/null || true)" != work.ianvs.linefold ]]; then
    printf 'Refusing to replace a non-Linefold item: %s\n' "$linefold_target" >&2
    exit 1
  fi
fi

# Stage on the same filesystem so a failed build or copy leaves the old app intact.
linefold_stage="$(mktemp -d "$linefold_install_dir/.linefold-install.XXXXXX")"
linefold_backup="$linefold_stage/Previous.app"
cleanup() {
  local linefold_status=$?
  if [[ -d "$linefold_backup" && ! -e "$linefold_target" && ! -L "$linefold_target" ]]; then
    if ! mv "$linefold_backup" "$linefold_target"; then
      printf 'Restore the previous app from %s\n' "$linefold_backup" >&2
      exit 1
    fi
  fi
  rm -rf "$linefold_stage"
  return "$linefold_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$linefold_source" "$linefold_stage/Linefold.app"
codesign --verify --deep --strict "$linefold_stage/Linefold.app"
if [[ -d "$linefold_target" ]]; then
  mv "$linefold_target" "$linefold_backup"
fi
mv "$linefold_stage/Linefold.app" "$linefold_target"

printf 'Installed Linefold at %s\n' "$linefold_target"
