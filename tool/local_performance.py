#!/usr/bin/env python3
"""Build/freeze actual mains and collect their opt-in R4-02 evidence. Never launches UI."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build/local-performance'
BUNDLES = {'example': 'Ianvs Markdown Playground', 'app': 'Linefold'}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def command(args, cwd=ROOT):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def sources():
    paths = command(['git', 'ls-files', '--cached', '--others', '--exclude-standard']).splitlines()
    prefixes = ('lib/', 'example/lib/', 'app/lib/', 'example/macos/', 'app/macos/', 'packages/')
    explicit = {'pubspec.yaml', 'pubspec.lock', 'example/pubspec.yaml', 'example/pubspec.lock',
                'app/pubspec.yaml', 'app/pubspec.lock', 'benchmark/LOCAL-PERFORMANCE-PROTOCOL.md',
                'tool/local_performance.py', 'tool/analyze_local_performance.py'}
    return {p: sha(ROOT / p) for p in sorted(set(paths))
            if p in explicit or (p.startswith(prefixes) and '/test/' not in p)}


def sdk_info(binary):
    sdk = Path(binary).resolve().parents[1]
    changes = command(['git', 'status', '--porcelain'], sdk)
    if changes:
        raise ValueError(f'SDK must be unmodified: {changes}')
    return {'path': str(sdk), 'revision': command(['git', 'rev-parse', 'HEAD'], sdk),
            'version': json.loads((sdk / 'bin/cache/flutter.version.json').read_text()),
            'workingTree': 'clean'}


def build(args):
    out = OUTPUT / f'build-{args.tag}'
    out.mkdir(parents=True, exist_ok=False)
    inputs = sources()
    frozen = {'schemaVersion': 1, 'sourceRevision': command(['git', 'rev-parse', 'HEAD']),
              'inputs': inputs, 'inputsDigest': digest(inputs), 'sdk': sdk_info(args.flutter),
              'mode': args.mode, 'attributionOnly': args.attribution, 'builds': {}, 'buildStartedUtc': datetime.now(timezone.utc).isoformat(),
              'machine': {'arch': platform.machine(), 'macos': command(['sw_vers']),
                          'xcode': command(['xcodebuild', '-version'])}}
    env = dict(os.environ, CARGO_PROFILE_RELEASE_STRIP='none', FLUTTER_XCODE_ARCHS=platform.machine())
    failed = []
    for entry, name in BUNDLES.items():
        cmd = [args.flutter, 'build', 'macos', f'--{args.mode}', '--target', 'lib/main.dart',
               '--dart-define=IANVS_LOCAL_PERFORMANCE=true',
               f"--dart-define=IANVS_PERF_REVISION={frozen['sourceRevision']}",
               f"--dart-define=IANVS_PERF_INPUTS={frozen['inputsDigest']}"]
        if args.attribution:
            cmd.append('--dart-define=IANVS_PERF_ATTRIBUTION=true')
        print(f'Building {entry} main ({args.mode})', flush=True)
        with (out / f'{entry}.log').open('w') as log:
            code = subprocess.run(cmd, cwd=ROOT / entry, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
        item = {'command': cmd, 'exitCode': code, 'logSha256': sha(out / f'{entry}.log')}
        if code == 0:
            bundle = ROOT / entry / 'build/macos/Build/Products' / args.mode.title() / f'{name}.app'
            item.update(bundle=str(bundle), executable=str(bundle / 'Contents/MacOS' / name),
                        binarySha256=sha(bundle / 'Contents/MacOS' / name),
                        appFrameworkSha256=sha(bundle / 'Contents/Frameworks/App.framework/Versions/A/App'))
        else:
            failed.append(entry)
        frozen['builds'][entry] = item
    if sources() != inputs:
        raise ValueError('Inputs changed during build; keep logs and rebuild after committing them')
    if sdk_info(args.flutter) != frozen['sdk']:
        raise ValueError('SDK changed during build')
    frozen['buildFinishedUtc'] = datetime.now(timezone.utc).isoformat()
    frozen['complete'] = not failed
    (out / 'freeze.json').write_text(json.dumps(frozen, indent=2, ensure_ascii=False) + '\n')
    print(out / 'freeze.json', flush=True)
    if failed:
        raise SystemExit(f'Failed actual main builds: {failed}; logs retained')


def collect(args):
    freeze = json.loads(args.freeze.read_text())
    if not freeze.get('complete'):
        raise ValueError('A completed build freeze is required')
    if sources() != freeze['inputs']:
        raise ValueError('Frozen sources changed')
    if sdk_info(str(Path(freeze['sdk']['path']) / 'bin/flutter')) != freeze['sdk']:
        raise ValueError('Frozen SDK changed')
    data = json.loads((args.source / 'result.json').read_text())
    entry = data['entry']
    built = freeze['builds'][entry]
    for key in ('sourceRevision', 'inputsDigest'):
        if data[key] != freeze[key]:
            raise ValueError(f'Running binary has different {key}')
    if data['buildMode'] != freeze['mode'] or data['system']['executable'] != built['executable']:
        raise ValueError('Wrong build mode/executable')
    if sha(built['executable']) != built['binarySha256'] or sha(Path(built['bundle']) / 'Contents/Frameworks/App.framework/Versions/A/App') != built['appFrameworkSha256']:
        raise ValueError('Built artifacts changed')
    out = OUTPUT / 'runs' / args.label
    out.mkdir(parents=True, exist_ok=False)
    names = ['result.json', 'trace.jsonl', *[f'corpus-{n}.md' for n in (10240, 102400, 1048576)]]
    artifacts = {}
    for name in names:
        source = args.source / name
        if source.exists():
            shutil.copyfile(source, out / name)
            artifacts[name] = sha(out / name)
    receipt = {'label': args.label, 'freeze': freeze, 'artifacts': artifacts,
               'collectedAtUtc': datetime.now(timezone.utc).isoformat(), 'complete': data['complete']}
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')
    print(f"Collected {'complete' if data['complete'] else 'INVALID partial'} run: {out}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    p = sub.add_parser('build')
    p.add_argument('--flutter', required=True)
    p.add_argument('--mode', choices=['profile', 'release'], default='profile')
    p.add_argument('--tag', required=True)
    p.add_argument('--attribution', action='store_true', help='CPU-only filtered run, rejected by acceptance validator')
    p = sub.add_parser('collect')
    p.add_argument('--freeze', type=Path, required=True)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--label', required=True)
    args = parser.parse_args()
    label = args.tag if args.action == 'build' else args.label
    if not label.replace('-', '').replace('_', '').isalnum():
        parser.error('Labels may only contain letters, digits, - and _')
    (build if args.action == 'build' else collect)(args)


if __name__ == '__main__':
    main()
