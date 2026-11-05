#!/bin/bash
set -euo pipefail
[[ "${PLATFORM_NAME:-}" == iphoneos && "${CONFIGURATION:-}" == Release && "${ACTION:-}" == install ]] || exit 0
app_dir="$(cd "$(dirname "$0")/.." && pwd)"
prepared="$app_dir/build/merman-symbols-0.9.3"
if [[ ! -f "$prepared/libmerman_ffi.dylib" ]]; then
  echo 'error: Run bash tool/prepare_merman_ios_symbols.sh in app/ before archiving.' >&2
  exit 1
fi
grep -qx '3b915f69c02d55b873d252cf6c8a6048e7f3427d' "$prepared/source-revision.txt"
# Resolve the actual framework created by Flutter Native Assets rather than
# assuming the old CocoaPods MermanFFI framework name.
python3 - "$app_dir" "$prepared" <<'PY'
import json, os, pathlib, plistlib, shutil, subprocess, sys
app, prepared = map(pathlib.Path, sys.argv[1:])
config = app / '.dart_tool/package_config.json'
package = next(p for p in json.loads(config.read_text())['packages'] if p['name'] == 'merman')
from urllib.parse import urljoin, urlparse
root = pathlib.Path(urlparse(urljoin(config.as_uri(), package['rootUri'])).path)
assert 'version: 0.9.3' in (root / 'pubspec.yaml').read_text()
frameworks = pathlib.Path(os.environ['TARGET_BUILD_DIR']) / os.environ['FRAMEWORKS_FOLDER_PATH']
matches = list(frameworks.glob('*merman*.framework'))
assert len(matches) == 1, f'Expected one Merman Native Assets framework: {matches}'
framework = matches[0]
info = plistlib.loads((framework / 'Info.plist').read_bytes())
name = info['CFBundleExecutable']
binary = framework / name
original = root / 'native/ios/arm64/libmerman_ffi.dylib'
def exports(path):
    return sorted(line for line in subprocess.check_output(['xcrun','nm','-gjU',str(path)],text=True).splitlines() if line.startswith('_merman_'))
assert exports(original) == exports(prepared / 'libmerman_ffi.dylib')
shutil.copy2(prepared / 'libmerman_ffi.dylib', binary)
subprocess.run(['install_name_tool','-id',f'@rpath/{framework.name}/{name}',str(binary)],check=True)
symbols_dir = pathlib.Path(os.environ['DWARF_DSYM_FOLDER_PATH'])
# Replace Flutter's generated Native Assets dSYM at its original location.
# A second root-level copy would make Xcode archive both the obsolete UUID and
# the source-level symbols under a suffixed name.
dsym = symbols_dir / 'native_assets' / (framework.name + '.dSYM')
legacy_dsym = symbols_dir / (framework.name + '.dSYM')
if legacy_dsym.exists():
    shutil.rmtree(legacy_dsym)
if dsym.exists():
    shutil.rmtree(dsym)
shutil.copytree(prepared / 'libmerman_ffi.dylib.dSYM', dsym, dirs_exist_ok=True)
(dsym / 'Contents/Resources/DWARF/libmerman_ffi.dylib').rename(dsym / 'Contents/Resources/DWARF' / name)
subprocess.run(['python3',str(app / 'tool/verify_merman_symbols.py'),str(binary),str(dsym)],check=True)
if os.environ.get('CODE_SIGNING_ALLOWED') == 'YES':
    subprocess.run(['codesign','--force','--sign',os.environ['EXPANDED_CODE_SIGN_IDENTITY'],'--timestamp=none',str(framework)],check=True)
PY
