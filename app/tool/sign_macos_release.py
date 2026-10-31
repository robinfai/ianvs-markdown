#!/usr/bin/env python3
"""Sign nested native code inside-out, preserving explicit sandbox entitlements."""
import os
from pathlib import Path
import datetime
import plistlib
import shutil
import subprocess
import sys
import tempfile


def cloud_entitlements(app: Path, source: Path) -> dict:
    """Fail closed if CI cannot authorize the shared production vault."""
    profile = Path(os.environ['APPLE_MACOS_PROVISIONING_PROFILE']).resolve(strict=True)
    team = os.environ['APPLE_TEAM_ID']
    decoded = subprocess.check_output(['security', 'cms', '-D', '-i', str(profile)])
    payload = plistlib.loads(decoded)
    allowed = payload['Entitlements']
    identifier = 'work.ianvs.linefold'
    container = 'iCloud.' + identifier
    if payload['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError('Developer ID provisioning profile has expired')
    if payload.get('TeamIdentifier') != [team]:
        raise ValueError('Provisioning profile belongs to a different team')
    if allowed.get('com.apple.application-identifier') != f'{team}.{identifier}':
        raise ValueError('Provisioning profile does not authorize Linefold')
    for key in ('com.apple.developer.icloud-container-identifiers',
                'com.apple.developer.ubiquity-container-identifiers'):
        if container not in allowed.get(key, []):
            raise ValueError(f'Provisioning profile lacks {key}: {container}')
    services = allowed.get('com.apple.developer.icloud-services', [])
    if services != '*' and 'CloudDocuments' not in services:
        raise ValueError('Provisioning profile lacks iCloud Documents')
    environments = allowed.get('com.apple.developer.icloud-container-environment', [])
    if 'Production' not in environments:
        raise ValueError('Provisioning profile lacks production iCloud')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('LinefoldCloudEnabled') != 'YES' or info.get('CFBundleIdentifier') != identifier:
        raise ValueError('Release must be built with LINEFOLD_CLOUD_ENABLED=YES')
    result = plistlib.loads((source / 'macos/Runner/Release.entitlements').read_bytes())
    result.update({
        'com.apple.application-identifier': f'{team}.{identifier}',
        'com.apple.developer.team-identifier': team,
        'com.apple.developer.icloud-container-environment': 'Production',
    })
    shutil.copyfile(profile, app / 'Contents/embedded.provisionprofile')
    return result


def sign(bundle: Path, identity: str, keychain: str, entitlements: Path | None = None):
    command = ['codesign', '--force', '--timestamp', '--options', 'runtime',
               '--sign', identity, '--keychain', keychain]
    if entitlements:
        command += ['--entitlements', str(entitlements)]
    subprocess.run(command + [str(bundle)], check=True)


def main():
    app = Path(sys.argv[1]).resolve(strict=True)
    source = Path(__file__).resolve().parents[1]
    identity = os.environ['APPLE_SIGNING_IDENTITY']
    keychain = os.environ['SIGNING_KEYCHAIN']
    entitlements = cloud_entitlements(app, source)
    bundles = [p for p in app.rglob('*') if p.is_dir() and not p.is_symlink()
               and p.suffix in ('.framework', '.appex', '.app', '.xpc')]
    # codesign treats a bundle's main executable as the bundle itself. Defer
    # those files until their nested code is signed (unsigned Xcode CI builds
    # otherwise fail on the still-unsigned Quick Look extension).
    bundle_executables = set()
    for bundle in [app, *bundles]:
        for relative in ('Contents/Info.plist', 'Resources/Info.plist', 'Info.plist'):
            info = bundle / relative
            if info.is_file():
                executable = plistlib.loads(info.read_bytes()).get('CFBundleExecutable')
                if executable:
                    for candidate in (bundle / 'Contents/MacOS' / executable, bundle / executable):
                        if candidate.is_file():
                            bundle_executables.add(candidate.resolve())
                break
    # Sign physical Mach-O files first (including Flutter native assets and Rust).
    # Resolve symlinks so framework aliases are never signed independently.
    binaries = set()
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink():
            kind = subprocess.check_output(['file', '-b', str(path)], text=True)
            if 'Mach-O' in kind and path.resolve() not in bundle_executables:
                binaries.add(path.resolve())
    for path in sorted(binaries):
        sign(path, identity, keychain)
    for bundle in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
        entitlement = None
        if bundle.suffix == '.appex':
            if bundle.name != 'LinefoldQuickLook.appex':
                raise ValueError(f'Unconfigured extension: {bundle}')
            entitlement = source / 'macos/QuickLook/QuickLook.entitlements'
        sign(bundle, identity, keychain, entitlement)
    with tempfile.TemporaryDirectory(prefix='linefold-entitlements-') as temporary:
        entitlement_path = Path(temporary) / 'Release.entitlements'
        entitlement_path.write_bytes(plistlib.dumps(entitlements))
        sign(app, identity, keychain, entitlement_path)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)


if __name__ == '__main__':
    main()
