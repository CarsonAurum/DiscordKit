#!/usr/bin/env python3
# File: Tools/ci/build_docc.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

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
    """Read the selected package's library product targets, excluding plugins and tests.

    The same entry point serves the runtime root and the independently selected
    authoring macro package; neither directory names nor transitive dependencies
    can add a public module to the conversion scope.
    """
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


def conversion_command(docc, repository, output, module, graphs, dependencies=()):
    """Plan strict conversion; dependencies resolve the umbrella's product links.

    ``dependencies`` contains already-built owned archives, never network URLs.
    Every archive exports link metadata so the independently converted products
    can be cross-referenced without importing them into a Swift target.
    """
    command = [docc, "convert"]
    catalog = repository / "Sources" / module / f"{module}.docc"
    if catalog.is_dir():
        command.append(str(catalog))
    command.extend(["--additional-symbol-graph-dir", str(graphs), "--output-dir", str(output),
                    "--fallback-display-name", module,
                    "--fallback-bundle-identifier", f"org.discordkit.{module}",
                    "--warnings-as-errors", "--analyze", "--experimental-documentation-coverage",
                    "--coverage-summary-level", "brief",
                    "--enable-experimental-external-link-support"])
    for dependency in dependencies:
        command.extend(["--dependency", str(dependency)])
    return command


def merge_command(docc, archives, output):
    """Plan a single browsable archive with all independent product navigators."""
    ordered = sorted(archives, key=lambda archive: archive.name != "DiscordKit.doccarchive")
    return [docc, "merge", *map(str, ordered), "--output-path", str(output),
            "--synthesized-landing-page-name", "DiscordKit Library",
            "--synthesized-landing-page-kind", "Swift Package",
            "--synthesized-landing-page-topics-style", "list"]


def remove_archive(path):
    """Remove one owned output archive, including a partial failed conversion.

    Symbolic links are unlinked rather than followed. Callers supply only the
    current modules' exact generated archive paths and the merged archive path.
    """
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


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
    archives = []
    merged = output / "DiscordKitLibrary.doccarchive"
    report_path = output / "build-report.json"
    # Output paths are owned generated artifacts. A failed rebuild must not leave
    # an earlier successful archive or report that appears to describe this run.
    report_path.unlink(missing_ok=True)
    for archive in [merged, *(output / f"{module}.doccarchive" for module in modules)]:
        remove_archive(archive)
    active_module = None
    merge_status = "skipped"
    try:
        # Product link metadata must exist before converting the umbrella.
        for module in sorted(modules, key=lambda value: (value == "DiscordKit", value)):
            active_module = module
            archive = output / f"{module}.doccarchive"
            with tempfile.TemporaryDirectory(prefix=f"docc-{module}-") as staging:
                for graph in module_graphs(directory, module):
                    shutil.copy2(graph, Path(staging) / graph.name)
                dependencies = archives if module == "DiscordKit" else ()
                result = subprocess.run(conversion_command(arguments.docc, repository, archive,
                                                           module, Path(staging), dependencies))
                if result.returncode:
                    failures.append(module)
                    remove_archive(archive)
                else:
                    archives.append(archive)
            active_module = None
        if not failures:
            merge_status = "failed"
            subprocess.run(merge_command(arguments.docc, archives, merged), check=True)
            merge_status = "succeeded"
    finally:
        if active_module is not None:
            if active_module not in failures:
                failures.append(active_module)
            remove_archive(output / f"{active_module}.doccarchive")
        if merge_status != "succeeded":
            remove_archive(merged)
        report_path.write_text(json.dumps({
            "modules": modules, "archiveCount": len(archives), "warningsAsErrors": True,
            "analyze": True, "publicSymbolsOnly": True, "failedModules": failures,
            "mergeStatus": merge_status,
            "mergedArchive": merged.name if merge_status == "succeeded" else None,
            "limits": "DocC conversion does not prove private documentation presence or semantic completeness",
        }, indent=2) + "\n")
    if failures:
        raise SystemExit("DocC conversion failed: " + ", ".join(failures))
    print(f"Converted {len(modules)} public-module DocC archives with strict diagnostics")


if __name__ == "__main__":
    main()
