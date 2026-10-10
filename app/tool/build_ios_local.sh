#!/bin/bash
set -euo pipefail

# Personal Apple teams cannot provision an iCloud container. Produce an explicit
# local-storage build without changing the cloud-enabled project configuration.
linefold_team="${1:?Usage: bash app/tool/build_ios_local.sh DEVELOPMENT_TEAM}"
linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linefold_local_dir="$linefold_app_dir/build/ios-local-signing"
mkdir -p "$linefold_local_dir"
python3 - "$linefold_app_dir/ios/Runner/Info.plist" "$linefold_local_dir/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
info.pop('NSUbiquitousContainers', None)
info['LinefoldCloudEnabled'] = 'NO'
with open(sys.argv[2], 'wb') as output:
    plistlib.dump(info, output, sort_keys=False)
from pathlib import Path
Path(sys.argv[2]).with_name('Local.entitlements').write_bytes(plistlib.dumps({}))
PY

xcodebuild -workspace "$linefold_app_dir/ios/Runner.xcworkspace" \
  -scheme Runner -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$linefold_app_dir/build/ios-device-install" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$linefold_team" CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY='Apple Development' CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_ENTITLEMENTS="$linefold_local_dir/Local.entitlements" LINEFOLD_CLOUD_ENABLED=NO \
  LINEFOLD_INFO_PLIST="$linefold_local_dir/Info.plist" build
