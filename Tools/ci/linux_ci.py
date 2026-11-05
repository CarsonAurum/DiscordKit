#!/usr/bin/env python3
# File: Tools/ci/linux_ci.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Run the offline Ubuntu gates with pinned resolution, bounded jobs and durable logs."""

import argparse
from contextlib import suppress
from dataclasses import dataclass
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time


SWIFT_VERSION = "6.4.1"
STAGES = ("root", "authoring", "tooling", "benchmarks", "audit", "consumers", "release")
EXAMPLES = ("RESTOnly", "GatewayBot", "HTTPApp", "CommandsApp", "DSLCommands", "DSLEvents",
            "DSLBot", "OAuthApp", "VoiceBot", "RPCApp", "ActivityHost", "SocialApp", "LoggingApp")


@dataclass(frozen=True)
class Command:
    """One shell-free command; timeout includes its compiler and plugin descendants."""

    name: str
    arguments: tuple[str, ...]
    timeout: float = 1800


def commands(stage, repository, jobs):
    """Plan a serial gate without writing sources or changing package resolution.

    Every Swift build, test and run receives the same positive job limit and
    requires committed pins. Consumer graphs share scratch space sequentially;
    macros, tooling and fixtures retain separate scratch directories.
    """
    if stage not in STAGES:
        raise ValueError(f"unknown Linux stage: {stage}")
    if type(jobs) is not int or jobs <= 0:
        raise ValueError("jobs must be a positive integer")
    repository = repository.resolve()
    python = sys.executable
    planned = []

    def add(name, *arguments, timeout=1800):
        """Append one bounded command with literal argument boundaries."""
        planned.append(Command(name, tuple(map(str, arguments)), timeout))

    def swift(name, verb, package=".", *arguments, scratch=None):
        """Apply Linux resource and dependency policy to a SwiftPM invocation."""
        add(name, "swift", verb, "--package-path", package, "--jobs", jobs,
            "--force-resolved-versions", *(["--scratch-path", scratch] if scratch else []), *arguments)

    def tests(name, directory):
        """Run deterministic Python helpers with the selected interpreter."""
        add(name, python, "-m", "unittest", "discover", "-s", directory, "-p", "test_*.py")

    if stage == "root":
        swift("build", "build")
        swift("test", "test")
    elif stage == "authoring":
        for package, helper in (("DiscordDSLMacros", "dsl_compile_fixtures.py"),
                                ("DiscordDSLExtensions", "dsl_extension_fixtures.py")):
            swift(package, "test", f"Packages/{package}", "--explicit-target-dependency-import-check", "error")
            # Cold SwiftSyntax builds can exceed the old ten-minute fixture limit.
            add(helper, python, f"Tools/ci/{helper}", "--repository", repository,
                "--jobs", jobs, "--timeout", "1200", timeout=2400)
    elif stage == "tooling":
        for package in ("DiscordKitTools", "DiscordKitLoadTests"):
            swift(package, "test", f"Tools/{package}")
            tests(f"{package}-python", f"Tools/{package}/scripts")
        tests("ci-python", "Tools/ci")
        browser_tests = sorted(str(path.relative_to(repository)) for path in
                               (repository / "Browser/DiscordActivityBridge").glob("*.test.mjs"))
        if not browser_tests:
            raise ValueError("browser bridge tests are missing")
        add("browser", "node", "--test", *browser_tests)
    elif stage == "benchmarks":
        swift("test", "test", "Tools/DiscordDSLBenchmarks", "--explicit-target-dependency-import-check", "error")
        tests("python", "Tools/DiscordDSLBenchmarks/scripts")
        swift("smoke", "run", "Tools/DiscordDSLBenchmarks", "--configuration", "release",
              "DiscordDSLBenchmarks", "--invocations", "1000", "--output", ".build/dsl-measurements/runtime-smoke.json")
    elif stage == "audit":
        for operation in (("documentation", "audit"), ("inventory", "validate"),
                          ("generate", "--check"), ("parity", "check")):
            swift(operation[0], "run", "Tools/DiscordKitTools", "DiscordKitTools", *operation, "--repository", ".")
        add("social-catalog", python, "Tools/DiscordKitTools/scripts/verify_social_catalog.py")
        script = "Tools/DiscordKitTools/scripts/release_check.py"
        add("graph", python, script, "graph", "--repository", ".")
        for report in ("release-report-0.14.0", "release-report-0.15.0", "release-report-0.15.0-final",
                       "semantic-logging-report", "publication-report"):
            add(report, python, script, "report", "--repository", ".", "--report", f"Docs/Release/{report}.json")
    elif stage == "consumers":
        scratch = str(repository / ".build/consumers")
        for example in EXAMPLES:
            swift(f"build-{example}", "build", f"Examples/{example}", "--explicit-target-dependency-import-check", "error", scratch=scratch)
        for example in ("LoggingApp", "CommandsApp", "DSLCommands", "DSLEvents", "DSLBot", "ActivityHost"):
            swift(f"test-{example}", "test", f"Examples/{example}", scratch=scratch)
        for example in ("LoggingApp", "CommandsApp", "DSLCommands", "DSLEvents", "DSLBot", "VoiceBot", "SocialApp"):
            swift(f"run-{example}", "run", f"Examples/{example}", example,
                  *(["--offline"] if example == "DSLCommands" else []), scratch=scratch)
    elif stage == "release":
        for name, package in (("root", "."), ("macros", "Packages/DiscordDSLMacros"),
                              ("extensions", "Packages/DiscordDSLExtensions")):
            swift(name, "build", package, "--configuration", "release")
    return planned


def preflight(repository, output):
    """Record nonsecret host evidence and reject the wrong OS, compiler or target.

    The workflow installs the compiler and Ubuntu dependencies before this check.
    Nothing is installed here, and the helper never changes the caller's toolchain
    or PATH.
    """
    output.mkdir(parents=True, exist_ok=True)
    host = {"system": platform.system(), "machine": platform.machine(),
            "python": platform.python_version(), "disk": shutil.disk_usage(repository)._asdict()}
    if platform.system() != "Linux":
        raise ValueError("Ubuntu validation requires a native Linux host or container")
    host["osRelease"] = platform.freedesktop_os_release()
    host["memory"] = Path("/proc/meminfo").read_text()
    host["revision"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repository,
                                              text=True, timeout=30).strip()
    (output / "host.json").write_text(json.dumps(host, indent=2) + "\n")
    if host["osRelease"].get("ID") != "ubuntu" or host["osRelease"].get("VERSION_ID") != "24.04":
        raise ValueError("Ubuntu validation requires Ubuntu 24.04")
    for executable in ("swift", "swiftc", "clang", "git", "node", "python3"):
        if not shutil.which(executable):
            raise ValueError(f"required executable is missing: {executable}")
    version = subprocess.check_output(["swift", "--version"], text=True, timeout=30)
    target = json.loads(subprocess.check_output(["swift", "-print-target-info"], text=True, timeout=30))
    (output / "swift-version.txt").write_text(version)
    (output / "target.json").write_text(json.dumps(target, indent=2) + "\n")
    if not re.search(rf"\bSwift version {re.escape(SWIFT_VERSION)}(?:\s|$)", version):
        raise ValueError(f"expected Swift {SWIFT_VERSION}: {version.strip()}")
    if "linux" not in target["target"]["triple"].split("-"):
        raise ValueError("expected a native Linux Swift target")
    print(json.dumps(host, indent=2), version, flush=True)


def stop_process_group(process):
    """Terminate timed-out SwiftPM, compiler and plugin processes as one group."""
    with suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    # The parent can exit before a compiler child; always clean the whole group.
    with suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGKILL)
    process.wait()


def execute(command, repository, log):
    """Stream merged output to console and disk; fail on timeout or nonzero exit.

    A separate session owns the complete command tree. Failed commands are never
    retried, and KeyboardInterrupt also terminates their descendants.
    """
    environment = dict(os.environ, SWIFTNIO_STRICT="1", PYTHONUNBUFFERED="1")
    with log.open("w") as destination:
        destination.write(shlex.join(command.arguments) + "\n")
        destination.flush()
        with subprocess.Popen(command.arguments, cwd=repository, env=environment, start_new_session=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace") as process:
            def forward():
                """Drain compiler output without retaining the complete log in memory."""
                try:
                    for line in process.stdout:
                        destination.write(line)
                        destination.flush()
                        print(line, end="", flush=True)
                except Exception as error:
                    forwarding_errors.append(error)
            forwarding_errors = []
            worker = threading.Thread(target=forward, daemon=True)
            deadline = time.monotonic() + command.timeout
            worker.start()
            try:
                result = process.wait(timeout=command.timeout)
                # A compiler child can outlive SwiftPM while retaining stdout.
                # The same deadline covers both parent exit and output draining.
                worker.join(timeout=max(0, deadline - time.monotonic()))
                if worker.is_alive():
                    raise subprocess.TimeoutExpired(command.arguments, command.timeout)
                if forwarding_errors:
                    raise OSError(f"could not preserve command output: {forwarding_errors[0]}")
            except BaseException:
                stop_process_group(process)
                worker.join(timeout=5)
                raise
            if result:
                stop_process_group(process)
                raise subprocess.CalledProcessError(result, command.arguments)


def run_stage(stage, repository, output, jobs):
    """Persist each command's state before execution and stop at the first failure.

    The initial running state survives cancellation; only a fully completed stage
    records passed. Reports and full logs are safe to upload on failed offline runs.
    """
    planned = commands(stage, repository, jobs)
    output.mkdir(parents=True, exist_ok=True)
    if stage == "benchmarks":
        (repository / ".build/dsl-measurements").mkdir(parents=True, exist_ok=True)
    report = {"stage": stage, "status": "running", "jobs": jobs, "commands": []}
    report_path = output / f"{stage}.json"

    def save():
        """Atomically replace the progress report after every state transition."""
        temporary = report_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(report, indent=2) + "\n")
        temporary.replace(report_path)

    save()
    for index, command in enumerate(planned):
        log = output / f"{stage}-{index:02d}-{command.name}.log"
        record = {"name": command.name, "arguments": command.arguments,
                  "log": log.name, "status": "running"}
        report["commands"].append(record)
        save()
        print(f"::group::{stage}: {command.name}\n{shlex.join(command.arguments)}", flush=True)
        started = time.monotonic()
        try:
            execute(command, repository, log)
        except BaseException as error:
            record.update(status="failed", error=str(error), seconds=round(time.monotonic() - started, 3))
            report["status"] = "failed"
            save()
            raise
        else:
            record.update(status="passed", seconds=round(time.monotonic() - started, 3))
            save()
        finally:
            print("::endgroup::", flush=True)
    report["status"] = "passed"
    save()


def main():
    """Run selected native Ubuntu gates with two compiler jobs unless overridden."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--stage", choices=("preflight", *STAGES, "all"), default="all")
    arguments = parser.parse_args()
    if arguments.jobs <= 0:
        parser.error("jobs must be a positive integer")
    repository = arguments.repository.resolve()
    output = arguments.output or repository / ".build/linux-ci"
    try:
        preflight(repository, output)
        for stage in STAGES if arguments.stage == "all" else (() if arguments.stage == "preflight" else (arguments.stage,)):
            run_stage(stage, repository, output, arguments.jobs)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Ubuntu validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
