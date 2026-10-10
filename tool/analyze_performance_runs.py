#!/usr/bin/env python3
"""Validate R2 full-workload repetitions and compare explicit source changes."""
import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path

from compare_benchmarks import MATCH_FIELDS, SDK_FIELDS, require, validate


def read_run(path):
    # R2 retains the R0 workload and selection/text-change invariants, but both
    # variants use the shipped selection optimization (force refresh is false).
    data, cases = validate(path, False)
    require(data.get('processingBudgetPolicy') == 'full-document-preflight-v1',
            f'{path}: current full-document budget policy required')
    require(data.get('phaseTimingsEnabled') is False,
            f'{path}: attribution runs cannot establish latency baselines')
    require(data['editorSha256'] == data['sourceFilesSha256']['lib/src/editor/live_editor.dart'],
            f'{path}: editor hash differs from source manifest')
    require(data.get('runtimeInputsSha256'), f'{path}: dependency/host inputs missing')
    trace_path = path.parent / data['sampleTraceFile']
    trace = trace_path.read_bytes()
    require(hashlib.sha256(trace).hexdigest() == data['sampleTraceSha256'],
            f'{path}: sample trace hash differs')
    pending, completed = {}, {}
    for line in trace.decode().splitlines():
        event = json.loads(line)
        identity = tuple(event[key] for key in ('utf8Bytes', 'budget', 'operation', 'stage', 'index'))
        if event['event'] == 'start':
            require(identity not in pending and identity not in completed,
                    f'{path}: duplicate action {identity}')
            pending[identity] = event
        else:
            require(event['event'] == 'end' and identity in pending,
                    f'{path}: end without start {identity}')
            start = pending.pop(identity)
            require(event['timelineMicros'] >= start['timelineMicros'],
                    f'{path}: reversed action timestamps')
            require('phases' not in event, f'{path}: attribution mixed into latency trace')
            completed[identity] = event
    require(not pending, f'{path}: unfinished actions in trace')
    for (size, budget), operations in cases.items():
        trace_budget = 'unlimited' if budget == 'unlimited-controlled-corpus' else budget
        for name, operation in operations.items():
            for stage, count in (('warmup', data['warmupPerOperation']), ('sample', data['samplesPerOperation'])):
                events = [completed.get((size, trace_budget, name, stage, index)) for index in range(count)]
                require(all(events), f'{path}: missing {stage} actions for {size}/{budget}/{name}')
                actual_count = sum(identity[:4] == (size, trace_budget, name, stage) for identity in completed)
                require(actual_count == count, f'{path}: extra actions for {size}/{budget}/{name}')
                if stage == 'sample':
                    for metric in ('latencyMs', 'documentParses', 'rssMiB'):
                        require([event[metric] for event in events] == operation[metric]['raw'],
                                f'{path}: trace disagrees with {size}/{budget}/{name}/{metric}')
    return data, cases


def compare_environment(reference, current, label, allowed_source_changes):
    excluded = {'sourceFilesSha256', 'editorSha256'}
    for field in (*MATCH_FIELDS, 'processingBudgetPolicy', 'phaseTimingsEnabled', 'runtimeInputsSha256'):
        if field in excluded:
            continue
        require(reference[field] == current[field], f'{label}: unmatched {field}')
    for field in SDK_FIELDS:
        require(reference['flutter'][field] == current['flutter'][field], f'{label}: unmatched SDK {field}')
    def workloads(data):
        return [{key: value for key, value in case.items() if key != 'operations'} for case in data['results']]
    require(workloads(reference) == workloads(current), f'{label}: workload or fallback behavior differs')
    old, new = reference['sourceFilesSha256'], current['sourceFilesSha256']
    changed = {name for name in old.keys() | new.keys() if old.get(name) != new.get(name)}
    require(changed == allowed_source_changes,
            f'{label}: source differences {sorted(changed)} do not match declared changes {sorted(allowed_source_changes)}')


def analyze(baseline_paths, candidate_paths=(), changed_sources=()):
    require(len(baseline_paths) >= 2, 'At least two fresh-process full baselines required')
    require(not candidate_paths or len(candidate_paths) >= 2,
            'At least two fresh-process full candidate runs required')
    require(candidate_paths or not changed_sources, 'Source changes require candidate runs')
    baseline = [read_run(path) for path in baseline_paths]
    candidate = [read_run(path) for path in candidate_paths]
    reference = baseline[0][0]
    for path, (data, _) in zip(baseline_paths, baseline):
        compare_environment(reference, data, str(path), set())
    if candidate:
        for path, (data, _) in zip(candidate_paths, candidate):
            compare_environment(reference, data, str(path), set(changed_sources))
            compare_environment(candidate[0][0], data, str(path), set())
    intervals = sorted((datetime.fromisoformat(data['runStartedAtUtc']),
                        datetime.fromisoformat(data['runFinishedAtUtc']), str(path))
                       for path, (data, _) in zip([*baseline_paths, *candidate_paths], [*baseline, *candidate]))
    for index, (start, end, path) in enumerate(intervals):
        require(start < end, f'{path}: invalid run interval')
        if index:
            require(start > intervals[index - 1][1], f'{path}: overlapping or duplicate runs')
    if candidate:
        require(max(datetime.fromisoformat(data['runFinishedAtUtc']) for data, _ in baseline) <
                min(datetime.fromisoformat(data['runStartedAtUtc']) for data, _ in candidate),
                'Baselines must finish before candidate measurements')
    rows = []
    for (size, budget), operations in baseline[0][1].items():
        for name in operations:
            before = [cases[(size, budget)][name] for _, cases in baseline]
            after = [cases[(size, budget)][name] for _, cases in candidate]
            p95s = [operation['latencyMs']['p95'] for operation in before]
            low, high = min(p95s), max(p95s)
            require(low > 0, 'Frame-completion latency must be positive')
            spread = (high - low) / low
            watch = math.ceil(high * max(1.25, 1 + 2 * spread))
            candidate_p95s = [operation['latencyMs']['p95'] for operation in after]
            rows.append({
                'utf8Bytes': size, 'budget': budget, 'operation': name,
                'baselineP95Ms': p95s, 'baselineP95RelativeSpread': spread,
                'sameEnvironmentWatchP95Ms': watch,
                'candidateP95Ms': candidate_p95s,
                'exceedsBaselineWatch': any(value > watch for value in candidate_p95s),
                'baseline': [{metric: operation[metric] for metric in ('latencyMs', 'buildMs', 'rasterMs', 'rssMiB')}
                             for operation in before],
                'candidate': [{metric: operation[metric] for metric in ('latencyMs', 'buildMs', 'rasterMs', 'rssMiB')}
                              for operation in after],
            })
    return {
        'schema': 1, 'baselineRuns': len(baseline), 'candidateRuns': len(candidate),
        'fullWorkloadValidation': 'passed',
        'deterministicGates': {'selectionBoth': 0, 'typingBoth': 1},
        'changedSources': sorted(changed_sources),
        'environment': {field: reference[field] for field in (*MATCH_FIELDS, 'processingBudgetPolicy', 'runtimeInputsSha256')
                        if field not in {'sourceFilesSha256', 'editorSha256'}},
        'flutter': {field: reference['flutter'][field] for field in SDK_FIELDS},
        'runs': [{'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                  'revision': data.get('revision'), 'trackedDiffSha256': data.get('trackedDiffSha256'),
                  'sourceFilesSha256': data['sourceFilesSha256']}
                 for path, (data, _) in zip([*baseline_paths, *candidate_paths], [*baseline, *candidate])],
        'watchRule': 'max baseline P95 * max(1.25, 1 + 2 * relative spread), rounded up; same-environment investigation line, not a portable CI latency target',
        'rows': rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', action='append', type=Path, required=True)
    parser.add_argument('--candidate', action='append', type=Path, default=[])
    parser.add_argument('--changed-source', action='append', default=[])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.baseline, args.candidate, args.changed_source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    regressions = sum(row['exceedsBaselineWatch'] for row in result['rows'])
    print(f"Validated {result['baselineRuns']} baseline and {result['candidateRuns']} candidate runs; {len(result['rows'])} operation rows; {regressions} exceed the baseline observation line")
    if regressions:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
