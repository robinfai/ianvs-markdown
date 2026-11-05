#!/usr/bin/env python3
"""Require matching, source-level MermanFFI symbols (not an empty dSYM)."""
import re
import subprocess
import sys
from pathlib import Path


def verify(binary: Path, dsym: Path) -> None:
    def dwarf(*args: str) -> str:
        return subprocess.check_output(["xcrun", "dwarfdump", *args], text=True)

    def uuids(path: Path) -> set[tuple[str, str]]:
        return set(re.findall(r"UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)", dwarf("--uuid", str(path))))

    expected = uuids(binary)
    if not expected or expected != uuids(dsym):
        raise ValueError("MermanFFI binary and dSYM UUID/architectures do not match")
    debug = dwarf("--name=merman_get_native_api", str(dsym))
    if "DW_TAG_subprogram" not in debug or "DW_AT_decl_line" not in debug:
        raise ValueError("MermanFFI dSYM has no source-level information for its ABI entry point")
    print(f"MermanFFI source symbols verified: {sorted(expected)}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: verify_merman_symbols.py BINARY DSYM")
    verify(Path(sys.argv[1]), Path(sys.argv[2]))
