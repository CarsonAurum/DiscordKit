# File: Tools/DiscordKitTools/scripts/test_verify_celt_band_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic verifier regression tests: no compiler, source archive or native codec is needed."""
import copy
import json
import math
from pathlib import Path
import unittest

import verify_celt_band_oracle as verifier


class CELTBandVerifierTests(unittest.TestCase):
    """Check deterministic fixture inputs and reject falsified exact/approximate evidence."""

    def setUp(self):
        """Read the committed independent fixture file without executing its Swift declaration."""
        repository = Path(__file__).resolve().parents[3]
        self.records = verifier.fixture_records(repository / verifier.FIXTURE_PATH)
        self.inputs = [record["input"] for record in self.records]
        self.expected = [record["output"] for record in self.records]

    def test_fixed_inputs_and_correct_results(self):
        """Ensure the actual oracle fixtures are reproducible and internally consistent."""
        self.assertEqual(self.inputs, verifier.fixed_cases())
        verifier.compare_results(self.inputs, self.expected, copy.deepcopy(self.expected))
        self.assertEqual(len(self.records), 16)

    def test_seeded_cases_are_admitted_and_repeatable(self):
        """Bound each generated context and verify identical seeds preserve exact inputs."""
        cases = verifier.random_cases(500, 6716)
        self.assertEqual(cases, verifier.random_cases(500, 6716))
        self.assertNotEqual(cases, verifier.random_cases(500, 6717))
        for case in cases:
            self.assertEqual(len(case["x"]), case["n"])
            self.assertLessEqual(sum(x*x for x in case["x"]), 1.001)
            self.assertEqual(case["n"] % case["blocks"], 0)
            self.assertIn(case["spread"], range(4))

    def test_wrong_case_count_rejected(self):
        """Dropped or duplicated output records cannot become a successful comparison."""
        for actual in [[], self.expected[:-1], self.expected+self.expected]:
            with self.assertRaises(RuntimeError):
                verifier.compare_results(self.inputs, self.expected, actual)

    def test_exact_fields_reject_mutation(self):
        """Corrupt every claimed exact comparison independently, including arithmetic state."""
        for key in ["pulses", "bytes", "mask", "decodedMask", "range", "decodedRange"]:
            actual = copy.deepcopy(self.expected)
            if isinstance(actual[0][key], list):
                actual[0][key][0] += 1
            else:
                actual[0][key] += 1
            with self.assertRaises(RuntimeError):
                verifier.compare_results(self.inputs, self.expected, actual)

    def test_float_corruption_and_lengths_rejected(self):
        """Large errors, NaNs, infinities and missing coefficients cannot hide in tolerance."""
        for key in ["coefficients", "decoded"]:
            for bad in [math.nan, math.inf, -math.inf, 1234]:
                actual = copy.deepcopy(self.expected)
                actual[0][key][0] = bad
                with self.assertRaises(RuntimeError):
                    verifier.compare_results(self.inputs, self.expected, actual)
            actual = copy.deepcopy(self.expected)
            actual[0][key].pop()
            with self.assertRaises(RuntimeError):
                verifier.compare_results(self.inputs, self.expected, actual)

    def test_small_float_roundoff_accepted(self):
        """Allow the documented coefficient tolerance without relaxing pulse/byte equality."""
        actual = copy.deepcopy(self.expected)
        actual[0]["coefficients"][0] += 1e-7
        verifier.compare_results(self.inputs, self.expected, actual)

    def test_independent_invariants_rejected(self):
        """Matching falsified outputs still fail codeword and matching decoder state invariants."""
        for key, value in [("pulses", [0]*8), ("range", 0), ("mask", 255)]:
            false_reference = copy.deepcopy(self.expected)
            false_reference[0][key] = value
            with self.assertRaises(RuntimeError):
                verifier.compare_results(self.inputs, false_reference, copy.deepcopy(false_reference))


if __name__ == "__main__":
    unittest.main()
