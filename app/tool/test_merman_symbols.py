#!/usr/bin/env python3
"""Exercise the release gate with real Mach-O/DWARF, including bad artifacts."""
import subprocess
import tempfile
import unittest
from pathlib import Path

from verify_merman_symbols import verify


class SymbolsTest(unittest.TestCase):
    def test_matching_mismatched_and_empty_symbols(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "abi.c"

            def build(name, value, debug):
                source.write_text(f"int merman_get_native_api(void) {{ return {value}; }}\n")
                binary = root / f"{name}.dylib"
                dsym = root / f"{name}.dSYM"
                obj = root / f"{name}.o"
                subprocess.run(
                    ["xcrun", "clang", "-c", "-O2", "-g" if debug else "-g0",
                     str(source), "-o", str(obj)], check=True,
                )
                subprocess.run(["xcrun", "clang", "-dynamiclib", str(obj), "-o", str(binary)], check=True)
                subprocess.run(["xcrun", "dsymutil", str(binary), "-o", str(dsym)], check=True)
                subprocess.run(["xcrun", "strip", "-x", str(binary)], check=True)
                return binary, dsym

            binary, dsym = build("valid", 1, True)
            verify(binary, dsym)
            other, _ = build("other", 2, True)
            with self.assertRaisesRegex(ValueError, "UUID/architectures"):
                verify(other, dsym)
            empty_binary, empty_dsym = build("empty", 1, False)
            with self.assertRaisesRegex(ValueError, "source-level"):
                verify(empty_binary, empty_dsym)


if __name__ == "__main__":
    unittest.main()
