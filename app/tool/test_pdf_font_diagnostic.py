import contextlib
import io
import json
from pathlib import Path
import tempfile
import resource
import select
import subprocess
import sys
import unittest
from unittest.mock import patch

import run_pdf_font_diagnostic as diagnostic


class PDFFontDiagnosticTests(unittest.TestCase):
    candidate = {"id": "pingfang", "family": "PingFang SC", "status": "selected"}

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_capture_emits_phase_before_stdin_eof(self):
        output = self.root / "acceptance.log"
        process = subprocess.Popen([sys.executable, str(Path(diagnostic.__file__)),
            "--capture-log", str(output)], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            phase = b"PHASE: small live line\n"
            process.stdin.write(phase)
            process.stdin.flush()
            readable, _, _ = select.select([process.stdout], [], [], 3)
            self.assertTrue(readable, "capture buffered phase until EOF")
            self.assertEqual(process.stdout.readline(), phase)
            # stdout can become readable just before the following file flush;
            # a second marker acknowledges that the prior iteration completed.
            process.stdin.write(b"PHASE: acknowledgment\n")
            process.stdin.flush()
            readable, _, _ = select.select([process.stdout], [], [], 3)
            self.assertTrue(readable)
            process.stdout.readline()
            self.assertTrue(output.read_bytes().startswith(phase))
            process.stdin.close()
            self.assertEqual(process.wait(timeout=3), 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)
            for stream in (process.stdin, process.stdout, process.stderr):
                stream.close()

    def case(self, root, order="forward", mutate=lambda value: value):
        root.mkdir()
        text = "\n".join(f"BEGIN_{key}_{value}_END_{key}"
            for key, value in diagnostic.expected_probes(order).items())
        (root / "pdfkit.txt").write_text(mutate(text), encoding="utf-8")
        (root / "result.json").write_text(json.dumps({
            "id": self.candidate["id"], "order": order, "font": self.candidate,
            "geometryOK": True, "strictUnicodePassed": True, "passed": True,
        }), encoding="utf-8")

    def test_original_unicode_including_literal_radicals_passes(self):
        root = self.root / "case"
        self.case(root)
        self.assertEqual(diagnostic.validate_result(root, self.candidate, "forward"), [])

    def test_compatibility_normalization_cannot_hide_changed_characters(self):
        root = self.root / "case"
        self.case(root, mutate=lambda text: text.replace("⽂", "文").replace("⻓", "长"))
        failures = diagnostic.validate_result(root, self.candidate, "forward")
        self.assertIn("BODY: original Unicode scalars changed", failures)
        self.assertIn("TITLE: original Unicode scalars changed", failures)

    def test_native_pass_flag_cannot_hide_changed_long_code(self):
        root = self.root / "case"
        self.case(root, mutate=lambda text: text.replace("长代码 ", "⻓代码 "))
        self.assertIn("LONGCODE: original Unicode scalars changed",
                      diagnostic.validate_result(root, self.candidate, "forward"))

    def test_only_named_unbroken_long_code_accepts_layout_linebreaks(self):
        root = self.root / "case"
        self.case(root, mutate=lambda text: text.replace("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "ABCDEFGHIJKLM\nNOPQRSTUVWXYZ"))
        self.assertEqual(diagnostic.validate_result(root, self.candidate, "forward"), [])
        text = (root / "pdfkit.txt").read_text(encoding="utf-8")
        (root / "pdfkit.txt").write_text(text.replace("ABCDEFGHIJKLM\n", "ABCDEFGHIJKLM "), encoding="utf-8")
        self.assertIn("LONGCODE: original Unicode scalars changed",
                      diagnostic.validate_result(root, self.candidate, "forward"))

    def test_original_long_line_is_not_reduced_or_reordered(self):
        original = "长代码 ABCDEFGHIJKLMNOPQRSTUVWXYZ "
        expected = diagnostic.expected_probes("forward")["LONGCODE"]
        self.assertEqual(expected, original * 35)
        self.assertEqual(expected.count("代码"), 35)
        self.assertEqual(expected.count(" "), 70)
        app = Path(__file__).resolve().parents[1]
        dart_fixture = (app / "test/document_export_service_test.dart").read_text(encoding="utf-8")
        swift_fixture = (app / "test/native_pdf_font_diagnostic.swift").read_text(encoding="utf-8")
        self.assertIn("'" + original + "' * 35", dart_fixture)
        self.assertIn('String(repeating: "' + original + '", count: 35)', swift_fixture)
        mutations = [lambda value: value.replace("代码", ""),
                     lambda value: value.replace(" ", ""),
                     lambda value: value.replace(original, "ABCDEFGHIJKLMNOPQRSTUVWXYZ 长代码 ")]
        for index, mutation in enumerate(mutations):
            with self.subTest(index=index):
                root = self.root / f"changed-{index}"
                self.case(root, mutate=mutation)
                self.assertIn("LONGCODE: original Unicode scalars changed",
                              diagnostic.validate_result(root, self.candidate, "forward"))

    def test_duplicate_marker_is_not_discarded(self):
        root = self.root / "case"
        self.case(root, mutate=lambda text: "BEGIN_BODY_" + text)
        self.assertIn("BODY: marker missing or duplicated",
                      diagnostic.validate_result(root, self.candidate, "forward"))

    def execute_matrix(self, *, failed_order=None, inventory=None, budget=None, outer_bytes=0):
        calls = []
        artifact = self.root / "attempt"
        artifact.mkdir()
        if outer_bytes:
            (artifact / "acceptance.log").write_bytes(b"x" * outer_bytes)
        output = artifact / "matrix"

        def fake_command(executable, arguments, log, watchdog, seconds):
            calls.append((arguments[:], seconds))
            log.write_text("phase evidence\n", encoding="utf-8")
            directory = Path(arguments[-1])
            if arguments[0] == "--inventory":
                directory.mkdir()
                (directory / "inventory.json").write_text(json.dumps({
                    "candidates": [self.candidate] if inventory is None else inventory,
                }), encoding="utf-8")
                return 0
            order = arguments[2]
            self.case(directory, order)
            return 124 if order == failed_order else 0

        with patch.object(diagnostic, "run_case_command", side_effect=fake_command), \
             patch.object(diagnostic, "MAX_EVIDENCE", budget or diagnostic.MAX_EVIDENCE), \
             contextlib.redirect_stdout(io.StringIO()):
            code = diagnostic.run(Path("/synthetic/fixture"), output, Path("/synthetic/watchdog.py"), artifact)
        return code, calls, json.loads((output / "summary.json").read_text(encoding="utf-8"))

    def test_each_order_is_separate_bounded_process(self):
        code, calls, summary = self.execute_matrix()
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 4)
        self.assertEqual([call[1] for call in calls], [30, 100, 100, 100])
        self.assertEqual(len({call[0][-1] for call in calls}), 4)
        self.assertIs(summary["productionAcceptance"], False)
        self.assertEqual(summary["visualReview"], "pending")

    def test_timeout_stays_failed_while_collecting_remaining_cases(self):
        code, calls, summary = self.execute_matrix(failed_order="forward")
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 4)
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["cases"][0]["exitCode"], 124)
        self.assertFalse(summary["cases"][0]["strictTextAndGeometryPassed"])

    def test_unknown_candidate_stops_before_render(self):
        code, calls, summary = self.execute_matrix(inventory=[{
            "id": "unknown", "family": "Not Installed", "status": "selected"}])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertIn("unknown", summary["error"])

    def test_empty_census_is_not_a_green_skip(self):
        code, calls, _ = self.execute_matrix(inventory=[])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)

    def test_output_budget_stops_before_next_render(self):
        code, calls, summary = self.execute_matrix(budget=diagnostic.MAX_CASE_RESERVE + diagnostic.MAX_ACCEPTANCE_LOG + diagnostic.MAX_SUMMARY + 1024)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 2)
        self.assertIn("budget", summary["error"])

    def test_outer_acceptance_log_is_counted_before_another_case(self):
        cap = diagnostic.MAX_CASE_RESERVE + diagnostic.MAX_ACCEPTANCE_LOG + diagnostic.MAX_SUMMARY + 1024
        code, calls, summary = self.execute_matrix(budget=cap, outer_bytes=2048)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertIn("artifact budget", summary["error"])

    def test_capture_does_not_double_store_unbounded_logs(self):
        source = b"phase\n" * 1000
        destination = io.BytesIO()
        path = self.root / "acceptance.log"
        with patch.object(diagnostic, "MAX_ACCEPTANCE_LOG", 256):
            status = diagnostic.capture_log(path, io.BytesIO(source), destination)
        self.assertEqual(status, 1)
        self.assertEqual(path.stat().st_size, 256)
        self.assertIn(b"truncated", path.read_bytes())
        self.assertEqual(destination.getvalue(), source)
        with self.assertRaises(FileExistsError):
            diagnostic.capture_log(path, io.BytesIO(b"new"), io.BytesIO())

    def test_final_summary_uses_its_reserved_cap(self):
        with patch.dict(self.candidate, {"extraSyntheticMetadata": "x" * 2048}), \
             patch.object(diagnostic, "MAX_SUMMARY", 512):
            code, _, summary = self.execute_matrix()
        self.assertEqual(code, 1)
        self.assertIn("summary exceeded", summary["error"])
        self.assertLessEqual((self.root / "attempt/matrix/summary.json").stat().st_size, 512)

    def test_small_acceptance_capture_preserves_bytes(self):
        source = b"PHASE: exact\nPASS: synthetic\n"
        output = self.root / "accepted.log"
        self.assertEqual(diagnostic.capture_log(output, io.BytesIO(source), io.BytesIO()), 0)
        self.assertEqual(output.read_bytes(), source)

    def test_whole_probe_reordering_fails(self):
        root = self.root / "case"
        self.case(root, mutate=lambda text: "\n".join(reversed(text.split("\n"))))
        self.assertTrue(any("order changed" in failure
            for failure in diagnostic.validate_result(root, self.candidate, "forward")))

    def test_file_size_limit_is_child_only_and_fails_closed(self):
        before = resource.getrlimit(resource.RLIMIT_FSIZE)
        target = self.root / "oversized.bin"
        code = "from pathlib import Path; Path(%r).write_bytes(b'x' * 4096)" % str(target)
        with patch.object(diagnostic, "MAX_NATIVE_FILE", 1024), contextlib.redirect_stdout(io.StringIO()):
            status = diagnostic.run_case_command(Path(sys.executable), ["-c", code],
                self.root / "bounded.log", Path(diagnostic.__file__).with_name("native_test_watchdog.py"), 5)
        self.assertNotEqual(status, 0)
        self.assertLessEqual(target.stat().st_size, 1024)
        self.assertEqual(resource.getrlimit(resource.RLIMIT_FSIZE), before)

    def test_existing_evidence_is_not_overwritten(self):
        root = self.root / "prior"
        root.mkdir()
        marker = root / "keep"
        marker.write_text("original", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            diagnostic.run(Path("/synthetic"), root, Path("/watchdog"))
        self.assertEqual(marker.read_text(encoding="utf-8"), "original")


if __name__ == "__main__":
    unittest.main()
