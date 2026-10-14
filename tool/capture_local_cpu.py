#!/usr/bin/env python3
"""Capture CPU attribution from an opt-in actual main; not a latency baseline."""
import argparse
import json
from pathlib import Path
import time
from urllib.parse import urlencode, urlparse
from urllib.request import urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sources = parser.add_mutually_exclusive_group(required=True)
    sources.add_argument('--source', type=Path)
    sources.add_argument('--source-parent', type=Path, help='Wait for a fresh actual-main diagnostic run')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    deadline = time.monotonic() + args.timeout
    if args.source_parent:
        started = time.time()
        while time.monotonic() < deadline:
            fresh = [p for p in args.source_parent.glob('ianvs-r402-*/diagnostic.json') if p.stat().st_mtime >= started]
            if fresh:
                args.source = max(fresh, key=lambda p: p.stat().st_mtime).parent
                print(f'Capturing {args.source}', flush=True)
                break
            time.sleep(.1)
        else:
            raise RuntimeError('Timed out waiting for a new diagnostic run')
    metadata = json.loads((args.source / 'diagnostic.json').read_text())
    uri = metadata['vmService']
    if not uri or urlparse(uri).hostname not in {'127.0.0.1', 'localhost', '::1'}:
        raise ValueError('Only a local VM service is allowed')
    args.output.mkdir(parents=True, exist_ok=False)

    def rpc(method, **parameters):
        with urlopen(uri + method + '?' + urlencode(parameters), timeout=30) as response:
            value = json.load(response)
        if 'error' in value:
            raise RuntimeError(value['error'])
        return value['result']

    rpc('setFlag', name='profiler', value='true')
    enabled_at = rpc('getVMTimelineMicros')['timestamp']
    isolate = next(i['id'] for i in rpc('getVM')['isolates'] if i['name'] == 'main')
    captured = set()
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        trace = args.source / 'trace.jsonl'
        lines = trace.read_text().splitlines() if trace.exists() else []
        for line in lines:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue  # A final line may still be being written.
            if event.get('event') != 'end' or event.get('stage') != 'sample' or event.get('timelineStartMicros', 0) < enabled_at:
                continue
            operation = event['operation']
            if operation in captured:
                continue
            profile = rpc('getCpuSamples', isolateId=isolate,
                          timeOriginMicros=event['timelineStartMicros'],
                          timeExtentMicros=event['timelineEndMicros'] - event['timelineStartMicros'])
            if not profile.get('sampleCount'):
                raise RuntimeError(f'No CPU samples for {operation}')
            profile['action'] = event
            (args.output / f'{operation}.cpu.json').write_text(json.dumps(profile, indent=2) + '\n')
            functions = []
            for item in profile['functions']:
                ref = item['function']
                functions.append(dict(name=ref.get('name'), owner=ref.get('owner', {}).get('name'),
                                      kind=item['kind'], source=item.get('resolvedUrl'),
                                      inclusiveTicks=int(item.get('inclusiveTicks', 0)),
                                      exclusiveTicks=int(item.get('exclusiveTicks', 0))))
            summary = dict(entry=metadata['entry'], operation=operation, sampleCount=profile['sampleCount'],
                           samplePeriodMicros=profile['samplePeriod'], nextFrameMs=event['nextFrameMs'],
                           topInclusive=sorted(functions, key=lambda f: f['inclusiveTicks'], reverse=True)[:40],
                           topExclusive=sorted(functions, key=lambda f: f['exclusiveTicks'], reverse=True)[:30])
            (args.output / f'{operation}.summary.json').write_text(json.dumps(summary, indent=2) + '\n')
            captured.add(operation)
            print(f'{operation}: {profile["sampleCount"]} CPU samples', flush=True)
        if len(captured) == 5:
            return
        time.sleep(.2)
    raise RuntimeError(f'Timed out; captured {sorted(captured)}')


if __name__ == '__main__':
    main()
