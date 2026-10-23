#!/usr/bin/env python3
"""Bounded, sequential synthetic font diagnostics. Never a product PDF pass."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import resource
import sys

ORDERS = {"forward": "文⽂长⻓", "reverse": "⽂文⻓长", "mixed": "文文⽂⽂长长⻓⻓"}
CANDIDATES = {"pingfang": "PingFang SC", "heiti": "Heiti SC", "songti": "Songti SC"}
MAX_JSON = 2 * 1024 * 1024
MAX_EVIDENCE = 128 * 1024 * 1024
MAX_NATIVE_FILE = 8 * 1024 * 1024
# Inspector (16 MiB), original PDF (8), census/result/text (<=5), HTML (<1),
# and bounded subprocess log (8). Reserve before starting, not only afterward.
MAX_CASE_RESERVE = 40 * 1024 * 1024
MAX_ACCEPTANCE_LOG = 1024 * 1024
MAX_SUMMARY = 2 * 1024 * 1024
LOG_TAIL = 2048


def read_json(path: Path) -> dict:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_JSON:
        raise ValueError(f"Missing or oversized JSON evidence: {path.name}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("Expected JSON object")
    return value


def expected_probes(order: str) -> dict[str, str]:
    text = ORDERS[order]
    return {"BODY": text, "TITLE": "中文文档" + text, "CODE": text,
            "TABLE": text, "LONGCODE": "长代码 ABCDEFGHIJKLMNOPQRSTUVWXYZ " * 35}


def validate_result(root: Path, candidate: dict, order: str) -> list[str]:
    result = read_json(root / "result.json")
    problems = []
    if result.get("id") != candidate["id"] or result.get("order") != order:
        problems.append("case identity mismatch")
    if result.get("font") != candidate:
        problems.append("font inventory changed between census and render")
    if result.get("geometryOK") is not True:
        problems.append("native page bounds check failed")
    path = root / "pdfkit.txt"
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_JSON:
        raise ValueError("Missing or oversized raw PDFKit text")
    text = path.read_text(encoding="utf-8")
    previous_end = 0
    for key, expected in expected_probes(order).items():
        start, end = f"BEGIN_{key}_", f"_END_{key}"
        if text.count(start) != 1 or text.count(end) != 1:
            problems.append(f"{key}: marker missing or duplicated")
            continue
        start_index = text.index(start) + len(start)
        end_index = text.index(end)
        if end_index < start_index or text.index(start) < previous_end:
            problems.append(f"{key}: marker order changed")
            continue
        previous_end = end_index + len(end)
        actual = text[start_index:end_index]
        if key == "LONGCODE":
            # The original committed probe contains no line breaks. This is the
            # sole layout-only exception; never normalize characters or spaces.
            actual = actual.replace("\n", "").replace("\r", "")
        if actual != expected:
            problems.append(f"{key}: original Unicode scalars changed")
    if result.get("strictUnicodePassed") is not True or result.get("passed") is not True:
        problems.append("native strict assertion failed")
    return problems


def evidence_bytes(root: Path) -> int:
    total = 0
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError("Unexpected evidence symlink")
        if path.is_file():
            total += path.stat().st_size
            if total > MAX_EVIDENCE:
                raise ValueError("Aggregate diagnostic evidence exceeds 128 MiB")
    return total


def limit_child_files() -> None:
    # Lower this test child's limit only; never change system/global settings.
    soft, hard = resource.getrlimit(resource.RLIMIT_FSIZE)
    limits = [MAX_NATIVE_FILE]
    if soft != resource.RLIM_INFINITY:
        limits.append(soft)
    if hard != resource.RLIM_INFINITY:
        limits.append(hard)
    cap = min(limits)
    resource.setrlimit(resource.RLIMIT_FSIZE, (cap, cap))


def run_case_command(executable: Path, arguments: list[str], log: Path,
                     watchdog: Path, seconds: int) -> int:
    command = [sys.executable, str(watchdog), "--timeout-seconds", str(seconds),
               "--", str(executable), *arguments]
    with log.open("xb") as stream:
        outcome = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                 check=False, preexec_fn=limit_child_files)
    size = log.stat().st_size
    if size > MAX_NATIVE_FILE:
        raise ValueError("Child log exceeded its file budget")
    with log.open("rb") as stream:
        stream.seek(max(0, size - LOG_TAIL))
        tail = stream.read(LOG_TAIL).decode("utf-8", errors="replace")
    print(f"PHASE: child exit {outcome.returncode}; {log.name} ({size} bytes); bounded tail follows", flush=True)
    print(tail, end="", flush=True)
    return outcome.returncode


def run(executable: Path, root: Path, watchdog: Path, artifact_root: Path | None = None) -> int:
    artifact_root = artifact_root or root
    if artifact_root != root and root.parent != artifact_root:
        raise ValueError("Matrix must be a direct child of its complete artifact root")
    # New-only evidence root: never clean or replace a prior diagnostic artifact.
    root.mkdir(parents=False, exist_ok=False)
    summary = {"schema": 1, "cases": [], "status": "failed",
               "productionAcceptance": False, "visualReview": "pending",
               "independentExtractor": "pending"}
    try:
        census_root = root / "census"
        code = run_case_command(executable, ["--inventory", str(census_root)],
                                root / "census.log", watchdog, 30)
        census = read_json(census_root / "inventory.json")
        candidates = [item for item in census.get("candidates", []) if item.get("status") == "selected"]
        if code != 0 or not 1 <= len(candidates) <= 3:
            raise ValueError("No eligible local-font census; no render is authorized")
        ids = [item.get("id") for item in candidates]
        if len(set(ids)) != len(ids) or any(item.get("family") != CANDIDATES.get(item.get("id")) for item in candidates):
            raise ValueError("Census selected an unknown or duplicate candidate")
        summary["census"] = census
        all_passed = True
        for candidate in candidates:
            for order in ORDERS:
                label = f"{candidate['id']}-{order}"
                # The outer acceptance capture can still grow after this process
                # exits, and summary.json has not been written yet. Reserve both.
                reserved = MAX_CASE_RESERVE + MAX_ACCEPTANCE_LOG + MAX_SUMMARY
                if evidence_bytes(artifact_root) > MAX_EVIDENCE - reserved:
                    raise ValueError("Aggregate artifact budget cannot reserve another bounded case")
                case_root = root / label
                print(f"PHASE: bounded case {label}", flush=True)
                code = run_case_command(executable,
                    ["--case", candidate["id"], order, str(case_root)],
                    root / f"{label}.log", watchdog, 100)
                problems = []
                try:
                    problems = validate_result(case_root, candidate, order)
                except (OSError, ValueError, KeyError, TypeError) as error:
                    problems.append(str(error))
                if code != 0:
                    problems.insert(0, f"native process exit {code}")
                passed = not problems
                all_passed = all_passed and passed
                summary["cases"].append({"id": label, "exitCode": code,
                    "strictTextAndGeometryPassed": passed, "problems": problems})
                summary["evidenceBytesBeforeFinalSummary"] = evidence_bytes(artifact_root)
                # A failed case remains a failed job, but later independent cases
                # still collect evidence. No persistent process/print lease is reused.
        summary["status"] = "diagnostic-text-geometry-passed" if all_passed else "failed"
    except (OSError, ValueError, KeyError, TypeError) as error:
        summary["error"] = str(error)
    finally:
        encoded = (json.dumps(summary, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        if len(encoded) > MAX_SUMMARY:
            summary = {"schema": 1, "status": "failed", "productionAcceptance": False,
                       "error": "Final summary exceeded its 2 MiB reservation"}
            encoded = (json.dumps(summary) + "\n").encode("utf-8")
        with (root / "summary.json").open("xb") as stream:
            stream.write(encoded)
    # Do not duplicate the full census/case evidence into acceptance.log.
    print(f"RESULT: {summary['status']}; {len(summary.get('cases', []))} cases; "
          "visual and independent extraction review pending", flush=True)
    if "error" in summary:
        print(str(summary["error"])[:1024], flush=True)
    return 0 if summary["status"] == "diagnostic-text-geometry-passed" else 1


def capture_log(output: Path, source=None, destination=None) -> int:
    """Fail-closed replacement for tee; uploaded transcript is also bounded."""
    source = source or sys.stdin.buffer
    destination = destination or sys.stdout.buffer
    count = 0
    truncated = False
    marker = b"\nFAIL: acceptance transcript exceeded its byte cap; artifact is truncated.\n"
    read_chunk = getattr(source, "read1", source.read)
    with output.open("xb") as stream:
        while True:
            chunk = read_chunk(64 * 1024)
            if not chunk:
                break
            destination.write(chunk)
            destination.flush()
            remaining = max(0, MAX_ACCEPTANCE_LOG - count)
            stream.write(chunk[:remaining])
            stream.flush()
            count += min(len(chunk), remaining)
            if len(chunk) > remaining:
                truncated = True
        if truncated:
            stream.seek(max(0, MAX_ACCEPTANCE_LOG - len(marker)))
            stream.write(marker[:MAX_ACCEPTANCE_LOG])
            stream.truncate(MAX_ACCEPTANCE_LOG)
    return 1 if truncated else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--artifact-root", type=Path)
    parser.add_argument("--capture-log", type=Path)
    args = parser.parse_args()
    if args.capture_log:
        if args.executable or args.output or args.artifact_root:
            parser.error("capture-log cannot be combined with matrix execution")
        return capture_log(args.capture_log)
    if not args.executable or not args.output or not args.artifact_root:
        parser.error("matrix execution requires executable, output and complete artifact-root")
    return run(args.executable.resolve(), args.output,
               Path(__file__).with_name("native_test_watchdog.py"), args.artifact_root)


if __name__ == "__main__":
    raise SystemExit(main())
