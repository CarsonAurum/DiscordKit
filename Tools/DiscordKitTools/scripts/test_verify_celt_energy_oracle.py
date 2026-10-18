"""Hermetic CELT energy verifier regressions without a compiler, archive or codec runtime."""
import copy
import json
import math
from pathlib import Path
import unittest
import verify_celt_energy_oracle as verifier


class CELTEnergyVerifierTests(unittest.TestCase):
    """Check independent evidence loading, deterministic contexts and falsification rejection."""

    def setUp(self):
        """Read committed official fixtures as JSON without evaluating their Swift declaration."""
        repository = Path(__file__).resolve().parents[3]
        text = (repository / verifier.FIXTURE_PATH).read_text()
        self.records = json.loads(text.split('#"""', 1)[1].split('"""#', 1)[0])
        self.inputs = [r["input"] for r in self.records]
        self.expected = [r["output"] for r in self.records]

    def test_fixed_cases_and_correct_results(self):
        """Require literal input reproducibility and admission of all independently produced outputs."""
        self.assertEqual(self.inputs, verifier.fixed_cases())
        self.assertEqual(len(self.inputs), 33)
        verifier.compare_results(self.inputs, self.expected, copy.deepcopy(self.expected))
        self.assertEqual({x["lm"] for x in self.inputs}, set(range(4)))
        self.assertEqual({x["c"] for x in self.inputs}, {1, 2})
        self.assertEqual({x["intra"] for x in self.inputs}, {False, True})

    def test_random_cases_are_bounded_repeatable_and_vary(self):
        """Seeded contexts obey shape, budget and successive fine-precision bounds."""
        cases = verifier.random_cases(500, 6716)
        self.assertEqual(cases, verifier.random_cases(500, 6716))
        self.assertNotEqual(cases, verifier.random_cases(500, 6717))
        for case in cases:
            self.assertIn(case["n"], range(1, 22))
            self.assertTrue(0 <= case["start"] < case["end"] <= case["n"])
            self.assertEqual(len(case["old"]), case["n"] * case["c"])
            self.assertEqual(len(case["target"]), case["n"] * case["c"])
            self.assertLessEqual(case["prefix"], max(0, case["bytes"] * 8 - 1))
            for fine, previous in zip(case["fine"], case["previous"]):
                self.assertTrue(0 <= fine + previous <= 8)
            self.assertEqual(len(verifier.commands([case]).splitlines()), 1)

    def test_wrong_case_counts_rejected(self):
        """Dropped, duplicated and missing records cannot pass verification."""
        for values in [[], self.expected[:-1], self.expected + self.expected]:
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, self.expected, values)

    def test_exact_evidence_mutations_rejected(self):
        """Every wire, range, accounting and mode field enforces exact equality."""
        for key in ["bytes", "range", "decodedRange", "bits", "decodedBits", "coarseBits",
                    "coarseRange", "decodedCoarseBits", "decodedCoarseRange", "fineBits",
                    "fineRange", "finalBudget", "intra"]:
            actual = copy.deepcopy(self.expected)
            if key == "bytes":
                actual[0][key][0] ^= 1
            elif key == "intra":
                actual[0][key] = not actual[0][key]
            else:
                actual[0][key] += 1
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, self.expected, actual)

    def test_float_corruption_lengths_and_schema_rejected(self):
        """NaNs/infinities, excessive error, truncated arrays and dropped fields fail closed."""
        for key in ["coarse", "coarseErrors", "fine", "fineErrors", "final", "finalErrors",
                    "decodedCoarse", "decodedFine", "decoded"]:
            for value in [math.nan, math.inf, -math.inf, 1234]:
                actual = copy.deepcopy(self.expected)
                actual[0][key][0] = value
                with self.assertRaises(ValueError):
                    verifier.compare_results(self.inputs, self.expected, actual)
            actual = copy.deepcopy(self.expected)
            actual[0][key].pop()
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, self.expected, actual)
        actual = copy.deepcopy(self.expected)
        del actual[0]["range"]
        with self.assertRaises(ValueError):
            verifier.compare_results(self.inputs, self.expected, actual)

    def test_roundoff_within_documented_tolerance_accepted(self):
        """Admit scalar-float rounding differences without relaxing exact entropy fields."""
        actual = copy.deepcopy(self.expected)
        actual[0]["coarseErrors"][0] += 1e-6
        verifier.compare_results(self.inputs, self.expected, actual)

    def test_mutually_falsified_evidence_violates_invariants(self):
        """Matching fake outputs still fail independent decoder, shape and numeric invariants."""
        for key, value in [("range", 0), ("bytes", []), ("decoded", [42]), ("coarseRange", 1),
                           ("bits", 0), ("finalBudget", -1), ("intra", 1)]:
            false_reference = copy.deepcopy(self.expected)
            false_reference[0][key] = value
            with self.assertRaises(ValueError):
                verifier.compare_results(self.inputs, false_reference, copy.deepcopy(false_reference))


if __name__ == "__main__":
    unittest.main()
