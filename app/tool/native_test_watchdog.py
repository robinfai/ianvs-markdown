"""Bound a synthetic native acceptance process even if its main thread blocks."""

import argparse
import os
import signal
import subprocess
import sys


def run_bounded(command: list[str], timeout_seconds: float) -> int:
    # The new group contains only this acceptance process and its descendants,
    # never the caller, runner, or other tests. No global process-name killing.
    process = subprocess.Popen(command, start_new_session=True)
    finished = False
    try:
        try:
            result = process.wait(timeout=timeout_seconds)
            finished = True
            return result
        except subprocess.TimeoutExpired:
            print(
                f"FAIL: native acceptance process exceeded {timeout_seconds:g}s; "
                "the last PHASE line identifies the blocked stage.",
                file=sys.stderr,
                flush=True,
            )
            return 124
    finally:
        # A timed-out leader may exit while a descendant still owns its group.
        # Always clean the timeout/exception group, not just a live leader.
        if not finished:
            # Only synthetic fixtures run here. Kill the entire isolated group
            # immediately so a child ignoring SIGTERM cannot remain behind.
            kill_error = None
            try:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except BaseException as error:
                    kill_error = error
                    print(f"FAIL: cleanup killpg({process.pid}) failed: {error!r}",
                          file=sys.stderr, flush=True)
            finally:
                # Reap even if group signalling failed. EPERM is never success,
                # and an un-reaped Popen is not evidence that its leader lives.
                try:
                    process.wait(timeout=5)
                except BaseException as wait_error:
                    print(f"FAIL: cleanup wait({process.pid}) failed: {wait_error!r}",
                          file=sys.stderr, flush=True)
                    if kill_error is not None:
                        raise wait_error from kill_error
                    raise
            if kill_error is not None:
                raise kill_error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout-seconds", type=float, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    command = arguments.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command or arguments.timeout_seconds <= 0:
        parser.error("a command and a positive timeout are required")
    return run_bounded(command, arguments.timeout_seconds)


if __name__ == "__main__":
    sys.exit(main())
