# File: Tools/DiscordKitTools/scripts/test_verify_celt_transform_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic CELT transform verifier tests; no compiler, source archive or network required."""

import base64
import contextlib
import importlib
import io
import json
from pathlib import Path
import random
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

import verify_celt_transform_oracle as oracle
import verify_opus_range_oracle as entropy


class CELTTransformOracleTests(unittest.TestCase):
    """Exercise deterministic inputs, exact fixture parsing and all comparison rejection guards."""

    def test_import_starts_no_work_and_reuses_pinned_archive_policy(self):
        """Import must not compile/extract or replace the shared validated-release archive gate."""
        with mock.patch.object(subprocess, "run") as run, \
                mock.patch.object(tarfile, "open") as open_archive, \
                mock.patch.object(tempfile, "TemporaryDirectory") as temporary:
            importlib.reload(oracle)
        run.assert_not_called()
        open_archive.assert_not_called()
        temporary.assert_not_called()
        self.assertIs(oracle.extract_verified_archive, entropy.extract_verified_archive)
        self.assertIs(oracle.run, entropy.run)
        self.assertEqual(oracle.ARCHIVE_SHA256, entropy.ARCHIVE_SHA256)

    def test_fixed_boundary_and_seeded_cases(self):
        """All contexts remain float32-exact, bounded and reproducible without changing global RNG."""
        self.assertEqual(oracle.FRAME_SIZES, (120, 240, 480, 960))
        fixed = oracle.fixed_cases()
        self.assertEqual([value["n"] for value in fixed], list(oracle.FRAME_SIZES))
        self.assertTrue(all(value["channels"] == 1 for value in fixed))
        boundary = oracle.boundary_cases()
        self.assertEqual(len(boundary), 40)
        self.assertEqual(set((v["n"], v["channels"]) for v in boundary),
                         set((n, c) for n in oracle.FRAME_SIZES for c in (1, 2)))
        state = random.getstate()
        mixed = oracle.mixed_cases(12, 6716437)
        self.assertEqual(state, random.getstate())
        self.assertEqual(mixed, oracle.mixed_cases(12, 6716437))
        self.assertNotEqual(mixed, oracle.mixed_cases(12, 6716438))
        self.assertEqual(oracle.mixed_cases(0, 0), [])
        for value in fixed + boundary + mixed:
            n, channels = value["n"], value["channels"]
            self.assertIn(n, oracle.FRAME_SIZES)
            self.assertIn(channels, (1, 2))
            self.assertEqual(len(value["pcm"]), (n + 120) * channels)
            self.assertEqual(len(value["spectrum"]), n * channels)
            self.assertTrue(all(-1 <= x <= 1 for x in value["pcm"]))
            self.assertTrue(all(-4 <= x <= 4 for x in value["spectrum"]))
            for x in value["pcm"] + value["spectrum"]:
                self.assertEqual(x, struct.unpack("<f", struct.pack("<f", x))[0])

    def test_output_count_json_and_object_guards(self):
        """Dropped/extra records, invalid JSON and non-object results cannot pass as evidence."""
        self.assertEqual(oracle.parse_outputs(b"{}\n", 1, "driver"), [{}])
        self.assertEqual(oracle.parse_outputs(b"", 0, "driver"), [])
        for data in [b"", b"{}\n{}"]:
            with self.assertRaisesRegex(RuntimeError, "unexpected number"):
                oracle.parse_outputs(data, 1, "driver")
        with self.assertRaises(json.JSONDecodeError):
            oracle.parse_outputs(b"invalid", 1, "driver")
        for data in [b"null", b"[]", b"1"]:
            with self.assertRaisesRegex(RuntimeError, "non-object"):
                oracle.parse_outputs(data, 1, "driver")

    def test_comparison_guards_and_tolerances(self):
        """Shape, finite-value and every-bin checks reject corruption while allowing documented error."""
        contexts = [{"n": 120, "channels": 1}]
        reference = [{"forward": [0.0] * 120, "inverse": [1.0] * 120}]
        owned = [{"forward": [0.000001] * 120, "inverse": [1.00001] * 120}]
        maxima = oracle.compare_results(contexts, reference, owned, 1)
        self.assertAlmostEqual(maxima["forward"], 0.000001)
        self.assertAlmostEqual(maxima["inverse"], 0.00001)
        with self.assertRaisesRegex(RuntimeError, "case count"):
            oracle.compare_results(contexts, [], owned, 1)
        for replacement in [{}, {"forward": [], "inverse": []},
                            {"forward": "bad", "inverse": [1] * 120}]:
            with self.assertRaisesRegex(RuntimeError, "shape"):
                oracle.compare_results(contexts, reference, [replacement], 1)
        for key in ("forward", "inverse"):
            for invalid in [float("nan"), float("inf"), -float("inf"), "bad", None, True, 100.0]:
                candidate = {"forward": [0.0] * 120, "inverse": [1.0] * 120}
                candidate[key][-1] = invalid
                with self.assertRaises(RuntimeError):
                    oracle.compare_results(contexts, reference, [candidate], 1)

    def test_complete_fixture_decoding_and_rejections(self):
        """Read exact little-endian reference words and reject partial, missing or duplicate contexts."""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixtures.swift"
            lines = []
            for n in oracle.FRAME_SIZES:
                encoded = base64.b64encode(struct.pack("<" + "f" * n, *([0.5] * n))).decode()
                lines.append(f'        ({n}, "{encoded}", "{encoded}"),')
            path.write_text("\n".join(lines))
            fixtures = oracle.committed_fixtures(path)
            self.assertEqual([v["n"] for v in fixtures], list(oracle.FRAME_SIZES))
            self.assertEqual(fixtures[0]["forward"], [0.5] * 120)
            self.assertEqual(fixtures[-1]["inverse"], [0.5] * 960)
            for content in ["", "\n".join(lines[:-1]), "\n".join(lines + [lines[0]])]:
                path.write_text(content)
                with self.assertRaisesRegex(ValueError, "four ordered"):
                    oracle.committed_fixtures(path)
            path.write_text('        (120, "AA==", "AA=="),')
            with self.assertRaisesRegex(ValueError, "length"):
                oracle.committed_fixtures(path)

    def test_fixture_reproduction_rejects_every_changed_float(self):
        """All four full-vector pairs must reproduce exactly at float32 precision."""
        fixtures = [{"n": n, "forward": [0.5] * n, "inverse": [-0.5] * n}
                    for n in oracle.FRAME_SIZES]
        official = [{"forward": [0.5] * n, "inverse": [-0.5] * n} for n in oracle.FRAME_SIZES]
        oracle.compare_fixtures(fixtures, official)
        with self.assertRaisesRegex(RuntimeError, "count"):
            oracle.compare_fixtures(fixtures[:-1], official)
        for key in ("forward", "inverse"):
            official[-1][key][-1] += 0.25
            with self.assertRaisesRegex(RuntimeError, "mismatch"):
                oracle.compare_fixtures(fixtures, official)
            official[-1][key][-1] -= 0.25

    def test_cli_rejects_unbounded_work_before_reading_or_compiling(self):
        """Invalid case/seed bounds fail through argparse before opening fixtures or source archives."""
        for tail in [["--cases", "0"], ["--cases", "2001"], ["--seed", "-1"]]:
            with mock.patch.object(sys, "argv", ["verify", "--source-archive", "missing"] + tail), \
                    mock.patch.object(oracle, "committed_fixtures") as fixtures, \
                    mock.patch.object(oracle, "run") as run, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    oracle.main()
            fixtures.assert_not_called()
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
