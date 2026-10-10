#!/usr/bin/env python3
"""Run synchronous preparse/copy regressions in separately killable processes.

This is a resource-bound correctness diagnostic, not a profile latency baseline.
Run `make deps-core` first. Each child owns a fresh process group; a timeout kills
only that group (including flutter_tester). Preserve partial results on failure.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import time


def positive_float(value):
    number = float(value)
    if not 0 < number < float("inf"):
        raise argparse.ArgumentTypeError("timeout must be finite and positive")
    return number


def probe(command, startup_timeout, operation_timeout):
    child = subprocess.Popen(
        command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        bufsize=0, start_new_session=True,
    )
    output = bytearray()
    entered = False
    timed_out = False
    deadline = time.monotonic() + startup_timeout
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    timed_out = True
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
                    break
                if selector.select(min(0.2, remaining)):
                    chunk = os.read(child.stdout.fileno(), 16384)
                    if not chunk:
                        child.wait()
                        break
                    output.extend(chunk)
                    if not entered and b"PROBE_READY " in output:
                        entered = True
                        deadline = time.monotonic() + operation_timeout
                elif child.poll() is not None:
                    output.extend(child.stdout.read())
                    break
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        output.extend(child.stdout.read())
        child.stdout.close()
    results = [json.loads(line.split("PROBE_RESULT ", 1)[1])
               for line in output.decode(errors="replace").splitlines()
               if "PROBE_RESULT " in line]
    return bytes(output), {
        "enteredOperation": entered, "timedOut": timed_out,
        "exitCode": child.returncode, "results": results,
        "passed": entered and not timed_out and child.returncode == 0 and len(results) == 1,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", default=os.environ.get("FLUTTER", "flutter"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--startup-timeout", type=positive_float, default=60)
    parser.add_argument("--operation-timeout", type=positive_float, default=5)
    args = parser.parse_args()
    if os.name != "posix":
        parser.error("process-group timeouts require a Linux or macOS validation host")
    root = Path(__file__).resolve().parent.parent
    os.chdir(root)
    args.output.mkdir(parents=True, exist_ok=True)
    report = {
        "schema": 1,
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "trackedDiffSha256": hashlib.sha256(subprocess.check_output(["git", "diff", "HEAD"])).hexdigest(),
        "flutter": subprocess.check_output([args.flutter, "--version"], text=True).strip(),
        "probeSha256": hashlib.sha256((root / "benchmark/processing_budget_probe_test.dart").read_bytes()).hexdigest(),
        "mode": "Flutter test diagnostic, not profile performance baseline",
        "startupTimeoutSeconds": args.startup_timeout,
        "operationTimeoutSeconds": args.operation_timeout,
        "rows": [],
    }
    fixtures = ["bracket", "plain", "dense", "lines", "line_boundary",
                "line_overflow", "carriage_returns", "bracket_lines"]
    for fixture in fixtures:
        for operation in ["controller", "document", "html", "partial"]:
            name = f"{fixture}/{operation}"
            command = [args.flutter, "test", "--no-pub", "--reporter", "expanded",
                       "benchmark/processing_budget_probe_test.dart", "--name", f"^{re.escape(name)}$"]
            output, row = probe(command, args.startup_timeout, args.operation_timeout)
            log = f"{fixture}-{operation}.log"
            (args.output / log).write_bytes(output)
            row.update(case=name, log=log)
            report["rows"].append(row)
            (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
            print(f"{name}: {'PASS' if row['passed'] else 'FAIL'}", flush=True)
            if not row["enteredOperation"]:
                break  # A broken build/setup is not a measured parser timeout.
        if not report["rows"][-1]["enteredOperation"]:
            break
    return 0 if len(report["rows"]) == len(fixtures) * 4 and all(row["passed"] for row in report["rows"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
