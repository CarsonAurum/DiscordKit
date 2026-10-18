#!/usr/bin/env python3
"""Convert owned public-module graphs and guides using the installed toolchain DocC.

No package plugin or runtime dependency is installed. The caller emits public
symbol graphs first; each archive receives only that module's primary/extension
graphs. Private declaration presence and semantic review remain separate checks.
"""

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


def public_modules(repository):
    """Read actual root library product targets from SwiftPM's parsed manifest."""
    result = subprocess.run(["swift", "package", "--disable-sandbox", "--package-path", str(repository),
                             "dump-package"], check=True, capture_output=True, text=True)
    return sorted({target for product in json.loads(result.stdout)["products"]
                   if "library" in product["type"] for target in product["targets"]})


def module_graphs(directory, module):
    """Select one required primary graph and its extensions; reject absent graphs."""
    primary = directory / f"{module}.symbols.json"
    if not primary.is_file():
        raise ValueError(f"Missing public module graph: {primary}")
    graphs = [primary, *sorted(directory.glob(f"{module}@*.symbols.json"))]
    for graph in graphs:
        if json.loads(graph.read_text()).get("module", {}).get("name") != module:
            raise ValueError(f"Symbol graph module does not match {module}: {graph.name}")
    return graphs


def conversion_command(docc, repository, output, module, graphs):
    """Return argument-array conversion with strict warnings, analysis and coverage."""
    command = [docc, "convert"]
    catalog = repository / "Sources" / module / f"{module}.docc"
    if catalog.is_dir():
        command.append(str(catalog))
    command.extend(["--additional-symbol-graph-dir", str(graphs), "--output-dir", str(output),
                    "--fallback-display-name", module,
                    "--fallback-bundle-identifier", f"org.discordkit.{module}",
                    "--warnings-as-errors", "--analyze", "--experimental-documentation-coverage",
                    "--coverage-summary-level", "brief"])
    return command


def main():
    """Build every library archive or fail; write machine-readable conversion scope."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--symbolgraphs", type=Path, default=Path(".build/out/symbolgraph"))
    parser.add_argument("--output", type=Path, default=Path(".build/documentation"))
    parser.add_argument("--docc", default=shutil.which("docc"))
    arguments = parser.parse_args()
    repository = arguments.repository.resolve()
    if not arguments.docc and shutil.which("xcrun"):
        arguments.docc = subprocess.check_output(["xcrun", "--find", "docc"], text=True).strip()
    if not arguments.docc:
        parser.error("docc is not installed; select a Swift toolchain with DocC")
    directory = arguments.symbolgraphs.resolve()
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    modules = public_modules(repository)
    failures = []
    for module in modules:
        with tempfile.TemporaryDirectory(prefix=f"docc-{module}-") as staging:
            for graph in module_graphs(directory, module):
                shutil.copy2(graph, Path(staging) / graph.name)
            result = subprocess.run(conversion_command(arguments.docc, repository, output / f"{module}.doccarchive",
                                                       module, Path(staging)))
            if result.returncode:
                failures.append(module)
    (output / "build-report.json").write_text(json.dumps({
        "modules": modules, "archiveCount": len(modules), "warningsAsErrors": True,
        "analyze": True, "publicSymbolsOnly": True, "failedModules": failures,
        "limits": "DocC conversion does not prove private documentation presence or semantic completeness",
    }, indent=2) + "\n")
    if failures:
        raise SystemExit("DocC conversion failed: " + ", ".join(failures))
    print(f"Converted {len(modules)} public-module DocC archives with strict diagnostics")


if __name__ == "__main__":
    main()
