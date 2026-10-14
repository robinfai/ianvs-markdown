import copy
import unittest

from analyze_local_performance import COMMON, SIZES, stats, validate_data


def fixture():
    window = dict(active=True, visible=True, occlusionVisible=True, onActiveSpace=True,
                  miniaturized=False, appHidden=False, x=100, y=100, width=1180, height=780,
                  scale=2, screen=1, generation=0)
    data = dict(schemaVersion=1, protocol='r4-main-entry-v1', complete=True, errors=[],
                entry='example', main='example/lib/main.dart', buildMode='profile', budget='default',
                corpusVersion=1, warmup=5, samples=20, initialWindow=window,
                cases=[dict(bytes=n, utf16Units=n-20, useMarkdown=n==10240,
                            exceeded=None if n==10240 else 'syntaxTokens', readingBytes=min(n, 65536)) for n in SIZES],
                records=[])
    trace = []
    def emit(value):
        trace.append(dict(sequence=len(trace), **value))
    frame = 1
    for n in SIZES:
        for op in COMMON:
            emit(dict(event='group', bytes=n, operation=op))
            for stage, count in (('warmup', 5), ('sample', 20)):
                for i in range(count):
                    identity = dict(bytes=n, operation=op, stage=stage, index=i)
                    emit(dict(**identity, event='start', window=copy.deepcopy(window), atUtc='2026-10-13T00:00:00Z'))
                    mode = 'preview' if op == 'sourceToRead' else 'livePreview' if op in ('liveType', 'livePaste', 'readToLive', 'liveTail') else 'source'
                    r = dict(**identity, callbackMs=2., nextFrameMs=5., frameWaitMs=3., rssMiB=100.,
                             firstFrameNumber=frame, lastFrameNumber=frame+2,
                             firstFrameMicros=frame, lastFrameMicros=frame+2, sourcePreserved=True,
                             mode=mode, window=copy.deepcopy(window))
                    if op.endswith('Tail'):
                        r['tailPasses'] = 3
                    emit(dict(**copy.deepcopy(r), event='end', atUtc='2026-10-13T00:00:01Z'))
                    r['frames'] = [dict(frameNumber=frame+1, vsyncMicros=frame+1, buildMs=1., rasterMs=.5, totalMs=1.5)]
                    data['records'].append(r)
                    frame += 10
    return data, trace


class LocalPerformanceValidationTest(unittest.TestCase):
    def setUp(self):
        self.data, self.trace = fixture()

    def test_accepts_full_workload(self):
        self.assertEqual(len(validate_data(self.data, self.trace)), 675)

    def test_rejects_attribution_protocol(self):
        self.data['protocol'] = 'r4-attribution-only-v1'
        with self.assertRaisesRegex(ValueError, 'protocol'):
            validate_data(self.data, self.trace)

    def test_rejects_missing_sample(self):
        self.data['records'].pop()
        with self.assertRaisesRegex(ValueError, 'samples'):
            validate_data(self.data, self.trace)

    def test_rejects_duplicate_sample(self):
        self.data['records'].append(copy.deepcopy(self.data['records'][0]))
        with self.assertRaisesRegex(ValueError, 'samples'):
            validate_data(self.data, self.trace)

    def test_rejects_loss_and_regain_between_samples(self):
        self.trace[1]['window']['generation'] = 2
        with self.assertRaisesRegex(ValueError, 'Window changed'):
            validate_data(self.data, self.trace)

    def test_rejects_trace_tampering(self):
        self.trace[2]['callbackMs'] = 20
        with self.assertRaisesRegex(ValueError, 'disagree'):
            validate_data(self.data, self.trace)

    def test_rejects_frame_from_preparation(self):
        self.data['records'][0]['frames'][0]['frameNumber'] = 0
        with self.assertRaisesRegex(ValueError, 'attribution'):
            validate_data(self.data, self.trace)

    def test_uses_frame_identity_despite_clock_rounding(self):
        self.data['records'][0]['frames'][0]['vsyncMicros'] += 2
        self.assertEqual(len(validate_data(self.data, self.trace)), 675)

    def test_rejects_frame_after_measured_completion(self):
        self.data['records'][0]['frames'][0]['frameNumber'] = 4
        with self.assertRaisesRegex(ValueError, 'attribution'):
            validate_data(self.data, self.trace)

    def test_rejects_no_raster_evidence(self):
        self.data['records'][0]['frames'] = []
        with self.assertRaisesRegex(ValueError, 'frame evidence'):
            validate_data(self.data, self.trace)

    def test_rejects_old_independent_main(self):
        self.data['main'] = 'benchmark/live_editor_benchmark.dart'
        with self.assertRaisesRegex(ValueError, 'main'):
            validate_data(self.data, self.trace)

    def test_rejects_partial_even_with_all_samples(self):
        self.data['complete'] = False
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            validate_data(self.data, self.trace)

    def test_nearest_rank_p95_uses_nineteenth_of_twenty(self):
        self.assertEqual(stats(list(range(1, 21)))['p95'], 19)


if __name__ == '__main__':
    unittest.main()
