#!/usr/bin/env python3
"""Check declared and (optionally) built app print permissions, not runtime UI."""
import argparse
from pathlib import Path
import plistlib
import subprocess


def validate(data: bytes, label: str) -> None:
    value = plistlib.loads(data)
    for key in ("com.apple.security.app-sandbox", "com.apple.security.print"):
        if value.get(key) is not True:
            raise SystemExit(f"{label}: missing {key}=true")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--built-apps", action="store_true")
    args = parser.parse_args()
    app = Path(__file__).resolve().parents[1]
    for name in ("DebugProfile", "Release", "DebugProfileLocal", "ReleaseLocal"):
        path = app / "macos" / "Runner" / f"{name}.entitlements"
        validate(path.read_bytes(), str(path))
    if args.built_apps:
        for mode in ("Debug", "Release"):
            bundle = app / "build/macos/Build/Products" / mode / "Linefold.app"
            if not bundle.is_dir():
                raise SystemExit(f"Missing built app: {bundle}")
            result = subprocess.run(
                ["codesign", "-d", "--entitlements", ":-", str(bundle)],
                check=True, capture_output=True,
            )
            validate(result.stdout, str(bundle))
    print("PASS: sandbox and printing declarations" +
          (" and actual Debug/Release code-signature entitlements" if args.built_apps else " (source only)"))


if __name__ == "__main__":
    main()
