"""Regression tests for the mandatory, bounded independent PDF content gate."""

import json
import os
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest import mock

import check_practical_pdf_content as checker


def complete_text() -> str:
    return "\n".join([
        "CJK START",
        *(f"CELL_{row}_{column}" for row in range(150) for column in "ABCD"),
        *([checker.CODE_RUN] * 35),
        "CODE_END", "CJK END", "IMAGE_START", "IMAGE_END",
    ])


def write_pdf(path: Path, text: str, pages: int = 3, *, first_page_only: bool = False) -> None:
    from pypdf import PdfWriter
    from pypdf.generic import DictionaryObject, NameObject, DecodedStreamObject

    writer = PdfWriter()
    lines = text.splitlines()
    for index in range(pages):
        page = writer.add_blank_page(width=595.276, height=841.89)
        page[NameObject("/Resources")] = DictionaryObject({
            NameObject("/Font"): DictionaryObject({
                NameObject("/F1"): DictionaryObject({
                    NameObject("/Type"): NameObject("/Font"),
                    NameObject("/Subtype"): NameObject("/Type1"),
                    NameObject("/BaseFont"): NameObject("/Helvetica"),
                })
            })
        })
        # This synthetic PDF tests extraction, not visual pagination. Geometry
        # and CJK appearance are separately gated by native acceptance.
        page_lines = lines[index * len(lines) // pages:(index + 1) * len(lines) // pages]
        if first_page_only:
            page_lines = lines if index == 0 else []
        stream = DecodedStreamObject()
        stream.set_data(("BT /F1 10 Tf 30 800 Td " + " ".join(
            f"({line}) Tj 0 -2 Td" for line in page_lines
        ) + " ET").encode("ascii"))
        page[NameObject("/Contents")] = writer._add_object(stream)
    with path.open("wb") as output:
        writer.write(output)


class ContentAssertionsTests(unittest.TestCase):
    def test_all_600_cells_35_runs_and_boundaries_pass(self):
        result = checker.validate_text(complete_text())
        self.assertTrue(result["contentChecksPassed"])
        self.assertEqual(result["observedTableCellOccurrences"], 600)
        self.assertEqual(result["uniqueTableCellMarkers"], 600)

    def test_layout_whitespace_only_is_allowed(self):
        self.assertTrue(checker.validate_text(complete_text().replace("CELL_0_A", "CELL_\n0_\tA"))["contentChecksPassed"])

    def test_missing_cell_is_a_real_failure(self):
        result = checker.validate_text(complete_text().replace("CELL_149_D", ""))
        self.assertFalse(result["contentChecksPassed"])
        self.assertEqual(result["missingMarkers"], ["CELL_149_D"])

    def test_duplicate_cell_is_a_real_failure(self):
        result = checker.validate_text(complete_text() + "\nCELL_0_A")
        self.assertFalse(result["contentChecksPassed"])
        self.assertEqual(result["duplicateMarkers"], {"CELL_0_A": 2})

    def test_unexpected_cell_is_a_real_failure(self):
        result = checker.validate_text(complete_text() + "\nCELL_150_A")
        self.assertFalse(result["contentChecksPassed"])
        self.assertEqual(result["unexpectedMarkers"], ["CELL_150_A"])

    def test_missing_or_duplicate_tail_boundaries_fail(self):
        for marker in ["CJK START", "CJK END", "CODE_END", "IMAGE_START", "IMAGE_END"]:
            with self.subTest(marker=marker):
                self.assertFalse(checker.validate_text(complete_text().replace(marker, ""))["contentChecksPassed"])
                self.assertFalse(checker.validate_text(complete_text() + "\n" + marker)["contentChecksPassed"])

    def test_missing_or_duplicate_long_code_run_fails(self):
        for text in [complete_text().replace(checker.CODE_RUN, "", 1), complete_text() + checker.CODE_RUN]:
            self.assertFalse(checker.validate_text(text)["contentChecksPassed"])

    def test_no_unicode_normalization_or_character_reordering(self):
        for replacement in ["ＣELL_0_A", "CELL\n0\n_\n_\nA"]:
            result = checker.validate_text(complete_text().replace("CELL_0_A", replacement))
            self.assertFalse(result["contentChecksPassed"])
            self.assertIn("CELL_0_A", result["missingMarkers"])


class BoundedInputTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = self.root / "input.pdf"
        self.path.write_bytes(b"bounded input")

    def test_single_descriptor_and_close_without_path_reopen(self):
        with mock.patch.object(checker.os, "open", wraps=os.open) as opened, mock.patch.object(checker.os, "close", wraps=os.close) as closed:
            self.assertEqual(checker.read_bounded_pdf(self.path), b"bounded input")
        self.assertEqual(opened.call_count, 1)
        self.assertEqual(closed.call_count, 1)
        self.assertTrue(opened.call_args.args[1] & os.O_NOFOLLOW)

    def test_empty_and_oversize_rejected_before_any_read(self):
        for size in [0, checker.MAXIMUM_PDF_BYTES + 1]:
            with self.subTest(size=size):
                with self.path.open("wb") as output:
                    output.truncate(size)
                with mock.patch.object(checker.os, "read", side_effect=AssertionError("must not read")):
                    with self.assertRaises(checker.ContentCheckError):
                        checker.read_bounded_pdf(self.path)

    def test_symlink_directory_and_fifo_fail_closed(self):
        link = self.root / "link.pdf"
        link.symlink_to(self.path)
        fifo = self.root / "fifo.pdf"
        os.mkfifo(fifo)
        for path in [link, fifo, self.root]:
            with self.subTest(path=path):
                with self.assertRaises((OSError, checker.ContentCheckError)):
                    checker.read_bounded_pdf(path)

    def test_mutating_file_rejected_without_reopen(self):
        read = os.read
        changed = False
        def mutate(descriptor, count):
            nonlocal changed
            data = read(descriptor, count)
            if not changed:
                changed = True
                with self.path.open("ab") as output:
                    output.write(b"changed")
            return data
        with mock.patch.object(checker.os, "read", side_effect=mutate):
            with self.assertRaisesRegex(checker.ContentCheckError, "changed"):
                checker.read_bounded_pdf(self.path)


class ActualPDFTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = self.root / "input.pdf"

    def test_real_three_page_pdf_extracts_complete_content(self):
        write_pdf(self.path, complete_text())
        result = checker.check_pdf(self.path, self.root)
        self.assertTrue(result["contentChecksPassed"], result)
        self.assertEqual(result["pageCount"], 3)
        self.assertEqual(result["extractorVersion"], checker.PINNED_PYPDF_VERSION)
        self.assertIn("CELL_149_D", (self.root / "pagination-pypdf.txt").read_text())

    def test_real_pdf_content_loss_fails_and_retains_pdfkit_diagnostics(self):
        diagnostics = b"PDFKit observed failure: CELL\n0\n_\n_\nA"
        (self.root / "pagination.txt").write_bytes(diagnostics)
        native_report = b'{"pdfkitObservedMarkerCount":29}'
        (self.root / "practical-pdf-report.json").write_bytes(native_report)
        for text in [complete_text().replace("CELL_149_D", ""), complete_text() + "\nCELL_0_A", complete_text().replace("IMAGE_END", "")]:
            with self.subTest(text_tail=text[-80:]):
                write_pdf(self.path, text)
                result = checker.check_pdf(self.path, self.root)
                self.assertFalse(result["contentChecksPassed"])
                saved = json.loads((self.root / "practical-pdf-content-report.json").read_text())
                self.assertFalse(saved["contentChecksPassed"])
                self.assertEqual((self.root / "pagination.txt").read_bytes(), diagnostics)
                self.assertEqual((self.root / "practical-pdf-report.json").read_bytes(), native_report)

    def test_cli_returns_zero_only_for_success(self):
        for complete in [True, False]:
            with self.subTest(complete=complete):
                text = complete_text() if complete else complete_text().replace("IMAGE_END", "")
                write_pdf(self.path, text)
                result = subprocess.run(
                    [sys.executable, checker.__file__, str(self.path), str(self.root)],
                    capture_output=True, text=True, timeout=10, check=False,
                )
                self.assertEqual(result.returncode, 0 if complete else 1, result.stderr)
                report = json.loads((self.root / "practical-pdf-content-report.json").read_text())
                self.assertEqual(report["contentChecksPassed"], complete)

    def test_page_limits_reject_before_extracting_text(self):
        for pages in [2, 31]:
            with self.subTest(pages=pages):
                write_pdf(self.path, "", pages=pages)
                with mock.patch("pypdf._page.PageObject.extract_text", side_effect=AssertionError("must not extract")):
                    with self.assertRaisesRegex(checker.ContentCheckError, "3...30"):
                        checker.extract_pdf(self.path)

    def test_all_cells_on_one_page_and_two_blank_pages_fail(self):
        write_pdf(self.path, complete_text(), first_page_only=True)
        result = checker.check_pdf(self.path, self.root)
        self.assertEqual(result["observedTableCellOccurrences"], 600)
        self.assertEqual(result["tablePages"], [1])
        self.assertFalse(result["contentChecksPassed"])
        self.assertIn("at least three pages", " ".join(result["failures"]))

    def test_raw_text_byte_budget_includes_page_separators(self):
        write_pdf(self.path, "", pages=3)
        with mock.patch("pypdf._page.PageObject.extract_text", return_value="aa"):
            with mock.patch.object(checker, "MAXIMUM_TEXT_BYTES", 12):
                text, _ = checker.extract_pdf(self.path)
                self.assertEqual(len(text.encode("utf-8")), 12)
            with mock.patch.object(checker, "MAXIMUM_TEXT_BYTES", 11):
                with self.assertRaisesRegex(checker.ContentCheckError, "text limit"):
                    checker.extract_pdf(self.path)

    def test_wrong_dependency_version_fails_closed(self):
        with mock.patch("pypdf.__version__", "0.0.0"):
            with self.assertRaisesRegex(checker.ContentCheckError, "hash-pinned"):
                checker.extract_pdf(self.path)


if __name__ == "__main__":
    unittest.main()
