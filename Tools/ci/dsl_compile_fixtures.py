#!/usr/bin/env python3
"""Compile external macro consumers and require semantic errors for negative fixtures.

This checks real Swift type checking and plugin loading, not printed expansions.
Each target is selected separately so deliberately invalid consumers cannot poison
the positive build. All builds share one scratch directory and have a finite
timeout. No fixture starts a Discord request, host, handler or registration.
"""

import argparse
from dataclasses import dataclass
import math
from pathlib import Path
import subprocess


@dataclass(frozen=True)
class Fixture:
    """One external Swift target and its required compiler failure fragments.

    An empty diagnostics tuple requires successful compilation. Otherwise every
    case-insensitive fragment must appear in a nonzero compiler result containing
    an error diagnostic. Locations and exact full messages are intentionally free
    to vary between compatible Swift toolchains.
    """

    target: str
    diagnostics: tuple[str, ...] = ()


FIXTURES = (
    Fixture("PositiveExternal"),
    Fixture("InvalidCommandMetadata", ("@SlashCommand requires a valid literal name",)),
    Fixture("DynamicMetadata", ("@SlashCommand requires a valid literal name",)),
    Fixture("ComputedOption", ("one explicitly typed stored property",)),
    Fixture("MissingOption", ("every instance property requires exactly one @Option",)),
    Fixture("InferredType", ("one explicitly typed stored property",)),
    Fixture("InitializedLet", ("initialized let options cannot be decoded",)),
    Fixture("MultipleBindings", ("one explicitly typed stored property",)),
    Fixture("DynamicDefault", ("option defaults must be finite scalar literals",)),
    Fixture("WrongDefaultType", ("option default is incompatible",)),
    Fixture("UnsupportedArgumentType", ("does not conform", "ArgumentValue")),
    Fixture("NonSendableHandler", ("non-sendable type", "MutableState")),
    Fixture("DuplicateOptions", ("duplicate Discord option name",)),
    Fixture("UnsupportedOptionMetadata", ("@Option requires a valid literal name",)),
    Fixture("MissingArgumentsAlias", ("@SlashCommand requires an explicit Arguments typealias",)),
)


@dataclass(frozen=True)
class Result:
    """One qualification result with bounded diagnostic text for actionable CI failures."""

    target: str
    passed: bool
    detail: str


def compiler_command(repository, scratch_path, target, swift="swift", cache_path=None):
    """Create a shell-free command that selects exactly one external consumer target.

    Parameters:
        repository: Absolute checkout root containing the separate fixture package.
        scratch_path: Writable SwiftPM build directory shared across fixture cases.
        target: Committed fixture target name, passed as one argument without shell expansion.
        swift: Swift executable name or absolute path, defaulting to PATH resolution.
        cache_path: Optional shared writable SwiftPM cache; default is checkout-local.
    Returns:
        Argument list with explicit package, cache, scratch and target selection.
        SwiftPM sandboxing is disabled for compiler plugins in managed CI; this
        does not alter the surrounding environment's permission boundary.
    """
    return [swift, "build", "--disable-sandbox", "--package-path",
            str(repository / "Tests/Fixtures/DSLCompile"), "--scratch-path", str(scratch_path),
            "--cache-path", str(cache_path or repository / ".build/dsl-compile-cache"),
            "--explicit-target-dependency-import-check", "error", "--target", target]


def assess(fixture, completed):
    """Require actual success or the selected semantic compiler failure, never just nonzero exit.

    Parameters:
        fixture: Expected target and required diagnostic fragments.
        completed: CompletedProcess-like value with returncode, stdout and stderr strings.
    Returns:
        Bounded Result. A failed negative case lists missing semantic fragments,
        preventing plugin crashes, resolution errors or unrelated type errors
        from satisfying a compile-failure expectation.
    """
    output = (completed.stdout or "") + "\n" + (completed.stderr or "")
    if not fixture.diagnostics:
        passed = completed.returncode == 0
        return Result(fixture.target, passed, "compiled" if passed else output[-12000:])
    if completed.returncode == 0:
        return Result(fixture.target, False, "negative fixture unexpectedly compiled")
    folded = output.casefold()
    missing = [fragment for fragment in fixture.diagnostics if fragment.casefold() not in folded]
    if "error:" not in folded:
        missing.append("error:")
    if missing:
        return Result(fixture.target, False, "missing expected compiler diagnostics: " + ", ".join(missing) + "\n" + output[-12000:])
    return Result(fixture.target, True, "expected compiler diagnostics observed")


def run_fixtures(repository, scratch_path, timeout=600, swift="swift", run=subprocess.run, fixtures=FIXTURES, cache_path=None):
    """Compile external fixtures sequentially through an injectable bounded process runner.

    Parameters:
        repository: Checkout root; no source or manifest is rewritten.
        scratch_path: Shared writable build directory, created by SwiftPM.
        timeout: Positive finite per-build seconds; default ten minutes permits a cold plugin build.
        swift: Compiler executable path or name, default swift.
        run: subprocess.run-compatible injection used by deterministic runner unit tests.
        fixtures: Ordered fixture sequence; committed qualification begins with a positive consumer.
        cache_path: Optional shared writable SwiftPM cache; default is checkout-local.
    Returns:
        Results in fixture order. A failed positive build stops the run because
        plugin/toolchain infrastructure has not been established. Negative-case
        failures continue so a single run reports all semantic mismatches.
    Raises:
        ValueError: Timeout is nonpositive, nonfinite, or the first fixture is not positive.
        KeyboardInterrupt: User interruption propagates instead of becoming qualification evidence.
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
    """Run independent type-checking qualification and exit nonzero for missing or incorrect evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--scratch-path", type=Path)
    parser.add_argument("--cache-path", type=Path, help="optional shared writable SwiftPM dependency cache")
    parser.add_argument("--timeout", type=float, default=600, help="finite seconds per compiler invocation")
    parser.add_argument("--swift", default="swift")
    arguments = parser.parse_args()
    repository = arguments.repository.resolve()
    scratch_path = arguments.scratch_path or repository / ".build/dsl-compile-fixtures"
    try:
        results = run_fixtures(repository, scratch_path, arguments.timeout, arguments.swift, cache_path=arguments.cache_path)
    except ValueError as error:
        parser.error(str(error))
    for result in results:
        print(f"{'PASS' if result.passed else 'FAIL'} {result.target}: {result.detail}", flush=True)
    passed = sum(result.passed for result in results)
    print(f"External Swift compile fixtures: {passed}/{len(FIXTURES)} passed")
    if len(results) != len(FIXTURES) or passed != len(FIXTURES):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
