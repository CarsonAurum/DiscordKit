"""Hermetic oracle-tool tests; no release archive, compiler, subprocess or network is needed."""

import contextlib
import hashlib
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

import verify_opus_range_oracle as oracle


class OpusRangeOracleTests(unittest.TestCase):
    """Check opt-in execution, archive policy and actual comparison guards independently."""

    def test_import_starts_no_execution(self):
        """Ordinary discovery imports definitions without extraction, compilation or workdirs."""
        with mock.patch.object(subprocess, "run") as run, \
                mock.patch.object(tarfile, "open") as open_archive, \
                mock.patch.object(tempfile, "TemporaryDirectory") as temporary:
            importlib.reload(oracle)
        run.assert_not_called()
        open_archive.assert_not_called()
        temporary.assert_not_called()

    def test_run_success_and_diagnostics(self):
        """Preserve binary stdout and produce decoded diagnostics for a failing direct command."""
        success = subprocess.CompletedProcess(["driver"], 0, stdout=b"\x00\xff", stderr=b"")
        with mock.patch.object(subprocess, "run", return_value=success) as run:
            self.assertEqual(oracle.run(["driver", "argument with spaces"], b"input"), b"\x00\xff")
        run.assert_called_once_with(["driver", "argument with spaces"], input=b"input",
                                    capture_output=True, check=False)
        failure = subprocess.CompletedProcess(["driver"], 7, stdout=b"bad\xff", stderr=b"reason")
        with mock.patch.object(subprocess, "run", return_value=failure):
            with self.assertRaisesRegex(RuntimeError, r"Command failed \(7\).*driver") as raised:
                oracle.run(["driver"])
        self.assertIn("bad\ufffd", str(raised.exception))
        self.assertIn("reason", str(raised.exception))
        with mock.patch.object(subprocess, "run", side_effect=FileNotFoundError("missing compiler")):
            with self.assertRaises(FileNotFoundError):
                oracle.run(["missing"])

    def test_digest_reads_empty_and_multiple_chunks(self):
        """Hash exact bytes, including empty input and data spanning the one-MiB read bound."""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "source"
            for data in [b"", b"abc", b"x" * (1024 * 1024 + 17)]:
                path.write_bytes(data)
                self.assertEqual(oracle.digest(path), hashlib.sha256(data).hexdigest())

    def test_archive_identity_rejects_before_parsing(self):
        """Wrong size or digest cannot reach tar parsing even if supplied as a local path."""
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "untrusted.tar.gz"
            archive.write_bytes(b"not a release archive")
            for count, digest in [(archive.stat().st_size + 1, oracle.digest(archive)),
                                  (archive.stat().st_size, "0" * 64)]:
                with self.subTest(count=count, digest=digest), \
                        mock.patch.object(oracle, "ARCHIVE_BYTE_COUNT", count), \
                        mock.patch.object(oracle, "ARCHIVE_SHA256", digest), \
                        mock.patch.object(tarfile, "open") as open_archive:
                    with self.assertRaisesRegex(ValueError, "does not match"):
                        oracle.extract_verified_archive(archive, Path(temporary) / "output")
                    open_archive.assert_not_called()

    def test_archive_extracts_only_dense_regular_files(self):
        """A tiny synthetic verified tar reproduces nested file bytes without special members."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = self.make_archive(root, [
                (f"opus-{oracle.VERSION}/celt/entenc.c", tarfile.REGTYPE, b"source\x00bytes"),
                (f"opus-{oracle.VERSION}/empty", tarfile.REGTYPE, b""),
                (f"opus-{oracle.VERSION}/celt", tarfile.DIRTYPE, b""),
            ])
            output = root / "output"
            output.mkdir()
            extracted = self.extract_synthetic(archive, output)
            self.assertEqual(extracted, output / f"opus-{oracle.VERSION}")
            self.assertEqual((extracted / "celt/entenc.c").read_bytes(), b"source\x00bytes")
            self.assertEqual((extracted / "empty").read_bytes(), b"")

    def test_archive_rejects_unsafe_paths_before_any_output(self):
        """Validate the full member list before writing even an earlier harmless member."""
        for name in ["/absolute", "../escape", f"opus-{oracle.VERSION}/../escape",
                     f"opus-{oracle.VERSION}/nested/../../escape", "other-root/file", "."]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = self.make_archive(root, [
                    (f"opus-{oracle.VERSION}/safe", tarfile.REGTYPE, b"safe"),
                    (name, tarfile.REGTYPE, b"unsafe"),
                ])
                output = root / "output"
                output.mkdir()
                with self.assertRaisesRegex(ValueError, "Unsafe archive member"):
                    self.extract_synthetic(archive, output)
                self.assertEqual(list(output.iterdir()), [])

    def test_archive_rejects_links_and_special_members(self):
        """Symlinks, hard links, devices and FIFOs cannot be materialized by extraction."""
        for kind in [tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.CHRTYPE, tarfile.BLKTYPE, tarfile.FIFOTYPE]:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = self.make_archive(root, [(f"opus-{oracle.VERSION}/special", kind, b"")])
                output = root / "output"
                output.mkdir()
                with self.assertRaisesRegex(ValueError, "Unsupported archive member"):
                    self.extract_synthetic(archive, output)
                self.assertEqual(list(output.iterdir()), [])

    def test_operation_translation_and_oracle_json(self):
        """Map bit/uniform/raw/sparse-symbol records to exact official-call arguments."""
        operations = [[0, 1, 15], [1, 4294967294, 4294967295], [2, 0, 0],
                      [2, 33554431, 25], [3, 2, 0, 2, 0, 3, 5, 1]]
        expected = b"B 1 15 0\nU 4294967294 4294967295 0\nR 0 0 0\nR 33554431 25 0\nS 2 5 11"
        self.assertEqual(oracle.operation_commands(operations), expected)
        self.assertEqual(oracle.operation_commands([]), b"")
        with mock.patch.object(oracle, "run", return_value=b'{"bytes":[1],"states":[]}') as run:
            self.assertEqual(oracle.oracle_result(Path("oracle"), 1, operations), {"bytes": [1], "states": []})
        run.assert_called_once_with(["oracle", "1"], expected)
        with mock.patch.object(oracle, "run", return_value=b"invalid json"):
            with self.assertRaises(json.JSONDecodeError):
                oracle.oracle_result(Path("oracle"), 1, [])

    def test_fixed_and_seeded_cases_are_valid_and_deterministic(self):
        """Keep generated calls inside primitive and stream bounds without global RNG mutation."""
        fixtures = oracle.fixture_cases()
        self.assertEqual(len(fixtures), 6)
        self.assertEqual(len({name for name, _, _ in fixtures}), 6)
        self.assertEqual(fixtures[0], ("empty", 0, []))
        self.assertEqual(oracle.fixture_cases(), fixtures)
        state = random.getstate()
        generated = oracle.mixed_cases(128, 67168251)
        self.assertEqual(random.getstate(), state)
        self.assertEqual(generated, oracle.mixed_cases(128, 67168251))
        self.assertNotEqual(generated, oracle.mixed_cases(128, 67168252))
        for operations in generated:
            self.assertTrue(1 <= len(operations) <= 79)
        for operations in generated + [ops for _, _, ops in fixtures]:
            self.assert_valid_operations(operations)

    def test_fixture_generation_is_complete_and_nonexecuting_with_fake_oracle(self):
        """Regeneration retains all operation kinds and per-call states using injected results."""
        def result(_executable, size, operations):
            """Supply fake deterministic output solely to exercise source serialization."""
            return {"bytes": [0] * size, "states": [[123, 1, 8]] * (len(operations) + 1)}

        with mock.patch.object(oracle, "oracle_result", side_effect=result) as reference:
            text = oracle.fixture_text(Path("not-executed"))
            self.assertEqual(text, oracle.fixture_text(Path("not-executed")))
        self.assertEqual(reference.call_count, 12)
        self.assertIn(oracle.ARCHIVE_SHA256, text)
        self.assertIn("entropy vectors, not full Opus decoded-PCM conformance vectors", text)
        self.assertEqual(text.count("OpusEntropyFixture(name:"), 6)
        for operation in [".bit(", ".uniform(", ".raw(", ".symbol("]:
            self.assertIn(operation, text)
        self.assertTrue(text.endswith("\n"))

    def test_cli_rejects_unbounded_work_before_archive_or_compiler(self):
        """Invalid stress counts and seeds stop at argument parsing without local tool work."""
        for arguments in [["--cases", "0"], ["--cases", "10001"], ["--seed", "-1"]]:
            with self.subTest(arguments=arguments), \
                    mock.patch.object(sys, "argv", ["oracle", "--source-archive", "unused"] + arguments), \
                    mock.patch.object(oracle, "extract_verified_archive") as extract, \
                    mock.patch.object(oracle, "run") as run, \
                    contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    oracle.main()
                self.assertEqual(raised.exception.code, 2)
                extract.assert_not_called()
                run.assert_not_called()

    def test_main_reports_only_the_comparisons_it_performs(self):
        """Fake driver success produces audit fields distinguishing bytes/states from decoding."""
        actual = {"bytes": [66], "states": [[123, 1, 8]], "decoded": [1]}
        report = self.run_main_with_fake_drivers([actual])
        self.assertEqual(report["stressCases"], 1)
        self.assertEqual(report["operationCountBounds"], [1, 79])
        self.assertEqual(report["compared"], ["final frame bytes", "every-operation rng/ec_tell/ec_tell_frac",
                                             "owned decoded input values"])
        self.assertIn("no decoded PCM", report["scope"])

    def test_main_rejects_bytes_states_decoding_and_output_count_mismatches(self):
        """Each claimed comparison is independently enforced; absent output is also rejected."""
        good = {"bytes": [66], "states": [[123, 1, 8]], "decoded": [1]}
        for key, wrong in [("bytes", [67]), ("states", [[124, 1, 8]]), ("decoded", [0])]:
            with self.subTest(key=key):
                actual = dict(good, **{key: wrong})
                with self.assertRaisesRegex(RuntimeError, "mismatchCase"):
                    self.run_main_with_fake_drivers([actual])
        for outputs in [[], [good, good]]:
            with self.subTest(count=len(outputs)):
                with self.assertRaisesRegex(RuntimeError, "unexpected number of streams"):
                    self.run_main_with_fake_drivers(outputs)

    def assert_valid_operations(self, operations):
        """Check internal generated operands against the actual primitive-admission bounds."""
        for op in operations:
            kind, value, parameter = op[:3]
            self.assertIn(kind, range(4))
            if kind == 0:
                self.assertIn(value, [0, 1])
                self.assertTrue(1 <= parameter <= 15)
            elif kind == 1:
                self.assertTrue(2 <= parameter <= 2**32 - 1)
                self.assertTrue(0 <= value < parameter)
            elif kind == 2:
                self.assertTrue(0 <= parameter <= 25)
                self.assertTrue(0 <= value < 1 << parameter)
            else:
                frequencies = op[3:]
                self.assertTrue(0 <= value < len(frequencies))
                self.assertGreater(frequencies[value], 0)
                self.assertTrue(all(frequency >= 0 for frequency in frequencies))
                self.assertTrue(1 <= sum(frequencies) <= 65535)

    def make_archive(self, directory, members):
        """Write a tiny synthetic gzip tar, including deliberately unsafe test-only members."""
        archive = directory / "synthetic.tar.gz"
        with tarfile.open(archive, "w:gz") as output:
            for name, kind, data in members:
                member = tarfile.TarInfo(name)
                member.type = kind
                member.size = len(data) if kind == tarfile.REGTYPE else 0
                if kind in [tarfile.SYMTYPE, tarfile.LNKTYPE]:
                    member.linkname = "../escape"
                output.addfile(member, io.BytesIO(data) if kind == tarfile.REGTYPE else None)
        return archive

    def extract_synthetic(self, archive, directory):
        """Substitute only test archive identity to exercise the real whitelist/extractor."""
        with mock.patch.object(oracle, "ARCHIVE_BYTE_COUNT", archive.stat().st_size), \
                mock.patch.object(oracle, "ARCHIVE_SHA256", oracle.digest(archive)):
            return oracle.extract_verified_archive(archive, directory)

    def run_main_with_fake_drivers(self, outputs):
        """Exercise actual comparison/report logic with fake compiler and driver responses."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = root / oracle.FIXTURE_PATH
            fixture.parent.mkdir(parents=True)
            fixture.write_text("test fixture\n")
            owned = root / oracle.OWNED_PATH
            owned.parent.mkdir(parents=True)
            owned.write_text("test owned source\n")
            upstream = root / "upstream"
            (upstream / "celt").mkdir(parents=True)
            (upstream / "COPYING").write_text("test license\n")
            for name in ["entenc.c", "entdec.c", "entcode.c"]:
                (upstream / "celt" / name).write_text("test upstream source\n")
            report = root / "report.json"
            argv = ["oracle", "--source-archive", "unused", "--repository", str(root),
                    "--cases", "1", "--report", str(report)]
            response = "\n".join(json.dumps(output) for output in outputs).encode()
            results = [b"", b"", b"", b"", response, b"test cc\n", b"test Swift\n"]
            with mock.patch.object(sys, "argv", argv), \
                    mock.patch.object(oracle, "extract_verified_archive", return_value=upstream), \
                    mock.patch.object(oracle, "fixture_text", return_value="test fixture\n"), \
                    mock.patch.object(oracle, "mixed_cases", return_value=[[[0, 1, 1]]]), \
                    mock.patch.object(oracle, "oracle_result", return_value={"bytes": [66], "states": [[123, 1, 8]]}), \
                    mock.patch.object(oracle, "run", side_effect=results), \
                    contextlib.redirect_stdout(io.StringIO()) as printed:
                oracle.main()
            decoded = json.loads(report.read_text())
            self.assertEqual(decoded, json.loads(printed.getvalue()))
            return decoded


if __name__ == "__main__":
    unittest.main()
