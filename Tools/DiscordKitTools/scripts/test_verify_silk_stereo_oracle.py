# File: Tools/DiscordKitTools/scripts/test_verify_silk_stereo_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic stereo verifier checks; no compiler, native codec, archive or network."""
import json
from pathlib import Path
import unittest
import verify_silk_stereo_oracle as verifier


class SILKStereoVerifierTests(unittest.TestCase):
    """Protect complete literal PCM evidence, state-stress inputs and packet packing."""

    def test_literal_evidence_dimensions_and_all_directed_rate_transitions(self):
        """Fixtures cover all durations and every rate direction with exact stereo dimensions."""
        fixtures = verifier.committed_fixtures(Path(__file__).resolve().parents[3])
        self.assertEqual(len(fixtures), 7)
        durations, directions, channel_directions = set(), set(), set()
        for item, expected in fixtures:
            self.assertEqual(len(item['packets']), len(expected))
            previous = None
            for packet, output in zip(item['packets'], expected):
                ms = [10, 20, 40, 60][(packet[0] >> 3) % 4]
                self.assertEqual(len(output['pcm']), ms * 96)
                durations.add(ms)
                current = (packet[0] >> 5, 1 + ((packet[0] >> 2) & 1))
                self.assertEqual(len(output['activity'][0]), current[1])
                if previous:
                    if previous[0] != current[0]: directions.add((previous[0], current[0]))
                    if previous[1] != current[1]: channel_directions.add((previous[1], current[1]))
                previous = current
        self.assertEqual(durations, {10, 20, 40, 60})
        self.assertEqual(directions, {(a, b) for a in range(3) for b in range(3) if a != b})
        # The regular fixtures and derived recovery stream may collapse to mono;
        # the generator corpus explicitly requests both directions as well.
        self.assertEqual(channel_directions, {(1, 2), (2, 1)})

    def test_generator_requests_are_deterministic_and_cover_transition_policy(self):
        """Each rate/FEC/variant has five duration policies and a 24-packet transition stream."""
        values = verifier.generator_requests(4)
        self.assertEqual(len(values), 144)
        self.assertEqual(values, verifier.generator_requests(4))
        self.assertEqual({p for _, _, _, _, p in values}, set(range(6)))
        self.assertTrue(all(n == (24 if p == 5 else 8) for _, _, n, _, p in values))

    def test_payload_extraction_preserves_stereo_toc(self):
        """Unpacking retains the stereo bit while excluding declared padding and headers."""
        self.assertEqual(verifier.single_payload([12, 1, 2]), (12, [1, 2]))
        self.assertEqual(verifier.single_payload([15, 0xc1, 2, 1, 2, 99, 255]), (12, [1, 2]))
        for packet in [[], [128], [1], [2], [3], [3, 2], [3, 0x41, 99]]:
            with self.assertRaises(RuntimeError): verifier.single_payload(packet)

    def test_every_pcm_range_bit_and_channel_flag_participates_in_comparison(self):
        """Any changed scalar or channel/header bit causes independent evidence failure."""
        expected = [[dict(pcm=[0, 1], ranges=[42], bits=[17], activity=[[[True], [False]]], redundancy=[[[False], [True]]])]]
        verifier.compare_results([{}], expected, expected, 4)
        for field in ['pcm', 'ranges', 'bits', 'activity', 'redundancy']:
            actual = json.loads(json.dumps(expected))
            if field in ['activity', 'redundancy']:
                actual[0][0][field][0][1][0] = not actual[0][0][field][0][1][0]
            else: actual[0][0][field][0] += 1
            with self.assertRaises(RuntimeError): verifier.compare_results([{}], expected, actual, 4)


if __name__ == '__main__':
    unittest.main()
