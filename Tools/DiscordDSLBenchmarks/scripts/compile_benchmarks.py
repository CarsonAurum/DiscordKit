#!/usr/bin/env python3
"""Measure finite external DSL consumers; no credentials, sockets or handlers run.

The bootstrap is separately reported. Measured clean builds remove only the named
consumer's outputs, retaining dependency and macro-plugin compilation. Incremental
builds change one response literal in the first ten-handler file, restore that file
in finally, and include ordinary SwiftPM planning, type checking, codegen and linking.
"""

import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time


COUNTS = (10, 100, 1000)
MODES = ("manual", "macro")
MARKER = ".discord-dsl-compiler-benchmark"


def digest_files(paths, root):
    """Hash relative names and exact bytes in deterministic order, without mtimes."""
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(str(path.relative_to(root)).encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def generated_sources(count, macro):
    """Return bounded concrete declarations with ten handlers per compilation file."""
    if count not in COUNTS:
        raise ValueError("handler count must be 10, 100 or 1000")
    imports = "import DiscordCommandDSL\nimport DiscordDSL\n"
    if macro:
        imports += "import DiscordDSLMacros\n"
    arguments = """@CommandArguments struct Arguments: Sendable {
    @Option(description: "Text") let text: String
}
""" if macro else """struct Arguments: CommandArguments {
    let text: String
    static var schema: CommandArgumentSchema<Self> {
        get throws {
            let text = try ArgumentOption<String>(name: "text", description: "Text")
            return try CommandArgumentSchema(options: [text.erased]) { try Self(text: $0.value(for: text)) }
        }
    }
}
"""
    sources = {"Arguments.swift": imports + arguments}
    for group in range(count // 10):
        text = imports
        for index in range(group * 10, group * 10 + 10):
            if macro:
                text += f'@SlashCommand("command{index}", description: "Bounded compiler fixture")\n'
            text += f"struct Handler{index}: SlashCommandHandler {{\n    typealias Arguments = {('Macro' if macro else 'Manual') + str(count)}.Arguments\n"
            if not macro:
                text += f'    var command: SlashCommandMetadata {{ .init(name: "command{index}", description: "Bounded compiler fixture") }}\n'
            text += r"""    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        try MessageResponse(visibility: .ephemeral) { Text("fixture \(arguments.text)") }
    }
}
"""
        text += f"func group{group}() throws -> BotDefinitionGroup {{\n    try BotDefinitionGroup([\n"
        text += ",\n".join((f'        Handler{index}().contribution(id: "handler{index}", source: .init(fileID: "compiler-fixture", line: {index + 1}))' if macro else
                              f'        SlashCommand(id: "handler{index}", handler: Handler{index}(), source: .init(fileID: "compiler-fixture", line: {index + 1}))')
                             for index in range(group * 10, group * 10 + 10))
        text += "\n    ])\n}\n"
        sources[f"Handlers{group:03}.swift"] = text
    sources["Main.swift"] = imports + "@main struct Consumer {\n    static func main() throws {\n        let groups = try [\n" + ",\n".join(f"            group{group}()" for group in range(count // 10)) + f"""
        ]
        let compiled = try CommandCompilation.compile(BotDefinitionGroup(groups))
        precondition(compiled.routes.count == {count} && compiled.definitions.count == {count})
        print("qualified {count} inert declarations")
    }}
}}
"""
    return sources


def prepare_workspace(repository, workspace):
    """Create only a marked generated workspace; reject unrelated nonempty directories."""
    if workspace.exists() and any(workspace.iterdir()) and not (workspace / MARKER).is_file():
        raise ValueError("workspace must be empty or marked by this runner")
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / MARKER).write_text("generated compiler consumers version 1\n")
    names = [f"{mode.title()}{count}" for count in COUNTS for mode in MODES]
    root_literal = json.dumps(str(repository))
    macro_literal = json.dumps(str(repository / "Packages/DiscordDSLMacros"))
    manifest = f"""// swift-tools-version: 6.4
import PackageDescription
let names = {json.dumps(names)}
let settings: [SwiftSetting] = [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]
let runtime: [Target.Dependency] = [
    .product(name: "DiscordCommandDSL", package: "DiscordKit"),
    .product(name: "DiscordDSL", package: "DiscordKit")]
let package = Package(name: "DSLCompilerCosts", platforms: [.macOS(.v13)],
    products: names.map {{ .executable(name: $0, targets: [$0]) }},
    dependencies: [.package(name: "DiscordKit", path: {root_literal}),
        .package(name: "DiscordDSLMacros", path: {macro_literal})],
    targets: [.target(name: "Warmup", dependencies: runtime + [.product(name: "DiscordDSLMacros", package: "DiscordDSLMacros")], swiftSettings: settings)] +
        names.map {{ name in .executableTarget(name: name, dependencies: runtime +
            (name.hasPrefix("Macro") ? [.product(name: "DiscordDSLMacros", package: "DiscordDSLMacros")] : []), swiftSettings: settings) }})
"""
    (workspace / "Package.swift").write_text(manifest)
    shutil.copyfile(repository / "Tests/Fixtures/DSLCompile/Package.resolved", workspace / "Package.resolved")
    warmup = workspace / "Sources/Warmup"
    warmup.mkdir(parents=True, exist_ok=True)
    (warmup / "Warmup.swift").write_text("import DiscordCommandDSL\nimport DiscordDSLMacros\nstruct Warmup {}\n")
    for count in COUNTS:
        for mode in MODES:
            directory = workspace / "Sources" / f"{mode.title()}{count}"
            directory.mkdir(parents=True, exist_ok=True)
            for name, content in generated_sources(count, mode == "macro").items():
                (directory / name).write_text(content)
    return names


def remove_consumer_outputs(scratch, target):
    """Remove only generated target outputs, retaining dependencies and plugins."""
    if not re.fullmatch(r"(?:Manual|Macro)(?:10|100|1000)", target):
        raise ValueError("unknown consumer target")
    removed = []
    for configuration in scratch.glob("*/debug"):
        # SwiftPM owns planning inputs (notably output-file-map.json and LinkFileList).
        # Removing them while its manifest cache is valid can fail before compilation.
        build_directory = configuration / f"{target}.build"
        for path in build_directory.rglob("*"):
            if path.is_file() and path.suffix in {".o", ".d", ".swiftdeps", ".swiftmodule", ".swiftdoc", ".swiftsourceinfo", ".swiftconstvalues", ".dia", ".autolink", ".priors"}:
                path.unlink()
                removed.append(str(path.relative_to(scratch)))
        for path in [configuration / target,
                     configuration / f"{target}.dSYM", *list((configuration / "Modules").glob(target + ".*"))]:
            if path.exists() and not path.is_symlink():
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
                removed.append(str(path.relative_to(scratch)))
    return removed


def run_timed(command, timeout, cwd, log_path):
    """Run shell-free under a process-group timeout with bounded retained diagnostics."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    wrapper = ["/usr/bin/time", "-l" if platform.system() == "Darwin" else "-v"]
    with log_path.open("wb") as output:
        process = subprocess.Popen(wrapper + command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            status = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            import signal
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise RuntimeError(f"compiler exceeded {timeout:g} seconds; see {log_path}")
    elapsed = time.perf_counter() - started
    with log_path.open("rb") as output:
        output.seek(max(0, log_path.stat().st_size - 65536))
        tail = output.read().decode(errors="replace")
    if status:
        raise RuntimeError(f"compiler failed ({status}): {tail[-12000:]}")
    pattern = r"(\d+)\s+maximum resident set size" if platform.system() == "Darwin" else r"Maximum resident set size \(kbytes\):\s*(\d+)"
    match = re.search(pattern, tail)
    if not match:
        raise RuntimeError("time did not report compiler peak RSS")
    return {"wallSeconds": elapsed, "peakRSSBytes": int(match.group(1)) * (1 if platform.system() == "Darwin" else 1024)}


def capture(command, cwd):
    """Read bounded version/environment evidence using a finite subprocess timeout."""
    completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=30, check=True)
    return completed.stdout.strip()[:16000]


def run_incremental(source, command, timeout, repository, log_path, timed=run_timed):
    """Make exactly one controlled semantic edit and restore bytes after success or failure."""
    original = source.read_bytes()
    edited = original.replace(b'fixture \\(', b'edited \\(', 1)
    if edited == original:
        raise ValueError("incremental fixture lacks the controlled response literal")
    try:
        source.write_bytes(edited)
        return timed(command, timeout, repository, log_path)
    finally:
        source.write_bytes(original)


def environment(swift, repository):
    """Record current compiler and hardware; compiler evidence must establish Swift 6.4+."""
    compiler = capture([swift, "--version"], repository)
    match = re.search(r"Swift version (\d+)\.(\d+)", compiler)
    if not match or tuple(map(int, match.groups())) < (6, 4):
        raise ValueError("Swift 6.4 or newer is required")
    value = {"compiler": compiler, "operatingSystem": platform.platform(), "architecture": platform.machine(),
             "processorCount": os.cpu_count() or 1}
    if platform.system() == "Darwin":
        value["hardwareModel"] = capture(["/usr/sbin/sysctl", "-n", "hw.model"], repository)
        value["physicalMemoryBytes"] = int(capture(["/usr/sbin/sysctl", "-n", "hw.memsize"], repository))
    else:
        value["hardwareModel"] = platform.machine()
        value["physicalMemoryBytes"] = os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE")
    return value


def run_matrix(repository, workspace, swift, jobs, timeout, samples, cache_path):
    """Bootstrap once, then execute every clean/edit pair and qualify compiled catalogs."""
    if jobs not in range(1, 33) or samples not in range(1, 6) or not math.isfinite(timeout) or not 1 <= timeout <= 3600:
        raise ValueError("jobs must be 1...32, samples 1...5 and timeout 1...3600 finite seconds")
    evidence_environment = environment(swift, repository)
    names = prepare_workspace(repository, workspace)
    scratch = workspace / "build"
    command = [swift, "build", "--disable-sandbox", "--skip-update", "--disable-automatic-resolution",
               "--package-path", str(workspace), "--scratch-path", str(scratch),
               "--cache-path", str(cache_path), "--jobs", str(jobs), "--configuration", "debug", "--build-system", "native",
               "--disable-build-manifest-caching"]
    print("Bootstrapping pinned dependencies and macro plugin (separate from measured consumer builds)", flush=True)
    bootstrap = run_timed(command + ["--target", "Warmup"], timeout, repository, workspace / "logs/bootstrap.log")
    rows = []
    for target in names:
        count = int(re.search(r"\d+", target).group())
        row = {"mode": "macro" if target.startswith("Macro") else "manual", "handlerCount": count, "samples": []}
        first = workspace / "Sources" / target / "Handlers000.swift"
        for sample in range(samples):
            removed = remove_consumer_outputs(scratch, target)
            print(f"Measuring {target} sample {sample + 1}/{samples}: clean consumer", flush=True)
            clean = run_timed(command + ["--product", target], timeout, repository, workspace / f"logs/{target}-{sample}-clean.log")
            incremental = run_incremental(first, command + ["--product", target], timeout, repository,
                                          workspace / f"logs/{target}-{sample}-incremental.log")
            # Executing validates finite catalog construction only; handlers remain inert.
            binaries = [path for path in scratch.glob(f"*/debug/{target}") if path.is_file()]
            if len(binaries) != 1 or capture([str(binaries[0])], repository) != f"qualified {count} inert declarations":
                raise RuntimeError(f"catalog qualification failed for {target}")
            row["samples"].append({"clean": clean, "incremental": incremental,
                                   "removedConsumerOutputs": removed, "binaryBytes": binaries[0].stat().st_size,
                                   "binarySHA256": hashlib.sha256(binaries[0].read_bytes()).hexdigest()})
        row["functionalGatesPassed"] = True
        rows.append(row)
    source_files = list((repository / "Sources").rglob("*.swift")) + list((repository / "Packages/DiscordDSLMacros/Sources").rglob("*.swift"))
    fixture_files = list((workspace / "Sources").rglob("*.swift"))
    return {"schemaVersion": 1, "reportKind": "dsl-compiler-cost", "recordedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "configuration": {"handlerCounts": list(COUNTS), "modes": list(MODES), "jobs": jobs, "samples": samples,
                              "configuration": "debug", "buildSystem": "native", "handlersPerFile": 10, "optionsPerHandler": 1,
                              "incrementalEdit": "one response literal in the first ten-handler file", "dependencyColdBuildIncluded": False},
            "environment": evidence_environment, "revision": capture(["git", "rev-parse", "HEAD"], repository),
            "sourceHash": digest_files(source_files, repository), "fixtureHash": digest_files(fixture_files, workspace),
            "resolutionHash": hashlib.sha256((workspace / "Package.resolved").read_bytes()).hexdigest(),
            "bootstrap": bootstrap, "workloads": rows,
            "qualification": {"localOnly": True, "liveDiscordQualified": False, "productionQualified": False,
                              "timingIsolationQualified": False,
                              "processRSSSemantics": "time ru_maxrss is the largest reported process RSS, not simultaneous aggregate compiler-family RSS",
                              "scope": "SwiftPM debug consumer compile/link; warm dependencies; no handler execution or live I/O"}}


def main():
    """Write complete JSON only after the entire matrix succeeds; failed runs exit nonzero."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--cache-path", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--swift", default="swift")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--timeout", type=float, default=1800)
    parser.add_argument("--samples", type=int, default=1)
    arguments = parser.parse_args()
    repository = arguments.repository.resolve()
    workspace = (arguments.workspace or repository / ".build/dsl-benchmarks/compiler").resolve()
    try:
        report = run_matrix(repository, workspace, arguments.swift, arguments.jobs, arguments.timeout, arguments.samples,
                            (arguments.cache_path or repository / ".build/dsl-compile-cache").resolve())
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Compiler benchmark failed: {error}\n")


if __name__ == "__main__":
    main()
