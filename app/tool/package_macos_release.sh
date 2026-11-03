#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
app="$root/app/build/macos/Build/Products/Release/Linefold.app"
: "${APPLE_SIGNING_IDENTITY:?}"
: "${SPARKLE_TOOLS:?}"
: "${SPARKLE_KEY_FILE:?}"
: "${RELEASE_VERSION:?}"
: "${RELEASE_OUTPUT:?}"
: "${GITHUB_REPOSITORY:?}"
RELEASE_REPOSITORY="$GITHUB_REPOSITORY"
MACOS_SIGNING_IDENTITY="$APPLE_SIGNING_IDENTITY"
notary_auth=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
mkdir -p "$RELEASE_OUTPUT"
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    lipo "$binary" -verify_arch arm64 x86_64
  fi
done < <(find "$app" -type f -print0)
archive="$RELEASE_OUTPUT/Linefold-$RELEASE_VERSION-macos-universal.zip"
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" "${notary_auth[@]}" --wait --timeout 45m --output-format json > "$RELEASE_OUTPUT/notarization.json"
python3 - "$RELEASE_OUTPUT/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple notarization was not accepted: ' + str(result.get('status')))
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
# Repackage after stapling, then sign the exact bytes users will download.
ditto -c -k --keepParent "$app" "$archive"
signature=$("$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" -p "$archive")
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" --verify "$archive" "$signature"
python3 "$root/app/tool/macos_release.py" appcast "$app" "$archive" "$RELEASE_OUTPUT/appcast.xml" \
  --url "https://github.com/$RELEASE_REPOSITORY/releases/download/linefold-v$RELEASE_VERSION/$(basename "$archive")" \
  --signature "$signature"
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" "$RELEASE_OUTPUT/appcast.xml"
"$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" --verify "$RELEASE_OUTPUT/appcast.xml"
# First-install disk image uses the same signed, stapled app as the update ZIP.
dmg="$RELEASE_OUTPUT/Linefold-$RELEASE_VERSION-macos-universal.dmg"
dmg_stage=$(mktemp -d)
trap 'rm -rf "$dmg_stage"' EXIT
ditto "$app" "$dmg_stage/Linefold.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create -volname "Linefold $RELEASE_VERSION" -srcfolder "$dmg_stage" \
  -format UDZO -ov "$dmg"
codesign --force --sign "$MACOS_SIGNING_IDENTITY" --timestamp "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
xcrun notarytool submit "$dmg" "${notary_auth[@]}" --wait --timeout 45m --output-format json > "$RELEASE_OUTPUT/notarization-dmg.json"
python3 - "$RELEASE_OUTPUT/notarization-dmg.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple DMG notarization was not accepted: ' + str(result.get('status')))
PY
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
hdiutil verify "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
(cd "$RELEASE_OUTPUT" && shasum -a 256 "$(basename "$archive")" "$(basename "$dmg")" appcast.xml > SHA256SUMS)
