"""Reject misleading performance evidence before it can close R2-01."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from analyze_performance_runs import analyze
from compare_benchmarks import MATCH_FIELDS, SDK_FIELDS, OPERATIONS, SIZES, BUDGETS


class PerformanceEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.reference = {field: 'same' for field in MATCH_FIELDS}
        self.window = {'active': True, 'visible': True, 'occlusionVisible': True,
                       'onActiveSpace': True, 'miniaturized': False, 'appHidden': False,
                       'generation': 0, 'width': 1180, 'height': 780}
        self.reference.update({
            'schemaVersion': 2, 'complete': True, 'fullBaseline': True, 'errors': [],
            'frameworkPackagePathVerified': True, 'forceDocumentRefresh': False,
            'warmupPerOperation': 5, 'samplesPerOperation': 20,
            'processingBudgetPolicy': 'full-document-preflight-v1', 'phaseTimingsEnabled': False,
            'runtimeInputsSha256': {'pubspec.lock': 'lock'},
            'environmentPolicy': 'native-window-stable-v1', 'initialWindowEnvironment': self.window,
            'sourceFilesSha256': {'lib/src/editor/live_editor.dart': 'original', 'lib/other.dart': 'same'},
            'editorSha256': 'original', 'flutter': {field: 'same' for field in SDK_FIELDS},
            'results': [],
        })
        self.events = []
        for size in sorted(SIZES):
            for budget in sorted(BUDGETS):
                operations = []
                self.reference['results'].append({'utf8Bytes': size, 'budget': budget, 'liveUsesMarkdown': True, 'operations': operations})
                for name in sorted(OPERATIONS):
                    parses = 1 if name == 'typing' else 0
                    metrics = {'latencyMs': 10, 'documentParses': parses, 'rssMiB': 100, 'buildMs': 2, 'rasterMs': 1}
                    operations.append({'operation': name, **{metric: {'count': 20, 'raw': [value] * 20, 'p50': value, 'p95': value, 'max': value}
                                                           for metric, value in metrics.items()}})
                    for stage, count in (('warmup', 5), ('sample', 20)):
                        for index in range(count):
                            identity = {'utf8Bytes': size, 'budget': 'unlimited' if budget.startswith('unlimited') else budget,
                                        'operation': name, 'stage': stage, 'index': index}
                            self.events.extend([
                                {**identity, 'windowEnvironment': self.window, 'event': 'start', 'timelineMicros': 1},
                                {**identity, 'event': 'end', 'timelineMicros': 2, 'latencyMs': 10,
                                 'windowEnvironment': self.window, 'documentParses': parses, 'rssMiB': 100},
                            ])

    def save(self, name, hour, change=None, trace_change=None):
        data = copy.deepcopy(self.reference)
        data.update({'runStartedAtUtc': f'2026-10-10T{hour:02}:00:00+00:00',
                     'runFinishedAtUtc': f'2026-10-10T{hour:02}:10:00+00:00',
                     'sampleTraceFile': name + '.samples.jsonl'})
        events = copy.deepcopy(self.events)
        if trace_change:
            trace_change(events)
        raw = ''.join(json.dumps(event) + '\n' for event in events).encode()
        (self.root / data['sampleTraceFile']).write_bytes(raw)
        data['sampleTraceSha256'] = hashlib.sha256(raw).hexdigest()
        if change:
            change(data)
        path = self.root / (name + '.json')
        path.write_text(json.dumps(data))
        return path

    def baselines(self):
        return [self.save('before1', 1), self.save('before2', 2)]

    def test_repetitions_define_observation_lines(self):
        result = analyze(self.baselines())
        self.assertEqual(len(result['rows']), 42)
        self.assertTrue(all(row['sameEnvironmentWatchP95Ms'] == 13 for row in result['rows']))

    def test_candidates_require_exact_declared_source_changes(self):
        before = self.baselines()
        def optimized(data):
            data['sourceFilesSha256']['lib/src/editor/live_editor.dart'] = 'optimized'
            data['editorSha256'] = 'optimized'
        after = [self.save('after1', 3, optimized), self.save('after2', 4, optimized)]
        with self.assertRaisesRegex(ValueError, 'source differences'):
            analyze(before, after)
        self.assertEqual(analyze(before, after, ['lib/src/editor/live_editor.dart'])['candidateRuns'], 2)

    def test_diagnostics_or_incomplete_coverage_cannot_replace_baseline(self):
        for change in (lambda data: data.update(phaseTimingsEnabled=True),
                       lambda data: data.update(fullBaseline=False),
                       lambda data: data['results'][0]['operations'].pop()):
            with self.subTest(change=change), self.assertRaises(ValueError):
                analyze([self.save('first', 1), self.save('second', 2, change)])

    def test_rejects_dependency_window_or_fallback_changes(self):
        for change in (lambda data: data['runtimeInputsSha256'].update({'pubspec.lock': 'other'}),
                       lambda data: data.update(viewPhysicalWidth=999),
                       lambda data: data['results'][0].update(liveUsesMarkdown=False)):
            with self.subTest(change=change), self.assertRaises(ValueError):
                analyze([self.save('first', 1), self.save('second', 2, change)])

    def test_rejects_duplicate_or_overlapping_processes(self):
        with self.assertRaisesRegex(ValueError, 'overlapping or duplicate'):
            analyze([self.save('first', 1), self.save('second', 1)])

    def test_rejects_tampered_or_inconsistent_sample_trace(self):
        first = self.save('first', 1)
        with self.assertRaisesRegex(ValueError, 'trace hash'):
            analyze([first, self.save('second', 2, lambda data: data.update(sampleTraceSha256='wrong'))])
        def wrong_sample(events):
            event = next(e for e in events if e['stage'] == 'sample' and e['event'] == 'end')
            event['latencyMs'] = 999
        with self.assertRaisesRegex(ValueError, 'trace disagrees'):
            analyze([first, self.save('second', 2, trace_change=wrong_sample)])

    def test_rejects_unfinished_action_even_with_complete_summary(self):
        with self.assertRaisesRegex(ValueError, 'unfinished actions'):
            analyze([self.save('first', 1), self.save('second', 2, trace_change=lambda events: events.pop())])

    def test_rejects_missing_window_evidence(self):
        with self.assertRaisesRegex(ValueError, 'environment policy'):
            analyze([self.save('first', 1), self.save('second', 2, lambda data: data.pop('environmentPolicy'))])
        with self.assertRaisesRegex(ValueError, 'missing native window state'):
            analyze([self.save('first', 1), self.save('second', 2, trace_change=lambda events: events[0].pop('windowEnvironment'))])

    def test_rejects_inactive_hidden_and_transient_environment_changes(self):
        for field, value in (('active', False), ('visible', False), ('occlusionVisible', False),
                             ('onActiveSpace', False), ('miniaturized', True), ('appHidden', True),
                             ('generation', 2), ('width', 1190)):
            def changed(events):
                events[1]['windowEnvironment'] = {**self.window, field: value}
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'window'):
                analyze([self.save('first', 1), self.save('second', 2, trace_change=changed)])

    def test_each_process_may_have_a_different_initial_generation(self):
        def change(data):
            data['initialWindowEnvironment']['generation'] = 7
        def trace_change(events):
            for event in events:
                event['windowEnvironment']['generation'] = 7
        result = analyze([self.save('first', 1), self.save('second', 2, change, trace_change)])
        self.assertEqual(result['baselineRuns'], 2)


if __name__ == '__main__':
    unittest.main()
