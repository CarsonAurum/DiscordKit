"""Hermetic independent-evidence tests; no compiler, archive or network is used."""
import copy
from pathlib import Path
import tempfile
import unittest
import verify_silk_nlsf_oracle as verifier


class SILKNLSFVerifierTests(unittest.TestCase):
    """Check fixture reproducibility, exact comparisons and evidence corruption handling."""

    def setUp(self):
        """Read literal official outputs as JSON without executing Swift declarations."""
        repository = Path(__file__).resolve().parents[3]
        self.records = verifier.fixture_records(repository / verifier.FIXTURE_PATH)
        self.inputs = [r["input"] for r in self.records]
        self.outputs = [r["output"] for r in self.records]

    def test_literal_cases_reproduce(self):
        """Both orders and both independent conversion/gain operations remain represented."""
        self.assertEqual(self.inputs, verifier.fixed_cases())
        self.assertEqual(len(self.inputs), 30)
        self.assertEqual({len(c["values"]) for c in self.inputs}, {10, 16})
        self.assertEqual({c["kind"] for c in self.inputs}, {0, 1})
        verifier.compare_results(self.inputs, self.outputs, copy.deepcopy(self.outputs))

    def test_seeded_inputs_are_bounded_and_repeatable(self):
        """Generator includes clustered/ordinary frequencies and arbitrary Q12 predictors."""
        cases = verifier.random_cases(100, 42)
        self.assertEqual(cases, verifier.random_cases(100, 42))
        self.assertNotEqual(cases, verifier.random_cases(100, 43))
        for case in cases:
            self.assertIn(len(case["values"]), (10, 16))
            if case["kind"] == 0:
                self.assertEqual(case["values"], sorted(case["values"]))
                self.assertTrue(all(0 <= v <= 32767 for v in case["values"]))
            else:
                self.assertTrue(all(-32768 <= v <= 32767 for v in case["values"]))

    def test_missing_or_extra_records_rejected(self):
        """Truncation and duplication cannot hide a failed independent driver."""
        for records in ([], self.outputs[:-1], self.outputs + self.outputs):
            with self.assertRaises(RuntimeError):
                verifier.compare_results(self.inputs, self.outputs, records)

    def test_wrong_exact_results_rejected(self):
        """Even one Q12 coefficient or Q30 gain unit is a failed comparison."""
        for key in ("q12", "gain"):
            values = copy.deepcopy(self.outputs)
            if key == "q12":
                values[0][key][0] += 1
            else:
                values[0][key] += 1
            with self.assertRaises(RuntimeError):
                verifier.compare_results(self.inputs, self.outputs, values)

    def test_mutually_forged_invalid_evidence_rejected(self):
        """Matching NaN/bool/range/schema/length corruption still violates independent invariants."""
        for key, value in (("gain", -1), ("gain", 1 << 31), ("gain", True),
                           ("gain", float("nan")), ("q12", []), ("q12", [32768]*10)):
            values = copy.deepcopy(self.outputs)
            values[0][key] = value
            with self.assertRaises(RuntimeError):
                verifier.compare_results(self.inputs, values, copy.deepcopy(values))
        values = copy.deepcopy(self.outputs)
        del values[0]["gain"]
        with self.assertRaises(RuntimeError):
            verifier.compare_results(self.inputs, values, copy.deepcopy(values))
        values = copy.deepcopy(self.outputs)
        values[9]["q12"][0] = 1
        with self.assertRaises(RuntimeError):
            verifier.compare_results(self.inputs, values, copy.deepcopy(values))

    def test_fixture_loader_requires_valid_literal(self):
        """Missing delimiters and malformed JSON fail rather than evaluating arbitrary source."""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/"fixture.swift"
            path.write_text("invalid")
            with self.assertRaises((ValueError, IndexError)):
                verifier.fixture_records(path)
            path.write_text('#"""[invalid]"""#')
            with self.assertRaises(ValueError):
                verifier.fixture_records(path)


if __name__ == "__main__":
    unittest.main()
