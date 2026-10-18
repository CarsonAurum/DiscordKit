"""Deterministic process-level tests for external Swift compilation qualification."""

from pathlib import Path
import subprocess
import unittest

import dsl_compile_fixtures as fixtures


class CompileFixtureTests(unittest.TestCase):
    """Reject false positives from unrelated failures, timeouts and unexpectedly accepted negative source."""

    def test_command_preserves_independent_package_target_and_paths_with_spaces(self):
        """Shell-free arguments preserve paths and always compile an actual external target."""
        root = Path("/checkout with spaces")
        command = fixtures.compiler_command(root, root / "scratch directory", "PositiveExternal", "/tool chain/swift")
        self.assertEqual(command[0], "/tool chain/swift")
        self.assertEqual(command[command.index("--target") + 1], "PositiveExternal")
        self.assertEqual(command[command.index("--package-path") + 1], str(root / "Tests/Fixtures/DSLCompile"))
        self.assertEqual(command[command.index("--scratch-path") + 1], str(root / "scratch directory"))
        self.assertIn("--disable-sandbox", command)
        self.assertEqual(command[command.index("--explicit-target-dependency-import-check") + 1], "error")
        self.assertNotIn("-dump-macro-expansions", command)
        alternate = fixtures.compiler_command(root, root / "scratch", "PositiveExternal", cache_path=root / "shared cache")
        self.assertEqual(alternate[alternate.index("--cache-path") + 1], str(root / "shared cache"))

    def test_success_and_semantic_failure_are_distinct(self):
        """A negative target needs compiler error text and every expected fragment in a nonzero result."""
        negative = fixtures.Fixture("Invalid", ("ArgumentValue", "does not conform"))
        success = subprocess.CompletedProcess([], 0, stdout="", stderr="")
        error = subprocess.CompletedProcess([], 1, stdout="", stderr="error: Type does not conform to ArgumentValue")
        self.assertTrue(fixtures.assess(fixtures.Fixture("Positive"), success).passed)
        self.assertFalse(fixtures.assess(fixtures.Fixture("Positive"), error).passed)
        self.assertTrue(fixtures.assess(negative, error).passed)
        self.assertFalse(fixtures.assess(negative, success).passed)
        for text in ["error: failed to load compiler plugin", "error: ArgumentValue crashed", "warning: does not conform to ArgumentValue"]:
            result = fixtures.assess(negative, subprocess.CompletedProcess([], 1, stdout=text, stderr=""))
            self.assertFalse(result.passed)

    def test_errors_are_case_insensitive_and_failure_output_is_bounded(self):
        """Compiler capitalization is irrelevant while an unrelated enormous log stays bounded."""
        negative = fixtures.Fixture("Negative", ("non-Sendable",))
        result = fixtures.assess(negative, subprocess.CompletedProcess([], 1, stdout="ERROR: NON-SENDABLE value", stderr=None))
        self.assertTrue(result.passed)
        failure = fixtures.assess(negative, subprocess.CompletedProcess([], 1, stdout="x" * 20000, stderr=""))
        self.assertFalse(failure.passed)
        self.assertLess(len(failure.detail), 12500)

    def test_injected_runner_compiles_each_target_with_finite_timeout(self):
        """The runner performs real build commands in order and never accepts expansion inspection as execution."""
        calls = []

        def run(command, **options):
            """Record process boundaries and synthesize one success followed by the selected compiler failure."""
            calls.append((command, options))
            target = command[command.index("--target") + 1]
            return subprocess.CompletedProcess(command, 0 if target == "Positive" else 1,
                                               stdout="" if target == "Positive" else "error: selected failure", stderr="")

        cases = (fixtures.Fixture("Positive"), fixtures.Fixture("Negative", ("selected failure",)))
        results = fixtures.run_fixtures(Path("/repo"), Path("/scratch"), timeout=17, run=run, fixtures=cases)
        self.assertTrue(all(result.passed for result in results))
        self.assertEqual([result.target for result in results], ["Positive", "Negative"])
        self.assertEqual(len(calls), 2)
        for command, options in calls:
            self.assertEqual(command[1], "build")
            self.assertEqual(options, {"cwd": Path("/repo"), "capture_output": True, "text": True, "timeout": 17})

    def test_infrastructure_failures_cannot_qualify_negative_fixtures(self):
        """Failure of the positive plugin build halts the run and retains its actual diagnostic."""
        calls = []

        def run(command, **options):
            """Simulate compiler infrastructure failure before any negative fixture may run."""
            calls.append(command)
            return subprocess.CompletedProcess(command, 1, stdout="error: dependency unavailable", stderr="")

        cases = (fixtures.Fixture("Positive"), fixtures.Fixture("Negative", ("dependency unavailable",)))
        result = fixtures.run_fixtures(Path("/repo"), Path("/scratch"), run=run, fixtures=cases)
        self.assertEqual(len(calls), 1)
        self.assertEqual(len(result), 1)
        self.assertFalse(result[0].passed)
        self.assertIn("dependency unavailable", result[0].detail)

    def test_timeout_spawn_failure_and_invalid_budget_fail_closed(self):
        """Missing executables and hung processes remain failures even for expected-failure Swift targets."""
        cases = (fixtures.Fixture("Positive"), fixtures.Fixture("Negative", ("error",)))
        for failure in [subprocess.TimeoutExpired(["swift"], 2), FileNotFoundError("swift missing")]:
            def run(command, **options):
                """Raise the selected local infrastructure error without starting an external compiler."""
                raise failure

            results = fixtures.run_fixtures(Path("/repo"), Path("/scratch"), run=run, fixtures=cases)
            self.assertEqual(len(results), 1)
            self.assertFalse(results[0].passed)
        for timeout in [0, -1, float("inf"), float("nan")]:
            with self.assertRaises(ValueError):
                fixtures.run_fixtures(Path("/repo"), Path("/scratch"), timeout=timeout)
        with self.assertRaises(ValueError):
            fixtures.run_fixtures(Path("/repo"), Path("/scratch"), fixtures=())
        with self.assertRaises(ValueError):
            fixtures.run_fixtures(Path("/repo"), Path("/scratch"), fixtures=cases[1:])

    def test_negative_mismatches_continue_for_complete_evidence(self):
        """One wrong diagnostic never prevents later independent negative consumers from being checked."""
        calls = []

        def run(command, **options):
            """Return a success and two unrelated failures to exercise complete negative reporting."""
            calls.append(command)
            return subprocess.CompletedProcess(command, 0 if len(calls) == 1 else 1,
                                               stdout="error: unrelated failure", stderr="")

        cases = (fixtures.Fixture("Positive"), fixtures.Fixture("NegativeA", ("expected a",)),
                 fixtures.Fixture("NegativeB", ("expected b",)))
        results = fixtures.run_fixtures(Path("/repo"), Path("/scratch"), run=run, fixtures=cases)
        self.assertEqual([result.passed for result in results], [True, False, False])
        self.assertEqual(len(calls), 3)

    def test_negative_timeout_never_counts_as_expected_compiler_failure(self):
        """A timed-out negative target remains failed after a successful infrastructure baseline."""
        calls = []

        def run(command, **options):
            """Establish the positive build, then simulate a hung compiler for the negative source."""
            calls.append(command)
            if len(calls) == 1:
                return subprocess.CompletedProcess(command, 0, stdout="", stderr="")
            raise subprocess.TimeoutExpired(command, 7)

        cases = (fixtures.Fixture("Positive"), fixtures.Fixture("Negative", ("error",)))
        results = fixtures.run_fixtures(Path("/repo"), Path("/scratch"), timeout=7, run=run, fixtures=cases)
        self.assertEqual([result.passed for result in results], [True, False])
        self.assertIn("timeout", results[1].detail)

    def test_catalog_compiles_every_committed_consumer(self):
        """New invalid consumers cannot silently escape qualification and the codec remains a separate target."""
        source_root = Path(__file__).resolve().parents[2] / "Tests/Fixtures/DSLCompile/Sources"
        actual = {path.name for path in source_root.iterdir() if path.is_dir()}
        declared = [case.target for case in fixtures.FIXTURES]
        self.assertEqual(len(declared), len(set(declared)))
        self.assertEqual(actual, set(declared) | {"ExternalCodec"})
        self.assertFalse(fixtures.FIXTURES[0].diagnostics)
        self.assertTrue(all(case.diagnostics for case in fixtures.FIXTURES[1:]))


if __name__ == "__main__":
    unittest.main()
