#!/usr/bin/env python3
"""Mandatory test-only content gate, independent of PDFKit reading order.

Run under native_test_watchdog.py (60 seconds). The production exporter and its
fonts are unchanged. Original extractor text is saved, never Unicode-normalized
or reordered; only whitespace is removed for marker comparisons.
"""

import argparse
from collections import Counter
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import sys


PINNED_PYPDF_VERSION = "6.21.2"
MAXIMUM_PDF_BYTES = 32 * 1024 * 1024
MAXIMUM_TEXT_BYTES = 8 * 1024 * 1024
EXPECTED_MARKERS = frozenset(
    f"CELL_{row}_{column}" for row in range(150) for column in "ABCD"
)
BOUNDARIES = ("CJKSTART", "CJKEND", "CODE_END", "IMAGE_START", "IMAGE_END")
CODE_RUN = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


class ContentCheckError(ValueError):
    """Fail-closed acceptance or input bound violation."""


def read_bounded_pdf(path: Path) -> bytes:
    """One no-follow descriptor, regular-file check, bounded reads, no reopen."""
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise ContentCheckError("PDF input must be a regular file")
        if not 0 < before.st_size <= MAXIMUM_PDF_BYTES:
            raise ContentCheckError("PDF input must contain 1 byte...32 MiB")
        chunks = []
        size = 0
        while True:
            chunk = os.read(descriptor, min(1024 * 1024, MAXIMUM_PDF_BYTES + 1 - size))
            if not chunk:
                break
            chunks.append(chunk)
            size += len(chunk)
            if size > MAXIMUM_PDF_BYTES:
                raise ContentCheckError("PDF input grew beyond the 32 MiB limit")
        after = os.fstat(descriptor)
        identity = lambda item: (  # Metadata only, never another path read.
            item.st_dev, item.st_ino, item.st_size, item.st_mtime_ns, item.st_ctime_ns
        )
        if identity(before) != identity(after) or size != before.st_size:
            raise ContentCheckError("PDF input changed during the bounded read")
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def validate_text(raw_text: str) -> dict:
    """Keep all content assertions; layout whitespace is the only adjustment."""
    compact = "".join(raw_text.split())
    counts = Counter(re.findall(r"CELL_[0-9]+_[A-D]", compact))
    missing = sorted(marker for marker in EXPECTED_MARKERS if counts[marker] == 0)
    duplicates = {marker: counts[marker] for marker in sorted(EXPECTED_MARKERS) if counts[marker] > 1}
    unexpected = sorted(set(counts) - EXPECTED_MARKERS)
    boundary_counts = {marker: compact.count(marker) for marker in BOUNDARIES}
    code_runs = compact.count(CODE_RUN)
    failures = []
    if missing or duplicates or unexpected:
        failures.append("All 600 original table-cell markers must appear exactly once")
    if code_runs != 35:
        failures.append(f"Expected all 35 unchanged ASCII long-code runs, got {code_runs}")
    if any(count != 1 for count in boundary_counts.values()):
        failures.append("CJK start/end, CODE_END and attachment start/end must each survive exactly once")
    # Report exact Unicode separately from the legacy ASCII content gate.
    # In particular U+2Fxx Kangxi radicals are not interchangeable with the
    # original U+4Exx characters for copying or searching. Never normalize them.
    phrases = ("中文文档", "文档结束", "中文内容", "中间列", "末列", "长代码")
    exact_chinese = {phrase: compact.count(phrase) for phrase in phrases}
    return {
        "exactChinesePhrases": exact_chinese,
        "exactChinesePhrasesPassed": all(exact_chinese.values()),
        "contentChecksPassed": not failures,
        "failures": failures,
        "expectedTableCells": 600,
        "observedTableCellOccurrences": sum(counts.values()),
        "uniqueTableCellMarkers": len(counts),
        "missingMarkers": missing,
        "duplicateMarkers": duplicates,
        "unexpectedMarkers": unexpected,
        "longCodeRuns": code_runs,
        "boundaryOccurrences": boundary_counts,
    }


def extract_pdf(path: Path) -> tuple[str, dict]:
    import pypdf

    if pypdf.__version__ != PINNED_PYPDF_VERSION:
        raise ContentCheckError(
            f"Expected hash-pinned pypdf {PINNED_PYPDF_VERSION}, got {pypdf.__version__}"
        )
    data = read_bounded_pdf(path)
    reader = pypdf.PdfReader(io.BytesIO(data), strict=True)
    if reader.is_encrypted:
        raise ContentCheckError("Synthetic acceptance PDF must not be encrypted")
    page_count = len(reader.pages)
    if not 3 <= page_count <= 30:
        raise ContentCheckError(f"Expected 3...30 PDF pages before extraction, got {page_count}")
    texts = []
    # Include the inserted UTF-8 page delimiters in the evidence byte budget.
    text_bytes = 3 * (page_count - 1)
    for page in reader.pages:
        raw = page.extract_text(extraction_mode="plain") or ""
        text_bytes += len(raw.encode("utf-8"))
        if text_bytes > MAXIMUM_TEXT_BYTES:
            raise ContentCheckError("Extracted evidence exceeds the 8 MiB text limit")
        texts.append(raw)
    return "\n\f\n".join(texts), {
        "extractor": "pypdf", "extractorVersion": pypdf.__version__,
        "extractionMode": "plain", "pageCount": page_count,
        "pdfBytes": len(data), "pdfSha256": hashlib.sha256(data).hexdigest(),
        "pageSeparator": "\\n\\f\\n", "pageTextCharacters": [len(text) for text in texts],
        "tablePages": [index + 1 for index, text in enumerate(texts)
                       if re.search(r"CELL_[0-9]+_[A-D]", "".join(text.split()))],
    }


def check_pdf(path: Path, evidence: Path) -> dict:
    evidence.mkdir(parents=True, exist_ok=True)
    report = {
        "standard": "Mandatory independent PDF content acceptance; no numerical fidelity score",
        "extractor": "pypdf", "requiredExtractorVersion": PINNED_PYPDF_VERSION,
        "pdf": path.name, "rawText": "pagination-pypdf.txt", "rawTextAvailable": False,
        "comparisonAdjustment": "Whitespace removal only; no NFKC, character rewrite or reordering",
        "pdfkitEvidence": "pagination.txt and practical-pdf-report.json remain unchanged diagnostics",
        "knownLimitations": [
            "PDFKit may reorder underscores or other characters while extracting text, so its observed marker/header counts are diagnostics, not proof of missing PDF content.",
            "This independent content gate does not fix viewer-dependent text extraction or reading order. Preview copy/search behavior has not been manually tested here.",
            "Native geometry, selectable CJK, image-resource and safety checks remain separate mandatory gates. All-page visual review remains required.",
        ],
    }
    try:
        raw_text, metadata = extract_pdf(path)
        # Preserve exact per-page extraction, separated only by documented page
        # delimiters. Never overwrite or repair the original PDFKit evidence.
        (evidence / "pagination-pypdf.txt").write_text(raw_text, encoding="utf-8")
        report["rawTextAvailable"] = True
        report.update(metadata)
        report.update(validate_text(raw_text))
        if len(metadata["tablePages"]) < 3:
            report["contentChecksPassed"] = False
            report["failures"].append("The original long table must span at least three pages containing cell markers")
    except Exception as error:
        report.update(contentChecksPassed=False, failures=[f"{type(error).__name__}: {error}"])
    (evidence / "practical-pdf-content-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path)
    parser.add_argument("evidence", type=Path)
    arguments = parser.parse_args()
    report = check_pdf(arguments.pdf, arguments.evidence)
    if not report["contentChecksPassed"]:
        print("FAIL: mandatory independent PDF content: " + "; ".join(report["failures"]), file=sys.stderr)
        return 1
    print(
        f"PASS: pypdf {report['extractorVersion']} independently confirms exactly 600 table cells, "
        "35 full code runs and all CJK/code/image boundaries; PDFKit diagnostics retained."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
