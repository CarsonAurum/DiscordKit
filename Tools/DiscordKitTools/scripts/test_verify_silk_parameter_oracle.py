"""Hermetic parameter oracle workflow tests; no native compiler/archive/network work."""
import json
from pathlib import Path
import unittest
import verify_silk_parameter_oracle as verifier


class SILKParameterVerifierTests(unittest.TestCase):
    """Check fixture provenance inputs, deterministic cases and exact comparison guards."""

    def test_literal_fixtures_cover_all_channel_configurations(self):
        """All internal rates/durations/categories appear in independently encoded literals."""
        fixtures = verifier.committed_fixtures(Path(__file__).resolve().parents[3])
        self.assertEqual(len(fixtures), 18)
        self.assertEqual({i["rate"] for i, _ in fixtures}, {8000, 12000, 16000})
        self.assertEqual({i["milliseconds"] for i, _ in fixtures}, {10, 20})
        self.assertEqual({e["signal"] for _, e in fixtures}, {0, 1, 2})
        for item, expected in fixtures:
            count = item["rate"] * item["milliseconds"] // 1000
            self.assertEqual(len(expected["pulses"]), (count + 15) // 16 * 16)
            self.assertGreater(len(item["bytes"]) * 8, expected["bits"])

    def test_generator_covers_all_modes_and_contexts(self):
        """The official generator receives108 distinct bounded channel configurations."""
        lines = verifier.generator_commands().decode().splitlines()
        self.assertEqual(len(lines), 108)
        self.assertEqual(len(set(lines)), 108)
        self.assertEqual({int(line.split()[4]) for line in lines}, {0, 1, 2})

    def test_boundary_cases_are_finite_and_include_empty_payloads(self):
        """All coding/VAD/LBRR combinations receive four explicit byte boundaries."""
        inputs = verifier.boundary_inputs()
        self.assertEqual(len(inputs), 288)
        self.assertEqual({len(i["bytes"]) for i in inputs}, {0, 1, 64})
        self.assertEqual({i["lbrr"] for i in inputs}, {False, True})
        self.assertEqual({i["vad"] for i in inputs}, {False, True})

    def test_mixed_inputs_are_reproducible_and_within_scalar_state_bounds(self):
        """Random input seeds reproduce bounded previous-gain and signed-lag histories."""
        inputs = verifier.mixed_inputs(100, 67164277)
        self.assertEqual(inputs, verifier.mixed_inputs(100, 67164277))
        self.assertNotEqual(inputs, verifier.mixed_inputs(100, 67164278))
        for item in inputs:
            self.assertTrue(0 <= item["previousGain"] <= 63)
            self.assertTrue(-32768 <= item["previousLag"] <= 32767)
            self.assertTrue(all(0 <= byte <= 255 for byte in item["bytes"]))

    def test_reference_commands_preserve_context_and_signed_history(self):
        """Explicit context fields and zero-length bytes remain distinct from numeric data."""
        item = dict(rate=12000, milliseconds=10, vad=True, lbrr=False, coding=2,
                    previousGain=63, previousType=2, previousLag=-32768, bytes=[255, 0])
        self.assertEqual(verifier.commands([item]), b"12000 10 1 0 2 63 2 -32768 2 255 0\n")

    def test_exact_comparison_rejects_parameter_and_pcm_state_changes(self):
        """Shared exact comparator includes every reconstructed parameter/state field."""
        expected = [dict(nlsfs=[100, 200], gains=[65536], pulses=[-1], completeRange=123)]
        verifier.compare_results([{}], expected, expected, 42)
        changed = json.loads(json.dumps(expected))
        changed[0]["nlsfs"][0] += 1
        with self.assertRaises(RuntimeError):
            verifier.compare_results([{}], expected, changed, 42)
        with self.assertRaises(RuntimeError):
            verifier.parse_outputs(b"{}\n", 2)


if __name__ == "__main__":
    unittest.main()
