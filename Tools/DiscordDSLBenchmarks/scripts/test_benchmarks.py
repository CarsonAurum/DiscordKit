"""Deterministic failure, isolation and budget checks; no compiler timing assertions."""

import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import subprocess

import baseline
import compile_benchmarks as compiler


def reports():
    """Provide finite synthetic complete matrices for parser and threshold tests only."""
    environment = {"compiler": "Swift version 6.4", "operatingSystem": "test", "architecture": "test",
                   "processorCount": 4, "hardwareModel": "test", "physicalMemoryBytes": 1024}
    compile_report = {"schemaVersion": 1, "configuration": {"samples": 1, "jobs": 4, "handlerCounts": [10, 100, 1000],
                      "modes": ["manual", "macro"], "handlersPerFile": 10, "optionsPerHandler": 1,
                      "configuration": "debug", "buildSystem": "native", "dependencyColdBuildIncluded": False}, "environment": environment,
                      "fixtureHash": "a" * 64, "resolutionHash": "b" * 64, "workloads": []}
    runtime_report = {"schemaVersion": 1, "configuration": {"invocations": 1000, "handlerCounts": [10, 100, 1000],
                      "concurrency": 8, "sampleLimit": 1000, "payloadBytes": 64, "minimumDurationSeconds": 0}, "environment": environment,
                      "workloads": []}
    for count in (10, 100, 1000):
        for mode in ("manual", "macro"):
            compile_report["workloads"].append({"mode": mode, "handlerCount": count, "functionalGatesPassed": True,
                "samples": [{"clean": {"wallSeconds": 2, "peakRSSBytes": 100},
                             "incremental": {"wallSeconds": 1, "peakRSSBytes": 100}, "binaryBytes": 100}]})
        for mode in ("direct", "dsl"):
            row = {"mode": mode, "handlerCount": count, "functionalGatesPassed": True, "invocations": 1000,
                   "planCompilationMilliseconds": 1, "durationSeconds": 10, "invocationsPerSecond": 100,
                   "latency": {"sampleCount": 1000, "p50Milliseconds": 1, "p95Milliseconds": 2, "p99Milliseconds": 3},
                   "schemaBuilds": count, "schemasAfterInvocations": count,
                   "accountedState": {"declaredHandlers": count, "retainedSchemas": count, "fixedInteractionCount": count,
                        "fixedInteractionJSONBytes": 1000, "registrationJSONBytes": 1000, "routeMetadataJSONBytes": 1000,
                        "planDescriptionTextBytes": 0 if mode == "direct" else 1000, "maximumWorkers": 8,
                        "maximumLatencySamples": 1000, "maximumMemorySamples": 121, "maximumPayloadBytes": 64,
                        "maximumActualInvocations": 100_000_000},
                   "counters": {"schemas": 0, "handlers": 1000, "callbacks": 1000, "activeWorkers": 0, "peakWorkers": 8},
                   "implicitHydrationRequests": 0, "implicitRegistrationRequests": 0,
                   "cleanup": {"activeHandlers": 0, "activeAcknowledgements": 0, "acknowledgementBytes": 0, "activeWorkers": 0}}
            for snapshot in baseline.SNAPSHOTS:
                row[snapshot] = {"peakRSSBytes": 100, "residentBytes": 100, "cpuSeconds": 1,
                                 "liveAllocationBlocks": 20, "liveAllocationBytes": 100}
            row["memoryObservations"] = [{"elapsedSeconds": 1, "completedInvocations": 100,
                                           "process": copy.deepcopy(row["afterPlan"])}]
            runtime_report["workloads"].append(row)
    return compile_report, runtime_report


class CompilerFixtureTests(unittest.TestCase):
    """Generated work is finite, concrete and preserves runtime product independence."""

    def test_concrete_handlers_and_bounded_file_groups(self):
        for count in compiler.COUNTS:
            for macro in (False, True):
                source = compiler.generated_sources(count, macro)
                handlers = [text for name, text in source.items() if name.startswith("Handlers")]
                self.assertEqual(len(handlers), count // 10)
                self.assertEqual(sum(text.count(": SlashCommandHandler") for text in handlers), count)
                self.assertTrue(all(text.count(": SlashCommandHandler") == 10 for text in handlers))
                self.assertEqual(sum(text.count("@SlashCommand") for text in handlers), count if macro else 0)
                self.assertNotIn("DiscordDSLMacros", "".join(source.values()) if not macro else "")
                self.assertIn(f"compiled.routes.count == {count}", source["Main.swift"])
                first = source["Handlers000.swift"]
                self.assertNotEqual(first, first.replace('fixture \\(', 'edited \\(', 1))
        for invalid in (0, 11, 1001, 10000):
            with self.assertRaises(ValueError):
                compiler.generated_sources(invalid, True)

    def test_workspace_does_not_overwrite_unrelated_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "important").write_text("retain")
            with self.assertRaises(ValueError):
                compiler.prepare_workspace(root, root)
            self.assertEqual((root / "important").read_text(), "retain")

    def test_target_cleanup_preserves_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            consumer = root / "test/debug/Manual10.build"
            dependency = root / "test/debug/DiscordCommandDSL.build"
            for path in (consumer, dependency):
                path.mkdir(parents=True)
                (path / "object.o").write_bytes(b"object")
                (path / "output-file-map.json").write_text("{}")
            self.assertTrue(compiler.remove_consumer_outputs(root, "Manual10"))
            self.assertFalse((consumer / "object.o").exists())
            self.assertTrue((consumer / "output-file-map.json").exists())
            self.assertTrue(dependency.exists())
            with self.assertRaises(ValueError):
                compiler.remove_consumer_outputs(root, "../DiscordCommandDSL")

    def test_hash_ignores_mtime_and_includes_names(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            one = root / "one.swift"
            one.write_text("one")
            before = compiler.digest_files([one], root)
            one.touch()
            self.assertEqual(before, compiler.digest_files([one], root))
            two = root / "two.swift"
            one.rename(two)
            self.assertNotEqual(before, compiler.digest_files([two], root))

    def test_incremental_restores_source_after_success_or_compiler_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Handlers.swift"
            original = b'fixture \\(arguments.text)\nfixture \\(arguments.text)'
            for fail in (False, True):
                source.write_bytes(original)

                def timed(command, timeout, repository, log_path):
                    self.assertEqual(source.read_bytes().count(b"edited"), 1)
                    self.assertEqual(source.read_bytes().count(b"fixture"), 1)
                    if fail:
                        raise RuntimeError("compiler failed")
                    return {"wallSeconds": 1, "peakRSSBytes": 100}

                if fail:
                    with self.assertRaises(RuntimeError):
                        compiler.run_incremental(source, ["swift"], 1, root, root / "log", timed)
                else:
                    self.assertEqual(compiler.run_incremental(source, ["swift"], 1, root, root / "log", timed)["wallSeconds"], 1)
                self.assertEqual(source.read_bytes(), original)
            source.write_text("unrelated source")
            with self.assertRaises(ValueError):
                compiler.run_incremental(source, ["swift"], 1, root, root / "log", timed)
            self.assertEqual(source.read_text(), "unrelated source")

    def test_process_timeout_failure_and_missing_rss_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for status, text in ((3, b"error: compiler failed\n"), (0, b"no resource evidence\n")):
                process = mock.Mock()
                process.wait.return_value = status

                def start(command, **kwargs):
                    kwargs["stdout"].write(text)
                    return process

                with mock.patch.object(compiler.subprocess, "Popen", side_effect=start), mock.patch.object(compiler.platform, "system", return_value="Darwin"):
                    with self.assertRaises(RuntimeError):
                        compiler.run_timed(["swift"], 1, root, root / "log")
            process = mock.Mock(pid=123)
            process.wait.side_effect = [subprocess.TimeoutExpired("swift", 1), 0]
            with mock.patch.object(compiler.subprocess, "Popen", return_value=process), mock.patch.object(compiler.os, "killpg") as kill:
                with self.assertRaisesRegex(RuntimeError, "exceeded"):
                    compiler.run_timed(["swift"], 1, root, root / "log")
                kill.assert_called_once()
                self.assertEqual(process.wait.call_count, 2)

    def test_process_resource_evidence_uses_platform_units(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for system, output, expected in (("Darwin", b"123 maximum resident set size\n", 123),
                                              ("Linux", b"Maximum resident set size (kbytes): 123\n", 125952)):
                process = mock.Mock()
                process.wait.return_value = 0

                def start(command, **kwargs):
                    self.assertEqual(command[:2], ["/usr/bin/time", "-l" if system == "Darwin" else "-v"])
                    self.assertTrue(kwargs["start_new_session"])
                    kwargs["stdout"].write(output)
                    return process

                with mock.patch.object(compiler.subprocess, "Popen", side_effect=start), mock.patch.object(compiler.platform, "system", return_value=system):
                    self.assertEqual(compiler.run_timed(["swift"], 1, root, root / "log")["peakRSSBytes"], expected)


class BaselineTests(unittest.TestCase):
    """Complete evidence and separate finite budgets fail closed on malformed reports."""

    def setUp(self):
        self.compile, self.runtime = reports()
        self.record = baseline.record(self.compile, self.runtime)
        self.budgets = baseline.budgets(self.record)

    def test_record_does_not_set_budgets_and_roundtrip_checks(self):
        self.assertNotIn("limits", self.record)
        self.assertTrue(baseline.check(self.record, self.budgets, self.compile, self.runtime)["passed"])
        self.assertGreater(len(self.record["measurements"]), 100)

    def test_regressions_cover_compile_tail_throughput_and_rss(self):
        self.compile["workloads"][0]["samples"][0]["clean"]["wallSeconds"] = 30
        row = self.runtime["workloads"][0]
        row["latency"]["p99Milliseconds"] = 30
        row["invocationsPerSecond"] = 1
        row["durationSeconds"] = 1000
        row["afterCleanup"]["residentBytes"] = 100_000_000
        result = baseline.check(self.record, self.budgets, self.compile, self.runtime)
        self.assertFalse(result["passed"])
        self.assertEqual(len(result["misses"]), 5)

    def test_incomplete_and_duplicate_matrices_rejected(self):
        for kind in ("compile", "runtime"):
            for duplicate in (False, True):
                report = copy.deepcopy(self.compile if kind == "compile" else self.runtime)
                report["workloads"].pop()
                if duplicate:
                    report["workloads"].append(report["workloads"][0])
                with self.assertRaises(ValueError):
                    baseline.collect_report(report, kind)

    def test_functional_gates_cleanup_and_schema_growth_rejected(self):
        mutations = [lambda row: row.update(functionalGatesPassed=False),
                     lambda row: row["cleanup"].update(activeHandlers=1),
                     lambda row: row.update(schemasAfterInvocations=10000),
                     lambda row: row.update(schemaBuilds=0, schemasAfterInvocations=0),
                     lambda row: row.update(invocations=1),
                     lambda row: row.update(invocations=True),
                     lambda row: row["latency"].update(p95Milliseconds=100),
                     lambda row: row["latency"].update(sampleCount=1001),
                     lambda row: row["afterCleanup"].update(peakRSSBytes=0),
                     lambda row: row["accountedState"].update(maximumWorkers=9),
                     lambda row: row["accountedState"].update(retainedSchemas=0),
                     lambda row: row["counters"].update(peakWorkers=9),
                     lambda row: row["counters"].update(callbacks=999),
                     lambda row: row.update(implicitHydrationRequests=1),
                     lambda row: row.update(memoryObservations=[]),
                     lambda row: row["memoryObservations"][0].update(elapsedSeconds=11),
                     lambda row: row["memoryObservations"][0].update(completedInvocations=1001)]
        for mutate in mutations:
            report = copy.deepcopy(self.runtime)
            mutate(report["workloads"][0])
            with self.assertRaises(ValueError):
                baseline.collect_report(report, "runtime")

    def test_configuration_bounds_are_not_overridden_by_success_assertion(self):
        for key, value in (("invocations", True), ("concurrency", 0), ("concurrency", 65), ("sampleLimit", 100_001),
                           ("payloadBytes", 1025), ("minimumDurationSeconds", 1801), ("handlerCounts", [10])):
            report = copy.deepcopy(self.runtime)
            report["configuration"][key] = value
            with self.assertRaises(ValueError):
                baseline.collect_report(report, "runtime")

    def test_duration_floor_requires_real_elapsed_time(self):
        self.runtime["configuration"]["minimumDurationSeconds"] = 60
        with self.assertRaises(ValueError):
            baseline.collect_report(self.runtime, "runtime")

    def test_nonfinite_negative_bool_missing_and_incompatible_evidence_rejected(self):
        for value in (float("nan"), float("inf"), -1, True, None):
            report = copy.deepcopy(self.compile)
            report["workloads"][0]["samples"][0]["clean"]["wallSeconds"] = value
            with self.assertRaises(ValueError):
                baseline.collect_report(report, "compile")
        self.runtime["environment"]["compiler"] = "other compiler"
        with self.assertRaises(ValueError):
            baseline.check(self.record, self.budgets, self.compile, self.runtime)

    def test_unavailable_environment_cannot_become_a_baseline(self):
        for key in baseline.ENVIRONMENT_KEYS:
            report = copy.deepcopy(self.runtime)
            report["environment"][key] = "unavailable"
            with self.assertRaises(ValueError):
                baseline.collect_report(report, "runtime")

    def test_budget_binding_coverage_and_direction_rejected(self):
        for mutate in (lambda budget: budget.update(baselineHash="bad"),
                       lambda budget: budget["limits"].pop(next(iter(budget["limits"]))),
                       lambda budget: budget["limits"].update({next(iter(budget["limits"])): {"minimum": 1}})):
            budget = copy.deepcopy(self.budgets)
            mutate(budget)
            with self.assertRaises(ValueError):
                baseline.check(self.record, budget, self.compile, self.runtime)

    def test_finite_tolerances_and_time_units(self):
        for value in (float("nan"), float("inf"), -0.1, 1.1):
            with self.assertRaises(ValueError):
                baseline.budgets(self.record, value)
        self.assertAlmostEqual(self.budgets["limits"]["compile.manual.10.0.clean.wallSeconds"]["maximum"], 2.200001)
        self.assertAlmostEqual(self.budgets["limits"]["runtime.direct.10.planCompilationMilliseconds"]["maximum"], 1.101)
        self.assertEqual(self.budgets["limits"]["runtime.direct.10.invocationsPerSecond"]["minimum"], 90)

    def test_submillisecond_tail_regression_exceeds_reviewed_observation_floor(self):
        self.runtime["workloads"][0]["latency"].update(p50Milliseconds=0.1, p95Milliseconds=0.15, p99Milliseconds=0.2)
        measured = baseline.record(self.compile, self.runtime)
        reviewed = baseline.budgets(measured)
        self.runtime["workloads"][0]["latency"]["p99Milliseconds"] = 0.4
        result = baseline.check(measured, reviewed, self.compile, self.runtime)
        self.assertFalse(result["passed"])
        self.assertEqual([miss["metric"] for miss in result["misses"]], ["runtime.direct.10.latency.p99Milliseconds"])
        self.assertAlmostEqual(result["misses"][0]["maximum"], 0.221)
        # The superseded 1 ms floor would conceal this twofold tail-latency change.
        self.assertTrue(baseline.check(measured, baseline.budgets(measured, time_floor=0.001), self.compile, self.runtime)["passed"])

    def test_json_nonfinite_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.json"
            path.write_text('{"value": NaN}')
            with self.assertRaises(ValueError):
                baseline.read(path)
            path.write_text('{"value": 1, "value": 2}')
            with self.assertRaises(ValueError):
                baseline.read(path)


if __name__ == "__main__":
    unittest.main()
