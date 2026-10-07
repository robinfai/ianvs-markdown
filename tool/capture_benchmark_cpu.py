#!/usr/bin/env python3
"""Capture one benchmark action's Dart CPU samples. Diagnostic runs only."""
import argparse
import json
from pathlib import Path
import re
import time
from urllib.parse import urlencode, urlparse
from urllib.request import urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--operation', default='liveToSource')
    parser.add_argument('--size', type=int, default=1048576)
    parser.add_argument('--budget', choices=['default', 'unlimited'], default='unlimited')
    parser.add_argument('--index', type=int, default=0)
    parser.add_argument('--wait-timeout', type=int, default=600)
    args = parser.parse_args()
    if not args.label.replace('-', '').replace('_', '').isalnum():
        parser.error('Invalid label')
    output = Path(__file__).resolve().parents[1] / 'build/benchmark'
    trace_file = output / f'{args.label}.samples.jsonl'
    log_file = output / f'{args.label}.log'
    deadline = time.monotonic() + args.wait_timeout
    uri = None
    isolate = None
    start = None
    end = None
    offset = 0

    def rpc(method, **parameters):
        query = '?' + urlencode(parameters) if parameters else ''
        with urlopen(uri + method + query, timeout=30) as response:
            data = json.load(response)
        if 'error' in data:
            raise RuntimeError(data['error'])
        return data['result']

    while time.monotonic() < deadline:
        if uri is None and log_file.exists():
            match = re.search(r'A Dart VM Service on macOS is available at: (http://\S+)', log_file.read_text())
            if match:
                uri = match.group(1)
                address = urlparse(uri)
                if address.hostname not in {'127.0.0.1', 'localhost', '::1'}:
                    raise RuntimeError('Only the local benchmark VM service is allowed')
                vm = rpc('getVM')
                isolate = next(item['id'] for item in vm['isolates'] if item['name'] == 'main')
        if uri and trace_file.exists():
            with trace_file.open() as trace:
                trace.seek(offset)
                while True:
                    position = trace.tell()
                    line = trace.readline()
                    if not line:
                        break
                    if not line.endswith('\n'):
                        trace.seek(position)
                        break
                    event = json.loads(line)
                    if (event['operation'], event['utf8Bytes'], event['budget'], event['stage'], event['index']) != (
                        args.operation, args.size, args.budget, 'sample', args.index
                    ):
                        continue
                    if event['event'] == 'start':
                        start = event
                    elif start is not None:
                        end = event
                        break
                offset = trace.tell()
        if end:
            profile = rpc('getCpuSamples', isolateId=isolate,
                          timeOriginMicros=start['timelineMicros'],
                          timeExtentMicros=end['timelineMicros'] - start['timelineMicros'])
            if not profile.get('sampleCount'):
                raise RuntimeError('No CPU samples; verify VM profiling is enabled')
            profile['benchmarkAction'] = {'start': start, 'end': end}
            path = output / f'{args.label}-{args.operation}.cpu.json'
            path.write_text(json.dumps(profile, indent=2) + '\n')
            functions = profile['functions']
            def compact(function):
                reference = function['function']
                owner = reference.get('owner', {}).get('name', '')
                name = reference.get('name', '')
                return {
                    'name': f'{owner}.{name}' if owner else name,
                    'kind': function['kind'],
                    'inclusiveTicks': int(function.get('inclusiveTicks', 0)),
                    'exclusiveTicks': int(function.get('exclusiveTicks', 0)),
                    'source': function.get('resolvedUrl', ''),
                }

            functions = [compact(function) for function in functions]
            component_path = str(Path(__file__).resolve().parents[1] / 'lib')
            summary = {
                'operation': args.operation,
                'sampleCount': profile['sampleCount'],
                'samplePeriodMicros': profile['samplePeriod'],
                'actionLatencyMs': end['latencyMs'],
                'componentFunctions': sorted((f for f in functions if component_path in f['source']), key=lambda f: f['inclusiveTicks'], reverse=True)[:30],
                'topInclusive': sorted(functions, key=lambda f: int(f.get('inclusiveTicks', 0)), reverse=True)[:30],
                'topExclusive': sorted(functions, key=lambda f: int(f.get('exclusiveTicks', 0)), reverse=True)[:20],
            }
            (output / f'{args.label}-{args.operation}.cpu-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
            print(f'Saved {path}; {profile["sampleCount"]} samples')
            return
        time.sleep(.1)
    raise RuntimeError('Timed out waiting for the requested benchmark action')


if __name__ == '__main__':
    main()
