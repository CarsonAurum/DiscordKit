#!/usr/bin/env python3
# File: Tools/ci/github_release.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Prepare and publish a manually versioned release from a certified Git commit."""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def validate_inputs(version, revision):
    """Accept canonical Major.Minor.Build numbers and an immutable full SHA."""
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("Version must be Major.Minor.Build, e.g. 1.2.37, without a v prefix or leading zeroes")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", revision):
        raise ValueError("Commit must be a full 40-character Git commit SHA")
    return version, revision.lower()


class GitHubAPI:
    """Use the workflow token, distinguishing missing resources from API failures."""

    def __init__(self):
        self.repository = os.environ["GITHUB_REPOSITORY"]
        self.base = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
        self.token = os.environ["GH_TOKEN"]

    def request(self, path, data=None, missing_ok=False):
        token = (os.environ.get("RELEASE_TOKEN") or self.token) if data is not None else self.token
        request = Request(
            f"{self.base}/repos/{self.repository}/{path}",
            data=json.dumps(data).encode() if data is not None else None,
            headers={"Accept": "application/vnd.github+json",
                     "Authorization": f"Bearer {token}",
                     "X-GitHub-Api-Version": "2022-11-28",
                     "Content-Type": "application/json"},
        )
        try:
            with urlopen(request, timeout=60) as response:
                return json.load(response)
        except HTTPError as error:
            if missing_ok and error.code == 404:
                return None
            raise RuntimeError(f"GitHub API {request.get_method()} {path} failed (HTTP {error.code})") from None


def require_default_branch(repository, revision):
    """Use default-branch tooling and an existing, exact repository commit."""
    branch = os.environ["RELEASE_DEFAULT_BRANCH"]
    if os.environ["GITHUB_REF"] != f"refs/heads/{branch}":
        raise ValueError("Run the Release workflow from the repository's default branch")
    kind = subprocess.check_output(["git", "-C", str(repository), "cat-file", "-t", revision], text=True).strip()
    if kind != "commit":
        raise ValueError("Release commit must identify a commit in this repository")


def certified_run(run, repository, revision):
    """A PR merge result or another repository's run cannot certify this commit."""
    return (run.get("head_sha") == revision
            and run.get("status") == "completed" and run.get("conclusion") == "success"
            and run.get("event") in {"push", "workflow_dispatch"}
            and (run.get("head_repository") or {}).get("full_name", "").lower() == repository.lower())


def successful_ci(api, revision):
    """Find existing successful offline certification without rebuilding the source."""
    for page in range(1, 11):
        runs = api.request(f"actions/workflows/ci.yml/runs?head_sha={revision}&per_page=100&page={page}")["workflow_runs"]
        for run in runs:
            if certified_run(run, api.repository, revision):
                return run
        if len(runs) < 100:
            break
    raise ValueError("No successful Offline certification (ci.yml) push/manual run for this exact commit; run CI first")


def require_unused_version(api, version):
    """Refuse both existing tags and releases, including unpublished drafts."""
    tag = f"v{version}"
    if api.request(f"git/ref/tags/{tag}", missing_ok=True) is not None:
        raise ValueError(f"Tag {tag} already exists; select a new version")
    page = 1
    while True:
        releases = api.request(f"releases?per_page=100&page={page}")
        if any(release["tag_name"] == tag for release in releases):
            raise ValueError(f"Release {tag} already exists; inspect any partial release before retrying")
        if len(releases) < 100:
            return
        page += 1


def prepare(repository, output, version, revision, api):
    """Produce the immutable source assets with read-only GitHub access."""
    from package_release import package_release

    version, revision = validate_inputs(version, revision)
    require_default_branch(repository, revision)
    require_unused_version(api, version)
    run = successful_ci(api, revision)
    assets = package_release(repository, output, version, revision, run)
    print(f"Prepared v{version} from {revision}; certification: {run['html_url']}")
    return assets


def verify_assets(output, version, revision):
    """Recheck downloaded bytes and metadata before granting them a release tag."""
    name = f"DiscordKit-{version}-source"
    archive = output / f"{name}.tar.gz"
    checksum = output / f"{name}.tar.gz.sha256"
    manifest = output / f"{name}.json"
    metadata = json.loads(manifest.read_text())
    with archive.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    expected = {"schemaVersion": 1, "format": "swiftpm-source", "version": version,
                "tag": f"v{version}", "revision": revision, "archive": archive.name, "sha256": digest}
    if any(metadata.get(key) != value for key, value in expected.items()):
        raise ValueError("Release manifest does not match the requested version, commit or archive bytes")
    if checksum.read_text() != f"{digest}  {archive.name}\n":
        raise ValueError("Release archive checksum does not match")
    return (archive, checksum, manifest), metadata["ciRun"]


def publish(repository, output, version, revision, api):
    """Create a new exact tag and release, never editing or replacing existing ones."""
    version, revision = validate_inputs(version, revision)
    require_default_branch(repository, revision)
    assets, evidence = verify_assets(output, version, revision)
    # Check the original run again: a later rerun may have failed or been deleted.
    run = api.request(f"actions/runs/{int(evidence['id'])}")
    workflow = api.request("actions/workflows/ci.yml")
    if (not certified_run(run, api.repository, revision)
            or run["workflow_id"] != workflow["id"]
            or any(run[key] != evidence[key] for key in ("id", "run_attempt", "html_url", "head_sha"))):
        raise ValueError("Recorded CI certification is no longer valid; prepare a new release run")
    require_unused_version(api, version)
    tag = f"v{version}"
    notes = output / "release-notes.md"
    notes.write_text(
        f"SwiftPM source distribution for DiscordKit {version}.\n\n"
        f"Commit: `{revision}`\n\n"
        f"Offline certification: {run['html_url']} (attempt {run['run_attempt']}).\n\n"
        "Assets include the full source tree, SHA-256 checksum and provenance manifest. "
        "Build the package with Swift 6.4 or newer. Offline CI retains its recorded scope; "
        "live Discord and additional platform qualifications are separate.\n")
    # GitHub rejects an existing ref atomically. Never force a tag or clean up on failure.
    api.request("git/refs", {"ref": f"refs/tags/{tag}", "sha": revision})
    remote_tag = api.request(f"git/ref/tags/{tag}")
    if remote_tag["object"].get("type") != "commit" or remote_tag["object"].get("sha") != revision:
        raise ValueError("Release tag no longer points to the packaged commit")
    # gh creates a draft, uploads assets, then publishes. An interrupted call can leave
    # a draft or tag: fail closed and let the maintainer inspect it, without replaying.
    subprocess.run(["gh", "release", "create", tag, *map(str, assets),
                    "--repo", api.repository, "--verify-tag", "--target", revision,
                    "--title", f"DiscordKit {version}", "--generate-notes",
                    "--notes-file", str(notes)], check=True,
                   env={**os.environ, "GH_TOKEN": os.environ.get("RELEASE_TOKEN") or api.token})
    print(f"Published {tag} from {revision}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("prepare", "publish"))
    parser.add_argument("--repository", type=Path, default=Path("."))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True)
    arguments = parser.parse_args()
    validate_inputs(arguments.version, arguments.commit)
    action = prepare if arguments.stage == "prepare" else publish
    action(arguments.repository.resolve(), arguments.output.resolve(),
           arguments.version, arguments.commit, GitHubAPI())


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        sys.exit(1)
