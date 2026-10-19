"""Deterministic qualification-runner tests; actual compiler evidence comes from its external targets."""

from pathlib import Path
import subprocess
import unittest

from dsl_compile_fixtures import assess
from dsl_extension_fixtures import FIXTURES, compiler_command, run_fixtures


class ExtensionFixtureTests(unittest.TestCase):
    """Keep infrastructure failure separate from real public API dependency diagnostics."""

    def test_exact_external_target_has_explicit_import_checks_and_no_macro_selection(self):
        command = compiler_command(Path("/repo"), Path("/scratch"), "PositiveDependencies", cache_path=Path("/cache"))
        self.assertIn("/repo/Tests/Fixtures/DSLExtensionsCompile", command)
        self.assertIn("--explicit-target-dependency-import-check", command)
        self.assertEqual(command[-2:], ["--target", "PositiveDependencies"])
        self.assertNotIn("DiscordDSLMacros", " ".join(command))

    def test_missing_and_wrong_typed_dependencies_need_semantic_diagnostics(self):
        for fixture in FIXTURES[1:]:
            crash = subprocess.CompletedProcess([], 1, "", "error: compiler plugin crashed")
            self.assertFalse(assess(fixture, crash).passed)
            diagnostic = subprocess.CompletedProcess([], 1, "", "error: " + " ".join(fixture.diagnostics))
            self.assertTrue(assess(fixture, diagnostic).passed)
            self.assertFalse(assess(fixture, subprocess.CompletedProcess([], 0, "", "")).passed)

    def test_failed_positive_stops_and_timeout_is_not_semantic_evidence(self):
        calls = []

        def timeout(command, **kwargs):
            """Capture invocation and model a finite compiler timeout without launching a subprocess."""
            calls.append(command)
            raise subprocess.TimeoutExpired(command, kwargs["timeout"])

        results = run_fixtures(Path("/repo"), Path("/scratch"), run=timeout)
        self.assertEqual(len(calls), 1)
        self.assertFalse(results[0].passed)
        self.assertIn("timeout", results[0].detail)

    def test_finite_timeout_and_positive_first_are_required(self):
        for timeout in [0, -1, float("inf"), float("nan")]:
            with self.assertRaises(ValueError):
                run_fixtures(Path("/repo"), Path("/scratch"), timeout=timeout)
        with self.assertRaises(ValueError):
            run_fixtures(Path("/repo"), Path("/scratch"), fixtures=FIXTURES[1:])


if __name__ == "__main__":
    unittest.main()
