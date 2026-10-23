#!/usr/bin/env python3
"""Bound synthetic export evidence immediately before its attempt-scoped upload.

This is a sequential CI admission check, not a snapshot against a malicious
same-user process. It never opens file contents or follows symbolic links.
"""
from pathlib import Path
import json
import os
import stat
import sys

MAXIMUM_FILES = 64
MAXIMUM_ENTRIES = 128
MAXIMUM_FILE_BYTES = 32 * 1024 * 1024
MAXIMUM_TOTAL_BYTES = 64 * 1024 * 1024


def validate_tree(root: Path, *, checkout: Path,
                  maximum_files: int = MAXIMUM_FILES,
                  maximum_entries: int = MAXIMUM_ENTRIES,
                  maximum_file_bytes: int = MAXIMUM_FILE_BYTES,
                  maximum_total_bytes: int = MAXIMUM_TOTAL_BYTES) -> dict[str, int]:
    if root.is_absolute() or not root.parts or ".." in root.parts:
        raise ValueError("Export evidence path must be relative to this checkout")
    # Resolve only the trusted checkout itself: /var may be a system alias on
    # macOS. Below that anchor every component must be an actual directory.
    current = checkout.resolve(strict=True)
    if not current.is_dir():
        raise ValueError("Checkout anchor must be a directory")
    for component in root.parts:
        current /= component
        if not stat.S_ISDIR(current.lstat().st_mode):
            raise ValueError("Export evidence path contains a symbolic link or non-directory")
    pending = [current]
    entries = files = total = 0
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as children:
            for child in children:
                entries += 1
                if entries > maximum_entries:
                    raise ValueError("Export evidence exceeds the entry-count limit")
                value = child.stat(follow_symlinks=False)
                if stat.S_ISDIR(value.st_mode):
                    pending.append(Path(child.path))
                    continue
                if not stat.S_ISREG(value.st_mode):
                    raise ValueError("Export evidence contains a symbolic link or special file")
                files += 1
                total += value.st_size
                if files > maximum_files:
                    raise ValueError("Export evidence exceeds the file-count limit")
                if value.st_size > maximum_file_bytes or total > maximum_total_bytes:
                    raise ValueError("Export evidence exceeds the byte limit")
    if files == 0:
        raise ValueError("Export evidence is empty")
    return {"files": files, "entries": entries, "bytes": total}


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: check_export_evidence_budget.py EXPORT_QA_DIRECTORY")
    try:
        result = validate_tree(Path(sys.argv[1]), checkout=Path.cwd())
    except (OSError, ValueError) as error:
        raise SystemExit(f"Export evidence rejected: {error}") from error
    print("PASS: bounded synthetic export evidence " + json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
