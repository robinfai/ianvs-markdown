#!/bin/bash
set -euo pipefail

linefold_app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linefold_bundle="${1:-$linefold_app_dir/build/macos/Build/Products/Release/Linefold.app}"
linefold_extension="$linefold_bundle/Contents/PlugIns/LinefoldQuickLook.appex"
linefold_executable="$linefold_extension/Contents/MacOS/LinefoldQuickLook"

python3 - "$linefold_bundle" "$linefold_extension" <<'PY'
import pathlib
import plistlib
import subprocess
import sys

app, extension = map(pathlib.Path, sys.argv[1:])
with (app / 'Contents/Info.plist').open('rb') as file:
    host = plistlib.load(file)
with (extension / 'Contents/Info.plist').open('rb') as file:
    info = plistlib.load(file)
assert info['CFBundleIdentifier'] == host['CFBundleIdentifier'] + '.QuickLook'
for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
    assert info[key] == host[key], f'Host/extension version mismatch: {key}'
assert info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.quicklook.preview'
attributes = info['NSExtension']['NSExtensionAttributes']
assert attributes['QLIsDataBasedPreview'] is False
assert attributes['QLSupportedContentTypes'] == ['net.daringfireball.markdown']
binary = extension / 'Contents/MacOS/LinefoldQuickLook'
libraries = subprocess.check_output(['otool', '-L', str(binary)], text=True).splitlines()
# Universal binaries emit one header per architecture; only indented rows are
# load commands. Validate every architecture's dependencies.
dependencies = [line.strip().split(' (')[0] for line in libraries if line.startswith('\t')]
assert '@rpath/FlutterMacOS.framework/Versions/A/FlutterMacOS' in dependencies
for dependency in dependencies:
    assert dependency.startswith(('@rpath/FlutterMacOS.framework/', '/System/Library/', '/usr/lib/')), dependency
frameworks = extension / 'Contents/Frameworks'
assert (frameworks / 'libmerman_ffi.dylib').is_file()
assert (frameworks / 'App.framework/Resources/flutter_assets/NativeAssetsManifest.json').is_file()
assert (frameworks / 'FlutterMacOS.framework/FlutterMacOS').is_file()
assert list(frameworks.glob('*svg*.framework')), 'Missing SVG native asset'
app_archs = set(subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/Linefold')], text=True).split())
for code in [binary, frameworks / 'App.framework/App', frameworks / 'FlutterMacOS.framework/FlutterMacOS', frameworks / 'libmerman_ffi.dylib']:
    assert app_archs <= set(subprocess.check_output(['lipo', '-archs', str(code)], text=True).split()), code
assert (extension / 'Contents/Resources/ThirdPartyNotices.txt').is_file()
entitlements = plistlib.loads(subprocess.check_output([
    'codesign', '-d', '--entitlements', '-', '--xml', str(extension)], stderr=subprocess.DEVNULL))
assert entitlements.get('com.apple.security.app-sandbox') is True
assert not entitlements.get('com.apple.security.network.client', False)
print('Quick Look bundle metadata, versions, isolated dependencies and sandbox verified')
PY
codesign --verify --deep --strict "$linefold_bundle"
