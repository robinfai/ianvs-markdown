#!/usr/bin/env python3
"""Compile one isolated macOS arm64 AOT probe; this does not build or run an app."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import shutil
import tempfile
from urllib.parse import unquote, urljoin, urlparse

from check_macos_candidates import ROOT, digest, git, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--component', action='store_true',
                        help='Resolve an isolated copy of the current core package')
    parser.add_argument('--dart-only', action='store_true',
                        help='Use dart compile aot-snapshot without Flutter dependencies')
    parser.add_argument('--timeout', type=int, default=120)
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        parser.error('This diagnostic is limited to macOS arm64')
    if args.dart_only and args.component:
        parser.error('--dart-only cannot be combined with --component')
    if args.timeout < 1:
        parser.error('timeout must be positive')
    if not args.label.replace('-', '').replace('_', '').replace('.', '').isalnum():
        parser.error('Use only letters, numbers, dot, hyphen or underscore in labels')
    source = args.source.resolve()
    if not source.is_file():
        parser.error('Source file is missing')
    flutter = Path(shutil.which(args.flutter) or args.flutter).resolve()
    if not flutter.is_file():
        parser.error('Flutter executable is missing')
    sdk = flutter.parents[1]
    if git('status', '--porcelain', '--untracked-files=no', cwd=sdk):
        parser.error('Diagnostic requires an unmodified Flutter SDK')
    sdk_revision = git('rev-parse', 'HEAD', cwd=sdk)
    # Never replace evidence from an earlier attempt.
    output = ROOT / 'build/aot-reduction' / args.label
    output.mkdir(parents=True, exist_ok=False)
    shutil.copy2(source, output / 'source.dart.txt')
    manifest = {}
    if args.component:
        if git('ls-files', '--others', '--exclude-standard', '--', 'lib'):
            parser.error('Commit new library inputs before verification')
        names = git('ls-files', '-z', '--', 'lib', 'pubspec.yaml',
                    'pubspec.lock', 'LICENSE').split('\0')
        manifest = {name: digest(ROOT / name) for name in names if name}
    env = dict(os.environ, CARGO_PROFILE_RELEASE_STRIP='none', FLUTTER_XCODE_ARCHS='arm64')
    report = {
        'schemaVersion': 1, 'startedAtUtc': datetime.now(timezone.utc).isoformat(),
        'kind': 'standalone Dart AOT' if args.dart_only else 'Flutter frontend + arm64 gen_snapshot',
        'scope': 'Compile only; no bundle, app launch or interaction acceptance',
        'revision': git('rev-parse', 'HEAD'), 'sourceSha256': digest(source),
        'componentInputsSha256': manifest,
        'sdkRevision': sdk_revision, 'sdkUnmodifiedBefore': True,
        'sdkUnmodifiedAfter': False, 'host': platform.platform(),
        'architecture': platform.machine(), 'runnerSha256': digest(Path(__file__)),
        'steps': [], 'errors': [], 'complete': False, 'passed': False,
        'windowingAotFailure': False,
    }

    def save():
        (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')

    def step(command, cwd, name):
        result = run(command, cwd, output / name, args.timeout, env)
        report['steps'].append(result)
        save()
        return result['exitCode'] == 0 and not result['timedOut']

    save()
    try:
        if not step([str(flutter), '--version', '--machine'], ROOT, 'sdk-version.json'):
            raise RuntimeError('SDK initialization failed')
        version = json.loads((output / 'sdk-version.json').read_text())
        if version['frameworkRevision'] != sdk_revision:
            raise RuntimeError('SDK version does not match checkout')
        report['flutter'] = version
        with tempfile.TemporaryDirectory(prefix='ianvs-aot-probe-') as temporary:
            host = Path(temporary) / 'host'
            host.mkdir()
            entry = host / 'main.dart'
            shutil.copy2(source, entry)
            if args.dart_only:
                artifact = host / 'probe.aot'
                ok = step([str(sdk / 'bin/cache/dart-sdk/bin/dart'), 'compile',
                           'aot-snapshot', str(entry), '-o', str(artifact)], host, 'dart-aot.log')
            else:
                pubspec = ('name: ianvs_aot_probe\npublish_to: none\nenvironment:\n'
                           '  sdk: ^3.12.0\ndependencies:\n  flutter:\n    sdk: flutter\n')
                if args.component:
                    component = Path(temporary) / 'component'
                    for name in manifest:
                        dest = component / name
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(ROOT / name, dest)
                        if digest(dest) != manifest[name]:
                            raise RuntimeError('Source changed while copying: ' + name)
                    pubspec += '  ianvs_markdown:\n    path: ../component\n'
                pubspec += 'flutter:\n  uses-material-design: true\n'
                (host / 'pubspec.yaml').write_text(pubspec)
                shutil.copy2(host / 'pubspec.yaml', output / 'pubspec.yaml.txt')
                if not step([str(flutter), 'pub', 'get'], host, 'pub-get.log'):
                    raise RuntimeError('Dependency resolution failed')
                shutil.copy2(host / 'pubspec.lock', output / 'pubspec.lock')
                config = host / '.dart_tool/package_config.json'
                packages = json.loads(config.read_text())['packages']
                expected = {'flutter': sdk / 'packages/flutter'}
                if args.component:
                    expected['ianvs_markdown'] = component
                for name, root in expected.items():
                    package = next(p for p in packages if p['name'] == name)
                    actual = Path(unquote(urlparse(urljoin(config.as_uri(), package['rootUri'])).path))
                    if actual.resolve() != root.resolve():
                        raise RuntimeError('Unexpected dependency path: ' + name)
                report['frameworkAndComponentPathsVerified'] = True
                cache = sdk / 'bin/cache'
                dill = host / 'probe.dill'
                artifact = host / 'probe.S'
                ok = step([str(cache / 'dart-sdk/bin/dartaotruntime'),
                           str(cache / 'dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot'),
                           '--sdk-root', str(cache / 'artifacts/engine/common/flutter_patched_sdk_product') + '/',
                           '--target=flutter', '--aot', '--tfa', '--target-os', 'macos',
                           '-Ddart.vm.product=true', '--packages', str(config),
                           '--output-dill', str(dill), str(entry)], host, 'frontend.log')
                if ok and dill.is_file():
                    report['kernelSha256'] = digest(dill)
                    ok = step([str(cache / 'artifacts/engine/darwin-x64-release/gen_snapshot_arm64'),
                               '--deterministic', '--snapshot_kind=app-aot-assembly',
                               '--assembly=' + str(artifact), str(dill)], host, 'snapshot.log')
                    log = (output / 'snapshot.log').read_text(errors='replace')
                    report['windowingAotFailure'] = ('Class with illegal cid, full-aot' in log
                                                    and '_window_macos.dart' in log)
                else:
                    ok = False
            report['passed'] = ok and artifact.is_file() and artifact.stat().st_size > 0
            if report['passed']:
                report['artifactSha256'] = digest(artifact)
            if git('rev-parse', 'HEAD', cwd=sdk) != sdk_revision or git('status', '--porcelain', '--untracked-files=no', cwd=sdk):
                raise RuntimeError('SDK changed during verification')
            report['sdkUnmodifiedAfter'] = True
            if digest(source) != report['sourceSha256'] or any(digest(ROOT / name) != value for name, value in manifest.items()):
                raise RuntimeError('Source changed during verification')
            report['complete'] = True
    except Exception as error:
        report['errors'].append(str(error))
        report['passed'] = False
        raise
    finally:
        report['finishedAtUtc'] = datetime.now(timezone.utc).isoformat()
        save()
    print(json.dumps({key: report[key] for key in ('complete', 'passed', 'windowingAotFailure')}))
    print('Evidence: ' + str(output))
    if not report['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
