#!/usr/bin/env bash
# Build two isolated app copies; never modifies /Applications/Linefold.app.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
source_app=${1:?built Linefold.app is required}
fixture=${2:?new fixture directory is required}
sparkle=${3:?Sparkle bin directory is required}
port=${4:-9123}
[[ ! -e "$fixture" ]] || { echo 'Use a fresh fixture directory' >&2; exit 1; }
mkdir -p "$fixture/installed" "$fixture/downloads" "$fixture/new"
public_key=$(xcrun swift "$root/app/tool/update_keys.swift" generate "$fixture/test-private.key")
printf '%s\n' "$public_key" > "$fixture/test-public.key"
python3 - "$root/app/macos/Runner/ReleaseLocal.entitlements" "$fixture/test.entitlements" <<'PY2'
import plistlib,sys
from pathlib import Path
value=plistlib.loads(Path(sys.argv[1]).read_bytes())
value['com.apple.security.temporary-exception.mach-lookup.global-name'] = ['work.ianvs.linefold.update-test-spks', 'work.ianvs.linefold.update-test-spki']
Path(sys.argv[2]).write_bytes(plistlib.dumps(value))
PY2
for pair in installed:900001 new:900002; do
  folder=${pair%:*}
  build=${pair#*:}
  app="$fixture/$folder/Linefold Update Test.app"
  ditto "$source_app" "$app"
  python3 "$root/app/tool/macos_release.py" configure "$app" --public-key "$public_key" \
    --feed "http://127.0.0.1:$port/appcast.xml" --test
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" -c "Set :CFBundleShortVersionString 9.0.$build" "$app/Contents/Info.plist"
  python3 "$root/app/tool/macos_release.py" sign "$app" --identity - --test \
    --entitlements "$fixture/test.entitlements" > "$fixture/sign-$build.log" 2>&1
done
archive="$fixture/downloads/Linefold-test.zip"
ditto -c -k --keepParent "$fixture/new/Linefold Update Test.app" "$archive"
signature=$("$sparkle/sign_update" --ed-key-file "$fixture/test-private.key" -p "$archive")
python3 "$root/app/tool/macos_release.py" appcast "$fixture/new/Linefold Update Test.app" \
  "$archive" "$fixture/downloads/appcast.xml" --url "http://127.0.0.1:$port/Linefold-test.zip" \
  --signature "$signature" --test
"$sparkle/sign_update" --ed-key-file "$fixture/test-private.key" "$fixture/downloads/appcast.xml"
"$sparkle/sign_update" --ed-key-file "$fixture/test-private.key" --verify "$archive" "$signature"
"$sparkle/sign_update" --ed-key-file "$fixture/test-private.key" --verify "$fixture/downloads/appcast.xml"
printf 'Fixture ready: %s\nServe downloads on 127.0.0.1:%s, then open the installed test app.\n' "$fixture" "$port"
