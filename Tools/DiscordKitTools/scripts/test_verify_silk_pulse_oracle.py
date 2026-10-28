# File: Tools/DiscordKitTools/scripts/test_verify_silk_pulse_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic verifier tests; no compiler, archive, network, native codec or subprocess."""

import copy
from pathlib import Path
import unittest

import verify_silk_pulse_oracle as verifier


class SILKPulseVerifierTests(unittest.TestCase):
    """Validate deterministic fixture/case generation and fail-closed comparisons."""

    def test_committed_fixtures_cover_contexts_and_lengths(self):
        """Read actual independent literals and cover all signal/offset/length values."""
        fixtures = verifier.committed_fixtures(Path(__file__).resolve().parents[3])
        self.assertEqual(len(fixtures), 11)
        self.assertEqual({f["signal"] for f in fixtures}, {0, 1, 2})
        self.assertEqual({f["offset"] for f in fixtures}, {0, 1})
        self.assertEqual({f["sampleCount"] for f in fixtures}, set(verifier.SAMPLE_COUNTS))
        inputs = verifier.fixture_inputs(fixtures)
        for fixture, item in zip(fixtures, inputs):
            self.assertEqual(len(item["pulses"]), item["sampleCount"])
            self.assertEqual(item["pulses"][0], fixture["pattern"][0])

    def test_boundary_inputs_cover_all_contexts(self):
        """Every 10/20ms NB/MB/WB size and six type/offset contexts get five bounds."""
        inputs = verifier.boundary_inputs()
        self.assertEqual(len(inputs), 150)
        self.assertEqual(len({(i["sampleCount"], i["signal"], i["offset"]) for i in inputs}), 30)
        self.assertTrue(all(abs(pulse) <= 127 for i in inputs for pulse in i["pulses"]))
        self.assertTrue(any(all(pulse == 0 for pulse in i["pulses"]) for i in inputs))

    def test_mixed_inputs_are_seeded_and_bounded(self):
        """Identical seeds reproduce varied sparse/dense frames; another seed differs."""
        inputs = verifier.mixed_inputs(40, 67164278)
        self.assertEqual(inputs, verifier.mixed_inputs(40, 67164278))
        self.assertNotEqual(inputs, verifier.mixed_inputs(40, 67164279))
        for item in inputs:
            self.assertIn(item["sampleCount"], verifier.SAMPLE_COUNTS)
            self.assertEqual(len(item["pulses"]), item["sampleCount"])
            self.assertTrue(all(-127 <= p <= 127 for p in item["pulses"]))

    def test_extended_and_arbitrary_inputs_cover_extremes(self):
        """All eleven shifts, both signs and contexts plus zero-byte cases are finite."""
        extended = verifier.extended_inputs()
        self.assertEqual(len(extended), 132)
        self.assertEqual({abs(i["pulses"][0]) for i in extended}, {8 << depth for depth in range(11)})
        self.assertTrue(all(len(i["pulses"]) == 80 for i in extended))
        malformed = verifier.malformed_inputs(42)
        self.assertEqual(malformed, verifier.malformed_inputs(42))
        self.assertEqual(len(malformed), 150)
        self.assertEqual({len(i["bytes"]) for i in malformed}, {0, 1, 2, 7, 64})
        self.assertTrue(all(0 <= byte <= 255 for i in malformed for byte in i["bytes"]))

    def test_commands_keep_encoder_and_decoder_modes_distinct(self):
        """Reference input carries explicit mode/count and preserves arbitrary bytes."""
        cases = [dict(signal=2, offset=1, sampleCount=80, pulses=[0] * 80),
                 dict(signal=0, offset=0, sampleCount=120, bytes=[255, 0, 18])]
        lines = verifier.commands(cases).decode().splitlines()
        self.assertTrue(lines[0].startswith("E 2 1 80 0 "))
        self.assertEqual(lines[1], "D 0 0 120 3 255 0 18")

    def test_output_parser_rejects_incomplete_and_invalid_outputs(self):
        """Wrong counts, malformed JSON, invalid UTF8 or nonobject data cannot pass."""
        self.assertEqual(verifier.parse_outputs(b'{"range":1}\n', 1), [{"range": 1}])
        for output, count in [(b"", 1), (b"bad", 1), (b"\xff", 1), (b"[]\n", 1), (b"{}\n", 2)]:
            with self.assertRaises(RuntimeError):
                verifier.parse_outputs(output, count)

    def test_comparison_detects_counts_bytes_accounting_and_samples(self):
        """Every exact output field and every result count participates in comparison."""
        expected = [{"bytes": [1], "decoded": [-1], "decodeRange": 32, "decodeBits": 4, "decodeFractional": 31}]
        verifier.compare_results([{}], expected, expected, 42)
        for key in expected[0]:
            actual = copy.deepcopy(expected)
            actual[0][key] = [2] if isinstance(actual[0][key], list) else 0
            with self.assertRaisesRegex(RuntimeError, "seed"):
                verifier.compare_results([{}], expected, actual, 42)
        with self.assertRaises(RuntimeError):
            verifier.compare_results([{}], expected, [], 42)

    def test_fixture_comparison_checks_every_literal(self):
        """A changed rate, accounting state, bytes or fixture count invalidates evidence."""
        fixture = dict(rate=0, range=1, bits=2, fractional=9, bytes=[255])
        verifier.compare_fixtures([fixture], [fixture])
        for key in fixture:
            actual = dict(fixture)
            actual[key] = [0] if key == "bytes" else 100
            with self.assertRaises(RuntimeError):
                verifier.compare_fixtures([fixture], [actual])
        with self.assertRaises(RuntimeError):
            verifier.compare_fixtures([fixture], [])


if __name__ == "__main__":
    unittest.main()
