#!/usr/bin/env python3
"""Validate complete matched benchmark pairs and summarize repeated runs."""
import argparse
import hashlib
import json
import math
from pathlib import Path

SIZES = {10240, 102400, 1048576}
BUDGETS = {'default', 'unlimited-controlled-corpus'}
OPERATIONS = {'initialDisplay', 'selection', 'typing', 'scroll', 'liveToSource', 'sourceToReading', 'readingToLive'}
MATCH_FIELDS = (
    'schemaVersion', 'corpusVersion', 'mode', 'warmupPerOperation', 'samplesPerOperation',
    'requestedSizes', 'requestedBudgets', 'requestedOperations', 'dart', 'os', 'host', 'cpu',
    'viewPhysicalWidth', 'viewPhysicalHeight', 'devicePixelRatio', 'sourceFilesSha256',
    'corpusGeneratorSha256', 'harnessSha256', 'runnerSha256', 'editorSha256',
    'frameworkFeatureFileSha256', 'frameworkFeatureDiff', 'experimentalWindowingWorkaround',
    'operationTimeoutSeconds', 'sampleTimeoutSeconds',
)
SDK_FIELDS = ('frameworkVersion', 'frameworkRevision', 'engineRevision', 'dartSdkVersion')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(path, force, selection_only=False):
    data = json.loads(path.read_text())
    require(data.get('schemaVersion') == 2, f'{path}: schema 2 required')
    require(data.get('complete') is True and data.get('fullBaseline') is (not selection_only),
            f'{path}: incomplete or filtered evidence is not a full baseline')
    expected_operations = {'selection'} if selection_only else OPERATIONS
    require(data.get('errors') == [], f'{path}: runtime errors present')
    require(data.get('frameworkPackagePathVerified') is True, f'{path}: SDK path unverified')
    require(data.get('forceDocumentRefresh') is force, f'{path}: wrong comparison variant')
    count = data['samplesPerOperation']
    require(count >= 20 and data['warmupPerOperation'] >= 5, f'{path}: acceptance needs at least 5 warmups and 20 measured samples')
    require(len(data['results']) == 6, f'{path}: expected six cases')
    cases = {}
    for case in data['results']:
        key = (case['utf8Bytes'], case['budget'])
        require(key not in cases, f'{path}: duplicate case {key}')
        operations = {operation['operation']: operation for operation in case['operations']}
        require(set(operations) == expected_operations and len(case['operations']) == len(expected_operations),
                f'{path}: operation coverage differs in {key}')
        for name, operation in operations.items():
            for metric in ('latencyMs', 'documentParses', 'rssMiB', 'buildMs', 'rasterMs'):
                distribution = operation[metric]
                raw = distribution['raw']
                require(raw and distribution['count'] == len(raw), f'{path}: invalid {metric} samples')
                require(all(isinstance(v, (int, float)) and math.isfinite(v) and v >= 0 for v in raw),
                        f'{path}: invalid values in {metric}')
                if metric in ('latencyMs', 'documentParses', 'rssMiB'):
                    require(len(raw) == count, f'{path}: wrong sample count for {key}/{name}/{metric}')
                ordered = sorted(raw)
                for field, quantile in (('p50', .5), ('p95', .95), ('max', 1.0)):
                    expected = ordered[math.ceil(len(ordered) * quantile) - 1]
                    require(distribution[field] == expected, f'{path}: stale {metric}/{field}')
            if name == 'selection':
                require(all(value == int(force) for value in operation['documentParses']['raw']),
                        f'{path}: selection parse-count regression')
            if name == 'typing':
                require(all(value == 1 for value in operation['documentParses']['raw']),
                        f'{path}: text changes must refresh document structure once')
        cases[key] = operations
    require(set(cases) == {(size, budget) for size in SIZES for budget in BUDGETS},
            f'{path}: scenario coverage differs')
    return data, cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', action='append', type=Path, required=True)
    parser.add_argument('--after', action='append', type=Path, required=True)
    parser.add_argument('--selection-before', action='append', type=Path, default=[])
    parser.add_argument('--selection-after', action='append', type=Path, default=[])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(len(args.before) == len(args.after) and len(args.before) >= 1,
            'At least one complete independent pair is required')
    require(len(args.selection_before) == len(args.selection_after), 'Selection repeat pairs must match')
    require(len(args.before) >= 2 or len(args.selection_before) >= 2, 'Require two complete pairs or two focused selection repeat pairs')
    paths = args.before + args.after + args.selection_before + args.selection_after
    require(args.output.resolve() not in {path.resolve() for path in paths}, 'Output must not replace input evidence')
    require(len({hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}) == len(paths),
            'Repeated use of the same evidence is not an independent run')
    reference = None
    started = set()
    runs = []
    rows = {}
    pairs = [(before, after, False) for before, after in zip(args.before, args.after)] + [(before, after, True) for before, after in zip(args.selection_before, args.selection_after)]
    for before_path, after_path, selection_only in pairs:
        before, old_cases = validate(before_path, True, selection_only)
        after, new_cases = validate(after_path, False, selection_only)
        for path, data in ((before_path, before), (after_path, after)):
            if reference is None:
                reference = data
            for field in MATCH_FIELDS:
                if field == 'requestedOperations' and selection_only:
                    require(data[field] == ['selection'], f'{path}: unexpected repeat workload')
                    continue
                require(field in data and data[field] == reference[field], f'{path}: unmatched {field}')
            for field in SDK_FIELDS:
                require(data['flutter'][field] == reference['flutter'][field], f'{path}: unmatched SDK {field}')
            require(data['runStartedAtUtc'] not in started, f'{path}: duplicate run timestamp')
            started.add(data['runStartedAtUtc'])
        runs.append({'before': before_path.name, 'after': after_path.name, 'selectionOnly': selection_only,
                     'beforeSha256': hashlib.sha256(before_path.read_bytes()).hexdigest(),
                     'afterSha256': hashlib.sha256(after_path.read_bytes()).hexdigest()})
        for (size, budget), operations in old_cases.items():
            for name, old in operations.items():
                new = new_cases[(size, budget)][name]
                scope = 'selection-repeat' if selection_only else 'full'
                row = rows.setdefault((size, budget, name, scope), {
                    'utf8Bytes': size, 'budget': budget, 'operation': name, 'scope': scope,
                    'beforeP95Ms': [], 'afterP95Ms': [], 'p95ReductionPercent': [],
                    'afterBuildP95Ms': [], 'afterRasterP95Ms': [], 'afterMaxRssMiB': [],
                })
                old_p95, new_p95 = old['latencyMs']['p95'], new['latencyMs']['p95']
                require(min(old_p95, new_p95) > 0, 'Frame-completion latency must be positive')
                row['beforeP95Ms'].append(old_p95)
                row['afterP95Ms'].append(new_p95)
                row['p95ReductionPercent'].append(100 * (1 - new_p95 / old_p95))
                row['afterBuildP95Ms'].append(new['buildMs']['p95'])
                row['afterRasterP95Ms'].append(new['rasterMs']['p95'])
                row['afterMaxRssMiB'].append(new['rssMiB']['max'])
    for row in rows.values():
        low, high = min(row['afterP95Ms']), max(row['afterP95Ms'])
        spread = (high - low) / low
        row['afterP95RelativeSpread'] = spread
        row['sameEnvironmentWatchP95Ms'] = math.ceil(high * max(1.25, 1 + 2 * spread)) if len(row['afterP95Ms']) >= 2 else None
    summary = {
        'matchedFullPairs': len(args.before), 'selectionRepeatPairs': len(args.selection_before), 'fullBaselineGate': 'passed',
        'deterministicGates': {'selectionBefore': 1, 'selectionAfter': 0, 'typingBoth': 1},
        'runs': runs, 'environment': {field: reference[field] for field in MATCH_FIELDS},
        'flutter': {field: reference['flutter'][field] for field in SDK_FIELDS},
        'watchRule': 'Full and selection-only contexts are summarized separately. max observed optimized P95 * max(1.25, 1 + 2 * relative spread); investigation threshold on the same machine, SDK and workload, not a cross-machine CI limit',
        'rows': [rows[key] for key in sorted(rows)],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(summary, indent=2) + '\n')
    print(f'{len(args.before)} complete pairs and {len(args.selection_before)} selection repeat pairs validated; {len(rows)} operation rows; saved {args.output}')


if __name__ == '__main__':
    main()
