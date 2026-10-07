#!/usr/bin/env python3
"""Run the profile benchmark in the minimal macOS host and retain raw evidence."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import tempfile
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--operation-timeout", type=int, default=180, help="Maximum seconds for an operation including warmup; partial results are retained on timeout")
    parser.add_argument("--flutter", default=os.environ.get("FLUTTER", "flutter"))
    parser.add_argument("--windowing-workaround", action="store_true", help="Apply the documented Flutter AOT workaround to a disposable SDK under a system temp directory")
    parser.add_argument("--force-document-parse", action="store_true", help="Reproduce the pre-cache document refresh behavior for comparison")
    args = parser.parse_args()
    if not args.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label must contain only letters, numbers, - or _")
    if args.samples < 1 or args.warmup < 0 or args.operation_timeout < 1:
        parser.error("samples and timeout must be positive; warmup must be nonnegative")
    root = Path(__file__).resolve().parents[1]
    output = root / "build/benchmark"
    output.mkdir(parents=True, exist_ok=True)
    # Reusing a label must not leave a previous success visible after a failed
    # build or SDK check. Use distinct labels to retain independent runs.
    for suffix in ('.json', '.partial.json'):
        (output / f'{args.label}{suffix}').unlink(missing_ok=True)
    started = datetime.now(timezone.utc).isoformat()
    flutter_binary = shutil.which(args.flutter)
    if flutter_binary is None:
        parser.error(f"Flutter binary not found: {args.flutter}")
    sdk = Path(flutter_binary).resolve().parents[1]
    feature_file = sdk / "packages/flutter/lib/src/foundation/_features.dart"
    if args.windowing_workaround:
        temporary_roots = {Path(tempfile.gettempdir()).resolve(), Path('/tmp').resolve()}
        if not any(sdk.is_relative_to(temp) for temp in temporary_roots):
            parser.error("The workaround is only allowed in a disposable SDK under a system temp directory")
        if 'bool isWindowingEnabled = false;' not in feature_file.read_text():
            patch = root / 'benchmark/flutter-windowing-workaround.patch'
            subprocess.run(['git', 'apply', '--check', '--unidiff-zero', str(patch)], cwd=sdk, check=True)
            subprocess.run(['git', 'apply', '--unidiff-zero', str(patch)], cwd=sdk, check=True)
    result = None
    timeout_error = None
    runtime_errors = []
    command = [
        args.flutter, "run", "-d", "macos", "--profile",
        "--target", "../benchmark/live_editor_benchmark.dart",
        "--dart-define=IANVS_MARKDOWN_DIAGNOSTICS=true",
        f"--dart-define=BENCHMARK_SAMPLES={args.samples}",
        f"--dart-define=BENCHMARK_WARMUP={args.warmup}",
        f"--dart-define=IANVS_MARKDOWN_FORCE_DOCUMENT_PARSE={str(args.force_document_parse).lower()}",
    ]
    environment = dict(os.environ)
    # Same native profile-build workaround as the app's macOS release target.
    environment["CARGO_PROFILE_RELEASE_STRIP"] = "none"
    environment["FLUTTER_XCODE_ARCHS"] = platform.machine()
    with (output / f"{args.label}.log").open("w") as log:
        # `flutter run` may reuse package_config.json after switching SDKs.
        # Resolve explicitly and verify the framework used by the compiler.
        subprocess.run([args.flutter, 'pub', 'get'], cwd=root / 'example', env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
        from urllib.parse import unquote, urljoin, urlparse
        config_file = root / 'example/.dart_tool/package_config.json'
        packages = json.loads(config_file.read_text())['packages']
        framework = next(p for p in packages if p['name'] == 'flutter')
        resolved = Path(unquote(urlparse(urljoin(config_file.as_uri(), framework['rootUri'])).path)).resolve()
        if resolved != sdk / 'packages/flutter':
            raise RuntimeError(f'Framework SDK mismatch: {resolved} != {sdk}')
        process = subprocess.Popen(command, cwd=root / "example", env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
        def stop_on_timeout(phase):
            nonlocal timeout_error
            if process.poll() is None:
                timeout_error = f"Timed out: {phase}"
                print(timeout_error, flush=True)
                os.killpg(process.pid, signal.SIGKILL)
        timer = threading.Timer(600, stop_on_timeout, args=('build/startup after 600 seconds',))
        timer.start()
        try:
            for line in process.stdout:
                log.write(line)
                log.flush()
                if "IANVS_BENCHMARK_PROGRESS:" in line:
                    print(line.strip(), flush=True)
                if "IANVS_BENCHMARK_FAILURE: " in line:
                    failure = json.loads(line.split("IANVS_BENCHMARK_FAILURE: ", 1)[1])
                    runtime_errors.append(failure)
                    print(f'Benchmark error: {failure}', flush=True)
                if "IANVS_BENCHMARK_CHECKPOINT: " in line:
                    result = json.loads(line.split("IANVS_BENCHMARK_CHECKPOINT: ", 1)[1])
                    timer.cancel()
                    case = result['results'][-1]
                    phase = f"{case['utf8Bytes']} bytes / {case['budget']} / {result['activeOperation']} after {args.operation_timeout} seconds"
                    timer = threading.Timer(args.operation_timeout, stop_on_timeout, args=(phase,))
                    timer.start()
                    (output / f"{args.label}.partial.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
                if "IANVS_BENCHMARK_RESULT: " in line:
                    result = json.loads(line.split("IANVS_BENCHMARK_RESULT: ", 1)[1])
                    timer.cancel()
            code = process.wait()
        finally:
            timer.cancel()
    if result is None:
        raise RuntimeError(f"Benchmark failed (exit {code}); see {output / (args.label + '.log')}")
    if timeout_error:
        result['errors'].append(timeout_error)
    result['errors'].extend(runtime_errors)
    if not result['complete'] and not result['errors']:
        result['errors'].append(f'Benchmark exited before completion (exit {code})')
    result['operationTimeoutSeconds'] = args.operation_timeout
    result['runStartedAtUtc'] = started
    result["host"] = platform.platform()
    result["cpu"] = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
    result["flutter"] = json.loads(subprocess.check_output([args.flutter, "--version", "--machine"], text=True))
    result["corpusGeneratorSha256"] = hashlib.sha256((root / "benchmark/corpus.dart").read_bytes()).hexdigest()
    result["editorSha256"] = hashlib.sha256((root / "lib/src/editor/live_editor.dart").read_bytes()).hexdigest()
    result["harnessSha256"] = hashlib.sha256((root / "benchmark/live_editor_benchmark.dart").read_bytes()).hexdigest()
    result["experimentalWindowingWorkaround"] = args.windowing_workaround
    result["frameworkFeatureFileSha256"] = hashlib.sha256(feature_file.read_bytes()).hexdigest()
    result["frameworkPackagePathVerified"] = True
    result["frameworkFeatureDiff"] = subprocess.check_output(['git', 'diff', '--', str(feature_file.relative_to(sdk))], cwd=sdk, text=True)
    (output / f"{args.label}.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(f"Saved {output / (args.label + '.json')}")
    if not result['complete'] or result['errors']:
        raise RuntimeError(f"Incomplete benchmark; partial evidence retained in {output / (args.label + '.json')}")


if __name__ == "__main__":
    main()
