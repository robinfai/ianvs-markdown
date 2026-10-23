import os
from pathlib import Path
import tempfile
import unittest

from check_export_evidence_budget import validate_tree


class ExportEvidenceBudgetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.checkout = Path(self.temporary.name)
        self.relative = Path("app/build/export-qa")
        self.root = self.checkout / self.relative
        self.root.mkdir(parents=True)

    def validate(self, **limits):
        return validate_tree(self.relative, checkout=self.checkout, **limits)

    def test_exact_byte_and_count_boundaries_include_all_nested_files(self):
        (self.root / "acceptance.log").write_bytes(b"logs")
        (self.root / "native").mkdir()
        (self.root / "native" / "output.pdf").write_bytes(b"pdf!")
        self.assertEqual(
            self.validate(maximum_files=2, maximum_entries=3,
                          maximum_file_bytes=4, maximum_total_bytes=8),
            {"files": 2, "entries": 3, "bytes": 8},
        )
        for limits in [{"maximum_files": 1}, {"maximum_entries": 2},
                       {"maximum_file_bytes": 3}, {"maximum_total_bytes": 7}]:
            with self.subTest(limits=limits), self.assertRaises(ValueError):
                self.validate(**limits)

    def test_empty_or_missing_root_is_not_uploadable_evidence(self):
        with self.assertRaises(ValueError):
            self.validate()
        with self.assertRaises(OSError):
            validate_tree(self.relative / "missing", checkout=self.checkout)

    def test_symbolic_root_file_or_subdirectory_is_rejected_without_following(self):
        outside = Path(self.temporary.name) / "outside"
        outside.mkdir()
        (outside / "unrelated").write_bytes(b"outside")
        alias = Path(self.temporary.name) / "alias"
        alias.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            validate_tree(Path("alias"), checkout=self.checkout)
        for target in [outside, outside / "unrelated", outside / "missing"]:
            child = self.root / "link"
            child.symlink_to(target, target_is_directory=target.is_dir())
            with self.assertRaises(ValueError):
                self.validate()
            child.unlink()
        self.assertEqual((outside / "unrelated").read_bytes(), b"outside")

    def test_every_component_below_checkout_rejects_static_symlinks(self):
        outside = self.checkout / "outside"
        (outside / "export-qa").mkdir(parents=True)
        (outside / "export-qa" / "unrelated").write_bytes(b"must not upload")
        linked_checkout = self.checkout / "linked-checkout"
        (linked_checkout / "app").mkdir(parents=True)
        (linked_checkout / "app" / "build").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symbolic link"):
            validate_tree(self.relative, checkout=linked_checkout)
        # An alias *above* the trusted checkout (e.g. macOS /var) is acceptable.
        (self.root / "allowed.log").write_bytes(b"ok")
        trusted_alias = self.checkout / "checkout-alias"
        trusted_alias.symlink_to(self.checkout, target_is_directory=True)
        self.assertEqual(validate_tree(self.relative, checkout=trusted_alias)["bytes"], 2)
        self.assertEqual((outside / "export-qa" / "unrelated").read_bytes(), b"must not upload")

    def test_absolute_and_parent_traversal_paths_are_rejected(self):
        for path in [self.root, Path("../export-qa"), Path("app/../build"), Path(".")]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                validate_tree(path, checkout=self.checkout)

    def test_special_file_is_rejected_without_opening_it(self):
        os.mkfifo(self.root / "fifo")
        with self.assertRaises(ValueError):
            self.validate()

    def test_directory_entries_are_bounded_even_without_files(self):
        (self.root / "one").mkdir()
        (self.root / "one" / "two").mkdir()
        (self.root / "one" / "two" / "three").mkdir()
        with self.assertRaisesRegex(ValueError, "entry-count"):
            self.validate(maximum_entries=2)


if __name__ == "__main__":
    unittest.main()
