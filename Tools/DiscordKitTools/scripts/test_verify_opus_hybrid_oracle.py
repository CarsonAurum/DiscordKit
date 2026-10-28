# File: Tools/DiscordKitTools/scripts/test_verify_opus_hybrid_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Native-free coverage for both directions of the pinned hybrid codec verifier."""
import copy
import math
from pathlib import Path
import tempfile
import unittest

from verify_opus_hybrid_oracle import (
    TOLERANCE, compare, decoder_commands, encoder_requests, requests, snapshot_sources, validate_encoded, recovery_commands, owned_fec_fixture_text,
)


class HybridOracleTests(unittest.TestCase):
    """Audit independent matrices, packet admission and exact-range/tolerant-float comparisons."""

    def test_reference_matrix_and_variant_admission(self):
        """Reference streams span both channels/bandwidths with LBRR policy variants."""
        cases = requests(4)
        self.assertEqual(len(cases), 16)
        self.assertEqual({case[0] for case in cases}, {1, 2})
        self.assertEqual({case[1] for case in cases}, {1104, 1105})
        self.assertTrue(all(case[2] == 8 for case in cases))
        for invalid in (-1, 0, 3, 21):
            with self.assertRaises(ValueError):
                requests(invalid)

    def test_owned_matrix_and_content(self):
        """Owned streams span both durations/budgets and finite low/high/stereo/quiet content."""
        cases = encoder_requests()
        self.assertEqual(len(cases), 32)
        self.assertEqual({case['channels'] for case in cases}, {1, 2})
        self.assertEqual({case['bandwidth'] for case in cases}, {1104, 1105})
        self.assertEqual({case['samples'] for case in cases}, {480, 960})
        self.assertEqual({case['bytes'] for case in cases}, {256, 512, 640, 1024})
        self.assertEqual({case['fec'] for case in cases}, {False, True})
        self.assertTrue(all(case['bytes'] in ({640, 1024} if case['fec'] else {256, 512}) for case in cases))
        for case in cases:
            self.assertEqual([len(frame) for frame in case['frames']], [case['samples'] * case['channels']] * 8)
            self.assertFalse(any(case['frames'][5]))
            self.assertNotEqual(case['frames'][2], case['frames'][3])
            self.assertTrue(all(math.isfinite(value) and -1 <= value <= 1 for frame in case['frames'] for value in frame))
            if case['channels'] == 2:
                self.assertNotEqual(case['frames'][0][::2], case['frames'][0][1::2])

    def test_compiled_source_snapshot_is_immutable(self):
        """Concurrent workspace edits cannot alter the exact bytes passed to native Swift compilation."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / 'repository'
            for target in ('DiscordMedia', 'DiscordVoiceCodecs'):
                source = repository / 'Sources' / target
                source.mkdir(parents=True)
                (source / 'Value.swift').write_text('let value = 1\n')
                (source / 'local.log').write_text('not source')
            snapshot = snapshot_sources(repository, root)
            (repository / 'Sources/DiscordMedia/Value.swift').write_text('let value = 2\n')
            self.assertEqual((snapshot / 'Sources/DiscordMedia/Value.swift').read_text(), 'let value = 1\n')
            self.assertEqual((snapshot / 'Sources/DiscordVoiceCodecs/Value.swift').read_text(), 'let value = 1\n')
            self.assertFalse((snapshot / 'Sources/DiscordMedia/local.log').exists())

    def test_float_tolerance_and_exact_range(self):
        """Nonfinite values, missing outputs, count errors and range changes cannot pass tolerance."""
        reference = [{'packets': [{'range': 17, 'pcm': [0.1, -0.2]}]}]
        output = [[{'range': 17, 'pcm': [0.1 + TOLERANCE / 2, -0.2]}]]
        self.assertLessEqual(compare(reference, output), TOLERANCE)
        invalid = [[], [[]], [[{'range': 18, 'pcm': [0.1, -0.2]}]],
                   [[{'range': 17, 'pcm': []}]], [[{'range': 17, 'pcm': [0.1 + TOLERANCE * 2, -0.2]}]]]
        for item in invalid:
            with self.assertRaises(RuntimeError):
                compare(reference, item)
        for value in (float('nan'), float('inf'), -float('inf')):
            with self.assertRaises(RuntimeError):
                compare(reference, [[{'range': 17, 'pcm': [value, -0.2]}]])
            with self.assertRaises(RuntimeError):
                compare([{'packets': [{'range': 17, 'pcm': [value, -0.2]}]}], output)

    def test_owned_packet_admission_and_decoder_serialization(self):
        """Fixed framing/budgets/dimensions are checked before using an independent native decoder."""
        request = dict(channels=1, bandwidth=1104, samples=480, bytes=65, frames=[[0] * 480])
        stream = dict(channels=1, packets=[dict(bytes=[96] + [0] * 64, pcm=[0] * 480, range=1)])
        validate_encoded([request], [stream])
        commands = decoder_commands([stream]).decode().splitlines()
        self.assertEqual(commands[0], '1 1')
        self.assertEqual(commands[1].split()[:2], ['65', '96'])
        self.assertEqual(len(commands[1].split()), 66)
        mutations = [
            lambda item: item.update(channels=2),
            lambda item: item.update(packets=[]),
            lambda item: item['packets'][0].update(bytes=[97] + [0] * 64),
            lambda item: item['packets'][0].update(bytes=[96] + [0] * 63),
            lambda item: item['packets'][0].update(pcm=[]),
        ]
        for mutation in mutations:
            invalid = copy.deepcopy(stream)
            mutation(invalid)
            with self.assertRaises(RuntimeError):
                validate_encoded([request], [invalid])
        with self.assertRaises(RuntimeError):
            validate_encoded([request], [])


    def test_recovery_serialization_and_tolerance(self):
        """Recovery calls serialize explicit FEC; optional scalar PLC comparison bounds remain enforced."""
        stream = dict(channels=2, recoveries=[dict(bytes=[124, 1, 2], samples=960, fec=True)])
        self.assertEqual(recovery_commands([stream]).decode(), '2 1\n960 1 3 124 1 2\n')
        reference = [dict(packets=[dict(range=17, pcm=[0., .5])])]
        actual = [[dict(range=17, pcm=[.005, .5])]]
        self.assertEqual(compare(reference, actual, absolute_tolerance=.006, relative_tolerance=.0001), .005)
        with self.assertRaises(RuntimeError):
            compare(reference, actual)
        with self.assertRaises(RuntimeError):
            compare(reference, [[dict(range=17, pcm=[.007, .5])]], absolute_tolerance=.006, relative_tolerance=.0001)
        request = dict(channels=1, bandwidth=1104, samples=480, bytes=65, fec=True, frames=[[0] * 480])
        selected = dict(channels=1, packets=[dict(bytes=[96] + [0] * 64, pcm=[0] * 480, range=1, lbrr=True)])
        validate_encoded([request], [selected])
        selected['packets'][0]['lbrr'] = False
        with self.assertRaises(RuntimeError):
            validate_encoded([request], [selected])


    def test_owned_fec_native_fixture_rendering(self):
        """Literal FEC fixtures retain native PCM/ranges rather than same-decoder reconstructed expectations."""
        import base64
        import json
        case = dict(fec=True, bytes=640, channels=1, bandwidth=1104, samples=480)
        operation = dict(bytes=[96, 1, 2], fec=True, samples=480, selectedLBRR=True, pcm=[99], range=99)
        native = dict(pcm=[.125], range=17)
        rendered = owned_fec_fixture_text([case], [dict(recoveries=[operation])], [[native]])
        value = json.loads(base64.b64decode(rendered.split('    "', 1)[1].split('"', 1)[0]))
        self.assertEqual(value['operations'][0]['pcm'], [.125])
        self.assertEqual(value['operations'][0]['range'], 17)
        self.assertTrue(value['operations'][0]['selectedLBRR'])
        case['fec'] = False
        self.assertNotIn('    "', owned_fec_fixture_text([case], [dict(recoveries=[operation])], [[native]]))


if __name__ == '__main__':
    unittest.main()
