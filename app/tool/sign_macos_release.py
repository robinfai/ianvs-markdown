#!/usr/bin/env python3
"""Sign nested native code inside-out, preserving explicit sandbox entitlements."""
import os
from pathlib import Path
import subprocess
import sys


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
    # Sign physical Mach-O files first (including Flutter native assets and Rust).
    # Resolve symlinks so framework aliases are never signed independently.
    binaries = set()
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink():
            kind = subprocess.check_output(['file', '-b', str(path)], text=True)
            if 'Mach-O' in kind:
                binaries.add(path.resolve())
    for path in sorted(binaries):
        sign(path, identity, keychain)
    bundles = [p for p in app.rglob('*') if p.is_dir() and not p.is_symlink()
               and p.suffix in ('.framework', '.appex', '.app', '.xpc')]
    for bundle in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
        entitlement = None
        if bundle.suffix == '.appex':
            if bundle.name != 'LinefoldQuickLook.appex':
                raise ValueError(f'Unconfigured extension: {bundle}')
            entitlement = source / 'macos/QuickLook/QuickLook.entitlements'
        sign(bundle, identity, keychain, entitlement)
    sign(app, identity, keychain, source / 'macos/Runner/ReleaseLocal.entitlements')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)


if __name__ == '__main__':
    main()
