#!/usr/bin/env python3
"""Supplement native UI measurements with killable, opt-in phase attribution.

No fixture contents are written to the output. Provide local Markdown files;
see app/quicklook/performance/LARGE_DOCUMENTS.md for the recorded corpus.
"""
import argparse
import hashlib
import json
from pathlib import Path

from check_processing_budget import positive_float, probe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('documents', type=Path, nargs='+')
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=positive_float, default=30)
    parser.add_argument('--modes', nargs='+', choices=['finder', 'live', 'read'],
                        default=['finder', 'live', 'read'])
    parser.add_argument('--expect-fallback', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    for number, path in enumerate(args.documents):
        data = path.read_bytes()
        for mode in args.modes:
            command = [args.flutter, 'test', '--no-pub',
                       'benchmark/large_document_probe_test.dart',
                       f'--dart-define=LARGE_DOCUMENT_PATH={path.resolve()}',
                       f'--dart-define=LARGE_DOCUMENT_MODE={mode}',
                       '--dart-define=IANVS_MARKDOWN_PROFILE_PHASES=true',
                       f'--dart-define=LARGE_DOCUMENT_REJECTED={str(args.expect_fallback).lower()}']
            output, result = probe(command, 120, args.timeout)
            log = f'{number}-{mode}.log'
            (args.output / log).write_bytes(output)
            result.update(document=path.name, bytes=len(data),
                          sha256=hashlib.sha256(data).hexdigest(), mode=mode,
                          log=log)
            results.append(result)
            (args.output / 'results.json').write_text(
                json.dumps(results, indent=2) + '\n')
            print(f'{path.name}/{mode}: {"PASS" if result["passed"] else "FAIL"}',
                  flush=True)
    return 0 if all(result['passed'] for result in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
