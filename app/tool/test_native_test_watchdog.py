"""Portable regressions for the native harness's outer, fail-closed deadline."""

import contextlib
import io
from pathlib import Path
import sys
import tempfile
import time
import unittest

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
        class SlowDiagnostic(io.StringIO):
            def write(self, text):
                time.sleep(0.3)
                return super().write(text)

        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "orphan-survived"
            ready = Path(directory) / "parent-ready"
            child = f"from pathlib import Path; import time; time.sleep(1); Path({str(marker)!r}).touch()"
            parent = (
                "import subprocess, sys, time; from pathlib import Path; "
                f"subprocess.Popen([sys.executable, '-c', {child!r}]); "
                f"Path({str(ready)!r}).touch(); time.sleep(0.35)"
            )
            with contextlib.redirect_stderr(SlowDiagnostic()):
                self.assertEqual(run_bounded([sys.executable, "-c", parent], 0.2), 124)
            self.assertTrue(ready.exists())
            time.sleep(0.6)
            self.assertFalse(marker.exists(), "A completed leader must not hide a live descendant")

if __name__ == "__main__":
    unittest.main()
