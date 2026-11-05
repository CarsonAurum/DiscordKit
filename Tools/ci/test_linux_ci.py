# File: Tools/ci/test_linux_ci.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Offline Ubuntu gate contracts, durable failure reports and real process cleanup."""

from contextlib import ExitStack, redirect_stdout, suppress
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import linux_ci


class LinuxCommandTests(unittest.TestCase):
    """Protect package coverage, dependency pins and argument boundaries without compiling."""

    def setUp(self):
        """Use an actual temporary checkout path containing shell-significant characters."""
        self.temporary = tempfile.TemporaryDirectory(prefix="Ubuntu gates $ literal ")
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        browser = self.repository / "Browser/DiscordActivityBridge"
        browser.mkdir(parents=True)
        (browser / "bridge.test.mjs").touch()

    def plan(self, stage):
        """Plan one stage with a distinguishable nondefault compiler job budget."""
        return linux_ci.commands(stage, self.repository, 3)

    def test_every_swift_invocation_requires_pins_and_bounded_jobs(self):
        """All packages inherit the same dependency and memory policy, including executable runs."""
        stages = ("root", "authoring", "tooling", "benchmarks", "audit", "consumers", "release")
        self.assertEqual(linux_ci.STAGES, stages)
        for stage in stages:
            for command in self.plan(stage):
                with self.subTest(stage=stage, command=command.name):
                    self.assertGreater(command.timeout, 0)
                    self.assertTrue(all(isinstance(argument, str) for argument in command.arguments))
                    if command.arguments[0] != "swift":
                        continue
                    arguments = command.arguments
                    self.assertIn(arguments[1], ("build", "test", "run"))
                    self.assertEqual(arguments.count("--jobs"), 1)
                    self.assertEqual(arguments[arguments.index("--jobs") + 1], "3")
                    self.assertEqual(arguments.count("--force-resolved-versions"), 1)
                    self.assertIn("--package-path", arguments)

    def test_run_options_precede_executable_and_program_arguments_follow(self):
        """SwiftPM flags cannot accidentally reach an example or audit program as its own options."""
        for stage in ("benchmarks", "audit", "consumers"):
            for command in self.plan(stage):
                if command.arguments[:2] != ("swift", "run"):
                    continue
                arguments = command.arguments
                executable = ("DiscordDSLBenchmarks" if stage == "benchmarks" else
                              "DiscordKitTools" if stage == "audit" else command.name.removeprefix("run-"))
                executable_index = arguments.index(executable)
                for flag in ("--package-path", "--jobs", "--force-resolved-versions"):
                    self.assertLess(arguments.index(flag), executable_index)
                if stage == "benchmarks":
                    self.assertLess(arguments.index("--configuration"), executable_index)
                    self.assertGreater(arguments.index("--invocations"), executable_index)
                if stage == "audit":
                    self.assertGreater(arguments.index("--repository"), executable_index)
                if command.name == "run-DSLCommands":
                    self.assertEqual(arguments[executable_index + 1:], ("--offline",))
                if "--scratch-path" in arguments:
                    self.assertLess(arguments.index("--scratch-path"), executable_index)

    def test_root_and_optimized_package_graphs_are_independent_gates(self):
        """A debug build alone cannot satisfy root runtime tests or optimized library/macro builds."""
        root = self.plan("root")
        self.assertEqual([command.arguments[1] for command in root], ["build", "test"])
        self.assertTrue(all(command.arguments[command.arguments.index("--package-path") + 1] == "."
                            for command in root))
        release = self.plan("release")
        self.assertEqual({command.arguments[command.arguments.index("--package-path") + 1] for command in release},
                         {".", "Packages/DiscordDSLMacros", "Packages/DiscordDSLExtensions"})
        for command in release:
            self.assertEqual(command.arguments[1], "build")
            self.assertEqual(command.arguments[command.arguments.index("--configuration") + 1], "release")

    def test_independent_consumer_builds_tests_and_offline_runs_are_retained(self):
        """Each consumer graph builds; selected application assertions and synthetic runs also execute."""
        examples = {"RESTOnly", "GatewayBot", "HTTPApp", "CommandsApp", "DSLCommands", "DSLEvents", "DSLBot",
                    "OAuthApp", "VoiceBot", "RPCApp", "ActivityHost", "SocialApp", "LoggingApp"}
        tests = {"LoggingApp", "CommandsApp", "DSLCommands", "DSLEvents", "DSLBot", "ActivityHost"}
        runs = {"LoggingApp", "CommandsApp", "DSLCommands", "DSLEvents", "DSLBot", "VoiceBot", "SocialApp"}
        planned = self.plan("consumers")
        self.assertEqual({command.name.removeprefix("build-") for command in planned
                          if command.arguments[1] == "build"}, examples)
        self.assertEqual({command.name.removeprefix("test-") for command in planned
                          if command.arguments[1] == "test"}, tests)
        self.assertEqual({command.name.removeprefix("run-") for command in planned
                          if command.arguments[1] == "run"}, runs)
        for command in planned:
            self.assertEqual(command.arguments[command.arguments.index("--scratch-path") + 1],
                             str(self.repository / ".build/consumers"))
            if command.arguments[1] == "build":
                self.assertEqual(command.arguments[command.arguments.index("--explicit-target-dependency-import-check") + 1],
                                 "error")

    def test_authoring_compilation_passes_fixture_resource_limits(self):
        """Negative compilation retains a longer cold-build timeout and the same job budget."""
        planned = self.plan("authoring")
        self.assertEqual([command.name for command in planned],
                         ["DiscordDSLMacros", "dsl_compile_fixtures.py",
                          "DiscordDSLExtensions", "dsl_extension_fixtures.py"])
        for command in planned:
            arguments = command.arguments
            if arguments[0] == "swift":
                self.assertEqual(arguments[arguments.index("--explicit-target-dependency-import-check") + 1], "error")
            else:
                self.assertEqual(arguments[0], sys.executable)
                self.assertEqual(arguments[arguments.index("--repository") + 1], str(self.repository))
                self.assertEqual(arguments[arguments.index("--jobs") + 1], "3")
                self.assertGreaterEqual(int(arguments[arguments.index("--timeout") + 1]), 1200)
                self.assertGreater(command.timeout, int(arguments[arguments.index("--timeout") + 1]))

    def test_browser_discovery_is_sorted_and_preserves_literal_paths(self):
        """Browser tests are explicit file arguments and never require shell wildcard expansion."""
        directory = self.repository / "Browser/DiscordActivityBridge"
        (directory / "bridge.test.mjs").unlink()
        for name in ("z.test.mjs", "a test.test.mjs", "bridge.mjs"):
            (directory / name).touch()
        browser, = [command for command in self.plan("tooling") if command.name == "browser"]
        self.assertEqual(browser.arguments, ("node", "--test", "Browser/DiscordActivityBridge/a test.test.mjs",
                                             "Browser/DiscordActivityBridge/z.test.mjs"))

    def test_missing_browser_fixtures_cannot_fall_back_to_node_discovery(self):
        """A missing suite must fail planning rather than let Node choose unrelated tests."""
        (self.repository / "Browser/DiscordActivityBridge/bridge.test.mjs").unlink()
        with self.assertRaisesRegex(ValueError, "browser"):
            self.plan("tooling")

    def test_plans_do_not_include_credentials_or_live_mutations(self):
        """The CI plan cannot start the qualification client, publish a package or sync Discord commands."""
        forbidden = ("live_rest_smoke", "VoiceSessionQualification", "DISCORD_TOKEN", "BOT_TOKEN",
                     "--token", "publish", "deploy", "sync-commands", "curl", "wget", "sudo")
        for stage in linux_ci.STAGES:
            for command in self.plan(stage):
                self.assertIn(command.arguments[0], ("swift", "node", sys.executable))
                for argument in command.arguments:
                    self.assertTrue(all(word not in argument for word in forbidden), (stage, argument))

    def test_invalid_stage_and_job_budgets_fail_before_execution(self):
        """Typos, booleans and nonpositive limits cannot silently remove the compiler cap."""
        with self.assertRaises(ValueError):
            self.plan("ubunty")
        for jobs in (0, -1, True, 1.5, "4", None):
            with self.subTest(jobs=jobs), self.assertRaises(ValueError):
                linux_ci.commands("root", self.repository, jobs)


class LinuxExecutionTests(unittest.TestCase):
    """Verify durable outcomes and bounded process ownership using harmless local Python children."""

    def test_failed_command_is_durable_and_stops_later_commands(self):
        """Inspect the saved running state before execution and preserve each earlier successful result."""
        with tempfile.TemporaryDirectory() as temporary, redirect_stdout(io.StringIO()):
            repository = Path(temporary)
            output = repository / "reports"
            planned = [linux_ci.Command(name, ("fixture", name)) for name in ("first", "failure", "never")]
            seen = []

            def execute(command, checkout, log):
                """Observe persisted admission and fail on the second command without invoking a compiler."""
                self.assertEqual(checkout, repository)
                report = json.loads((output / "root.json").read_text())
                self.assertEqual(report["status"], "running")
                self.assertEqual(report["commands"][-1]["status"], "running")
                self.assertEqual(report["commands"][-1]["name"], command.name)
                if seen:
                    self.assertEqual(report["commands"][0]["status"], "passed")
                seen.append(command.name)
                log.write_text(command.name + " output\n")
                if command.name == "failure":
                    raise subprocess.CalledProcessError(7, command.arguments)

            with patch.object(linux_ci, "commands", return_value=planned), patch.object(linux_ci, "execute", execute):
                with self.assertRaises(subprocess.CalledProcessError):
                    linux_ci.run_stage("root", repository, output, 3)
            report = json.loads((output / "root.json").read_text())
            self.assertEqual(seen, ["first", "failure"])
            self.assertEqual(report["status"], "failed")
            self.assertEqual([command["status"] for command in report["commands"]], ["passed", "failed"])
            self.assertIn("7", report["commands"][-1]["error"])
            self.assertTrue(all(isinstance(command["seconds"], (int, float)) for command in report["commands"]))
            self.assertFalse((output / "root.tmp").exists())
            self.assertTrue(all((output / command["log"]).is_file() for command in report["commands"]))

    def test_successful_stage_finishes_with_all_commands_passed(self):
        """Only completion of every command writes the terminal passed result."""
        with tempfile.TemporaryDirectory() as temporary, redirect_stdout(io.StringIO()):
            repository = Path(temporary)
            command = linux_ci.Command("local", (sys.executable, "-c", "print('offline passed')"))
            with patch.object(linux_ci, "commands", return_value=[command]):
                linux_ci.run_stage("root", repository, repository / "reports", 3)
            report = json.loads((repository / "reports/root.json").read_text())
            self.assertEqual(report["status"], "passed")
            self.assertEqual(report["commands"][0]["status"], "passed")
            self.assertIn("offline passed", (repository / "reports" / report["commands"][0]["log"]).read_text())

    def test_benchmark_stage_creates_output_directory_on_a_cold_checkout(self):
        """The smoke executable's output path works without a prior local benchmark run."""
        with tempfile.TemporaryDirectory() as temporary, redirect_stdout(io.StringIO()):
            repository = Path(temporary)
            destination = repository / ".build/dsl-measurements"
            self.assertFalse(destination.exists())
            seen = []

            def execute(command, checkout, log):
                """Check the actual smoke program's destination before any stage command runs."""
                self.assertTrue(destination.is_dir())
                self.assertEqual(checkout, repository)
                seen.append(command.name)

            with patch.object(linux_ci, "execute", execute):
                linux_ci.run_stage("benchmarks", repository, repository / "reports", 3)
            self.assertIn("smoke", seen)

    def test_real_subprocess_failure_streams_both_outputs_and_strict_environment(self):
        """A nonzero child retains stdout, stderr, working-directory and strict-mode evidence in its log."""
        with tempfile.TemporaryDirectory(prefix="Ubuntu process $ literal ") as temporary:
            repository = Path(temporary)
            code = ("import os, sys; print('stdout fixture', flush=True); "
                    "print('stderr fixture', file=sys.stderr, flush=True); "
                    "print('strict=' + os.environ['SWIFTNIO_STRICT']); "
                    "print('unbuffered=' + os.environ['PYTHONUNBUFFERED']); "
                    "print('cwd=' + os.getcwd()); sys.exit(7)")
            command = linux_ci.Command("failure", (sys.executable, "-c", code), timeout=5)
            console = io.StringIO()
            with redirect_stdout(console), self.assertRaises(subprocess.CalledProcessError) as caught:
                linux_ci.execute(command, repository, repository / "failure.log")
            self.assertEqual(caught.exception.returncode, 7)
            log = (repository / "failure.log").read_text()
            for expected in ("stdout fixture", "stderr fixture", "strict=1", "unbuffered=1",
                             "cwd=" + str(repository.resolve())):
                self.assertIn(expected, log)
                self.assertIn(expected, console.getvalue())

    def test_output_forwarding_failure_cannot_be_reported_as_success(self):
        """A successful child still fails qualification if its output cannot reach the console sink."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            command = linux_ci.Command("logging", (sys.executable, "-c", "print('offline output')"), timeout=5)
            with patch.object(linux_ci, "print", side_effect=BrokenPipeError("console sink failed"), create=True):
                with self.assertRaisesRegex(OSError, "could not preserve command output"):
                    linux_ci.execute(command, repository, repository / "logging.log")
            self.assertIn("offline output", (repository / "logging.log").read_text())

    @unittest.skipUnless(os.name == "posix", "process-group cleanup is a POSIX contract")
    def test_timeout_terminates_parent_and_sigterm_resistant_descendant(self):
        """A timed-out compiler tree cannot leave a plugin alive after its group leader is reaped."""
        self.assert_descendant_timeout(parent_waits=True)

    @unittest.skipUnless(os.name == "posix", "process-group cleanup is a POSIX contract")
    def test_timeout_includes_descendants_after_successful_parent_exit(self):
        """A successful SwiftPM exit cannot pass while its child still owns the command output pipe."""
        self.assert_descendant_timeout(parent_waits=False)

    def assert_descendant_timeout(self, parent_waits):
        """Run a synthetic child tree with an observable PID and always clean it on assertion failure."""
        with tempfile.TemporaryDirectory() as temporary, redirect_stdout(io.StringIO()):
            repository = Path(temporary)
            pid_file = repository / "descendant.pid"
            child = ("import os, pathlib, signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                     f"pathlib.Path({str(pid_file)!r}).write_text(str(os.getpid())); "
                     "print('descendant started', flush=True); time.sleep(60)")
            parent = (f"import subprocess, sys; process = subprocess.Popen([sys.executable, '-c', {child!r}]); "
                      + ("process.wait()" if parent_waits else "sys.exit(0)"))
            command = linux_ci.Command("timeout", (sys.executable, "-c", parent), timeout=1.5)
            started = time.monotonic()
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    linux_ci.execute(command, repository, repository / "timeout.log")
                self.assertLess(time.monotonic() - started, 8)
                self.assertTrue(pid_file.is_file(), "the descendant must start to exercise cleanup")
                pid = int(pid_file.read_text())
                deadline = time.monotonic() + 2
                while self.process_is_running(pid) and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertFalse(self.process_is_running(pid), "timed-out descendant is still running")
                self.assertIn("descendant started", (repository / "timeout.log").read_text())
            finally:
                if pid_file.exists():
                    with suppress(ProcessLookupError):
                        os.kill(int(pid_file.read_text()), signal.SIGKILL)

    @staticmethod
    def process_is_running(pid):
        """Count unreaped Linux zombies as terminated, independently of a container's init process."""
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        stat = Path(f"/proc/{pid}/stat")
        if sys.platform.startswith("linux"):
            try:
                return stat.read_text().rsplit(")", 1)[1].split()[0] != "Z"
            except FileNotFoundError:
                return False
        return True


class LinuxPreflightTests(unittest.TestCase):
    """Reject misleading host/toolchain combinations while recording nonsecret diagnostics."""

    def test_macos_is_rejected_before_any_compiler_process(self):
        """The unchanged working macOS installation cannot accidentally qualify as Ubuntu."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            with patch.object(linux_ci.platform, "system", return_value="Darwin"), \
                    patch.object(linux_ci.subprocess, "check_output") as compiler:
                with self.assertRaisesRegex(ValueError, "native Linux"):
                    linux_ci.preflight(repository, repository / "reports")
                compiler.assert_not_called()

    def test_wrong_distribution_and_missing_executables_fail_before_compilation(self):
        """Linux alone is insufficient, and missing build tools cannot become a later opaque failure."""
        for release, missing, message in (({"ID": "debian", "VERSION_ID": "12"}, None, "Ubuntu 24.04"),
                                          ({"ID": "ubuntu", "VERSION_ID": "24.04"}, "clang", "missing: clang")):
            with self.subTest(release=release, missing=missing), tempfile.TemporaryDirectory() as temporary:
                repository = Path(temporary)
                with self.host_mocks(release), \
                        patch.object(linux_ci.shutil, "which", side_effect=lambda name: None if name == missing else "/fixture/" + name), \
                        patch.object(linux_ci.subprocess, "check_output", return_value="fixture-revision\n") as queries:
                    with self.assertRaisesRegex(ValueError, message):
                        linux_ci.preflight(repository, repository / "reports")
                    self.assertEqual([call.args[0] for call in queries.call_args_list], [["git", "rev-parse", "HEAD"]])
                    host = json.loads((repository / "reports/host.json").read_text())
                    self.assertEqual(host["osRelease"], release)
                    self.assertEqual(host["revision"], "fixture-revision")

    def test_wrong_swift_version_and_nonlinux_target_are_rejected(self):
        """Installed-command success cannot qualify a mismatched compiler or Apple cross target."""
        for version, triple, message in (("Swift version 6.4.0\n", "x86_64-unknown-linux-gnu", "expected Swift 6.4.1"),
                                         ("Swift version 6.4.1\n", "arm64-apple-macosx", "native Linux Swift target")):
            with self.subTest(version=version, triple=triple), tempfile.TemporaryDirectory() as temporary:
                repository = Path(temporary)
                target = {"target": {"triple": triple}}
                with self.host_mocks(), patch.object(linux_ci.shutil, "which", return_value="/fixture/tool"), \
                        patch.object(linux_ci.subprocess, "check_output", side_effect=["fixture-revision\n", version, json.dumps(target)]):
                    with self.assertRaisesRegex(ValueError, message):
                        linux_ci.preflight(repository, repository / "reports")
                self.assertEqual((repository / "reports/swift-version.txt").read_text(), version)
                self.assertEqual(json.loads((repository / "reports/target.json").read_text()), target)

    def test_matching_ubuntu_and_swift_record_evidence_without_installing_tools(self):
        """The approved host/compiler pair passes using read-only, explicitly bounded compiler queries."""
        with tempfile.TemporaryDirectory() as temporary, redirect_stdout(io.StringIO()):
            repository = Path(temporary)
            version = "Swift version 6.4.1 (swift-6.4.1-RELEASE)\nTarget: x86_64-unknown-linux-gnu\n"
            target = {"target": {"triple": "x86_64-unknown-linux-gnu"}}
            with self.host_mocks(), patch.object(linux_ci.shutil, "which", return_value="/fixture/tool"), \
                    patch.object(linux_ci.subprocess, "check_output", side_effect=["fixture-revision\n", version, json.dumps(target)]) as compiler:
                linux_ci.preflight(repository, repository / "reports")
            self.assertEqual([call.args[0] for call in compiler.call_args_list],
                             [["git", "rev-parse", "HEAD"], ["swift", "--version"], ["swift", "-print-target-info"]])
            self.assertTrue(all(call.kwargs["timeout"] == 30 for call in compiler.call_args_list))
            self.assertTrue((repository / "reports/host.json").is_file())

    @staticmethod
    def host_mocks(release=None):
        """Replace Linux-only metadata reads while retaining real report writes on either test host."""
        stack = ExitStack()
        stack.enter_context(patch.object(linux_ci.platform, "system", return_value="Linux"))
        stack.enter_context(patch.object(linux_ci.platform, "freedesktop_os_release", create=True,
                                       return_value=release or {"ID": "ubuntu", "VERSION_ID": "24.04"}))
        original = Path.read_text

        def read_text(path, *arguments, **options):
            """Supply only the missing procfs fixture; all report reads use the real filesystem."""
            return "MemTotal: 123456 kB\n" if str(path) == "/proc/meminfo" else original(path, *arguments, **options)

        stack.enter_context(patch.object(Path, "read_text", read_text))
        return stack


if __name__ == "__main__":
    unittest.main()
