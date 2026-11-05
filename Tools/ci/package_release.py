#!/usr/bin/env python3
# File: Tools/ci/package_release.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Package an exact Git commit as a versioned, platform-neutral SwiftPM source release."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from github_release import validate_inputs


def git(repository, *arguments):
    """Run Git with literal arguments against an explicit repository."""
    return subprocess.check_output(["git", "-C", str(repository), *arguments])


def package_release(repository: Path, output: Path, version: str, revision: str,
                    ci_run: dict) -> tuple[Path, Path, Path]:
    """Archive the selected commit without including working-tree or local state.

    Source, pins, licenses and relative package relationships come from the same
    immutable Git tree. CI provenance identifies that exact revision and makes no
    compiler, binary, Linux or runtime qualification claim about this archive.
    Existing assets are never replaced, including when a concurrent run creates
    one after the initial check.
    """
    version, revision = validate_inputs(version, revision)
    repository = repository.resolve()
    if git(repository, "cat-file", "-t", revision).decode().strip() != "commit":
        raise ValueError("The selected revision must identify a Git commit")
    resolved = git(repository, "rev-parse", "--verify", f"{revision}^{{commit}}").decode().strip()
    if resolved != revision:
        raise ValueError("The selected revision must be an exact full commit SHA")
    if not isinstance(ci_run, dict) or ci_run.get("head_sha") != revision:
        raise ValueError("CI evidence must identify the selected commit")
    try:
        ci_evidence = {key: ci_run[key] for key in ("id", "run_attempt", "html_url", "head_sha")}
    except KeyError as error:
        raise ValueError(f"CI evidence is missing {error.args[0]}") from error

    output = output.resolve()
    name = f"DiscordKit-{version}-source"
    archive = output / f"{name}.tar.gz"
    checksum = output / f"{name}.tar.gz.sha256"
    manifest = output / f"{name}.json"
    assets = (archive, checksum, manifest)
    for path in assets:
        if path.exists() or path.is_symlink():
            raise FileExistsError(f"Release asset already exists: {path.name}")
    output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix=".discordkit-release-", dir=output) as temporary:
        staged_archive = Path(temporary) / archive.name
        subprocess.run([
            "git", "-C", str(repository), "archive", "--format=tar.gz",
            f"--output={staged_archive}", f"--prefix=DiscordKit-{version}/", revision,
            "--", ".", ":(exclude,glob)**/.air", ":(exclude,glob)**/.air/**",
            ":(exclude,glob)**/.build", ":(exclude,glob)**/.build/**",
            ":(exclude,glob)**/.swiftpm", ":(exclude,glob)**/.swiftpm/**",
        ], check=True)
        with staged_archive.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        staged_checksum = Path(temporary) / checksum.name
        staged_checksum.write_text(f"{digest}  {archive.name}\n")
        metadata = {
            "schemaVersion": 1,
            "format": "swiftpm-source",
            "version": version,
            "tag": f"v{version}",
            "revision": revision,
            "archive": archive.name,
            "sha256": digest,
            "ciRun": ci_evidence,
        }
        staged_manifest = Path(temporary) / manifest.name
        staged_manifest.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
        created = []
        try:
            for staged, destination in zip((staged_archive, staged_checksum, staged_manifest), assets):
                # A hard link commits the completed file and refuses replacement.
                os.link(staged, destination)
                created.append(destination)
        except BaseException:
            for destination in created:
                destination.unlink()
            raise
    return assets


def main():
    """Write source assets using an independently verified CI run record."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--ci-run", type=Path, required=True)
    arguments = parser.parse_args()
    ci_run = json.loads(arguments.ci_run.read_text())
    for path in package_release(arguments.repository, arguments.output, arguments.version,
                                arguments.revision, ci_run):
        print(path)


if __name__ == "__main__":
    main()
