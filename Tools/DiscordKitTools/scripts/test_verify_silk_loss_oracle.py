# File: Tools/DiscordKitTools/scripts/test_verify_silk_loss_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic scalar loss/FEC verifier checks; no native codec, compiler or network."""
import json
from pathlib import Path
import unittest
import verify_silk_loss_oracle as verifier


class SILKLossVerifierTests(unittest.TestCase):
    """Protect real packet-derived operation coverage and complete scalar evidence."""

    def test_committed_evidence_covers_every_loss_duration_and_output_owner(self):
        """Literal scalar outputs cover all rates, both API layouts, CNG and actual FEC."""
        fixtures = verifier.committed_fixtures(Path(__file__).resolve().parents[3])
        self.assertEqual(len(fixtures), 12)
        self.assertEqual({i['rate'] for i, _ in fixtures}, {8000, 12000, 16000})
        self.assertEqual({(i['channels'], i['generalized']) for i, _ in fixtures}, {(1, False), (1, True), (2, True)})
        durations, modes, available = set(), set(), set()
        for item, expected in fixtures:
            self.assertEqual(len(item['operations']), len(expected))
            for operation, output in zip(item['operations'], expected):
                modes.add(operation['mode'])
                if operation['mode'] == 1:
                    durations.add(operation['ms'])
                    self.assertEqual(len(output['pcm']), operation['ms'] * 48 * item['channels'])
                    self.assertEqual(output['ranges'], [])
                if operation['mode'] == 2:
                    available.update(flag for payload in output['redundancy'] for channel in payload for flag in channel)
                self.assertTrue(all(-32768 <= x <= 32767 for x in output['pcm']))
        self.assertEqual(durations, {10, 20, 40, 60})
        self.assertEqual(modes, {0, 1, 2})
        self.assertEqual(available, {False, True})

    def test_operation_generation_and_commands_preserve_loss_fec_and_boundaries(self):
        """Every authentic stream is independently decoded for both API channel counts."""
        repository = Path(__file__).resolve().parents[3]
        packet = [4, 7, 0]
        generated = [dict(rate=8000, packets=[packet, packet])]
        inputs = verifier.operation_inputs(generated, repository)
        self.assertEqual(len(inputs), 7 + 2 + 6)
        first = next(i for i in inputs if i.get('generalized') and i['channels'] == 2 and i['operations'][0]['packet'])
        self.assertEqual([o['mode'] for o in first['operations']], [0, 1, 1, 1, 1, 2, 0])
        self.assertEqual([o['ms'] for o in first['operations'] if o['mode'] == 1], [10, 20, 40, 60])
        sample = dict(rate=8000, channels=2, generalized=True, operations=[dict(mode=1, ms=20, packet=[]), dict(mode=2, ms=0, packet=packet)])
        self.assertEqual(verifier.commands([sample]), b'8000 2 2\n1 20 0 \n2 0 3 4 7 0\n')
        initial = [i for i in inputs if all(o['mode'] == 1 for o in i['operations'])]
        self.assertEqual(len(initial), 6)

    def test_one_sample_entropy_or_availability_difference_fails_comparison(self):
        """Independent validation rejects every observable PCM or selected-FEC boundary drift."""
        expected = [[dict(pcm=[0, 1], ranges=[42], bits=[17], redundancy=[[[False], [True]]])]]
        verifier.compare_results([{}], expected, expected, 4)
        for field in ['pcm', 'ranges', 'bits', 'redundancy']:
            actual = json.loads(json.dumps(expected))
            if field == 'redundancy': actual[0][0][field][0][1][0] = False
            else: actual[0][0][field][0] += 1
            with self.assertRaises(RuntimeError): verifier.compare_results([{}], expected, actual, 4)


if __name__ == '__main__':
    unittest.main()
