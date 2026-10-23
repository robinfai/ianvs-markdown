import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import resource
import select
import subprocess
import sys
import unittest
from unittest.mock import patch

import run_pdf_font_diagnostic as diagnostic


def candidate_for(identity, *, missing=None):
    missing = missing or {}
    faces = {}
    inventory = []
    for role in ("regular", "bold"):
        postscript = f"Synthetic-{identity}-{role}"
        face = {
            "referenceRole": role, "postScriptName": postscript,
            "systemFile": f"{identity}.ttc", "systemRelativePath": f"{identity}.ttc",
            "fileSHA256": "a" * 64, "fileBytes": 64,
            "fileIdentity": {"device": 1, "inode": 2, "size": 64,
                             "mtimeSeconds": 3, "mtimeNanoseconds": 4,
                             "ctimeSeconds": 5, "ctimeNanoseconds": 6},
            "inventoryEnabled": True, "inventoryDownloadable": False,
            "dataDescriptorRegistered": False,
            "options": ["preventAutoActivation", "preventAutoDownload"],
            "weight": 0.4 if role == "bold" else 0.0,
            "symbolicTraits": 2 if role == "bold" else 0,
            "coverage": [{"scalar": scalar, "glyphs": [0 if scalar in missing.get(role, ()) else 1]}
                         for scalar in diagnostic.COVERAGE_SCALARS],
            "coverageComplete": not missing.get(role),
        }
        faces[role] = face
        inventory.append({"postScriptName": postscript, "enabled": True,
                          "downloadable": False, "italic": False, "bold": role == "bold",
                          "fileName": face["systemFile"], "weight": face["weight"],
                          "symbolicTraits": face["symbolicTraits"]})
    return {"id": identity, "family": diagnostic.CANDIDATES[identity],
            "status": "selected" if all(face["coverageComplete"] for face in faces.values()) else "partial-coverage",
            "availableFaces": 2, "inventoryFaces": inventory, **faces}


class PDFFontDiagnosticTests(unittest.TestCase):
    candidate = candidate_for("pingfang")

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

    def case(self, root, order="forward", mutate=lambda value: value, candidate=None):
        candidate = candidate or self.candidate
        root.mkdir()
        text = "\n".join(f"BEGIN_{key}_{value}_END_{key}"
            for key, value in diagnostic.expected_probes(order).items())
        (root / "pdfkit.txt").write_text(mutate(text), encoding="utf-8")
        (root / "result.json").write_text(json.dumps({
            "id": candidate["id"], "order": order, "font": candidate,
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

    def execute_matrix(self, *, failed_order=None, inventory=None, budget=None,
                       outer_bytes=0, unavailable=None, failed_census=None,
                       missing_census=None, wrong_request=None, elapsed=None,
                       matrix_seconds=None, census_metadata=None, candidates=None,
                       failed_configuration=None, unicode_failure=None,
                       case_bytes=0, last_census_padding=0, manifest_collision=False):
        calls = []
        artifact = self.root / "attempt"
        artifact.mkdir()
        if outer_bytes:
            (artifact / "acceptance.log").write_bytes(b"x" * outer_bytes)
        output = artifact / "matrix"
        now = 0

        def fake_command(executable, arguments, log, watchdog, seconds):
            nonlocal now
            calls.append((arguments[:], seconds))
            now += elapsed[len(calls) - 1] if elapsed else 0
            log.write_text("phase evidence\n", encoding="utf-8")
            if arguments[0] == "--inventory":
                directory, identity = Path(arguments[2]), arguments[1]
                candidate = copy.deepcopy((candidates or {}).get(identity, candidate_for(identity)))
                directory.mkdir()
                if identity == unavailable:
                    candidate["status"] = "unavailable"
                    candidate["reason"] = "Synthetic local file absent"
                if identity != missing_census:
                    data = {
                        "requestedID": "wrong" if identity == wrong_request else identity,
                        "candidates": [candidate] if inventory is None else inventory,
                        "maxFamiliesPerProcess": 1, "maxPreflightFaces": 2,
                        "crossFamilyRetainedData": False, "perProcessInputBytes": 64,
                        "uniqueInputFiles": 1,
                    }
                    data.update(census_metadata or {})
                    if identity == "songti" and last_census_padding:
                        data["syntheticPadding"] = "x" * last_census_padding
                        log.write_bytes(b"x" * diagnostic.MAX_NATIVE_FILE)
                    (directory / "inventory.json").write_text(json.dumps(data), encoding="utf-8")
                if identity == "songti" and manifest_collision:
                    (output / diagnostic.MANIFEST_NAME).write_bytes(b"prior evidence")
                return 124 if identity == failed_census else (2 if identity == unavailable else 0)
            if arguments[0] == "--composite-case":
                self.assertEqual(len(arguments), 5)
                order, directory = arguments[1], Path(arguments[2])
                manifest = Path(arguments[3]).read_bytes()
                self.assertEqual(arguments[4], hashlib.sha256(manifest).hexdigest())
                candidate = json.loads(manifest)["configuration"]
                identity = "songti-heiti"
            else:
                self.assertEqual(arguments[0], "--case")
                identity, order, directory = arguments[1], arguments[2], Path(arguments[3])
                candidate = copy.deepcopy((candidates or {}).get(identity, candidate_for(identity)))
            mutation = (lambda text: text.replace("⽂", "文")) if identity == unicode_failure else (lambda text: text)
            self.case(directory, order, mutate=mutation, candidate=candidate)
            if case_bytes:
                (directory / "synthetic.pdf").write_bytes(b"x" * case_bytes)
            return 124 if order == failed_order or identity == failed_configuration else 0

        with patch.object(diagnostic, "run_case_command", side_effect=fake_command), \
             patch.object(diagnostic, "MAX_EVIDENCE", budget or diagnostic.MAX_EVIDENCE), \
             patch.object(diagnostic, "MAX_MATRIX_SECONDS", matrix_seconds or diagnostic.MAX_MATRIX_SECONDS), \
             patch.object(diagnostic.time, "monotonic", side_effect=lambda: now), \
             contextlib.redirect_stdout(io.StringIO()):
            code = diagnostic.run(Path("/synthetic/fixture"), output, Path("/synthetic/watchdog.py"), artifact)
        return code, calls, json.loads((output / "summary.json").read_text(encoding="utf-8"))

    def test_each_order_is_separate_bounded_process(self):
        code, calls, summary = self.execute_matrix()
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 12)
        self.assertEqual([call[1] for call in calls], [30] * 3 + [100] * 9)
        roots = [call[0][2] if call[0][0] in ("--inventory", "--composite-case") else call[0][3]
                 for call in calls]
        self.assertEqual(len(set(roots)), 12)
        self.assertEqual(sum(call[0][0] == "--composite-case" for call in calls), 3)
        self.assertFalse(any(call[0][:2] == ["--case", "songti"] for call in calls))
        self.assertEqual([call[0][1] for call in calls[:3]], list(diagnostic.CANDIDATES))
        self.assertEqual([item["status"] for item in summary["families"]], ["selected"] * 3)
        self.assertEqual([item["id"] for item in summary["configurations"]], list(diagnostic.CONFIGURATIONS))
        self.assertEqual([item["id"] for item in summary["cases"]],
                         [f"{identity}-{order}" for identity in diagnostic.CONFIGURATIONS for order in diagnostic.ORDERS])
        self.assertEqual(len(summary["cases"]), 9)
        self.assertIs(summary["productionAcceptance"], False)
        self.assertEqual(summary["visualReview"], "pending")

    def test_timeout_stays_failed_while_collecting_remaining_cases(self):
        code, calls, summary = self.execute_matrix(failed_order="forward")
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 12)
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["cases"][0]["exitCode"], 124)
        self.assertFalse(summary["cases"][0]["strictTextAndGeometryPassed"])

    def test_unknown_candidate_stops_before_render(self):
        code, calls, summary = self.execute_matrix(inventory=[{
            "id": "unknown", "family": "Not Installed", "status": "selected"}])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 3)
        self.assertTrue(all("unknown" in item["problems"][0] for item in summary["families"]))

    def test_empty_census_is_not_a_green_skip(self):
        code, calls, summary = self.execute_matrix(inventory=[])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 3)
        self.assertEqual(summary["cases"], [])

    def test_duplicate_or_cross_family_entries_do_not_render(self):
        code, calls, summary = self.execute_matrix(inventory=[self.candidate, self.candidate])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 3)
        self.assertTrue(all("exactly one family" in item["problems"][0] for item in summary["families"]))

    def test_unavailable_family_is_explicitly_not_a_pass(self):
        code, calls, summary = self.execute_matrix(unavailable="pingfang")
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 9)
        self.assertEqual(summary["families"][0]["status"], "unavailable")
        self.assertEqual(len(summary["cases"]), 6)
        self.assertTrue(all(item["strictTextAndGeometryPassed"] for item in summary["cases"]))
        self.assertEqual(summary["status"], "failed")
        self.assertFalse(any(call[0][:2] == ["--case", "pingfang"] for call in calls))

    def test_failed_family_process_cannot_authorize_render(self):
        code, calls, summary = self.execute_matrix(failed_census="heiti")
        self.assertEqual(code, 1)
        self.assertEqual(summary["families"][1]["exitCode"], 124)
        self.assertFalse(any(call[0][:2] == ["--case", "heiti"] for call in calls))
        self.assertEqual(len(summary["cases"]), 3)
        self.assertFalse(any(call[0][0] == "--composite-case" for call in calls))

    def test_missing_manifest_is_not_a_pass_or_authorization(self):
        code, calls, summary = self.execute_matrix(missing_census="songti")
        self.assertEqual(code, 1)
        self.assertEqual(summary["families"][2]["status"], "failed")
        self.assertIn("Missing", summary["families"][2]["problems"][0])
        self.assertFalse(any(call[0][0] == "--composite-case" for call in calls))

    def test_requested_family_mismatch_is_not_authorization(self):
        code, calls, summary = self.execute_matrix(wrong_request="heiti")
        self.assertEqual(code, 1)
        self.assertIn("identity mismatch", summary["families"][1]["problems"][0])
        self.assertFalse(any(call[0][:2] == ["--case", "heiti"] for call in calls))

    def test_unisolated_census_cannot_authorize_render(self):
        code, calls, summary = self.execute_matrix(census_metadata={"maxFamiliesPerProcess": 3})
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 3)
        self.assertTrue(all("isolation" in item["problems"][0] for item in summary["families"]))

    def test_missing_or_excessive_input_evidence_cannot_authorize_render(self):
        for index, value in enumerate((None, True, 128 * 1024 * 1024 + 1, 0)):
            with self.subTest(value=value):
                self.root = Path(self.temporary.name) / f"inputs-{index}"
                self.root.mkdir()
                code, calls, summary = self.execute_matrix(census_metadata={"perProcessInputBytes": value})
                self.assertEqual(code, 1)
                self.assertEqual(len(calls), 3)
                self.assertEqual(summary["cases"], [])

    def test_output_budget_stops_before_next_render(self):
        code, calls, summary = self.execute_matrix(budget=diagnostic.MAX_CASE_RESERVE + diagnostic.MAX_ACCEPTANCE_LOG + diagnostic.MAX_SUMMARY + 64 * 1024, case_bytes=64 * 1024)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 4)
        self.assertIn("budget", summary["error"])

    def test_outer_acceptance_log_is_counted_before_another_case(self):
        cap = diagnostic.MAX_CASE_RESERVE + diagnostic.MAX_ACCEPTANCE_LOG + diagnostic.MAX_SUMMARY + 64 * 1024
        code, calls, summary = self.execute_matrix(budget=cap, outer_bytes=64 * 1024)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 3)
        self.assertIn("artifact budget", summary["error"])

    def test_census_also_reserves_complete_artifact_budget(self):
        cap = diagnostic.MAX_CENSUS_RESERVE + diagnostic.MAX_ACCEPTANCE_LOG + diagnostic.MAX_SUMMARY + 1024
        code, calls, summary = self.execute_matrix(budget=cap, outer_bytes=2048)
        self.assertEqual(code, 1)
        self.assertEqual(calls, [])
        self.assertIn("artifact budget", summary["error"])

    def test_global_deadline_does_not_reset_between_family_censuses(self):
        code, calls, summary = self.execute_matrix(matrix_seconds=40, elapsed=[6])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertIn("Global matrix time budget", summary["error"])
        self.assertEqual(summary["families"][1]["status"], "not-started")

    def test_global_deadline_includes_cases_and_cleanup_reservation(self):
        code, calls, summary = self.execute_matrix(matrix_seconds=140, elapsed=[2, 2, 2, 40])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 4)
        self.assertEqual(len(summary["cases"]), 1)
        self.assertIn("Global matrix time budget", summary["error"])

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
        with patch.object(diagnostic, "MAX_SUMMARY", 512):
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

    def test_partial_songti_can_only_pass_as_a_distinct_combination(self):
        songti = candidate_for("songti", missing={"regular": {"U+2ED3"}, "bold": {"U+2ED3", "U+2F42"}})
        code, calls, summary = self.execute_matrix(candidates={"songti": songti})
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 12)
        self.assertEqual(len(summary["cases"]), 9)
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(summary["families"][2]["status"], "partial-coverage")
        self.assertEqual(summary["configurations"][2]["id"], "songti-heiti")
        self.assertEqual(summary["configurations"][2]["mode"], "combination-only")
        self.assertTrue(all(item["status"] == "diagnostic-text-geometry-passed"
                            for item in summary["configurations"]))
        self.assertFalse(any(call[0][:2] == ["--case", "songti"] for call in calls))
        self.assertTrue(all(item["strictTextAndGeometryPassed"] for item in summary["cases"]))

    def test_fixed_coverage_universe_matches_native_and_is_not_reduced(self):
        self.assertEqual(diagnostic.COVERAGE_TEXT,
                         "文⽂长⻓中文文档代码ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789 ")
        self.assertEqual(len(diagnostic.COVERAGE_SCALARS), 46)
        self.assertEqual(tuple(sorted(set(diagnostic.COVERAGE_SCALARS))), diagnostic.COVERAGE_SCALARS)
        native = (Path(__file__).resolve().parents[1] / "test/native_pdf_font_diagnostic.swift").read_text(encoding="utf-8")
        self.assertIn('static let coverage = "' + diagnostic.COVERAGE_TEXT + '"', native)

    def test_rolewise_union_preserves_exact_audited_candidates(self):
        primary = candidate_for("songti", missing={"regular": {"U+2ED3"}, "bold": {"U+2F42"}})
        fallback = candidate_for("heiti")
        configuration = diagnostic.composite_configuration(primary, fallback)
        self.assertEqual(set(configuration), {"id", "family", "status", "primary", "fallback"})
        self.assertIs(configuration["primary"], primary)
        self.assertIs(configuration["fallback"], fallback)
        self.assertEqual(configuration["status"], "combination-only")
        for role in ("regular", "bold"):
            primary_set = diagnostic.validate_candidate(primary, "songti")[role]
            fallback_set = diagnostic.validate_candidate(fallback, "heiti")[role]
            self.assertEqual(primary_set | fallback_set, set(diagnostic.COVERAGE_SCALARS))

    def test_partial_fallback_cannot_fill_from_the_other_role(self):
        primary = candidate_for("songti", missing={"regular": {"U+2ED3"}})
        fallback = candidate_for("heiti", missing={"regular": {"U+2ED3"}})
        self.assertIn("U+2ED3", diagnostic.validate_candidate(fallback, "heiti")["bold"])
        with self.assertRaisesRegex(ValueError, "complete audited Heiti"):
            diagnostic.composite_configuration(primary, fallback)
        # Even full union from a complete primary cannot authorize partial Heiti.
        with self.assertRaisesRegex(ValueError, "complete audited Heiti"):
            diagnostic.composite_configuration(candidate_for("songti"), fallback)

    def test_missing_or_wrong_role_coverage_cannot_authorize_composition(self):
        for mutation in (lambda c: c["regular"]["coverage"].pop(),
                         lambda c: c["bold"].update(referenceRole="regular"),
                         lambda c: c.pop("bold")):
            primary = candidate_for("songti")
            mutation(primary)
            with self.assertRaises(ValueError):
                diagnostic.composite_configuration(primary, candidate_for("heiti"))

    def test_duplicate_unknown_or_unordered_coverage_is_rejected(self):
        for mutation in (lambda rows: rows.__setitem__(1, copy.deepcopy(rows[0])),
                         lambda rows: rows[0].update(scalar="U+FFFF"),
                         lambda rows: rows.reverse(),
                         lambda rows: rows[0].update(untrusted=True)):
            primary = candidate_for("songti")
            mutation(primary["regular"]["coverage"])
            with self.assertRaisesRegex(ValueError, "duplicate, unknown, or unordered"):
                diagnostic.composite_configuration(primary, candidate_for("heiti"))

    def test_unknown_family_or_status_is_never_a_composition(self):
        for changes in ({"id": "heiti"}, {"family": "Unknown CSS Font"},
                        {"status": "unavailable"}, {"status": "combination-only"}):
            primary = candidate_for("songti")
            primary.update(changes)
            with self.assertRaises(ValueError):
                diagnostic.composite_configuration(primary, candidate_for("heiti"))

    def test_zero_glyph_and_false_completion_cannot_be_reported_selected(self):
        for glyphs in ([0], [True], [-1], [65536], [1.0], [], [1, 2]):
            primary = candidate_for("songti")
            primary["regular"]["coverage"][0]["glyphs"] = glyphs
            with self.assertRaises(ValueError):
                diagnostic.composite_configuration(primary, candidate_for("heiti"))
        primary = candidate_for("songti")
        primary["regular"]["coverageComplete"] = 1
        with self.assertRaises(ValueError):
            diagnostic.composite_configuration(primary, candidate_for("heiti"))
        primary = candidate_for("songti")
        primary["status"] = "partial-coverage"
        with self.assertRaisesRegex(ValueError, "status disagrees"):
            diagnostic.composite_configuration(primary, candidate_for("heiti"))

    def test_partial_noncoverage_error_cannot_render_or_write_manifest(self):
        songti = candidate_for("songti", missing={"regular": {"U+2ED3"}})
        songti["reason"] = "Synthetic identity audit failed"
        code, calls, summary = self.execute_matrix(candidates={"songti": songti})
        self.assertEqual(code, 1)
        self.assertEqual(summary["families"][2]["status"], "failed")
        self.assertEqual(len(summary["cases"]), 6)
        self.assertFalse(any(call[0][0] == "--composite-case" for call in calls))
        self.assertFalse((self.root / "attempt/matrix" / diagnostic.MANIFEST_NAME).exists())

    def test_face_errors_cannot_be_reclassified_as_partial_coverage(self):
        for key in ("reason", "error", "problems"):
            for target in ("candidate", "regular", "bold"):
                with self.subTest(key=key, target=target):
                    candidate = candidate_for("songti", missing={"regular": {"U+2ED3"}})
                    destination = candidate if target == "candidate" else candidate[target]
                    destination[key] = None
                    with self.assertRaisesRegex(ValueError, "non-coverage preflight error"):
                        diagnostic.composite_configuration(candidate, candidate_for("heiti"))

    def test_missing_fallback_prevents_composition_and_does_not_run_songti_solo(self):
        code, calls, summary = self.execute_matrix(unavailable="heiti")
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 6)
        self.assertEqual(len(summary["cases"]), 3)
        self.assertEqual(summary["configurations"][1]["status"], "unavailable")
        self.assertEqual(summary["configurations"][2]["status"], "unavailable")
        self.assertFalse(any(call[0][0] == "--composite-case" or call[0][:2] == ["--case", "songti"]
                             for call in calls))

    def test_partial_control_is_not_rendered_or_made_green_by_combination(self):
        pingfang = candidate_for("pingfang", missing={"bold": {"U+2ED3"}})
        code, calls, summary = self.execute_matrix(candidates={"pingfang": pingfang})
        self.assertEqual(code, 1)
        self.assertEqual(len(summary["cases"]), 6)
        self.assertEqual(summary["families"][0]["status"], "partial-coverage")
        self.assertEqual(summary["configurations"][0]["status"], "unavailable")
        self.assertFalse(any(call[0][:2] == ["--case", "pingfang"] for call in calls))

    def test_combination_or_heiti_control_failure_always_fails_job(self):
        for index, configuration in enumerate(("songti-heiti", "heiti")):
            with self.subTest(configuration=configuration):
                self.root = Path(self.temporary.name) / f"failed-{index}"
                self.root.mkdir()
                code, calls, summary = self.execute_matrix(failed_configuration=configuration)
                self.assertEqual(code, 1)
                self.assertEqual(len(calls), 12)
                self.assertEqual(summary["status"], "failed")
                actual = {item["id"]: item["status"] for item in summary["configurations"]}
                self.assertEqual(actual[configuration], "failed")
                self.assertTrue(all(status == "diagnostic-text-geometry-passed"
                                    for identity, status in actual.items() if identity != configuration))

    def test_native_pass_cannot_hide_unicode_failure_in_combination(self):
        code, _, summary = self.execute_matrix(unicode_failure="songti-heiti")
        self.assertEqual(code, 1)
        failures = [item for item in summary["cases"] if item["configurationID"] == "songti-heiti"]
        self.assertEqual(len(failures), 3)
        self.assertTrue(all("BODY: original Unicode scalars changed" in item["problems"] for item in failures))

    def test_one_manifest_has_exact_bytes_hash_and_attempt_provenance(self):
        code, calls, summary = self.execute_matrix()
        self.assertEqual(code, 0)
        matrix = self.root / "attempt/matrix"
        files = list(matrix.rglob("*manifest*.json"))
        self.assertEqual(files, [matrix / diagnostic.MANIFEST_NAME])
        encoded = files[0].read_bytes()
        payload = json.loads(encoded)
        self.assertEqual(set(payload), {"schema", "matrixDirectory", "configuration"})
        self.assertEqual(payload["schema"], 1)
        self.assertEqual(payload["matrixDirectory"], str(matrix.resolve()))
        self.assertEqual(payload["configuration"]["primary"], summary["families"][2]["census"]["candidates"][0])
        self.assertEqual(payload["configuration"]["fallback"], summary["families"][1]["census"]["candidates"][0])
        self.assertEqual(summary["manifest"], {"name": diagnostic.MANIFEST_NAME, "bytes": len(encoded),
                                             "sha256": hashlib.sha256(encoded).hexdigest()})
        composite_calls = [call for call, _ in calls if call[0] == "--composite-case"]
        self.assertEqual(len(composite_calls), 3)
        self.assertEqual({call[3] for call in composite_calls}, {str(files[0].resolve())})
        self.assertEqual({call[4] for call in composite_calls}, {summary["manifest"]["sha256"]})
        self.assertTrue(all(Path(call[2]).parent == matrix.resolve() for call in composite_calls))
        self.assertGreaterEqual(summary["evidenceBytesBeforeFinalSummary"], len(encoded))
        self.assertNotIn("primary", json.dumps(summary["configurations"]))

    def test_manifest_hash_does_not_trust_candidate_self_report(self):
        primary = candidate_for("songti")
        primary["sha256"] = "0" * 64
        configuration, evidence = diagnostic.write_composite_manifest(self.root, primary, candidate_for("heiti"))
        encoded = (self.root / diagnostic.MANIFEST_NAME).read_bytes()
        self.assertEqual(evidence["sha256"], hashlib.sha256(encoded).hexdigest())
        self.assertNotEqual(evidence["sha256"], primary["sha256"])
        self.assertEqual(json.loads(encoded)["configuration"], configuration)

    def test_existing_manifest_is_never_overwritten_or_authorization(self):
        code, calls, summary = self.execute_matrix(manifest_collision=True)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 3)
        self.assertEqual(summary["cases"], [])
        self.assertEqual((self.root / "attempt/matrix" / diagnostic.MANIFEST_NAME).read_bytes(), b"prior evidence")
        self.assertNotIn("manifest", summary)

    def test_oversized_manifest_is_not_written(self):
        with patch.object(diagnostic, "MAX_JSON", 128):
            with self.assertRaisesRegex(ValueError, "manifest exceeded"):
                diagnostic.write_composite_manifest(self.root, candidate_for("songti"), candidate_for("heiti"))
        self.assertFalse((self.root / diagnostic.MANIFEST_NAME).exists())

    def test_manifest_reserves_full_artifact_budget_before_write_or_render(self):
        cap = diagnostic.MAX_CENSUS_RESERVE + diagnostic.MAX_ACCEPTANCE_LOG + diagnostic.MAX_SUMMARY + 64 * 1024
        code, calls, summary = self.execute_matrix(budget=cap, last_census_padding=128 * 1024)
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 3)
        self.assertIn("artifact budget", summary["error"])
        self.assertFalse((self.root / "attempt/matrix" / diagnostic.MANIFEST_NAME).exists())
        self.assertEqual(summary["cases"], [])
        self.assertNotIn("manifest", summary)

    def test_shared_manifest_counts_against_case_admission_budget(self):
        real_write = diagnostic.write_composite_manifest
        observed = {}
        def write_manifest(root, primary, fallback):
            result = real_write(root, primary, fallback)
            observed["manifest_bytes"] = result[1]["bytes"]
            observed["before"] = diagnostic.evidence_bytes(root.parent)
            # Enough for every other byte plus a case, but one byte short once
            # this already-persisted shared manifest is correctly included.
            diagnostic.MAX_EVIDENCE = (observed["before"] - observed["manifest_bytes"] +
                diagnostic.MAX_CASE_RESERVE + diagnostic.MAX_ACCEPTANCE_LOG + diagnostic.MAX_SUMMARY)
            return result
        with patch.object(diagnostic, "write_composite_manifest", side_effect=write_manifest):
            code, calls, summary = self.execute_matrix()
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 3)
        self.assertIn("artifact budget", summary["error"])
        self.assertGreater(observed["manifest_bytes"], 0)
        self.assertEqual(summary["cases"], [])

    def test_manifest_does_not_reset_global_deadline_before_combination(self):
        code, calls, summary = self.execute_matrix(matrix_seconds=300, elapsed=[0, 0, 0, 35, 35, 35, 35, 35, 35])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 9)
        self.assertEqual(len(summary["cases"]), 6)
        self.assertIn("Global matrix time budget", summary["error"])
        self.assertEqual(summary["configurations"][2]["status"], "incomplete")
        self.assertFalse(any(call[0][0] == "--composite-case" for call in calls))

    def test_json_reader_rejects_duplicate_fields_and_oversized_bytes(self):
        path = self.root / "evidence.json"
        path.write_text('{"status":"unavailable","status":"selected"}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Duplicate JSON"):
            diagnostic.read_json(path)
        path.write_bytes(b" " * 33)
        with patch.object(diagnostic, "MAX_JSON", 32):
            with self.assertRaisesRegex(ValueError, "oversized"):
                diagnostic.read_json(path)

    def test_json_reader_rejects_final_symlink_directory_and_fifo(self):
        target = self.root / "target.json"
        target.write_text("{}", encoding="utf-8")
        link = self.root / "link.json"
        link.symlink_to(target)
        fifo = self.root / "fifo.json"
        os.mkfifo(fifo)
        for path in (link, self.root, fifo):
            with self.subTest(path=path):
                with self.assertRaises(ValueError):
                    diagnostic.read_json(path)
        self.assertEqual(diagnostic.read_json(target), {})

    def test_json_reader_bounds_actual_read_if_file_grows_after_stat(self):
        path = self.root / "evidence.json"
        path.write_bytes(b"{}")
        actual_fstat = os.fstat
        def grow_after_stat(fd):
            value = actual_fstat(fd)
            path.write_bytes(b" " * 65)
            return value
        with patch.object(diagnostic, "MAX_JSON", 64), patch.object(diagnostic.os, "fstat", side_effect=grow_after_stat):
            with self.assertRaisesRegex(ValueError, "Oversized"):
                diagnostic.read_json(path)

    def test_canonical_parent_alias_keeps_new_only_matrix_and_manifest(self):
        real = self.root / "real"
        real.mkdir()
        alias = self.root / "alias"
        alias.symlink_to(real, target_is_directory=True)
        self.root = alias
        code, calls, summary = self.execute_matrix()
        self.assertEqual(code, 0)
        # macOS's temporary directory can itself use the /var -> /private/var alias.
        expected_matrix = (real / "attempt/matrix").resolve()
        payload = json.loads((real / "attempt/matrix" / diagnostic.MANIFEST_NAME).read_bytes())
        self.assertEqual(payload["matrixDirectory"], str(expected_matrix))
        for arguments, _ in calls:
            case_path = arguments[2] if arguments[0] in ("--inventory", "--composite-case") else arguments[3]
            self.assertEqual(Path(case_path).parent, expected_matrix)
        existing = alias / "existing-matrix"
        existing.symlink_to(real / "new-target", target_is_directory=True)
        with self.assertRaises((FileExistsError, ValueError)):
            diagnostic.run(Path("/synthetic"), existing, Path("/watchdog"))
        self.assertFalse((real / "new-target").exists())

    def test_wrong_artifact_parent_cannot_create_a_manifest_or_launch(self):
        outer = self.root / "outer"
        outer.mkdir()
        nested = outer / "nested"
        nested.mkdir()
        with patch.object(diagnostic, "run_case_command") as command:
            with self.assertRaisesRegex(ValueError, "direct child"):
                diagnostic.run(Path("/synthetic"), nested / "matrix", Path("/watchdog"), outer)
        command.assert_not_called()
        self.assertFalse((nested / "matrix").exists())


if __name__ == "__main__":
    unittest.main()
