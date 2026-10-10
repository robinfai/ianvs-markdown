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
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--operation-timeout", type=int, default=900, help="Maximum seconds for an operation group, including warmup and all mode directions")
    parser.add_argument("--sample-timeout", type=int, default=120, help="Maximum seconds for one warmup, measured action, or preparation")
    parser.add_argument("--sizes", default="10240,102400,1048576", help="Comma-separated corpus byte sizes")
    parser.add_argument("--budgets", default="default,unlimited", help="Comma-separated budget cases")
    parser.add_argument("--operations", default="initialDisplay,selection,typing,scroll,liveToSource,sourceToReading,readingToLive", help="Comma-separated operation names; filtered runs are diagnostic only")
    parser.add_argument("--flutter", default=os.environ.get("FLUTTER", "flutter"))
    parser.add_argument("--windowing-workaround", action="store_true", help="Apply the documented Flutter AOT workaround to a disposable SDK under a system temp directory")
    parser.add_argument("--force-document-parse", action="store_true", help="Reproduce the pre-cache document refresh behavior for comparison")
    parser.add_argument("--phase-timings", action="store_true", help="Enable synchronous component attribution; diagnostic runs only, not accepted latency baselines")
    args = parser.parse_args()
    if not args.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label must contain only letters, numbers, - or _")
    if args.samples < 1 or args.warmup < 0 or min(args.operation_timeout, args.sample_timeout) < 1:
        parser.error("samples and timeout must be positive; warmup must be nonnegative")
    for name, allowed in {
        "sizes": {"10240", "102400", "1048576"},
        "budgets": {"default", "unlimited"},
        "operations": {"initialDisplay", "selection", "typing", "scroll", "liveToSource", "sourceToReading", "readingToLive"},
    }.items():
        values = getattr(args, name).split(",")
        if not values or not set(values) <= allowed or len(values) != len(set(values)):
            parser.error(f"Invalid or duplicate --{name}: {getattr(args, name)}")
    root = Path(__file__).resolve().parents[1]
    output = root / "build/benchmark"
    output.mkdir(parents=True, exist_ok=True)
    # Reusing a label must not leave a previous success visible after a failed
    # build or SDK check. Use distinct labels to retain independent runs.
    for suffix in ('.json', '.partial.json', '.samples.jsonl', '.progress.json'):
        (output / f'{args.label}{suffix}').unlink(missing_ok=True)
    started = datetime.now(timezone.utc).isoformat()
    started_clock = time.monotonic()
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
    runtime_paths = [root / name for name in (
        'pubspec.yaml', 'pubspec.lock', 'example/pubspec.yaml', 'example/pubspec.lock',
        'example/macos/Runner/MainFlutterWindow.swift',
        'example/macos/Runner/Base.lproj/MainMenu.xib',
    )]
    source_paths = sorted((root / 'lib').rglob('*.dart'))
    input_paths = source_paths + runtime_paths + [
        root / 'benchmark/corpus.dart', root / 'benchmark/live_editor_benchmark.dart',
        Path(__file__).resolve(), feature_file,
    ]
    input_hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in input_paths}
    result = None
    timeout_errors = []
    last_sample = None
    runtime_errors = []
    command = [
        args.flutter, "run", "-d", "macos", "--profile",
        "--target", "../benchmark/live_editor_benchmark.dart",
        "--dart-define=IANVS_MARKDOWN_DIAGNOSTICS=true",
        f"--dart-define=IANVS_MARKDOWN_PROFILE_PHASES={str(args.phase_timings).lower()}",
        f"--dart-define=BENCHMARK_SAMPLES={args.samples}",
        f"--dart-define=BENCHMARK_WARMUP={args.warmup}",
        f"--dart-define=BENCHMARK_SIZES={args.sizes}",
        f"--dart-define=BENCHMARK_BUDGETS={args.budgets}",
        f"--dart-define=BENCHMARK_OPERATIONS={args.operations}",
        f"--dart-define=IANVS_MARKDOWN_FORCE_DOCUMENT_PARSE={str(args.force_document_parse).lower()}",
    ]
    environment = dict(os.environ)
    # Same native profile-build workaround as the app's macOS release target.
    environment["CARGO_PROFILE_RELEASE_STRIP"] = "none"
    environment["FLUTTER_XCODE_ARCHS"] = platform.machine()
    samples_file = output / f"{args.label}.samples.jsonl"
    with (output / f"{args.label}.log").open("w") as log, samples_file.open("w") as sample_log:
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
        timers = {}
        generations = {}
        timer_lock = threading.Lock()

        def cancel(kind):
            with timer_lock:
                generations[kind] = generations.get(kind, 0) + 1
                timer = timers.pop(kind, None)
                if timer:
                    timer.cancel()

        def arm(kind, seconds, phase):
            cancel(kind)
            token = generations[kind]

            def stop_on_timeout():
                with timer_lock:
                    if generations[kind] != token or process.poll() is not None:
                        return
                    message = f"Timed out: {phase} after {seconds} seconds"
                    timeout_errors.append(message)
                    print(message, flush=True)
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

            timer = threading.Timer(seconds, stop_on_timeout)
            timer.daemon = True
            timers[kind] = timer
            timer.start()

        arm('operation', 600, 'build/startup')
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
                if "IANVS_BENCHMARK_ERROR: " in line:
                    runtime_errors.append(line.split("IANVS_BENCHMARK_ERROR: ", 1)[1].strip())
                if "IANVS_BENCHMARK_CHECKPOINT: " in line:
                    result = json.loads(line.split("IANVS_BENCHMARK_CHECKPOINT: ", 1)[1])
                    case = result['results'][-1]
                    phase = f"{case['utf8Bytes']} bytes / {case['budget']} / {result['activeOperation']}"
                    arm('operation', args.operation_timeout, phase)
                    (output / f"{args.label}.partial.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
                if "IANVS_BENCHMARK_SAMPLE: " in line:
                    last_sample = json.loads(line.split("IANVS_BENCHMARK_SAMPLE: ", 1)[1])
                    sample_log.write(json.dumps(last_sample, ensure_ascii=False) + '\n')
                    sample_log.flush()
                    (output / f"{args.label}.progress.json").write_text(json.dumps(last_sample, indent=2) + '\n')
                    if last_sample['event'] == 'start':
                        phase = f"{last_sample['utf8Bytes']} bytes / {last_sample['budget']} / {last_sample['operation']} / {last_sample['stage']}[{last_sample['index']}]"
                        arm('sample', args.sample_timeout, phase)
                    else:
                        cancel('sample')
                if "IANVS_BENCHMARK_RESULT: " in line:
                    result = json.loads(line.split("IANVS_BENCHMARK_RESULT: ", 1)[1])
                    cancel('operation')
                    cancel('sample')
            code = process.wait()
        finally:
            cancel('operation')
            cancel('sample')
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    if result is None:
        result = {'complete': False, 'fullBaseline': False, 'results': [], 'errors': [f'No measurements started (exit {code})']}
    result['errors'].extend(timeout_errors)
    if code != 0:
        result['complete'] = False
        result['fullBaseline'] = False
        result['errors'].append(f'Benchmark process failed (exit {code})')
    result['errors'].extend(runtime_errors)
    changed_inputs = [path for path, digest in input_hashes.items()
                      if hashlib.sha256(Path(path).read_bytes()).hexdigest() != digest]
    if source_paths != sorted((root / 'lib').rglob('*.dart')):
        changed_inputs.append('library source file inventory')
    if changed_inputs:
        result['complete'] = False
        result['fullBaseline'] = False
        result['errors'].append(f'Inputs changed during measurement: {changed_inputs}')
    if not result['complete'] and not result['errors']:
        result['errors'].append(f'Benchmark exited before completion (exit {code})')
    result['operationTimeoutSeconds'] = args.operation_timeout
    result['sampleTimeoutSeconds'] = args.sample_timeout
    result['lastSample'] = last_sample
    result['sampleTraceFile'] = samples_file.name
    result['sampleTraceSha256'] = hashlib.sha256(samples_file.read_bytes()).hexdigest()
    result['wallSeconds'] = time.monotonic() - started_clock
    result['runFinishedAtUtc'] = datetime.now(timezone.utc).isoformat()
    result['runnerSha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    result['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    result['trackedDiffSha256'] = hashlib.sha256(subprocess.check_output(['git', 'diff', 'HEAD', '--', 'lib', 'benchmark', 'tool/run_benchmark.py'], cwd=root)).hexdigest()
    result['sourceFilesSha256'] = {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((root / 'lib').rglob('*.dart'))
    }
    result['runtimeInputsSha256'] = {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in runtime_paths
    }
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
