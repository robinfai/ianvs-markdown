import copy
import unittest
from compare_local_performance import compare_environment, compare_rows
from analyze_local_performance import SIZES


class PairValidationTest(unittest.TestCase):
    def fixture(self):
        data = {k: 'fixed' for k in ('entry', 'main', 'protocol', 'buildMode', 'inputKind',
                                   'corpusVersion', 'warmup', 'samples', 'budget', 'display', 'cases')}
        data['initialWindow'] = dict(x=1, y=1, width=1180, height=780, scale=2, screen=1)
        receipt = dict(freeze=dict(sdk='clean', mode='profile', machine='same', inputs={'lib/editor.dart': 'old'}),
                       artifacts={f'corpus-{n}.md': 'same' for n in SIZES})
        return data, receipt, {('sourceType',): {'inputStyle': {'fontSize': 13.5}}}

    def test_source_changes_must_be_explicit(self):
        before = self.fixture()
        after = copy.deepcopy(before)
        after[1]['freeze']['inputs']['lib/editor.dart'] = 'new'
        with self.assertRaisesRegex(ValueError, 'Source differences'):
            compare_environment(before, after, [])
        compare_environment(before, after, ['lib/editor.dart'])

    def test_cannot_change_environment_or_typography(self):
        before = self.fixture()
        mutations = [lambda a: a[0].update(display='other'),
                     lambda a: a[1]['freeze'].update(sdk='patched'),
                     lambda a: a[0]['initialWindow'].update(width=800),
                     lambda a: a[1]['artifacts'].update({'corpus-1048576.md': 'new'}),
                     lambda a: a[2][('sourceType',)]['inputStyle'].update(fontSize=12),
                     lambda a: a[1]['freeze'].update(attributionOnly=True)]
        for mutation in mutations:
            after = copy.deepcopy(before)
            mutation(after)
            with self.assertRaises(ValueError):
                compare_environment(before, after, [])

    def rows(self):
        return [dict(entry='example', bytes=1048576, operation=op,
                     runs=[{'nextFrameMs': {'p95': 100}}, {'nextFrameMs': {'p95': 110}}],
                     nextFrameObservationLineMs=132) for op in ('readToLive', 'sourceType')]

    def test_both_repetitions_must_meet_target(self):
        before, after = self.rows(), self.rows()
        target = dict(entry='example', bytes=1048576, operation='readToLive', p95MaxMs=80)
        after[0]['runs'] = [{'nextFrameMs': {'p95': 70}}, {'nextFrameMs': {'p95': 81}}]
        result = compare_rows(before, after, [target])
        self.assertFalse(result[0]['passed'])
        after[0]['runs'][1]['nextFrameMs']['p95'] = 80
        self.assertTrue(all(r['passed'] for r in compare_rows(before, after, [target])))
        after[1]['runs'][1]['nextFrameMs']['p95'] = 133
        self.assertFalse(compare_rows(before, after, [target])[1]['passed'])

    def test_rejects_deleted_scenes_or_unknown_targets(self):
        rows = self.rows()
        target = dict(entry='example', bytes=1048576, operation='unknown', p95MaxMs=80)
        with self.assertRaisesRegex(ValueError, 'target'):
            compare_rows(rows, rows, [target])
        with self.assertRaisesRegex(ValueError, 'Scene'):
            compare_rows(rows, rows[:1], [target])


if __name__ == '__main__':
    unittest.main()
