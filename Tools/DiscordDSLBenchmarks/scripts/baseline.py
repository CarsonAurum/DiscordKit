#!/usr/bin/env python3
"""Record complete local DSL evidence, then explicitly derive and check finite budgets.

Recording measurements never approves a threshold. Budget derivation is a separate
operation and embeds the measured baseline hash. Checks require matching hardware,
compiler and workload, the complete matrix and successful functional cleanup gates.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re


COUNTS = {10, 100, 1000}
ENVIRONMENT_KEYS = ("compiler", "operatingSystem", "architecture", "processorCount", "hardwareModel", "physicalMemoryBytes")
SNAPSHOTS = ("beforePlan", "afterPlan", "afterInvocations", "afterCleanup")
SAMPLE_KEYS = ("cpuSeconds", "peakRSSBytes", "residentBytes", "liveAllocationBlocks", "liveAllocationBytes")


def positive_number(value, path, zero=True):
    """Reject booleans, nonfinite values and invalid negative resource evidence."""
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 or (not zero and value == 0):
        raise ValueError(f"{path} must be a {'nonnegative' if zero else 'positive'} finite number")
    return value


def canonical_hash(value):
    """Bind evidence to deterministic complete JSON, disallowing NaN/Infinity."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def add_metric(metrics, path, value, direction="maximum", zero=True):
    """Adopt a unique numerical measurement and its unambiguous budget direction."""
    positive_number(value, path, zero)
    if path in metrics:
        raise ValueError(f"duplicate metric {path}")
    metrics[path] = {"value": value, "direction": direction}


def bounded_integer(value, low, high, path):
    """Require integral workload/accounting values; booleans never represent counts."""
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f"{path} must be an integer in {low}...{high}")
    return value


def compiler_fingerprint(value):
    """Normalize only the Swift build-version line; retain exact toolchain build identifiers."""
    if not isinstance(value, str):
        raise ValueError("compiler identity must be text")
    match = re.search(r"(?:Apple )?Swift version (\d+)\.(\d+)[^\n]*", value)
    if not match or tuple(map(int, match.groups())) < (6, 4):
        raise ValueError("Swift 6.4 or newer compiler evidence is required")
    return match.group()


def validate_configuration(configuration, kind):
    """Require explicit finite workload bounds before accepting measurement assertions."""
    if configuration.get("handlerCounts") != [10, 100, 1000] or any(type(value) is not int for value in configuration["handlerCounts"]):
        raise ValueError("configuration must select exactly 10/100/1000 handlers")
    if kind == "compile":
        bounded_integer(configuration.get("samples"), 1, 5, "samples")
        bounded_integer(configuration.get("jobs"), 1, 32, "jobs")
        if configuration.get("modes") != ["manual", "macro"] or configuration.get("handlersPerFile") != 10 or configuration.get("optionsPerHandler") != 1:
            raise ValueError("compiler declaration workload differs")
        if configuration.get("dependencyColdBuildIncluded") is not False or configuration.get("buildSystem") != "native" or configuration.get("configuration") != "debug":
            raise ValueError("compiler measurement boundary differs")
    else:
        bounded_integer(configuration.get("invocations"), 1, 10_000_000, "invocations")
        bounded_integer(configuration.get("concurrency"), 1, 64, "concurrency")
        bounded_integer(configuration.get("sampleLimit"), 1, 100_000, "sampleLimit")
        bounded_integer(configuration.get("payloadBytes"), 1, 1024, "payloadBytes")
        bounded_integer(configuration.get("minimumDurationSeconds"), 0, 1800, "minimumDurationSeconds")


def collect_report(report, kind):
    """Validate complete compiler/runtime matrices and collect explicit metric families."""
    if report.get("schemaVersion") != 1:
        raise ValueError(f"unsupported {kind} report version")
    environment = report.get("environment", {})
    for key in ENVIRONMENT_KEYS:
        if key not in environment or environment[key] in (None, "") or (isinstance(environment[key], str) and environment[key].casefold() in {"unavailable", "unknown", "not recorded"}):
            raise ValueError(f"missing {kind} environment {key}")
    bounded_integer(environment["processorCount"], 1, 1_000_000, "processorCount")
    bounded_integer(environment["physicalMemoryBytes"], 1, 2 ** 60, "physicalMemoryBytes")
    compiler_fingerprint(environment["compiler"])
    if not isinstance(report.get("configuration"), dict):
        raise ValueError(f"missing {kind} configuration")
    validate_configuration(report["configuration"], kind)
    modes = {"manual", "macro"} if kind == "compile" else {"direct", "dsl"}
    rows = report.get("workloads", [])
    expected = {(mode, count) for mode in modes for count in COUNTS}
    actual = [(row.get("mode"), row.get("handlerCount")) for row in rows]
    if len(actual) != 6 or set(actual) != expected:
        raise ValueError(f"{kind} requires exactly all 10/100/1000 {sorted(modes)} workloads")
    metrics = {}
    for row in rows:
        bounded_integer(row.get("handlerCount"), 10, 1000, kind + ".handlerCount")
        prefix = f"{kind}.{row['mode']}.{row['handlerCount']}"
        if row.get("functionalGatesPassed") is not True:
            raise ValueError(f"{prefix} functional gates failed")
        if kind == "compile":
            samples = row.get("samples", [])
            if len(samples) != report["configuration"].get("samples") or not samples:
                raise ValueError(f"{prefix} incomplete samples")
            for index, sample in enumerate(samples):
                for operation in ("clean", "incremental"):
                    for key in ("wallSeconds", "peakRSSBytes"):
                        add_metric(metrics, f"{prefix}.{index}.{operation}.{key}", sample[operation][key], zero=False)
                add_metric(metrics, f"{prefix}.{index}.binaryBytes", sample["binaryBytes"], zero=False)
        else:
            configuration = report["configuration"]
            invocations = bounded_integer(row.get("invocations"), 1, 100_000_000, prefix + ".invocations")
            if invocations < configuration.get("invocations", math.inf) or invocations > 100_000_000:
                raise ValueError(f"{prefix} invocation floor or finite ceiling failed")
            if configuration["minimumDurationSeconds"] == 0 and invocations != configuration["invocations"]:
                raise ValueError(f"{prefix} invocation count differs from configured fixed work")
            for key in ("planCompilationMilliseconds", "durationSeconds"):
                add_metric(metrics, f"{prefix}.{key}", row.get(key), zero=False)
            if row["durationSeconds"] < configuration["minimumDurationSeconds"]:
                raise ValueError(f"{prefix} did not satisfy configured duration floor")
            add_metric(metrics, f"{prefix}.invocationsPerSecond", row.get("invocationsPerSecond"), "minimum", zero=False)
            if not math.isclose(row["invocationsPerSecond"], invocations / row["durationSeconds"], rel_tol=0.000001):
                raise ValueError(f"{prefix} throughput disagrees with completed work and elapsed time")
            latency = row.get("latency", {})
            bounded_integer(latency.get("sampleCount"), 1, min(invocations, configuration["sampleLimit"]), prefix + ".latency.sampleCount")
            previous = 0
            for key in ("p50Milliseconds", "p95Milliseconds", "p99Milliseconds"):
                value = positive_number(latency.get(key), prefix + ".latency." + key)
                if value < previous:
                    raise ValueError(f"{prefix} unordered latency quantiles")
                previous = value
                add_metric(metrics, f"{prefix}.latency.{key}", value)
            if type(row.get("schemaBuilds")) is not int or row["schemaBuilds"] != row["handlerCount"] or row["schemaBuilds"] != row.get("schemasAfterInvocations"):
                raise ValueError(f"{prefix} schemas grew during invocations")
            cleanup = row.get("cleanup", {})
            for key in ("activeHandlers", "activeAcknowledgements", "acknowledgementBytes", "activeWorkers"):
                if type(cleanup.get(key)) is not int or cleanup[key] != 0:
                    raise ValueError(f"{prefix} cleanup {key} is not zero")
            for name in SNAPSHOTS:
                snapshot = row.get(name, {})
                positive_number(snapshot.get("peakRSSBytes"), prefix + "." + name + ".peakRSSBytes", zero=False)
                for key in SAMPLE_KEYS:
                    if snapshot.get(key) is not None:
                        add_metric(metrics, f"{prefix}.{name}.{key}", snapshot[key])
            observations = row.get("memoryObservations", [])
            if not isinstance(observations, list) or not 1 <= len(observations) <= 121:
                raise ValueError(f"{prefix} missing or excessive memory observations")
            previous_time, previous_work = 0, 0
            for observation in observations:
                elapsed = positive_number(observation.get("elapsedSeconds"), prefix + ".memory.elapsedSeconds", zero=False)
                completed = bounded_integer(observation.get("completedInvocations"), 1, invocations, prefix + ".memory.completedInvocations")
                if not previous_time < elapsed <= row["durationSeconds"] or completed <= previous_work:
                    raise ValueError(f"{prefix} unordered/out-of-range memory observations")
                previous_time, previous_work = elapsed, completed
                positive_number(observation.get("process", {}).get("peakRSSBytes"), prefix + ".memory.peakRSSBytes", zero=False)
            for key in SAMPLE_KEYS:
                values = [observation["process"][key] for observation in observations if observation["process"].get(key) is not None]
                for value in values:
                    positive_number(value, prefix + ".memory." + key)
                if values:
                    add_metric(metrics, f"{prefix}.memoryMaximum.{key}", max(values))
            accounted = row.get("accountedState", {})
            if not accounted:
                raise ValueError(f"{prefix} lacks accounted state")
            expected_accounting = {"declaredHandlers": row["handlerCount"], "retainedSchemas": row["handlerCount"],
                "fixedInteractionCount": row["handlerCount"], "maximumWorkers": configuration["concurrency"],
                "maximumLatencySamples": configuration["sampleLimit"], "maximumMemorySamples": 121,
                "maximumPayloadBytes": configuration["payloadBytes"], "maximumActualInvocations": 100_000_000}
            for key, expected_value in expected_accounting.items():
                if type(accounted.get(key)) is not int or accounted[key] != expected_value:
                    raise ValueError(f"{prefix} invalid accounted bound {key}")
            for key in ("fixedInteractionJSONBytes", "registrationJSONBytes", "routeMetadataJSONBytes"):
                bounded_integer(accounted.get(key), 1, 64 * 1024 * 1024, prefix + ".accountedState." + key)
            description_bytes = bounded_integer(accounted.get("planDescriptionTextBytes"), 0, 16 * 1024 * 1024, prefix + ".accountedState.planDescriptionTextBytes")
            if (row["mode"] == "direct" and description_bytes != 0) or (row["mode"] == "dsl" and description_bytes == 0):
                raise ValueError(f"{prefix} invalid plan description accounting")
            counters = row.get("counters", {})
            for key, expected_value in {"schemas": 0, "handlers": invocations, "callbacks": invocations, "activeWorkers": 0}.items():
                if type(counters.get(key)) is not int or counters[key] != expected_value:
                    raise ValueError(f"{prefix} invalid invocation counter {key}")
            bounded_integer(counters.get("peakWorkers"), 1, configuration["concurrency"], prefix + ".peakWorkers")
            for key in ("implicitHydrationRequests", "implicitRegistrationRequests"):
                if type(row.get(key)) is not int or row[key] != 0:
                    raise ValueError(f"{prefix} implicit remote work {key}")
            for key, value in accounted.items():
                add_metric(metrics, f"{prefix}.accountedState.{key}", value)
    identity = {"environment": {key: environment[key] for key in ENVIRONMENT_KEYS}, "configuration": report["configuration"]}
    if kind == "compile":
        for key in ("fixtureHash", "resolutionHash"):
            if not isinstance(report.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", report[key]):
                raise ValueError(f"missing compiler {key}")
            identity[key] = report[key]
    return identity, metrics


def record(compile_report, runtime_report):
    """Record measured values without introducing regression tolerances."""
    identities, metrics = {}, {}
    for kind, report in (("compile", compile_report), ("runtime", runtime_report)):
        identities[kind], values = collect_report(report, kind)
        metrics.update(values)
    compile_environment, runtime_environment = compile_report["environment"], runtime_report["environment"]
    for key in ("architecture", "processorCount", "hardwareModel", "physicalMemoryBytes"):
        if compile_environment[key] != runtime_environment[key]:
            raise ValueError("compile and runtime reports must come from the same hardware")
    if compiler_fingerprint(compile_environment["compiler"]) != compiler_fingerprint(runtime_environment["compiler"]):
        raise ValueError("compile and runtime reports must use the same Swift toolchain build")
    return {"schemaVersion": 1, "reportKind": "dsl-local-baseline", "identities": identities, "measurements": metrics,
            "sourceReports": {"compile": canonical_hash(compile_report), "runtime": canonical_hash(runtime_report)}}


def budgets(baseline, tolerance=0.1, time_floor=0.000001, memory_floor=1048576):
    """Derive explicit finite thresholds only after a recorded measured baseline exists."""
    if baseline.get("reportKind") != "dsl-local-baseline" or not baseline.get("measurements"):
        raise ValueError("a recorded baseline is required before budget derivation")
    if not math.isfinite(tolerance) or not 0 <= tolerance <= 1:
        raise ValueError("relative tolerance must be finite in 0...1")
    positive_number(time_floor, "time floor")
    positive_number(memory_floor, "memory floor")
    limits = {}
    for path, metric in baseline["measurements"].items():
        value = positive_number(metric["value"], path)
        direction = metric["direction"]
        if direction not in ("minimum", "maximum"):
            raise ValueError("unknown metric direction")
        # The absolute time floor is numerical observation tolerance, not evidence
        # of clock resolution. RSS floors bound allocator page noise.
        floor = memory_floor if path.endswith(("RSSBytes", "residentBytes", "liveAllocationBytes")) else 0
        if path.endswith(("Seconds", "Milliseconds")):
            floor = time_floor * (1000 if path.endswith("Milliseconds") else 1)
        threshold = value * (1 - tolerance) if direction == "minimum" else value * (1 + tolerance) + floor
        positive_number(threshold, path + " threshold")
        limits[path] = {direction: threshold}
    return {"schemaVersion": 1, "reportKind": "dsl-local-budgets", "baselineHash": canonical_hash(baseline),
            "policy": {"relativeTolerance": tolerance, "absoluteTimeFloorSeconds": time_floor,
                       "absoluteMemoryFloorBytes": memory_floor, "attributionRequiresMatchingRuns": 3}, "limits": limits}


def check(baseline, budget, compile_report, runtime_report):
    """Fail closed on incompatible evidence; return all finite numerical threshold misses."""
    current = record(compile_report, runtime_report)
    if baseline.get("schemaVersion") != 1 or budget.get("schemaVersion") != 1 or budget.get("reportKind") != "dsl-local-budgets":
        raise ValueError("unsupported baseline or budget schema")
    if budget.get("baselineHash") != canonical_hash(baseline):
        raise ValueError("budgets do not refer to this recorded baseline")
    if current["identities"] != baseline.get("identities"):
        raise ValueError("hardware/compiler/workload identity differs from the local baseline")
    metrics = current["measurements"]
    if set(metrics) != set(baseline.get("measurements", {})) or set(metrics) != set(budget.get("limits", {})):
        raise ValueError("measurement or budget matrix is incomplete")
    misses = []
    for path, metric in metrics.items():
        bounds = budget["limits"][path]
        if set(bounds) != {metric["direction"]}:
            raise ValueError(f"incorrect direction or missing bound for {path}")
        threshold = positive_number(bounds[metric["direction"]], path + " budget")
        value = metric["value"]
        if (metric["direction"] == "maximum" and value > threshold) or (metric["direction"] == "minimum" and value < threshold):
            misses.append({"metric": path, "observed": value, **bounds})
    return {"schemaVersion": 1, "passed": not misses, "misses": misses,
            "selfCheck": current["sourceReports"] == baseline.get("sourceReports"),
            "controlledRegressionDemonstrated": False,
            "attribution": "A threshold miss needs three matching runs before regression attribution."}


def read(path):
    """Read bounded JSON evidence and reject extensions accepting NaN/Infinity."""
    if path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError("report exceeds 8 MiB bound")
    def unique_keys(pairs):
        """Never let duplicate-key last-wins parsing rewrite hash-bound evidence."""
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique_keys,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"nonfinite JSON {value}")))


def main():
    """Expose separate record/budgets/check operations with explicit output artifacts."""
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    for name in ("record", "budgets", "check"):
        sub = subparsers.add_parser(name)
        sub.add_argument("--output", type=Path, required=True)
        if name != "budgets":
            sub.add_argument("--compile-report", type=Path, required=True)
            sub.add_argument("--runtime-report", type=Path, required=True)
        if name != "record":
            sub.add_argument("--baseline", type=Path, required=True)
        if name == "check":
            sub.add_argument("--budgets", type=Path, required=True)
        if name == "budgets":
            sub.add_argument("--tolerance", type=float, default=0.1)
            sub.add_argument("--time-floor-seconds", type=float, default=0.000001)
            sub.add_argument("--memory-floor-bytes", type=int, default=1048576)
    arguments = parser.parse_args()
    try:
        if arguments.operation == "record":
            result = record(read(arguments.compile_report), read(arguments.runtime_report))
        elif arguments.operation == "budgets":
            result = budgets(read(arguments.baseline), arguments.tolerance, arguments.time_floor_seconds, arguments.memory_floor_bytes)
        else:
            result = check(read(arguments.baseline), read(arguments.budgets), read(arguments.compile_report), read(arguments.runtime_report))
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
        if arguments.operation == "check" and not result["passed"]:
            parser.exit(1, f"DSL budget check: {len(result['misses'])} thresholds exceeded; repeat three matching runs before attribution.\n")
    except (ValueError, TypeError, KeyError, OSError) as error:
        parser.exit(1, f"DSL evidence rejected: {error}\n")


if __name__ == "__main__":
    main()
