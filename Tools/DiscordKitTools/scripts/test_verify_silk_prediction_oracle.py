"""Hermetic SILK verifier tests; no archive, native compiler/executable or network."""

import contextlib
import importlib
import io
import json
from pathlib import Path
import random
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

import verify_opus_range_oracle as entropy
import verify_silk_prediction_oracle as oracle


class SILKPredictionOracleTests(unittest.TestCase):
    """Keep offline native comparisons, exact fixtures and evidence scope enforceable."""

    def test_import_starts_no_native_work_and_reuses_archive_gate(self):
        """Import performs no execution/extraction and preserves the pinned shared policy."""
        with mock.patch.object(subprocess, "run") as run, mock.patch.object(tarfile, "open") as extract:
            importlib.reload(oracle)
        run.assert_not_called()
        extract.assert_not_called()
        self.assertIs(oracle.extract_verified_archive, entropy.extract_verified_archive)
        self.assertIs(oracle.run, entropy.run)
        self.assertEqual(oracle.ARCHIVE_SHA256, entropy.ARCHIVE_SHA256)

    def test_bounded_fixed_boundary_and_seeded_contexts(self):
        """Cover all seed/offset choices, both LPC orders, sample extremes and local RNG."""
        fixed = oracle.fixture_cases()
        self.assertEqual(len(fixed), 26)
        self.assertEqual([len(case["q12"]) for case in fixed[:2]], [10, 16])
        self.assertEqual(len({(case["signal"], case["offset"], case["seed"]) for case in fixed[2:]}), 24)
        boundaries = oracle.boundary_cases()
        self.assertEqual(len(boundaries), 90)
        state = random.getstate()
        mixed = oracle.mixed_cases(1000, 67164279)
        self.assertEqual(random.getstate(), state)
        self.assertEqual(mixed, oracle.mixed_cases(1000, 67164279))
        self.assertNotEqual(mixed, oracle.mixed_cases(1000, 67164280))
        self.assertEqual(oracle.mixed_cases(0, 1), [])
        for case in fixed + boundaries + mixed:
            if case["kind"] == "analysis":
                self.assertIn(len(case["q12"]), [10, 16])
                self.assertEqual(len(case["history"]), len(case["q12"]))
                self.assertLessEqual(len(case["samples"]), 960)
                self.assertTrue(all(-32768 <= value <= 32767 for value in case["q12"]))
            else:
                self.assertLessEqual(len(case["pulses"]), 320)
                self.assertTrue(all(-32768 <= value <= 32767 for value in case["pulses"]))
                self.assertIn(case["seed"], range(4))
                self.assertIn(case["signal"], range(3))
                self.assertIn(case["offset"], range(2))

    def test_command_encoding_and_finite_tolerances(self):
        """Native input records preserve both LPC history and signed excitation pulses."""
        analysis = {"kind": "analysis", "q12": [2048] * 10, "history": [0] * 10, "samples": [1, -2]}
        excitation = {"kind": "excitation", "signal": 2, "offset": 0, "seed": 3, "pulses": [-32768, 32767]}
        lines = oracle.commands([analysis, excitation]).decode().splitlines()
        self.assertTrue(lines[0].startswith("A 10 2 2048"))
        self.assertTrue(lines[0].endswith("1 -2"))
        self.assertEqual(lines[1], "X 2 0 3 2 -32768 32767")
        self.assertTrue(oracle.close(1.0, 1.000001))
        for wrong in [None, "1", True, float("nan"), float("inf"), -float("inf"), 1.1]:
            self.assertFalse(oracle.close(wrong, 1.0))

    def test_committed_fixture_parsing_and_order_rejection(self):
        """Literal rows are read without Swift execution; omissions and reordered rows fail."""
        repository = Path(__file__).resolve().parents[3]
        fixtures = oracle.committed_fixtures(repository)
        self.assertEqual(len(fixtures), 26)
        self.assertEqual(len(fixtures[0]["samples"]), 24)
        self.assertEqual(fixtures[2]["excitation"], [25, -261, -211, -517, 467, -32517, 32723, -25])
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative in oracle.FIXTURE_PATHS:
                destination = root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text((repository / relative).read_text())
            first = root / oracle.FIXTURE_PATHS[0]
            first.write_text(first.read_text().replace("(16, 0.909089", "(10, 0.909089"))
            with self.assertRaisesRegex(ValueError, "LPC"):
                oracle.committed_fixtures(root)
            first.write_text((repository / oracle.FIXTURE_PATHS[0]).read_text())
            second = root / oracle.FIXTURE_PATHS[1]
            second.write_text(second.read_text().replace("(0, 0, 0, [", "(0, 0, 1, [", 1))
            with self.assertRaisesRegex(ValueError, "ordered"):
                oracle.committed_fixtures(root)

    def test_every_claimed_comparison_is_enforced(self):
        """Samples/gain, inverse recovery and exact excitation/seed cannot silently mismatch."""
        analysis = {"kind": "analysis", "samples": [1.0]}
        official = {"gain": 0.75, "samples": [1.0]}
        owned = dict(official, recovered=[1.0])
        oracle.compare_results([analysis], [official], [owned], 1)
        for bad in [dict(owned, gain=0.8), dict(owned, samples=[]), dict(owned, samples=[2]),
                    dict(owned, recovered=[2]), dict(owned, recovered=[float("nan")]), {"error": "failed"}]:
            with self.assertRaisesRegex(RuntimeError, "mismatchCase"):
                oracle.compare_results([analysis], [official], [bad], 1)
        excitation = {"kind": "excitation", "seed": 0, "pulses": [0]}
        expected = {"excitation": [8]}
        actual = dict(expected, seed=907633515)
        oracle.compare_results([excitation], [expected], [actual], 1)
        for bad in [dict(actual, excitation=[9]), dict(actual, excitation=[]), dict(actual, excitation=None), dict(actual, seed=0)]:
            with self.assertRaisesRegex(RuntimeError, "mismatchCase"):
                oracle.compare_results([excitation], [expected], [bad], 1)
        with self.assertRaisesRegex(RuntimeError, "number"):
            oracle.compare_results([excitation], [], [actual], 1)
        oracle.compare_fixtures([expected], [expected])
        for bad in [[], [{"excitation": [9]}]]:
            with self.assertRaisesRegex(RuntimeError, "fixture mismatch"):
                oracle.compare_fixtures([expected], bad)

    def test_cli_rejects_unbounded_work_before_execution(self):
        """Invalid case counts/seeds stop before archive verification or compiler invocation."""
        for arguments in [["--cases", "0"], ["--cases", "10001"], ["--seed", "-1"]]:
            with mock.patch.object(sys, "argv", ["oracle", "--source-archive", "unused"] + arguments), \
                    mock.patch.object(oracle, "extract_verified_archive") as extract, \
                    mock.patch.object(oracle, "run") as run, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    oracle.main()
                self.assertEqual(raised.exception.code, 2)
                extract.assert_not_called()
                run.assert_not_called()

    def test_main_reports_scoped_evidence_and_propagates_mismatches(self):
        """Fake isolated drivers cover orchestration/reporting without any native execution."""
        self.run_fake_main(False)
        with self.assertRaisesRegex(RuntimeError, "mismatchCase"):
            self.run_fake_main(True)

    def run_fake_main(self, mismatch):
        """Run the real CLI around hermetic driver outputs; optionally corrupt one result."""
        context = {"kind": "excitation", "signal": 2, "offset": 0, "seed": 0, "pulses": [0]}
        expected = {"excitation": [8]}
        actual = dict(expected, seed=0 if mismatch else 907633515)

        def fake_run(command, input_bytes=None):
            """Return deterministic native-version/driver data without starting any process."""
            if str(command[0]).endswith("official-oracle"):
                return (json.dumps(expected) + "\n").encode()
            if str(command[0]).endswith("owned-driver"):
                return (json.dumps(actual) + "\n").encode()
            return b"fake compiler 1.0\n"

        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            report = directory / "report.json"
            arguments = ["oracle", "--source-archive", "unused", "--repository", str(directory),
                         "--cases", "1", "--report", str(report)]
            with mock.patch.object(sys, "argv", arguments), \
                    mock.patch.object(oracle, "committed_fixtures", return_value=[expected]), \
                    mock.patch.object(oracle, "fixture_cases", return_value=[context]), \
                    mock.patch.object(oracle, "boundary_cases", return_value=[]), \
                    mock.patch.object(oracle, "mixed_cases", return_value=[]), \
                    mock.patch.object(oracle, "extract_verified_archive", return_value=directory), \
                    mock.patch.object(oracle, "digest", return_value="0" * 64), \
                    mock.patch.object(oracle, "run", side_effect=fake_run), contextlib.redirect_stdout(io.StringIO()):
                oracle.main()
            result = json.loads(report.read_text())
            self.assertEqual(result["fixtureCount"], 1)
            self.assertEqual(result["comparedCases"], 1)
            self.assertEqual(set(result["officialSourceSHA256"]), set(oracle.OFFICIAL_PATHS))
            self.assertEqual(set(result["ownedSwiftSHA256"]), set(oracle.OWNED_PATHS))
            self.assertEqual(set(result["driverSHA256"]), {"c", "swift"})
            self.assertIn("no compressed syntax", result["scope"])
            self.assertIn("complete codec conformance", result["scope"])
