#!/usr/bin/env python3
"""Pair two complete real-main repetitions with R4-02; retain failed targets."""
import argparse
import json
from pathlib import Path

from analyze_local_performance import analyze, read_run, require, SIZES


def compare_environment(before, after, allowed):
    bd, br, brecords = before
    ad, ar, arecords = after
    for key in ('entry', 'main', 'protocol', 'buildMode', 'inputKind', 'corpusVersion',
                'warmup', 'samples', 'budget', 'display', 'cases'):
        require(bd[key] == ad[key], f'Baseline configuration changed: {key}')
    for key in ('sdk', 'mode', 'machine'):
        require(br['freeze'][key] == ar['freeze'][key], f'Baseline environment changed: {key}')
    require(not ar['freeze'].get('attributionOnly', False), 'Attribution build cannot be a candidate')
    for key in ('x', 'y', 'width', 'height', 'scale', 'screen'):
        require(bd['initialWindow'][key] == ad['initialWindow'][key], f'Baseline window changed: {key}')
    for size in SIZES:
        name = f'corpus-{size}.md'
        require(br['artifacts'][name] == ar['artifacts'][name], f'Baseline corpus changed: {size}')
    bi, ai = br['freeze']['inputs'], ar['freeze']['inputs']
    changed = {p for p in bi.keys() | ai.keys() if bi.get(p) != ai.get(p)}
    require(changed == set(allowed), f'Source differences {sorted(changed)} do not match declared changes {sorted(allowed)}')
    for key, old in brecords.items():
        require(old.get('inputStyle') == arecords[key].get('inputStyle'), f'Input typography changed: {key}')
    return sorted(changed)


def compare_rows(baseline, candidate, targets):
    def key(row):
        return row['entry'], row['bytes'], row['operation']
    old = {key(row): row for row in baseline}
    new = {key(row): row for row in candidate}
    limits = {key(row): row['p95MaxMs'] for row in targets}
    require(len(old) == len(baseline) and len(new) == len(candidate) and old.keys() == new.keys(), 'Scene set changed')
    require(len(limits) == len(targets) and limits and limits.keys() <= old.keys(), 'Missing/duplicate/unknown target')
    rows = []
    for identity, row in old.items():
        candidate_p95 = [r['nextFrameMs']['p95'] for r in new[identity]['runs']]
        require(len(candidate_p95) == 2, 'Two candidate repetitions required')
        threshold = limits.get(identity, row['nextFrameObservationLineMs'])
        rows.append(dict(entry=identity[0], bytes=identity[1], operation=identity[2],
                         target=identity in limits, thresholdMs=threshold,
                         baselineP95Ms=[r['nextFrameMs']['p95'] for r in row['runs']],
                         candidateP95Ms=candidate_p95, passed=all(v <= threshold for v in candidate_p95)))
    return rows


def compare(baseline_paths, candidate_paths, allowed, targets):
    baseline = analyze(baseline_paths)
    candidate = analyze(candidate_paths)
    baseline_runs = [read_run(p) for p in baseline_paths]
    candidate_runs = [read_run(p) for p in candidate_paths]
    for current in candidate_runs:
        reference = next(run for run in baseline_runs if run[0]['entry'] == current[0]['entry'])
        compare_environment(reference, current, allowed)
    rows = compare_rows(baseline['rows'], candidate['rows'], targets)
    return dict(protocol='r4-main-entry-paired-v1', valid=True,
                baselineRuns=[str(p) for p in baseline_paths], candidateRuns=[str(p) for p in candidate_paths],
                declaredSourceChanges=sorted(allowed), targets=targets,
                passed=all(row['passed'] for row in rows), rows=rows,
                candidateSummary=candidate)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, nargs=4, required=True)
    parser.add_argument('--candidate', type=Path, nargs=4, required=True)
    parser.add_argument('--allow-source', action='append', default=[])
    parser.add_argument('--targets', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = compare(args.baseline, args.candidate, args.allow_source,
                     json.loads(args.targets.read_text())['targets'])
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('rows', 'candidateSummary')}, indent=2))
    for row in result['rows']:
        if row['target'] or not row['passed']:
            print(json.dumps(row))
    if not result['passed']:
        raise SystemExit('Paired targets/observation lines failed; evidence retained')


if __name__ == '__main__':
    main()
