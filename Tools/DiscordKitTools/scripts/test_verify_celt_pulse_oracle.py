# File: Tools/DiscordKitTools/scripts/test_verify_celt_pulse_oracle.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Hermetic PVQ verifier tests: no archive, compiler, native executable or network."""

import contextlib
from datetime import date
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

import verify_celt_pulse_oracle as oracle
import verify_opus_range_oracle as entropy


class CELTPulseOracleTests(unittest.TestCase):
    """Exercise bounded generation, native/owned comparison guards and evidence scope."""

    def test_import_starts_no_execution_and_reuses_archive_policy(self):
        """Importing performs no native work and reuses the exact pinned entropy archive gate."""
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

    def test_independent_counts(self):
        """Check zero/one-dimensional and published counts without the owned U recurrence."""
        for n, row in [(1, [1, 2, 2, 2]), (2, [1, 4, 8, 12]),
                       (3, [1, 6, 18, 38]), (4, [1, 8, 32, 88])]:
            self.assertEqual([oracle.codeword_count(n, k) for k in range(4)], row)
        self.assertEqual(oracle.codeword_count(176, 4), 639716352)
        self.assertGreater(oracle.codeword_count(176, 5), oracle.UINT32_MAX)
        self.assertGreater(oracle.codeword_count(176, 128), 2**64)
        for n, k in [(0, 0), (-1, 1), (2, -1)]:
            with self.assertRaises(ValueError):
                oracle.codeword_count(n, k)

    def test_fixed_boundary_and_seeded_inputs(self):
        """Keep deterministic contexts in official table bounds and preserve global RNG state."""
        fixtures = oracle.fixture_cases()
        self.assertEqual(len(fixtures), 40)
        self.assertEqual(fixtures[0], {"n": 2, "k": 2, "index": 0})
        self.assertEqual(fixtures, oracle.fixture_cases())
        boundaries = oracle.boundary_cases()
        self.assertEqual(oracle.ORDINARY_DIMENSIONS,
                         (2, 3, 4, 6, 8, 9, 11, 12, 16, 18, 22, 24, 32, 36, 44, 48,
                          64, 72, 88, 96, 144, 176))
        self.assertEqual(oracle.ORDINARY_MAX_PULSES,
                         (128, 128, 128, 88, 36, 26, 18, 16, 12, 11, 9, 9, 7, 7,
                          6, 6, 5, 5, 5, 5, 4, 4))
        self.assertIn({"n": 6, "k": 88, "index": 0}, boundaries)
        self.assertIn({"n": 9, "k": 26, "index": 0}, boundaries)
        self.assertEqual(len(boundaries), len(oracle.ORDINARY_DIMENSIONS) * 10)
        self.assertIn({"n": 176, "k": 4, "index": 639716351}, boundaries)
        self.assertTrue(any(value["k"] == 128 for value in boundaries))
        state = random.getstate()
        generated = oracle.mixed_cases(2000, 67164342)
        self.assertEqual(random.getstate(), state)
        self.assertEqual(generated, oracle.mixed_cases(2000, 67164342))
        self.assertNotEqual(generated, oracle.mixed_cases(2000, 67164343))
        self.assertEqual(oracle.mixed_cases(0, 0), [])
        for value in fixtures + boundaries + generated:
            self.assertTrue(2 <= value["n"] <= 176)
            self.assertTrue(1 <= value["k"] <= 128)
            count = oracle.codeword_count(value["n"], value["k"])
            self.assertTrue(0 <= value["index"] < count <= oracle.UINT32_MAX)

    def test_sparse_fixture_parsing_and_validation(self):
        """Read literal sparse vectors without Swift execution, rejecting bad positions/counts."""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixtures.swift"
            line = "            (2, 2, 8, 0, [(0, 2)]),\n"
            prefix = "@Test func officialCodewordFixtures() throws {\nlet fixtures = [\n"
            path.write_text(prefix + line * 40 + "        ]\n}")
            parsed = oracle.committed_fixtures(path)
            self.assertEqual(len(parsed), 40)
            self.assertEqual(parsed[0], {"n": 2, "k": 2, "count": 8, "index": 0, "vector": [2, 0]})
            for replacement in ["[(2, 2)]", "[(0, 1), (0, 1)]"]:
                path.write_text(prefix + line.replace("[(0, 2)]", replacement) * 40 + "        ]\n}")
                with self.assertRaisesRegex(ValueError, "position"):
                    oracle.committed_fixtures(path)
            path.write_text(prefix + line * 39 + "        ]\n}")
            with self.assertRaisesRegex(ValueError, "forty"):
                oracle.committed_fixtures(path)
            path.write_text("no fixture function")
            with self.assertRaisesRegex(ValueError, "Missing"):
                oracle.committed_fixtures(path)

    def test_output_count_json_and_object_validation(self):
        """Dropped/extra lines, malformed JSON and non-object results cannot become evidence."""
        self.assertEqual(oracle.parse_outputs(b'{"count":8}\n', 1, "driver"), [{"count": 8}])
        self.assertEqual(oracle.parse_outputs(b"", 0, "driver"), [])
        for data in [b"", b"{}\n{}"]:
            with self.assertRaisesRegex(RuntimeError, "unexpected number"):
                oracle.parse_outputs(data, 1, "driver")
        with self.assertRaises(json.JSONDecodeError):
            oracle.parse_outputs(b"invalid", 1, "driver")
        for data in [b"[]", b"null", b"1"]:
            with self.assertRaisesRegex(RuntimeError, "non-object"):
                oracle.parse_outputs(data, 1, "driver")

    def test_every_native_owned_comparison_is_enforced(self):
        """Counts, ranks, vectors, bytes, decoding and input invariants fail independently."""
        context = {"n": 2, "k": 2, "index": 0}
        good = {"count": 8, "index": 0, "vector": [2, 0], "decoded": [2, 0], "bytes": [0] * 8}
        oracle.compare_results([context], [good], [good], 42)
        for key, wrong in [("count", 9), ("index", 1), ("vector", [0, 2]),
                           ("decoded", [1, 1]), ("bytes", [1] * 8)]:
            with self.subTest(key=key):
                bad = dict(good, **{key: wrong})
                with self.assertRaisesRegex(RuntimeError, "mismatchCase"):
                    oracle.compare_results([context], [good], [bad], 42)
        for bad in [dict(good, count=9), dict(good, index=1),
                    dict(good, vector=[2], decoded=[2]), dict(good, vector=[1, 0], decoded=[1, 0]),
                    dict(good, decoded=[0, 2])]:
            with self.assertRaisesRegex(RuntimeError, "mismatchCase"):
                oracle.compare_results([context], [bad], [bad], 42)
        with self.assertRaisesRegex(RuntimeError, "number"):
            oracle.compare_results([context], [], [good], 42)

    def test_committed_fixture_comparison(self):
        """The tracked sparse vectors/counts must agree with official contexts and output."""
        context = {"n": 2, "k": 2, "index": 0}
        fixture = dict(context, count=8, vector=[2, 0])
        result = {"count": 8, "vector": [2, 0]}
        oracle.compare_fixtures([fixture], [context], [result])
        for bad in [dict(fixture, n=3), dict(fixture, k=1), dict(fixture, index=1),
                    dict(fixture, count=9), dict(fixture, vector=[0, 2])]:
            with self.assertRaisesRegex(RuntimeError, "fixtureMismatch"):
                oracle.compare_fixtures([bad], [context], [result])
        with self.assertRaisesRegex(RuntimeError, "count"):
            oracle.compare_fixtures([], [context], [result])

    def test_cli_rejects_unbounded_work_before_native_execution(self):
        """Invalid case counts/seeds stop before archive handling or compiler invocation."""
        for arguments in [["--cases", "0"], ["--cases", "10001"], ["--seed", "-1"]]:
            with mock.patch.object(sys, "argv", ["oracle", "--source-archive", "unused"] + arguments), \
                    mock.patch.object(oracle, "extract_verified_archive") as extract, \
                    mock.patch.object(oracle, "run") as run, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    oracle.main()
                self.assertEqual(raised.exception.code, 2)
                extract.assert_not_called()
                run.assert_not_called()

    def test_main_scoped_evidence_and_mismatch_propagation(self):
        """Fake local drivers exercise reporting, file hashes, comparison and process failures."""
        report = self.run_fake_main()
        self.assertEqual(report["fixtureCount"], 1)
        self.assertEqual(report["boundaryCases"], 0)
        self.assertEqual(report["stressCases"], 1)
        self.assertEqual(report["comparedCases"], 2)
        self.assertEqual(report["seed"], 67164342)
        self.assertRegex(report["verifiedOn"], r"^\d{4}-\d{2}-\d{2}$")
        self.assertEqual(date.fromisoformat(report["verifiedOn"]).isoformat(), report["verifiedOn"])
        self.assertEqual(set(report["ownedSwiftSHA256"]), set(oracle.OWNED_PATHS))
        self.assertIn("celt/cwrs.c", report["officialSourceSHA256"])
        self.assertIn("no decoded PCM", report["scope"])
        self.assertIn("complete codec conformance", report["scope"])
        self.assertEqual(report["sourceArchiveSHA256"], entropy.ARCHIVE_SHA256)
        with self.assertRaisesRegex(RuntimeError, "mismatchCase"):
            self.run_fake_main(mismatch=True)
        with self.assertRaisesRegex(RuntimeError, "compiler failed"):
            self.run_fake_main(compile_failure=True)

    def run_fake_main(self, mismatch=False, compile_failure=False):
        """Run orchestration against temporary fake sources/results, never executing a process."""
        context = {"n": 2, "k": 2, "index": 0}
        good = {"count": 8, "index": 0, "vector": [2, 0], "decoded": [2, 0], "bytes": [0] * 8}
        fixture = dict(context, count=8, vector=[2, 0])
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in list(oracle.OWNED_PATHS) + [oracle.FIXTURE_PATH]:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("fake test source")
            report_path = root / "report.json"

            def extract(_archive, directory):
                """Materialize only fake files needed by report hashing, preserving native isolation."""
                upstream = directory / "upstream"
                (upstream / "celt").mkdir(parents=True)
                for path in ["COPYING", "celt/cwrs.c", "celt/entenc.c", "celt/entdec.c", "celt/entcode.c"]:
                    (upstream / path).write_text("fake upstream source")
                return upstream

            def run(command, input_bytes=None):
                """Return synthetic native outputs or a deliberate compiler failure."""
                if "--version" in command:
                    return b"test compiler 1.0\n"
                executable = Path(command[0]).name
                if executable in ["official-oracle", "owned-driver"]:
                    result = dict(good, index=1) if mismatch and executable == "owned-driver" else good
                    return (json.dumps(result) + "\n").encode() * 2
                if compile_failure:
                    raise RuntimeError("compiler failed")
                return b""

            arguments = ["oracle", "--source-archive", "unused", "--repository", str(root),
                         "--cases", "1", "--report", str(report_path)]
            with mock.patch.object(sys, "argv", arguments), \
                    mock.patch.object(oracle, "committed_fixtures", return_value=[fixture]), \
                    mock.patch.object(oracle, "fixture_cases", return_value=[context]), \
                    mock.patch.object(oracle, "boundary_cases", return_value=[]), \
                    mock.patch.object(oracle, "mixed_cases", return_value=[context]), \
                    mock.patch.object(oracle, "extract_verified_archive", side_effect=extract), \
                    mock.patch.object(oracle, "run", side_effect=run), contextlib.redirect_stdout(io.StringIO()):
                oracle.main()
            return json.loads(report_path.read_text())


if __name__ == "__main__":
    unittest.main()
