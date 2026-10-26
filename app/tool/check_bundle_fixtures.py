#!/usr/bin/env python3
"""Independently verify and relocate ZIPs produced by the Dart export fixtures."""
import base64
import json
from pathlib import Path
import sys
import tempfile
import zipfile


def verify(path, expected):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or set(names) != set(expected) | {'document.md', 'manifest.json'}:
            raise ValueError(f'{path.name}: unexpected or duplicate archive entries')
        if archive.testzip() is not None:
            raise ValueError(f'{path.name}: CRC failure')
        # All entry names are fixed fixture names above. No user archive is
        # accepted here, and extraction cannot escape this temporary directory.
        with tempfile.TemporaryDirectory(prefix='linefold-relocated-bundle-') as directory:
            archive.extractall(directory)
            root = Path(directory)
            markdown = (root / 'document.md').read_text(encoding='utf-8')
            manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
            if manifest['document'] != 'document.md' or manifest['notices']:
                raise ValueError(f'{path.name}: incomplete resource manifest')
            copied = {row['path'] for row in manifest['resources'] if row['status'] == 'copied'}
            if copied != set(expected):
                raise ValueError(f'{path.name}: missing manifest resources')
            for name, content in expected.items():
                if (root / name).read_bytes() != content or './' + name not in markdown:
                    raise ValueError(f'{path.name}: changed bytes or broken relocated path: {name}')
            return markdown


def main():
    directory = Path(sys.argv[1])
    png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==')
    image_text = verify(directory / 'bundle.zip', {'assets/1.png': png})
    if '`![code](../assets/image.png)`' not in image_text or '![[./assets/1.png|200]]' not in image_text:
        raise ValueError('Code example or Wiki alias changed')
    mixed_text = verify(directory / 'bundle-assets.zip', {
        'assets/1.pdf': bytes([37, 80, 68, 70, 0, 255]),
        'assets/2.svg': b'<svg>source</svg>',
        'assets/3.zip': bytes([80, 75, 3, 4, 255]),
        'assets/4': b'license',
    })
    if './assets/1.pdf#page=2' not in mixed_text:
        raise ValueError('PDF fragment lost')
    print('PASS: independent ZIP CRC, exact bytes, manifest and relocated image/general attachments')


if __name__ == '__main__':
    main()
