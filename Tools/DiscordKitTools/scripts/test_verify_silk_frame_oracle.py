# File: Tools/DiscordKitTools/scripts/test_verify_silk_frame_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic ordinary channel PCM verifier tests; no archive/compiler/network use."""
import json
from pathlib import Path
import unittest
import verify_silk_frame_oracle as verifier


class SILKFrameVerifierTests(unittest.TestCase):
    """Validate complete scalar-stream literal handling and deterministic generators."""

    def test_fixtures_cover_formats_and_persistent_histories(self):
        """All internal formats retain exact per-frame PCM/state values, including regression."""
        fixtures = verifier.committed_fixtures(Path(__file__).resolve().parents[3])
        self.assertEqual(len(fixtures), 7)
        self.assertEqual({(i["rate"], i["milliseconds"]) for i, _ in fixtures},
                         {(r, m) for r in (8000, 12000, 16000) for m in (10, 20)})
        for item, expected in fixtures:
            self.assertEqual(len(item["frames"]), len(expected))
            for frame in expected:
                self.assertEqual(len(frame["pcm"]), item["rate"] * item["milliseconds"] // 1000)
                self.assertEqual(len(frame["outputHistory"]), item["rate"] // 50)
                self.assertEqual(len(frame["lpcState"]), 16)

    def test_sequence_inputs_are_bounded_seeded_and_cover_formats(self):
        """Deterministic stream construction uses only authenticated generator outputs."""
        generated = [dict(rate=r, milliseconds=m, bytes=[r // 1000, m])
                     for r in (8000, 12000, 16000) for m in (10, 20)]
        inputs = verifier.sequence_inputs(generated, 18, 42)
        self.assertEqual(inputs, verifier.sequence_inputs(generated, 18, 42))
        self.assertNotEqual(inputs, verifier.sequence_inputs(generated, 18, 43))
        self.assertEqual(len({(i["rate"], i["milliseconds"]) for i in inputs}), 6)
        for item in inputs:
            self.assertTrue(2 <= len(item["frames"]) <= 12)
            self.assertTrue(all(f in generated for f in item["frames"]))

    def test_commands_keep_stream_and_entropy_boundaries(self):
        """A two-frame stream preserves both frame contexts and zero-length byte frames."""
        item = dict(rate=8000, milliseconds=20, frames=[
            dict(vad=True, lbrr=False, coding=0, bytes=[255, 0]),
            dict(vad=False, lbrr=True, coding=2, bytes=[])])
        self.assertEqual(verifier.commands([item]), b"8000 20 2\n1 0 0 2 255 0\n0 1 2 0 \n")

    def test_output_parser_rejects_missing_wrong_shape_and_invalid_data(self):
        """Missing results and object/array confusion cannot silently pass comparison."""
        self.assertEqual(verifier.parse_outputs(b"[]\n", 1), [[]])
        self.assertEqual(verifier.parse_outputs(b"{}\n", 1, arrays=False), [{}])
        for data, count in [(b"", 1), (b"{}\n", 1), (b"[]\n", 2), (b"bad", 1), (b"\xff", 1)]:
            with self.assertRaises(RuntimeError):
                verifier.parse_outputs(data, count)

    def test_comparison_includes_every_pcm_and_history_value(self):
        """A one-unit PCM/state deviation invalidates exact ordinary-channel evidence."""
        expected = [[dict(pcm=[0, 1], lpcState=[16], gain=65536)]]
        verifier.compare_results([{}], expected, expected, 42)
        for field in ("pcm", "lpcState"):
            actual = json.loads(json.dumps(expected))
            actual[0][0][field][0] += 1
            with self.assertRaises(RuntimeError):
                verifier.compare_results([{}], expected, actual, 42)


if __name__ == "__main__":
    unittest.main()
