#!/usr/bin/env python3
# File: Tools/ci/package_source.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Archive the clean, tested Git revision as a SwiftPM source distribution."""

import argparse
import hashlib
import json
import platform
import subprocess
from pathlib import Path


def git(repository, *arguments):
    """Run Git against an explicit checkout without shell interpolation."""
    return subprocess.check_output(["git", "-C", str(repository), *arguments])


def package_source(repository, output):
    """Package tracked source only, with compiler/host provenance and a checksum.

    A clean checkout ensures that the archived HEAD is the source just built and
    tested. Untracked files and ignored build caches never enter the archive.
    The complete tree preserves local dependencies between root, authoring
    packages, examples and fixtures. Private Air task data is excluded.
    """
    repository = repository.resolve()
    if git(repository, "status", "--porcelain", "--untracked-files=no").strip():
        raise ValueError("Source packaging requires a clean tracked checkout")
    revision = git(repository, "rev-parse", "HEAD").decode().strip()
    target = json.loads(subprocess.check_output(["swift", "-print-target-info"], text=True))
    triple = target["target"]["triple"]
    if "linux" not in triple.split("-"):
        raise ValueError("Linux source packaging requires a native Linux Swift toolchain")
    swift_version = subprocess.check_output(["swift", "--version"], text=True).strip()
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    name = f"DiscordKit-{revision}-linux-source"
    archive = output / f"{name}.tar.gz"
    subprocess.run(["git", "-C", str(repository), "archive", "--format=tar.gz",
                    f"--output={archive}", "--prefix=DiscordKit/", revision,
                    "--", ".", ":(exclude).air"], check=True)
    with archive.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    checksum = output / f"{name}.tar.gz.sha256"
    checksum.write_text(f"{digest}  {archive.name}\n")
    metadata = {
        "schemaVersion": 1,
        "format": "swiftpm-source",
        "revision": revision,
        "archive": archive.name,
        "sha256": digest,
        "configuration": "release",
        "swiftVersion": swift_version,
        "targetTriple": triple,
        "host": platform.freedesktop_os_release(),
    }
    manifest = output / f"{name}.json"
    manifest.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    return archive, checksum, manifest


def main():
    """Write a Linux source bundle after the workflow's test and release-build gates."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, default=Path(".build/packages"))
    arguments = parser.parse_args()
    for path in package_source(arguments.repository, arguments.output):
        print(path)


if __name__ == "__main__":
    main()
