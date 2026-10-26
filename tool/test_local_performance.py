"""The performance receipt must bind shared native code used by actual mains."""
from pathlib import Path
import tempfile
import os
import json
import unittest
from unittest.mock import patch

import local_performance as performance


class PerformanceSourceReceiptTest(unittest.TestCase):
    def test_sdk_name_resolves_path_before_git_and_version_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory) / 'SDK with spaces'
            executable = sdk / 'bin/flutter'
            executable.parent.mkdir(parents=True)
            executable.write_text('#!/bin/sh\n')
            executable.chmod(0o755)
            version = sdk / 'bin/cache/flutter.version.json'
            version.parent.mkdir()
            version.write_text(json.dumps({'frameworkVersion': 'test'}))
            observed = []

            def command(arguments, cwd):
                observed.append(cwd)
                return '' if 'status' in arguments else 'revision'

            with patch.dict(os.environ, {'PATH': str(executable.parent)}), patch.object(
                    performance, 'command', side_effect=command):
                info = performance.sdk_info('flutter')
            self.assertEqual(info['path'], str(sdk.resolve()))
            self.assertEqual(info['revision'], 'revision')
            self.assertEqual(observed, [sdk.resolve(), sdk.resolve()])

    def test_shared_native_edit_changes_frozen_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = ['app/apple/CloudWorkspace.swift',
                     'app/apple/WorkspaceNoteTransaction.swift',
                     'app/lib/main.dart', 'app/test/preview_app_test.dart']
            for name in names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('before')
            with patch.object(performance, 'ROOT', root), patch.object(
                    performance, 'command', return_value='\n'.join(names)):
                before = performance.sources()
                self.assertIn('app/apple/CloudWorkspace.swift', before)
                self.assertIn('app/apple/WorkspaceNoteTransaction.swift', before)
                self.assertNotIn('app/test/preview_app_test.dart', before)
                (root / names[0]).write_text('changed attachment access policy')
                after = performance.sources()
                self.assertNotEqual(performance.digest(before), performance.digest(after))
                self.assertEqual(before[names[1]], after[names[1]])


if __name__ == '__main__':
    unittest.main()
