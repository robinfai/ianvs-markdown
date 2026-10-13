#!/usr/bin/env python3
"""Validate and compare two full repetitions for each real main; never fills gaps."""
import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path

SIZES = (10240, 102400, 1048576)
COMMON = ('sourceType', 'sourcePaste', 'liveType', 'livePaste', 'liveToSource',
          'sourceToRead', 'readToLive', 'sourceTail', 'liveTail')
METRICS = ('callbackMs', 'nextFrameMs', 'frameWaitMs', 'rssMiB')


def require(value, message):
    if not value:
        raise ValueError(message)


def stats(raw):
    require(raw, 'Empty distribution')
    ordered = sorted(raw)
    return {**{name: ordered[math.ceil(len(raw) * p) - 1] for name, p in (('p50', .5), ('p95', .95), ('max', 1))}, 'count': len(raw), 'raw': raw}


def valid_window(s):
    require(isinstance(s, dict), 'Window missing')
    require(all(s.get(k) is True for k in ('active', 'visible', 'occlusionVisible', 'onActiveSpace'))
            and all(s.get(k) is False for k in ('miniaturized', 'appHidden')), 'Inactive window')
    require(all(isinstance(s.get(k), (int, float)) and math.isfinite(s[k]) for k in ('x', 'y', 'width', 'height', 'scale', 'screen', 'generation')), 'Incomplete window snapshot')
    require(s['width'] > 0 and s['height'] > 0 and s['scale'] > 0, 'Bad window size')


def validate_data(data, trace):
    require(data.get('complete') is True and data.get('errors') == [], 'Incomplete/error run')
    require(data.get('schemaVersion') == 1 and data.get('protocol') == 'r4-main-entry-v1', 'Unknown protocol')
    entry = data.get('entry')
    require(entry in ('example', 'app') and data.get('main') == f'{entry}/lib/main.dart', 'Wrong actual main')
    require(data.get('buildMode') in ('profile', 'release') and data.get('budget') == 'default', 'Wrong build/budget')
    require(data.get('corpusVersion') == 1 and data.get('warmup') == 5 and data.get('samples') == 20, 'Workload changed')
    valid_window(data['initialWindow'])
    operations = (*COMMON, 'open', 'save') if entry == 'app' else COMMON
    cases = data['cases']
    require([c['bytes'] for c in cases] == list(SIZES), 'Missing/duplicate corpus sizes')
    require(cases[0]['useMarkdown'] and not cases[-1]['useMarkdown'], 'Normal/fallback coverage missing')
    for c in cases:
        require(c['utf16Units'] > 0 and c['readingBytes'] <= c['bytes'], 'Invalid corpus lengths')
        if not c['useMarkdown']:
            require(c['exceeded'] == 'syntaxTokens' and c['readingBytes'] <= 65536, 'Budget branch changed')
    expected = {(size, op, stage, i) for size in SIZES for op in operations
                for stage, count in (('warmup', 5), ('sample', 20)) for i in range(count)}
    def identity(r):
        return tuple(r[k] for k in ('bytes', 'operation', 'stage', 'index'))
    records = {identity(r): r for r in data['records']}
    require(len(records) == len(data['records']) and set(records) == expected, 'Missing/duplicate samples')
    pending, ends, groups = {}, {}, set()
    for index, event in enumerate(trace):
        require(event.get('sequence') == index, 'Trace sequence missing/duplicated')
        if event['event'] == 'group':
            group = (event['bytes'], event['operation'])
            require(group not in groups, 'Duplicate group')
            groups.add(group)
            continue
        require(event['event'] in ('start', 'end'), 'Unexpected/error event')
        key = identity(event)
        valid_window(event.get('window'))
        require(event['window'] == data['initialWindow'], 'Window changed during run')
        if event['event'] == 'start':
            require(key not in pending and key not in ends and not pending, 'Duplicate/overlapping start')
            pending[key] = event
        else:
            require(key in pending, 'End without start')
            start = pending.pop(key)
            require(event['atUtc'] >= start['atUtc'], 'Reversed event time')
            ends[key] = event
    require(not pending and set(ends) == expected, 'Incomplete trace')
    require(groups == {(n, op) for n in SIZES for op in operations}, 'Missing groups')
    frame_ids = set()
    for key, r in records.items():
        require(all(ends[key].get(k) == v for k, v in r.items() if k != 'frames'), 'Trace/result disagree')
        require(r['sourcePreserved'] is True and r['window'] == data['initialWindow'], 'Integrity/window failed')
        for metric in METRICS:
            require(isinstance(r[metric], (int, float)) and math.isfinite(r[metric]) and r[metric] >= 0, f'Invalid {metric}')
        require(r['nextFrameMs'] > 0 and r['rssMiB'] > 0 and abs(r['nextFrameMs'] - r['callbackMs'] - r['frameWaitMs']) < 1e-6, 'Invalid latency/RSS')
        operation = r['operation']
        mode = 'source'
        if operation in ('liveType', 'livePaste', 'readToLive', 'liveTail', 'open'):
            mode = 'livePreview'
        if operation == 'sourceToRead':
            mode = 'preview'
        require(r['mode'] == mode, f'Wrong mode for {operation}')
        require(r.get('frames'), 'Missing frame evidence')
        for frame in r['frames']:
            stamp = frame['frameNumber']
            require(0 <= r['firstFrameNumber'] < stamp <= r['lastFrameNumber'] and stamp not in frame_ids, 'Frame attribution overlap/outside interval')
            frame_ids.add(stamp)
            require(all(isinstance(frame[m], (int, float)) and math.isfinite(frame[m]) and frame[m] >= 0 for m in ('buildMs', 'rasterMs', 'totalMs')), 'Invalid frame duration')
        if operation.endswith('Tail'):
            require(2 <= r.get('tailPasses', 0) <= 100, 'Unverified tail arrival')
        if operation in ('open', 'save'):
            io = r['ioMs']['read' if operation == 'open' else 'write']
            require(0 <= io <= r['callbackMs'], 'Disk interval outside callback')
    return records


def read_run(folder):
    receipt = json.loads((folder / 'receipt.json').read_text())
    for name, value in receipt['artifacts'].items():
        require(hashlib.sha256((folder / name).read_bytes()).hexdigest() == value, f'Artifact hash mismatch: {name}')
    data = json.loads((folder / 'result.json').read_text())
    trace = [json.loads(line) for line in (folder / 'trace.jsonl').read_text().splitlines()]
    freeze = receipt['freeze']
    require(freeze['complete'] and freeze['sdk']['workingTree'] == 'clean', 'Unverified build/SDK')
    require(all(freeze[k] == data[k] for k in ('sourceRevision', 'inputsDigest')), 'Build/run source mismatch')
    require(hashlib.sha256(json.dumps(freeze['inputs'], sort_keys=True, separators=(',', ':')).encode()).hexdigest() == freeze['inputsDigest'], 'Input digest mismatch')
    require(freeze['mode'] == data['buildMode'], 'Build mode mismatch')
    for n in SIZES:
        require(len((folder / f'corpus-{n}.md').read_bytes()) == n, 'Corpus byte size mismatch')
    records = validate_data(data, trace)
    return data, receipt, records


def analyze(folders):
    runs = [read_run(p) for p in folders]
    require(len(runs) == 4, 'Exactly two repetitions for each main required')
    for _, receipt, _ in runs[1:]:
        for field in ('inputs', 'inputsDigest', 'sdk', 'mode', 'machine', 'builds'):
            require(receipt['freeze'][field] == runs[0][1]['freeze'][field], f'Cross-entry freeze differs: {field}')
    intervals = sorted((datetime.fromisoformat(d['startedAtUtc']), datetime.fromisoformat(d['finishedAtUtc'])) for d, _, _ in runs)
    for i, (start, end) in enumerate(intervals):
        require(start < end and (i == 0 or start > intervals[i-1][1]), 'Overlapping/invalid runs')
    require(len({d['system']['pid'] for d, _, _ in runs}) == 4, 'Each repetition requires a fresh process')
    rows = []
    for entry in ('example', 'app'):
        pair = [run for run in runs if run[0]['entry'] == entry]
        require(len(pair) == 2, f'Two complete {entry} runs required')
        d0, receipt0, r0 = pair[0]
        d1, receipt1, r1 = pair[1]
        for field in ('sourceRevision', 'inputsDigest', 'buildMode', 'inputKind', 'display', 'cases'):
            require(d0[field] == d1[field], f'Unmatched {entry}/{field}')
        for field in ('sdk', 'inputs', 'mode', 'machine', 'builds'):
            require(receipt0['freeze'][field] == receipt1['freeze'][field], f'Unmatched frozen {field}')
        for field in ('x', 'y', 'width', 'height', 'scale', 'screen'):
            require(d0['initialWindow'][field] == d1['initialWindow'][field], f'Unmatched window {field}')
        for n in SIZES:
            name = f'corpus-{n}.md'
            require(receipt0['artifacts'][name] == receipt1['artifacts'][name], 'Unmatched corpus hash')
        for n, op in sorted({(key[0], key[1]) for key in r0}):
            selected = [[r[(n, op, 'sample', i)] for i in range(20)] for r in (r0, r1)]
            summaries = []
            for samples in selected:
                item = {m: stats([s[m] for s in samples]) for m in METRICS}
                for metric in ('buildMs', 'rasterMs', 'totalMs'):
                    item[metric] = stats([f[metric] for s in samples for f in s['frames']])
                if op in ('open', 'save'):
                    item['diskMs'] = stats([s['ioMs']['read' if op == 'open' else 'write'] for s in samples])
                summaries.append(item)
            high = max(s['nextFrameMs']['p95'] for s in summaries)
            rows.append({'entry': entry, 'bytes': n, 'operation': op, 'runs': summaries,
                         'nextFrameObservationLineMs': max(high * 1.2, high + 2)})
    return {'protocol': 'r4-main-entry-v1', 'runs': [str(p) for p in folders], 'valid': True,
            'formalSamples': 2400, 'warmups': 600, 'groupsPerRepetition': {'example': 27, 'app': 33},
            'rows': rows, 'ranking': sorted([{'entry': r['entry'], 'bytes': r['bytes'], 'operation': r['operation'],
                                            'worstP95Ms': max(s['nextFrameMs']['p95'] for s in r['runs'])} for r in rows],
                                           key=lambda r: r['worstP95Ms'], reverse=True)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs', nargs=4, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = analyze(args.runs)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'rows'}, indent=2))


if __name__ == '__main__':
    main()
