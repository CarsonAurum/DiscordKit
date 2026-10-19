#!/usr/bin/env python3
"""Compile public, macro-free extension consumers and reject missing or wrong dependency injection."""

import argparse
import math
from pathlib import Path
import subprocess

from dsl_compile_fixtures import Fixture, Result, assess


FIXTURES = (
    Fixture("PositiveDependencies"),
    Fixture("MissingDependencies", ("missing argument", "dependencies")),
    Fixture("WrongDependencies", ("cannot convert value", "String", "ExtensionDependencies")),
)


def compiler_command(repository, scratch_path, target, swift="swift", cache_path=None):
    """Select exactly one real external target with explicit dependency imports and shared writable caches."""
    return [swift, "build", "--disable-sandbox", "--skip-update", "--package-path",
            str(repository / "Tests/Fixtures/DSLExtensionsCompile"), "--scratch-path", str(scratch_path),
            "--cache-path", str(cache_path or repository / ".build/dsl-extension-cache"),
            "--explicit-target-dependency-import-check", "error", "--target", target]


def run_fixtures(repository, scratch_path, timeout=600, swift="swift", run=subprocess.run,
                 fixtures=FIXTURES, cache_path=None):
    """Require a real successful public consumer before accepting exact semantic failure diagnostics.

    The finite timeout bounds each compiler process. Infrastructure, crashes and unrelated failures
    cannot satisfy the negative cases. Injected process execution supports deterministic runner tests.
    Sources are read-only, and no target executes a handler, host or registration request.
    """
    if not math.isfinite(timeout) or timeout <= 0:
        raise ValueError("timeout must be positive and finite")
    if not fixtures or fixtures[0].diagnostics:
        raise ValueError("external compilation must begin with a positive fixture")
    results = []
    for fixture in fixtures:
        command = compiler_command(repository, scratch_path, fixture.target, swift, cache_path)
        try:
            completed = run(command, cwd=repository, capture_output=True, text=True, timeout=timeout)
            result = assess(fixture, completed)
        except subprocess.TimeoutExpired:
            result = Result(fixture.target, False, f"compiler exceeded {timeout:g} second timeout")
        except OSError as error:
            result = Result(fixture.target, False, "compiler process could not start: " + str(error))
        results.append(result)
        if not result.passed and not fixture.diagnostics:
            break
    return results


def main():
    """Run all committed independent fixtures and report bounded compiler evidence to CI."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--scratch-path", type=Path)
    parser.add_argument("--cache-path", type=Path)
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--swift", default="swift")
    arguments = parser.parse_args()
    repository = arguments.repository.resolve()
    try:
        results = run_fixtures(repository, arguments.scratch_path or repository / ".build/dsl-extension-fixtures",
                               arguments.timeout, arguments.swift, cache_path=arguments.cache_path)
    except ValueError as error:
        parser.error(str(error))
    for result in results:
        print(f"{'PASS' if result.passed else 'FAIL'} {result.target}: {result.detail}", flush=True)
    passed = sum(result.passed for result in results)
    print(f"External dependency fixtures: {passed}/{len(FIXTURES)} passed")
    if len(results) != len(FIXTURES) or passed != len(FIXTURES):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
