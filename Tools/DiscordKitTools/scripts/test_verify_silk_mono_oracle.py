# File: Tools/DiscordKitTools/scripts/test_verify_silk_mono_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic mono packet verifier tests; no archive, compiler, native library or network."""
import json
from pathlib import Path
import unittest
import verify_silk_mono_oracle as verifier


class SILKMonoVerifierTests(unittest.TestCase):
    """Validate literal PCM, deterministic native requests and packet boundary tooling."""

    def test_fixtures_cover_rates_durations_and_all_redundancy_sizes(self):
        """Committed literals contain all rates/durations and real one/two/three-frame FEC syntax."""
        fixtures = verifier.committed_fixtures(Path(__file__).resolve().parents[3])
        self.assertEqual(len(fixtures), 7)
        self.assertEqual({i['rate'] for i, _ in fixtures}, {8000, 12000, 16000})
        durations = set()
        redundant_sizes = set()
        for item, expected in fixtures:
            self.assertEqual(len(item['packets']), len(expected))
            for packet, output in zip(item['packets'], expected):
                self.assertEqual(len(output['pcm']), [480, 960, 1920, 2880][(packet[0] >> 3) % 4])
                durations.add(len(output['pcm']) // 48)
                for flags in output['redundancy']:
                    if any(flags):
                        redundant_sizes.add(len(flags))
        self.assertEqual(durations, {10, 20, 40, 60})
        self.assertEqual(redundant_sizes, {1, 2, 3})
        silent = fixtures[-1][1]
        self.assertTrue(all(not any(flags) for packet in silent for flags in packet['activity']))
        self.assertTrue(all(abs(sample) <= 2 for packet in silent for sample in packet['pcm']))

    def test_requests_are_deterministic_and_cover_all_policies(self):
        """Five duration policies, all rates and both FEC settings remain independent streams."""
        values = verifier.generator_requests(3)
        self.assertEqual(len(values), 90)
        self.assertEqual(values, verifier.generator_requests(3))
        self.assertEqual({(r, f, p) for r, f, _, _, p in values},
                         {(r, f, p) for r in (8000, 12000, 16000) for f in (0, 1) for p in range(5)})
        self.assertTrue(all(n == 8 and 0 <= v <= 2 for _, _, n, v, _ in values))

    def test_command_streams_keep_full_packet_headers_and_boundaries(self):
        """A mixed stream retains TOC and packet boundaries while preserving zero byte values."""
        item = dict(rate=8000, packets=[[0, 255], [3, 1, 0]])
        self.assertEqual(verifier.commands([item]), b'8000 2\n2 0 255\n3 3 1 0\n')

    def test_generator_payload_extraction_bounds_padding(self):
        """Code-zero/code-three extraction excludes only declared headers and trailing padding."""
        self.assertEqual(verifier.single_payload([8, 1, 2]), (8, [1, 2]))
        self.assertEqual(verifier.single_payload([11, 1, 1, 2]), (8, [1, 2]))
        self.assertEqual(verifier.single_payload([11, 0xc1, 2, 1, 2, 99, 255]), (8, [1, 2]))
        self.assertEqual(verifier.single_payload([11, 0x41, 255, 0] + [1] + [0] * 254), (8, [1]))
        for packet in [[], [128], [4], [1], [2], [3], [3, 2], [3, 0x41], [3, 0x41, 99]]:
            with self.assertRaises(RuntimeError):
                verifier.single_payload(packet)

    def test_lengths_cover_single_double_and_maximum_fields(self):
        """Boundary values preserve normative RFC 6716 length encoding and reject excess."""
        for value in [0, 1, 251, 252, 253, 254, 255, 256, 1274, 1275]:
            encoded = verifier.length_bytes(value)
            self.assertEqual(encoded[0] if len(encoded) == 1 else encoded[0] + 4 * encoded[1], value)
        for value in [-1, 1276]:
            with self.assertRaises(ValueError):
                verifier.length_bytes(value)

    def test_repackings_cover_codes_padding_and_duration_limit(self):
        """Repacking inputs include all packing modes, code-three VBR/padding and 12-by-10ms."""
        generated = [dict(rate=r, packets=[[toc, 7]] * 8) for r, toc in [(8000, 0), (12000, 32), (16000, 64)]]
        repacked = verifier.repacked_inputs(generated)
        self.assertEqual(len(repacked), 6)
        self.assertEqual({p[0] & 3 for item in repacked for p in item['packets']}, {0, 1, 2, 3})
        self.assertEqual(repacked[0]['packets'][-1], [3, 12] + [7] * 12)
        self.assertTrue(any(p[0] & 3 == 3 and p[1] == 0xc2 for item in repacked for p in item['packets']))

    def test_every_pcm_range_and_flag_is_part_of_comparison(self):
        """A one-sample, one-bit, one-range or one-header difference cannot pass evidence."""
        expected = [[dict(pcm=[0, 1], ranges=[42], bits=[17], activity=[[True]], redundancy=[[False]])]]
        verifier.compare_results([{}], expected, expected, 3)
        for field in ['pcm', 'ranges', 'bits', 'activity', 'redundancy']:
            actual = json.loads(json.dumps(expected))
            if field in ['activity', 'redundancy']:
                actual[0][0][field][0][0] = not actual[0][0][field][0][0]
            else:
                actual[0][0][field][0] += 1
            with self.assertRaises(RuntimeError):
                verifier.compare_results([{}], expected, actual, 3)


if __name__ == '__main__':
    unittest.main()
