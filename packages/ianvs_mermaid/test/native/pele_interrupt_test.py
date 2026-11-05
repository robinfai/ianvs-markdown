"""Public JSC bridge regression. Run on macOS: python3 <this file>.

The subprocess deadline protects the test runner if checkpoint insertion breaks.
This tests actual worker completion, not a timed-out/discarded Dart Future.
"""
import ctypes
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]


def run(library, fixture):
    lib = ctypes.CDLL(library)
    lib.ianvs_pele_allocate.restype = ctypes.c_void_p
    for name in ('ianvs_pele_close', 'ianvs_pele_release', 'ianvs_pele_free'):
        getattr(lib, name).argtypes = [ctypes.c_void_p]
    lib.ianvs_pele_cancel.argtypes = [ctypes.c_void_p, ctypes.c_int64]
    lib.ianvs_pele_evaluate.argtypes = [ctypes.c_void_p, ctypes.c_char_p,
        ctypes.c_int64, ctypes.c_double, ctypes.POINTER(ctypes.c_int32)]
    lib.ianvs_pele_evaluate.restype = ctypes.c_void_p
    engine = lib.ianvs_pele_allocate()
    assert engine

    def evaluate(source, request, budget):
        status = ctypes.c_int32()
        start = time.monotonic()
        pointer = lib.ianvs_pele_evaluate(engine, source.encode(), request,
                                         budget, ctypes.byref(status))
        assert pointer
        try:
            return status.value, ctypes.string_at(pointer).decode(), time.monotonic()-start
        finally:
            lib.ianvs_pele_free(pointer)

    measurements = []
    try:
        source = Path(fixture).read_text()
        for cycle in range(5):
            request = cycle * 3
            status, message, elapsed = evaluate(source, request, .08)
            assert status == 3, (status, message)
            assert .06 < elapsed < 2, elapsed
            measurements.append({'kind': 'timeout', 'seconds': elapsed})
            timer = threading.Timer(.08, lib.ianvs_pele_cancel, (engine, request+1))
            timer.start()
            try:
                status, message, elapsed = evaluate(source, request+1, 5)
            finally:
                timer.join()
            assert status == 2, (status, message)
            assert elapsed < 2, elapsed
            measurements.append({'kind': 'cancel', 'seconds': elapsed})
            status, value, _ = evaluate('6*7', request+2, 1)
            assert (status, value) == (0, '42'), (status, value)
        # Cancellation before start must not execute side effects.
        lib.ianvs_pele_cancel(engine, 15)
        assert evaluate('throw "must not execute"', 15, 1)[0] == 2
        runtime = (ROOT / 'vendor/pele/pele-runtime.js').read_text()
        assert evaluate(runtime, 16, 5)[0] == 0
        status, value, _ = evaluate(
            'JSON.stringify(Pele.render("flowchart LR\\n中文节点-->结束",{responsive:false}))', 17, 5)
        assert status == 0, value
        assert '<svg' in json.loads(value)['svg']
        print(json.dumps({'cycles': 5, 'recovery': 'passed', 'timings': measurements}, indent=2))
    finally:
        lib.ianvs_pele_close(engine)
        lib.ianvs_pele_release(engine)


if __name__ == '__main__':
    if len(sys.argv) == 3:
        run(*sys.argv[1:])
    else:
        with tempfile.TemporaryDirectory(prefix='pele-public-jsc-') as directory:
            library = str(Path(directory) / 'bridge.dylib')
            subprocess.run(['xcrun', 'clang', '-std=c11', '-O2', '-Wall', '-Wextra',
                '-Werror', '-dynamiclib', str(ROOT / 'native/pele_jsc.c'),
                '-framework', 'JavaScriptCore', '-o', library], check=True)
            symbols = subprocess.check_output(['nm', '-u', library], text=True)
            # Explicit public C API allowlist: future additions require review.
            allowed = set('JSClassCreate JSClassRelease JSContextGetGlobalObject '
                'JSEvaluateScript JSGarbageCollect JSGlobalContextCreate '
                'JSGlobalContextRelease JSObjectGetPrivate JSObjectSetPrivate '
                'JSObjectMakeFunctionWithCallback JSObjectSetProperty '
                'JSStringCreateWithUTF8CString JSStringGetMaximumUTF8CStringSize '
                'JSStringGetUTF8CString JSStringRelease JSValueMakeString '
                'JSValueMakeUndefined JSValueToStringCopy'.split())
            linked = {line.strip().split()[-1][1:] for line in symbols.splitlines()
                      if line.strip().split()[-1].startswith('_JS')}
            assert linked <= allowed, linked - allowed
            fixture = Path(directory) / 'loop.js'
            fixture.write_bytes(subprocess.check_output(
                ['node', str(ROOT / 'tool/pele/interrupt-fixture.mjs')]))
            subprocess.run([sys.executable, __file__, library, str(fixture)],
                           check=True, timeout=30)
