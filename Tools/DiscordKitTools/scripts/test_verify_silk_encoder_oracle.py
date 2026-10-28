# File: Tools/DiscordKitTools/scripts/test_verify_silk_encoder_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Native-free regression tests for conservative SILK encoder oracle admission checks."""
import copy
import unittest

from verify_silk_encoder_oracle import requests, validate_encoded, recovery_requests


class SILKEncoderOracleTests(unittest.TestCase):
    """Keep independent matrix coverage, framing and evidence checks from becoming tautologies."""

    def test_all_formats_caps_and_signal_patterns(self):
        """Every rate/duration/channel/cap tuple includes silence and independent stereo input."""
        inputs = requests()
        self.assertEqual(len(inputs), 72)
        self.assertEqual({item["rate"] for item in inputs}, {8000, 12000, 16000})
        self.assertEqual({item["milliseconds"] for item in inputs}, {10, 20})
        self.assertEqual({item["channels"] for item in inputs}, {1, 2})
        self.assertEqual({item["fec"] for item in inputs}, {False, True})
        self.assertEqual({item["cap"] for item in inputs}, {64, 128, 1275})
        for item in inputs:
            count = item["rate"] * item["milliseconds"] // 1000 * item["channels"]
            self.assertEqual([len(frame) for frame in item["frames"]], [count] * 8)
            self.assertFalse(any(item["frames"][0]))
            self.assertFalse(any(item["frames"][-1]))
            self.assertTrue(all(-32768 <= value <= 32767 for frame in item["frames"] for value in frame))
            self.assertNotEqual(item["frames"][1], item["frames"][4])

    def test_validation_rejects_missing_and_invalid_evidence(self):
        """Each independent shape/admission invariant fails even if other evidence is valid."""
        request = dict(rate=8000, milliseconds=10, channels=1, cap=64, frames=[[0] * 80])
        stream = dict(rate=8000, packets=[[0, 0]], rejected=0,
                      decoded=[dict(pcm=[0] * 960, redundancy=[[[False]]])])
        validate_encoded([request], [stream])
        mutations = [
            lambda item: item.update(packets=[]),
            lambda item: item.update(rejected=1),
            lambda item: item.update(decoded=[]),
            lambda item: item.update(packets=[[4, 0]]),
            lambda item: item.update(packets=[[1, 0]]),
            lambda item: item.update(packets=[[8, 0]]),
            lambda item: item.update(packets=[[0] * 66]),
            lambda item: item["decoded"][0].update(pcm=[]),
            lambda item: item["decoded"][0].update(redundancy=[[[True]]]),
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                invalid = copy.deepcopy(stream)
                mutation(invalid)
                with self.assertRaises(RuntimeError):
                    validate_encoded([request], [invalid])
        with self.assertRaises(RuntimeError):
            validate_encoded([request], [])

    def test_recovery_really_omits_each_missing_packet(self):
        """Each API layout selects FEC from the next packet after an independent normal prefix."""
        packets = [[0, 2], [0, 3], [0, 4]]
        inputs = recovery_requests([dict(rate=8000, packets=packets)])
        self.assertEqual(len(inputs), 6)
        self.assertEqual([item["channels"] for item in inputs], [1, 1, 1, 2, 2, 2])
        for offset in (0, 3):
            cold, missing_first, missing_second = inputs[offset:offset + 3]
            self.assertEqual([op["mode"] for op in cold["operations"]], [2, 0])
            self.assertEqual([op["packet"] for op in cold["operations"]], [packets[0], packets[0]])
            self.assertEqual([op["mode"] for op in missing_first["operations"]], [2, 0, 0])
            self.assertEqual([op["packet"] for op in missing_first["operations"]], [packets[1], packets[1], packets[2]])
            self.assertEqual([op["mode"] for op in missing_second["operations"]], [0, 2, 0])
            self.assertEqual([op["packet"] for op in missing_second["operations"]], [packets[0], packets[2], packets[2]])
            self.assertTrue(all(item["generalized"] for item in inputs[offset:offset + 3]))
        self.assertEqual(recovery_requests([]), [])


if __name__ == "__main__":
    unittest.main()
