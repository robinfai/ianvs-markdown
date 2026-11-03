import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import capture_local_cpu as capture


class CpuCaptureTest(unittest.TestCase):
    def test_counts_actual_stacks_once_per_recursive_sample(self):
        profile = dict(functions=[dict(function=dict(name=str(i)), kind='Dart',
                                      inclusiveTicks=999, exclusiveTicks=999)
                                  for i in range(3)],
                       samples=[dict(stack=[0, 1, 1, 2]), dict(stack=[1, 2]), dict(stack=[])])
        summary = capture.summarize_functions(profile)
        self.assertEqual([f['inclusiveTicks'] for f in summary], [1, 2, 2])
        self.assertEqual([f['exclusiveTicks'] for f in summary], [1, 1, 0])

    def test_all_samples_waits_for_complete_run_before_vm_queries(self):
        self.run_capture(invalid=False)

    def test_invalid_run_is_never_extracted(self):
        self.run_capture(invalid=True)

    def run_capture(self, invalid):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'source'
            source.mkdir()
            (source / 'diagnostic.json').write_text(json.dumps(dict(vmService='http://127.0.0.1:1/', entry='app')))
            result = source / 'result.json'
            result.write_text(json.dumps(dict(complete=False, errors=[])))
            events = [dict(event='end', stage='sample', operation='save', index=i,
                           timelineStartMicros=10+i*10, timelineEndMicros=20+i*10,
                           nextFrameMs=10) for i in range(20)]
            (source / 'trace.jsonl').write_text('\n'.join(map(json.dumps, events)))
            calls = []

            def request(url, timeout):
                method = url.split('/')[-1].split('?')[0]
                calls.append(method)
                if method == 'getCpuSamples':
                    self.assertTrue(json.loads(result.read_text())['complete'])
                    value = dict(sampleCount=0, samplePeriod=1000, samples=[], functions=[])
                elif method == 'getVMTimelineMicros':
                    value = dict(timestamp=0)
                elif method == 'getVM':
                    value = dict(isolates=[dict(name='main', id='main')])
                else:
                    value = {}
                return io.BytesIO(json.dumps(dict(result=value)).encode())

            def finish(_):
                self.assertNotIn('getCpuSamples', calls)
                result.write_text(json.dumps(dict(complete=not invalid, errors=['lost focus'] if invalid else [])))

            args = ['capture', '--source', str(source), '--output', str(Path(temp)/'output'),
                    '--operations', 'save', '--all-samples']
            with patch('sys.argv', args), patch.object(capture, 'urlopen', request), patch.object(capture.time, 'sleep', finish), patch('sys.stdout', io.StringIO()):
                if invalid:
                    with self.assertRaisesRegex(RuntimeError, 'invalid'):
                        capture.main()
                    self.assertNotIn('getCpuSamples', calls)
                else:
                    capture.main()
                    self.assertEqual(calls.count('getCpuSamples'), 20)
                    self.assertEqual(len(list((Path(temp)/'output').glob('*.cpu.json'))), 20)


if __name__ == '__main__':
    unittest.main()
