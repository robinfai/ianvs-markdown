#!/usr/bin/env python3
"""Compare clipboard build cost in isolated copies of a fixed Git revision.

Only the experimental copy loses its native writer. Never modifies the working
tree, SDK, package cache sources, or existing build outputs. Global download and
toolchain caches remain warm; 'first' means a new project build, not a cold Mac.
"""

import argparse
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
VARIANTS = ("default", "injected_plain", "experimental_no_native")
HOST = """import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Future<void> plain(IanvsMarkdownClipboardData data) =>
    Clipboard.setData(ClipboardData(text: data.markdown));

void main() => runApp(MaterialApp(home: Scaffold(body: IanvsMarkdownView(
  data: '# Clipboard cost\\n\\nSame **Markdown** reading host.',
  %s
))));
"""


def capture(command, cwd=ROOT):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def run(command, cwd, log, environment):
    started = time.perf_counter()
    with log.open("w") as output:
        result = subprocess.run(
            command, cwd=cwd, env=environment, stdout=output,
            stderr=subprocess.STDOUT, timeout=1200,
        )
    elapsed = time.perf_counter() - started
    if result.returncode:
        raise RuntimeError(f"Exit {result.returncode}; inspect {log}")
    return round(elapsed, 3)


def remove_native_backend(snapshot):
    pubspec = snapshot / "pubspec.yaml"
    text = pubspec.read_text()
    lines = [line for line in text.splitlines(True) if line.startswith("  super_clipboard:")]
    if len(lines) != 1:
        raise RuntimeError("Expected one native dependency at the measured revision")
    pubspec.write_text(text.replace(lines[0], ""))
    writer = snapshot / "lib/src/rich_clipboard.dart"
    text = writer.read_text()
    text = text.replace("import 'package:super_clipboard/super_clipboard.dart';\n", "")
    start = text.index("Future<void> writeIanvsMarkdownClipboard(")
    end = text.index("/// Converts Markdown", start)
    text = text[:start] + """Future<void> writeIanvsMarkdownClipboard(
  IanvsMarkdownClipboardData data,
) => Clipboard.setData(ClipboardData(text: data.markdown));

""" + text[end:]
    writer.write_text(text)


def file_bytes(directory):
    return sum(p.stat().st_size for p in directory.rglob("*")
               if p.is_file() and not p.is_symlink())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default="HEAD")
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--mode", choices=("debug", "profile", "release"), default="debug")
    parser.add_argument("--variants", choices=VARIANTS, nargs="+", default=list(VARIANTS))
    parser.add_argument("--output", type=Path, default=ROOT / "build/roadmap/r1-04/clipboard-cost")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("This comparison measures the existing macOS host")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    revision = capture(["git", "rev-parse", "--verify", args.revision + "^{commit}"])
    archive = subprocess.check_output([
        "git", "archive", revision, "lib", "example", "pubspec.yaml", "pubspec.lock",
    ], cwd=ROOT)
    environment = dict(os.environ, CARGO_PROFILE_RELEASE_STRIP="none", FLUTTER_XCODE_ARCHS=platform.machine())
    report = {
        "revision": revision,
        "host": "same minimal IanvsMarkdownView; project-first then unchanged warm build",
        "mode": args.mode,
        "cacheScope": "fresh project outputs per variant; shared SDK/Pub/Cargo/download caches retained",
        "order": args.variants,
        "flutter": json.loads(capture([args.flutter, "--version", "--machine"])),
        "macOS": capture(["sw_vers", "-productVersion"]),
        "architecture": platform.machine(),
        "xcode": capture(["xcodebuild", "-version"]),
        "rust": capture(["rustc", "--version"]),
        "environment": {k: environment[k] for k in ("CARGO_PROFILE_RELEASE_STRIP", "FLUTTER_XCODE_ARCHS")},
        "results": [],
    }
    summary = output / "summary.json"
    summary.write_text(json.dumps(report, indent=2) + "\n")
    with tempfile.TemporaryDirectory(prefix="ianvs-clipboard-cost-") as temporary:
        for variant in args.variants:
            snapshot = Path(temporary) / variant
            snapshot.mkdir()
            with tarfile.open(fileobj=io.BytesIO(archive)) as package:
                for entry in package.getmembers():
                    if entry.issym() or entry.islnk() or not (entry.isdir() or entry.isfile()):
                        raise RuntimeError("Unexpected archive member")
                    if not (snapshot / entry.name).resolve().is_relative_to(snapshot.resolve()):
                        raise RuntimeError("Archive path escaped snapshot")
                package.extractall(snapshot)
            if variant == "experimental_no_native":
                remove_native_backend(snapshot)
            host = snapshot / "example"
            (host / "lib/main.dart").write_text(HOST % (
                "clipboardWriter: plain," if variant == "injected_plain" else ""
            ))
            logs = output / variant
            logs.mkdir(exist_ok=True)
            print(f"{variant}: resolve isolated host", flush=True)
            resolve = run([args.flutter, "pub", "get"], host, logs / "get.log", environment)
            graph = json.loads((host / ".dart_tool/package_graph.json").read_text())
            (logs / "dependencies.json").write_text(json.dumps(graph, indent=2) + "\n")
            names = sorted(p["name"] for p in graph["packages"])
            plugins_file = host / ".flutter-plugins-dependencies"
            plugins = json.loads(plugins_file.read_text()) if plugins_file.exists() else {}
            plugin_names = sorted(p["name"] for p in plugins.get("plugins", {}).get("macos", []))
            if ("super_clipboard" in names) != (variant != "experimental_no_native"):
                raise RuntimeError("Variant did not resolve expected clipboard dependency")
            # The tracked macOS host is already CocoaPods-integrated. Flutter
            # skips auto-install when no native plugins remain, leaving its
            # existing Xcode phase references unresolved. Prepare Pods equally
            # for all variants and report that cost separately from compilation.
            pods = run(["pod", "install"], host / "macos", logs / "pods.log", environment)
            timings = {}
            for phase in ("first", "warm"):
                print(f"{variant}: {phase} {args.mode} build", flush=True)
                timings[phase] = run(
                    [args.flutter, "build", "macos", f"--{args.mode}", "--no-pub"],
                    host, logs / f"{phase}.log", environment,
                )
            apps = list((host / f"build/macos/Build/Products/{args.mode.title()}").glob("*.app"))
            if len(apps) != 1:
                raise RuntimeError("Expected one built application")
            app = apps[0]
            frameworks = app / "Contents/Frameworks"
            row = {
                "variant": variant, "resolveSeconds": resolve, "podsSeconds": pods,
                "buildSeconds": timings, "applicationBytes": file_bytes(app),
                "frameworkBytes": {p.name: file_bytes(p) for p in sorted(frameworks.glob("*.framework"))},
                "resolvedPackages": names, "macOSPlugins": plugin_names,
            }
            report["results"].append(row)
            summary.write_text(json.dumps(report, indent=2) + "\n")
            print(f"{variant}: {timings}, {row['applicationBytes']} bytes", flush=True)
    print(f"Evidence: {summary}", flush=True)


if __name__ == "__main__":
    main()
