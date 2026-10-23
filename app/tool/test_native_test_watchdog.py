"""Portable regressions for the native harness's outer, fail-closed deadline."""

import contextlib
import io
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

from native_test_watchdog import run_bounded


class NativeTestWatchdogTests(unittest.TestCase):
    def test_preserves_success_and_failure(self):
        for code in (0, 7):
            with self.subTest(code=code):
                self.assertEqual(
                    run_bounded([sys.executable, "-c", f"raise SystemExit({code})"], 5),
                    code,
                )

    def test_blocked_process_is_failure_and_its_child_is_stopped(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "child-survived"
            ready = Path(directory) / "parent-ready"
            child = f"import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); from pathlib import Path; time.sleep(1); Path({str(marker)!r}).touch()"
            parent = (
                "import subprocess, sys, time; from pathlib import Path; "
                f"subprocess.Popen([sys.executable, '-c', {child!r}]); "
                f"Path({str(ready)!r}).touch(); time.sleep(30)"
            )
            diagnostic = io.StringIO()
            started = time.monotonic()
            with contextlib.redirect_stderr(diagnostic):
                self.assertEqual(run_bounded([sys.executable, "-c", parent], 0.5), 124)
            self.assertLess(time.monotonic() - started, 6)
            self.assertTrue(ready.exists(), "The child must have been launched before timeout")
            self.assertIn("FAIL:", diagnostic.getvalue())
            self.assertIn("PHASE", diagnostic.getvalue())
            time.sleep(1.1)
            self.assertFalse(marker.exists(), "A test-owned descendant must not outlive timeout")


    def test_timeout_cleans_group_after_leader_exits_during_diagnostic(self):
        # A pipe proves the descendant is alive after the timed-out leader is
        # reaped. Relative sleeps can accidentally leave only zombies on macOS.
        with tempfile.TemporaryDirectory() as directory:
            exit_leader = Path(directory) / "exit-leader"
            read_fd, write_fd = os.pipe()
            child = f"import os,time; os.write({write_fd}, b'R'); time.sleep(30)"
            parent = (
                "import os,subprocess,sys,time; from pathlib import Path; "
                f"subprocess.Popen([sys.executable, '-c', {child!r}], pass_fds=({write_fd},)); "
                f"os.close({write_fd}); deadline=time.monotonic()+5\n"
                f"while not Path({str(exit_leader)!r}).exists():\n"
                " if time.monotonic()>deadline: raise SystemExit(9)\n"
                " time.sleep(0.005)\n"
            )
            real_popen = subprocess.Popen
            processes = []
            owner = self

            def launch(*args, **kwargs):
                process = real_popen(*args, **kwargs, pass_fds=(write_fd,))
                processes.append(process)
                os.close(write_fd)
                ready, _, _ = select.select([read_fd], [], [], 5)
                owner.assertTrue(ready, "Descendant did not start within bounded setup")
                owner.assertEqual(os.read(read_fd, 1), b"R")
                return process

            class ExitLeaderOnTimeout(io.StringIO):
                exited = False

                def write(self, text):
                    # run_bounded emits this only after its first wait timed out.
                    if not self.exited:
                        exit_leader.touch()
                        owner.assertEqual(processes[0].wait(timeout=3), 0)
                        owner.assertEqual(select.select([read_fd], [], [], 0)[0], [],
                                          "Descendant must still hold the pipe open")
                        self.exited = True
                    return super().write(text)

            diagnostic = ExitLeaderOnTimeout()
            descendant_stopped = False
            unrelated = real_popen([sys.executable, "-c", "import time; time.sleep(30)"],
                                   start_new_session=True)
            try:
                with patch("native_test_watchdog.subprocess.Popen", side_effect=launch):
                    with contextlib.redirect_stderr(diagnostic):
                        self.assertEqual(run_bounded([sys.executable, "-c", parent], 0.2), 124)
                self.assertTrue(diagnostic.exited)
                ready, _, _ = select.select([read_fd], [], [], 3)
                self.assertTrue(ready, "Descendant still owns the pipe after cleanup")
                self.assertEqual(os.read(read_fd, 1), b"", "Expected EOF from stopped descendant")
                descendant_stopped = True
                self.assertIsNone(unrelated.poll(), "Cleanup must not touch unrelated processes")
            finally:
                # Only this test's isolated group, even when an assertion fails.
                try:
                    for process in processes:
                        try:
                            if not descendant_stopped:
                                os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        finally:
                            process.wait(timeout=3)
                finally:
                    if not processes:
                        os.close(write_fd)
                    os.close(read_fd)
                    unrelated.kill()
                    unrelated.wait(timeout=3)

    def test_group_permission_failure_is_reported_and_leader_is_reaped(self):
        process = Mock(pid=12345)
        process.wait.side_effect = [subprocess.TimeoutExpired(["synthetic"], 0.2), 0]
        denied = PermissionError(1, "synthetic denied group signal")
        diagnostic = io.StringIO()
        with patch("native_test_watchdog.subprocess.Popen", return_value=process):
            with patch("native_test_watchdog.os.killpg", side_effect=denied):
                with contextlib.redirect_stderr(diagnostic):
                    with self.assertRaises(PermissionError) as result:
                        run_bounded(["synthetic"], 0.2)
        self.assertIs(result.exception, denied)
        self.assertEqual(process.wait.call_count, 2)
        self.assertEqual(process.wait.call_args.kwargs, {"timeout": 5})
        self.assertIn("killpg(12345)", diagnostic.getvalue())
        self.assertIn("PermissionError", diagnostic.getvalue())

    def test_kill_and_reap_failures_both_remain_visible(self):
        process = Mock(pid=12345)
        wait_error = subprocess.TimeoutExpired(["synthetic"], 5)
        process.wait.side_effect = [subprocess.TimeoutExpired(["synthetic"], 0.2), wait_error]
        denied = PermissionError(1, "synthetic denied group signal")
        diagnostic = io.StringIO()
        with patch("native_test_watchdog.subprocess.Popen", return_value=process):
            with patch("native_test_watchdog.os.killpg", side_effect=denied):
                with contextlib.redirect_stderr(diagnostic):
                    with self.assertRaises(subprocess.TimeoutExpired) as result:
                        run_bounded(["synthetic"], 0.2)
        self.assertIs(result.exception, wait_error)
        self.assertIs(result.exception.__cause__, denied)
        self.assertIn("killpg(12345)", diagnostic.getvalue())
        self.assertIn("wait(12345)", diagnostic.getvalue())

if __name__ == "__main__":
    unittest.main()
