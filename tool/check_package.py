#!/usr/bin/env python3
"""Validate a Pub-selected package snapshot from an unrelated temporary host.

Pub's verbose archive manifest is the authority, not a second implementation of
.pubignore. Fail closed if its log format changes. Never publish or modify Git.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = {"app", "packages", "demos", "build", "tool", "benchmark", ".git"}


def run(command, cwd, log, allowed=(0,)):
    print(f"[{log.stem}] {' '.join(map(str, command))}", flush=True)
    with log.open("w") as output:
        result = subprocess.run(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode not in allowed:
        print(log.read_text()[-8000:])
        raise RuntimeError(f"Exit {result.returncode}; see {log}")
    return log.read_text()


def archive_files(log, root):
    marker = "FINE: Creating .tar.gz stream containing:\n"
    if log.count(marker) != 1:
        raise RuntimeError("Pub archive manifest missing or ambiguous; inspect verbose log")
    files = set()
    for line in log.split(marker, 1)[1].splitlines():
        if not line.startswith("    | "):
            break
        path = Path(line[6:])
        if not path.is_absolute():
            path = root / path
        # Resolving also prevents silently following an external symlink.
        relative = path.resolve().relative_to(root.resolve())
        if path.is_file():
            files.add(relative.as_posix())
    if not {"pubspec.yaml", "LICENSE", "lib/ianvs_markdown.dart", "example/pubspec.yaml"} <= files:
        raise RuntimeError("Pub manifest is incomplete")
    for name in files:
        if Path(name).parts[0] in FORBIDDEN:
            raise RuntimeError(f"Unexpected publication content: {name}")
    return sorted(files)


def check_resolved_paths(package, snapshot):
    config = json.loads((package / ".dart_tool/package_config.json").read_text())
    from urllib.parse import unquote, urljoin, urlparse

    config_uri = (package / ".dart_tool/package_config.json").as_uri()
    core_root = None
    for item in config["packages"]:
        uri = urlparse(urljoin(config_uri, item["rootUri"]))
        if uri.scheme != "file":
            raise RuntimeError(f"Unexpected package URI: {uri}")
        path = Path(unquote(uri.path)).resolve()
        if path.is_relative_to(ROOT):
            raise RuntimeError(f"Snapshot leaked original workspace: {path}")
        if item["name"] in {"ianvs_mermaid", "merman"}:
            raise RuntimeError("Minimal host resolved an optional Mermaid backend")
        if item["name"] == "ianvs_markdown":
            core_root = path
    if core_root != snapshot.resolve():
        raise RuntimeError(f"Host did not resolve the package snapshot: {core_root}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", default=os.environ.get("FLUTTER", "flutter"))
    parser.add_argument("--dart", default=os.environ.get("DART", "dart"))
    parser.add_argument("--keep", action="store_true", help="Keep the temporary snapshot and host")
    args = parser.parse_args()
    logs = ROOT / "build/package-check"
    logs.mkdir(parents=True, exist_ok=True)
    command = [args.dart, "pub", "--verbose", "publish", "--dry-run"]
    # A dirty workspace can emit exit 65. The identical snapshot must pass
    # validation with exit 0; warnings are never ignored there.
    original = run(command, ROOT, logs / "source-publish.log", allowed=(0, 65))
    files = archive_files(original, ROOT)
    temporary = Path(tempfile.mkdtemp(prefix="ianvs-package-"))
    try:
        if temporary.resolve().is_relative_to(ROOT):
            raise RuntimeError("Temporary host must be outside the repository")
        snapshot = temporary / "package"
        manifest = []
        for name in files:
            source, target = ROOT / name, snapshot / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            data = target.read_bytes()
            manifest.append({"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        (logs / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        # Validate the pristine archive before Flutter generates platform files
        # (the published snapshot deliberately contains no local ignore files).
        validated = run(command, snapshot, logs / "snapshot-publish.log")
        if archive_files(validated, snapshot) != files:
            raise RuntimeError("Repacking the snapshot changed the publication file list")
        # Dependency resolution must not rewrite any content under validation.
        for entry in manifest:
            if hashlib.sha256((snapshot / entry["path"]).read_bytes()).hexdigest() != entry["sha256"]:
                raise RuntimeError(f"Snapshot content changed: {entry['path']}")
        run([args.flutter, "pub", "get"], snapshot, logs / "snapshot-get.log")
        check_resolved_paths(snapshot / "example", snapshot)
        run([args.flutter, "test"], snapshot / "example", logs / "example-test.log")
        host = temporary / "host"
        (host / "test").mkdir(parents=True)
        (host / "pubspec.yaml").write_text(
            "name: ianvs_package_smoke\npublish_to: none\n"
            "environment:\n  sdk: ^3.12.0\ndependencies:\n"
            "  flutter:\n    sdk: flutter\n"
            f"  ianvs_markdown:\n    path: {json.dumps(str(snapshot))}\n"
            "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n"
        )
        shutil.copy2(ROOT / "tool/package_smoke_test.dart", host / "test/package_smoke_test.dart")
        run([args.flutter, "pub", "get"], host, logs / "host-get.log")
        check_resolved_paths(host, snapshot)
        run([args.flutter, "test"], host, logs / "host-test.log")
        size = re.search(r"Total compressed archive size: ([^\n]+)", validated)
        summary = {
            "files": len(files),
            "uncompressedBytes": sum(item["bytes"] for item in manifest),
            "pubCompressedSize": size.group(1) if size else "see snapshot-publish.log",
            "snapshotDryRun": "passed without warnings",
            "exampleTests": "passed",
            "externalHostTests": "passed",
            "workspacePathLeak": False,
        }
        (logs / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary, indent=2))
    finally:
        if args.keep:
            print(f"Temporary snapshot retained at {temporary}")
        else:
            shutil.rmtree(temporary)


if __name__ == "__main__":
    main()
