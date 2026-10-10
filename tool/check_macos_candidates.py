#!/usr/bin/env python3
"""Build macOS candidate entry points in an isolated host with an unmodified SDK."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import signal
import subprocess
import tempfile
import time
from urllib.parse import unquote, urljoin, urlparse


ROOT = Path(__file__).resolve().parents[1]
TARGETS = ('body', 'reading', 'editor', 'main', 'streaming')
CONTROL = """import 'package:flutter/material.dart';
void main() => runApp(const MaterialApp(
  home: Scaffold(body: Center(child: Text('Flutter AOT control'))),
));
"""


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args, cwd=ROOT):
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()


def run(command, cwd, log, timeout, environment):
    started = time.monotonic()
    with log.open('w') as output:
        process = subprocess.Popen(command, cwd=cwd, env=environment,
                                   stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired:
            # This process group belongs to this build, never another Flutter job.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            code = process.wait()
            timed_out = True
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    return {'command': command, 'exitCode': code, 'timedOut': timed_out,
            'seconds': time.monotonic() - started,
            'log': log.name, 'logSha256': digest(log)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--target', action='append', choices=TARGETS)
    parser.add_argument('--mode', action='append', choices=('profile', 'release'))
    parser.add_argument('--include-control', action='store_true')
    parser.add_argument('--keep-host', action='store_true')
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    if not args.label.replace('-', '').replace('_', '').replace('.', '').isalnum():
        parser.error('Use only letters, numbers, dot, hyphen or underscore in labels')
    if any(values and len(values) != len(set(values)) for values in (args.target, args.mode)):
        parser.error('Duplicate targets or modes are not independent builds')
    if args.timeout < 1:
        parser.error('timeout must be positive')
    flutter = Path(shutil.which(args.flutter) or args.flutter).resolve()
    if not flutter.is_file():
        parser.error('Flutter executable is missing')
    sdk = flutter.parents[1]
    if git('status', '--porcelain', '--untracked-files=no', cwd=sdk):
        parser.error('Candidate builds require an unmodified Flutter SDK')
    sdk_revision = git('rev-parse', 'HEAD', cwd=sdk)
    output = ROOT / 'build/platform-candidates' / args.label
    output.mkdir(parents=True, exist_ok=False)  # Never overwrite earlier evidence.
    environment = dict(os.environ, CARGO_PROFILE_RELEASE_STRIP='none',
                       FLUTTER_XCODE_ARCHS=platform.machine())
    version_run = run([str(flutter), '--version', '--machine'], ROOT,
                      output / 'sdk-version.json', args.timeout, environment)
    if version_run['exitCode'] != 0:
        raise RuntimeError('SDK initialization failed; see sdk-version.json')
    version = json.loads((output / 'sdk-version.json').read_text())
    if version['frameworkRevision'] != sdk_revision:
        raise RuntimeError('SDK version does not match its checkout')
    tracked = git('ls-files', '-z', '--', 'lib', 'example', 'pubspec.yaml',
                  'pubspec.lock', 'analysis_options.yaml', 'LICENSE').split('\0')
    tracked = [name for name in tracked if name]
    untracked = git('ls-files', '--others', '--exclude-standard', '--', 'lib', 'example')
    if untracked:
        raise RuntimeError('Commit new library/example inputs before candidate verification')
    manifest = {name: digest(ROOT / name) for name in tracked}
    temporary = Path(tempfile.mkdtemp(prefix='ianvs-macos-candidate-'))
    host = temporary / 'repository'
    for name in tracked:
        destination = host / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    if args.include_control:
        (host / 'example/lib/aot_control.dart').write_text(CONTROL)
    report = {
        'schemaVersion': 1, 'startedAtUtc': datetime.now(timezone.utc).isoformat(),
        'revision': git('rev-parse', 'HEAD'), 'sourceInputsSha256': manifest,
        'sourceDiffSha256': hashlib.sha256(git('diff', 'HEAD', '--', *tracked).encode()).hexdigest(),
        'flutter': version, 'sdkRevision': sdk_revision, 'sdkUnmodified': True,
        'frameworkFeatureFileSha256': digest(sdk / 'packages/flutter/lib/src/foundation/_features.dart'),
        'host': platform.platform(), 'architecture': platform.machine(),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'hostDirectory': str(host), 'hostRetained': args.keep_host,
        'runnerSha256': digest(Path(__file__)), 'timeoutSeconds': args.timeout,
        'controlSource': CONTROL if args.include_control else None,
        'environment': {key: environment[key] for key in ('CARGO_PROFILE_RELEASE_STRIP', 'FLUTTER_XCODE_ARCHS')},
        'builds': [], 'errors': [], 'complete': False, 'passed': False,
    }
    def save():
        (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    save()
    try:
        resolved = run([str(flutter), 'pub', 'get'], host / 'example',
                       output / 'pub-get.log', args.timeout, environment)
        report['dependencyResolution'] = resolved
        if resolved['exitCode'] != 0:
            raise RuntimeError('Dependency resolution failed')
        config_path = host / 'example/.dart_tool/package_config.json'
        packages = json.loads(config_path.read_text())['packages']
        for name, expected in [('flutter', sdk / 'packages/flutter'), ('ianvs_markdown', host)]:
            package = next(item for item in packages if item['name'] == name)
            actual = Path(unquote(urlparse(urljoin(config_path.as_uri(), package['rootUri'])).path)).resolve()
            if actual != expected.resolve():
                raise RuntimeError(f'Unexpected {name} package path: {actual}')
        report['frameworkAndComponentPathsVerified'] = True
        for lock in ('pubspec.lock', 'example/pubspec.lock'):
            shutil.copy2(host / lock, output / lock.replace('/', '-'))
        report['hostLocksSha256'] = {name: digest(host / name) for name in ('pubspec.lock', 'example/pubspec.lock')}
        targets = args.target or list(TARGETS)
        if args.include_control:
            targets = ['aot_control', *targets]
        for target in targets:
            for mode in args.mode or ('profile', 'release'):
                print(f'Building {version["frameworkVersion"]} {target} {mode}', flush=True)
                bundle = host / f'example/build/macos/Build/Products/{mode.title()}/Ianvs Markdown Playground.app'
                if bundle.exists():
                    shutil.rmtree(bundle)  # Only output in this newly created temporary host.
                result = run([str(flutter), 'build', 'macos', f'--{mode}', '--no-pub',
                              '--target', f'lib/{target}.dart'], host / 'example',
                             output / f'{target}-{mode}.log', args.timeout, environment)
                result.update(target=target, mode=mode, passed=False)
                report['builds'].append(result)
                text = (output / result['log']).read_text(errors='replace')
                result['windowingAotFailure'] = ('Class with illegal cid, full-aot' in text
                                                and '_window_macos.dart' in text)
                if result['exitCode'] == 0 and bundle.is_dir():
                    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
                    executable = bundle / 'Contents/MacOS' / info['CFBundleExecutable']
                    architectures = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).strip()
                    framework = bundle / 'Contents/Frameworks/App.framework/App'
                    framework_architectures = subprocess.check_output(['lipo', '-archs', str(framework)], text=True).strip()
                    result['artifact'] = {
                        'name': bundle.name, 'architectures': architectures,
                        'executableSha256': digest(executable), 'appFrameworkArchitectures': framework_architectures,
                        'appFrameworkSha256': digest(framework),
                        'bytes': sum(path.stat().st_size for path in bundle.rglob('*') if path.is_file() and not path.is_symlink()),
                    }
                    result['passed'] = (platform.machine() in architectures.split()
                                        and platform.machine() in framework_architectures.split())
                save()
                print(f'{target}/{mode}: {"PASS" if result["passed"] else "FAIL"}', flush=True)
        if git('rev-parse', 'HEAD', cwd=sdk) != sdk_revision or git('status', '--porcelain', '--untracked-files=no', cwd=sdk):
            raise RuntimeError('Flutter SDK changed during verification')
        if any(digest(ROOT / name) != value for name, value in manifest.items()):
            raise RuntimeError('Source inputs changed during verification')
        report['complete'] = True
        report['passed'] = all(row['passed'] for row in report['builds'])
    except Exception as error:
        report['errors'].append(str(error))
        raise
    finally:
        report['finishedAtUtc'] = datetime.now(timezone.utc).isoformat()
        save()
        if not args.keep_host:
            shutil.rmtree(temporary)
    print(f'Saved {output / "summary.json"}', flush=True)
    if not report['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
