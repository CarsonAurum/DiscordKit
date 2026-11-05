# File: Tools/ci/test_github_release.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Exercise release gates and publication failures without network or remote writes."""

import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

import github_release


REVISION = "abcdef0123" * 4
VERSION = "1.2.37"
REPOSITORY = "example/DiscordKit"


def ci_run(**changes):
    run = {
        "id": 1234, "run_attempt": 2, "workflow_id": 42,
        "html_url": f"https://github.com/{REPOSITORY}/actions/runs/1234",
        "head_sha": REVISION, "head_repository": {"full_name": REPOSITORY},
        "status": "completed", "conclusion": "success", "event": "push",
    }
    run.update(changes)
    return run


class FakeAPI:
    """Allow only explicitly configured reads and one atomic tag creation."""

    repository = REPOSITORY
    token = "workflow-test-token"

    def __init__(self):
        self.calls = []
        self.responses = {
            "actions/runs/1234": ci_run(),
            "actions/workflows/ci.yml": {"id": 42},
            f"git/ref/tags/v{VERSION}": None,
            "releases?per_page=100&page=1": [],
        }
        self.created_object = {"type": "commit", "sha": REVISION}

    def request(self, path, data=None, missing_ok=False):
        self.calls.append((path, copy.deepcopy(data), missing_ok))
        if data is not None:
            if path != "git/refs":
                raise AssertionError(f"Unexpected remote mutation: {path}")
            self.responses[f"git/ref/tags/v{VERSION}"] = {"object": self.created_object}
            return {"ref": data["ref"], "object": self.created_object}
        value = self.responses[path]
        if isinstance(value, BaseException):
            raise value
        return copy.deepcopy(value)

    @property
    def mutations(self):
        return [(path, data) for path, data, _ in self.calls if data is not None]


class ReleaseGateTests(unittest.TestCase):
    def test_canonical_versions_and_full_revisions(self):
        for version in ("0.0.0", VERSION, "12.30.987654321"):
            with self.subTest(version=version):
                self.assertEqual(github_release.validate_inputs(version, REVISION.upper()),
                                 (version, REVISION))

    def test_malformed_or_executable_inputs_are_rejected(self):
        versions = ("v1.2.3", "01.2.3", "1.02.3", "1.2.03", "1.2", "1.2.3.4",
                    "-1.2.3", "1.2.3-beta", "1.2.3+build", "1.2.3\n", " 1.2.3",
                    "1.2.$(touch injected)", "1.2.3;echo bad", "١.2.3", "")
        revisions = ("main", "v1.2.3", REVISION[:-1], REVISION + "0", "g" * 40,
                     REVISION + "\n", f"{REVISION};echo bad", "$(touch injected)", "")
        for version in versions:
            with self.subTest(version=version), self.assertRaises(ValueError):
                github_release.validate_inputs(version, REVISION)
        for revision in revisions:
            with self.subTest(revision=revision), self.assertRaises(ValueError):
                github_release.validate_inputs(VERSION, revision)

    def test_only_completed_exact_repository_push_or_manual_runs_certify(self):
        for event in ("push", "workflow_dispatch"):
            self.assertTrue(github_release.certified_run(
                ci_run(event=event, head_repository={"full_name": REPOSITORY.upper()}),
                REPOSITORY, REVISION))
        invalid = ({"head_sha": "0" * 40}, {"status": "in_progress"},
                   {"conclusion": "failure"}, {"conclusion": "cancelled"},
                   {"event": "pull_request"}, {"event": "workflow_run"},
                   {"head_repository": {"full_name": "other/DiscordKit"}},
                   {"head_repository": None})
        for changes in invalid:
            with self.subTest(changes=changes):
                self.assertFalse(github_release.certified_run(ci_run(**changes), REPOSITORY, REVISION))

    def test_certification_search_paginates_before_accepting_exact_run(self):
        api = FakeAPI()
        prefix = f"actions/workflows/ci.yml/runs?head_sha={REVISION}&per_page=100&page="
        api.responses[prefix + "1"] = {"workflow_runs": [ci_run(event="pull_request")] * 100}
        api.responses[prefix + "2"] = {"workflow_runs": [ci_run()]}
        self.assertEqual(github_release.successful_ci(api, REVISION), ci_run())
        self.assertEqual([call[0] for call in api.calls], [prefix + "1", prefix + "2"])
        self.assertEqual(api.mutations, [])

    def test_absent_or_failed_certification_never_becomes_a_success(self):
        for runs in ([], [ci_run(conclusion="failure")], [ci_run(head_sha="0" * 40)]):
            with self.subTest(runs=runs):
                api = FakeAPI()
                path = f"actions/workflows/ci.yml/runs?head_sha={REVISION}&per_page=100&page=1"
                api.responses[path] = {"workflow_runs": runs}
                with self.assertRaises(ValueError):
                    github_release.successful_ci(api, REVISION)
                self.assertEqual(api.mutations, [])

    def test_api_http_errors_fail_closed_except_explicit_missing_404(self):
        with patch.dict(os.environ, {"GITHUB_REPOSITORY": REPOSITORY, "GH_TOKEN": "test"}):
            api = github_release.GitHubAPI()
        for status, missing_ok in ((404, False), (401, True), (403, True), (500, True)):
            error = HTTPError("https://example.invalid", status, "failure", {}, None)
            self.addCleanup(error.close)
            with self.subTest(status=status, missing_ok=missing_ok):
                with patch.object(github_release, "urlopen", side_effect=error):
                    with self.assertRaisesRegex(RuntimeError, f"HTTP {status}"):
                        api.request("releases", missing_ok=missing_ok)
        missing = HTTPError("https://example.invalid", 404, "missing", {}, None)
        self.addCleanup(missing.close)
        with patch.object(github_release, "urlopen", side_effect=missing):
            self.assertIsNone(api.request("git/ref/tags/v1.2.37", missing_ok=True))

    def test_optional_publication_token_is_used_only_for_mutations(self):
        captured = []

        def response(request, timeout):
            captured.append((request.get_method(), request.get_header("Authorization")))
            self.assertEqual(timeout, 60)
            return io.StringIO("{}")

        with patch.dict(os.environ, {"GITHUB_REPOSITORY": REPOSITORY, "GH_TOKEN": "read-token",
                                     "RELEASE_TOKEN": "publish-token"}):
            api = github_release.GitHubAPI()
            with patch.object(github_release, "urlopen", side_effect=response):
                api.request("actions/runs/1234")
                api.request("git/refs", {"ref": "refs/tags/v1.2.37", "sha": REVISION})
        self.assertEqual(captured, [("GET", "Bearer read-token"), ("POST", "Bearer publish-token")])

    def test_existing_tag_and_paginated_draft_release_are_rejected(self):
        api = FakeAPI()
        api.responses[f"git/ref/tags/v{VERSION}"] = {"object": {"sha": REVISION}}
        with self.assertRaisesRegex(ValueError, "Tag.*already exists"):
            github_release.require_unused_version(api, VERSION)
        self.assertEqual(len(api.calls), 1)
        api = FakeAPI()
        api.responses["releases?per_page=100&page=1"] = [{"tag_name": "v0.0.1"}] * 100
        api.responses["releases?per_page=100&page=2"] = [{"tag_name": f"v{VERSION}", "draft": True}]
        with self.assertRaisesRegex(ValueError, "Release.*already exists"):
            github_release.require_unused_version(api, VERSION)
        self.assertEqual(api.calls[-1][0], "releases?per_page=100&page=2")
        self.assertEqual(api.mutations, [])

    def test_dispatch_uses_default_branch_but_target_may_be_any_commit(self):
        environment = {"RELEASE_DEFAULT_BRANCH": "main", "GITHUB_REF": "refs/heads/main"}
        with patch.dict(os.environ, environment):
            with patch.object(github_release.subprocess, "check_output", return_value="commit\n") as git:
                github_release.require_default_branch(Path("repo"), REVISION)
                self.assertEqual(git.call_args.args[0][-3:], ["cat-file", "-t", REVISION])
            for kind in ("blob\n", "tree\n", "tag\n"):
                with self.subTest(kind=kind), patch.object(
                        github_release.subprocess, "check_output", return_value=kind):
                    with self.assertRaises(ValueError):
                        github_release.require_default_branch(Path("repo"), REVISION)
            with patch.object(github_release.subprocess, "check_output", side_effect=
                              subprocess.CalledProcessError(128, ["git", "cat-file"])):
                with self.assertRaises(subprocess.CalledProcessError):
                    github_release.require_default_branch(Path("repo"), REVISION)
        with patch.dict(os.environ, {**environment, "GITHUB_REF": "refs/heads/feature"}):
            with patch.object(github_release.subprocess, "check_output") as git:
                with self.assertRaises(ValueError):
                    github_release.require_default_branch(Path("repo"), REVISION)
                git.assert_not_called()


class ReleasePublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.repository = Path(temporary.name) / "repository"
        self.repository.mkdir()
        self.output = Path(temporary.name) / "release assets"
        self.output.mkdir()
        self.api = FakeAPI()
        self.run = ci_run()
        self.assets = self.write_assets()
        branch = patch.object(github_release, "require_default_branch")
        self.branch_check = branch.start()
        self.addCleanup(branch.stop)
        environment = patch.dict(os.environ, {"RELEASE_TOKEN": ""})
        environment.start()
        self.addCleanup(environment.stop)

    def write_assets(self):
        name = f"DiscordKit-{VERSION}-source"
        archive = self.output / f"{name}.tar.gz"
        checksum = self.output / f"{name}.tar.gz.sha256"
        manifest = self.output / f"{name}.json"
        archive.write_bytes(b"selected source archive bytes")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        checksum.write_text(f"{digest}  {archive.name}\n")
        manifest.write_text(json.dumps({
            "schemaVersion": 1, "format": "swiftpm-source", "version": VERSION,
            "tag": f"v{VERSION}", "revision": REVISION, "archive": archive.name,
            "sha256": digest,
            "ciRun": {key: self.run[key] for key in ("id", "run_attempt", "html_url", "head_sha")},
        }))
        return archive, checksum, manifest

    def publish(self, **changes):
        arguments = {"repository": self.repository, "output": self.output,
                     "version": VERSION, "revision": REVISION, "api": self.api}
        arguments.update(changes)
        github_release.publish(**arguments)

    def test_asset_verification_returns_exact_files_and_certification(self):
        assets, evidence = github_release.verify_assets(self.output, VERSION, REVISION)
        self.assertEqual(assets, self.assets)
        self.assertEqual(evidence, {key: self.run[key] for key in ("id", "run_attempt", "html_url", "head_sha")})

    def test_tampered_archive_checksum_or_manifest_is_rejected(self):
        for target in ("archive", "checksum", "version", "revision", "tag", "archive-name", "sha256"):
            with self.subTest(target=target):
                archive, checksum, manifest = self.write_assets()
                if target == "archive":
                    archive.write_bytes(b"different source")
                elif target == "checksum":
                    checksum.write_text("0" * 64 + f"  {archive.name}\n")
                else:
                    metadata = json.loads(manifest.read_text())
                    metadata["archive" if target == "archive-name" else target] = "mismatch"
                    manifest.write_text(json.dumps(metadata))
                with self.assertRaises(ValueError):
                    github_release.verify_assets(self.output, VERSION, REVISION)

    def test_publication_creates_exact_tag_and_release_with_all_assets(self):
        with patch.object(github_release.subprocess, "run") as command:
            self.publish(revision=REVISION.upper())
        self.assertEqual(self.api.mutations, [("git/refs", {"ref": f"refs/tags/v{VERSION}", "sha": REVISION})])
        self.branch_check.assert_called_once_with(self.repository, REVISION)
        command.assert_called_once()
        arguments = command.call_args.args[0]
        self.assertEqual(arguments[:4], ["gh", "release", "create", f"v{VERSION}"])
        self.assertEqual(arguments[4:7], list(map(str, self.assets)))
        self.assertEqual(arguments[arguments.index("--target") + 1], REVISION)
        self.assertEqual(arguments[arguments.index("--title") + 1], f"DiscordKit {VERSION}")
        self.assertIn("--verify-tag", arguments)
        self.assertTrue(command.call_args.kwargs["check"])
        self.assertEqual(command.call_args.kwargs["env"]["GH_TOKEN"], self.api.token)
        self.assertIn(self.run["html_url"], (self.output / "release-notes.md").read_text())

    def test_publication_uses_optional_token_for_gh(self):
        with patch.dict(os.environ, {"RELEASE_TOKEN": "publication-only-token"}):
            with patch.object(github_release.subprocess, "run") as command:
                self.publish()
        self.assertEqual(command.call_args.kwargs["env"]["GH_TOKEN"], "publication-only-token")

    def test_invalid_inputs_never_read_api_or_mutate(self):
        with patch.object(github_release.subprocess, "run") as command:
            for changes in ({"version": "1.2.37; bad"}, {"revision": "main"}):
                with self.subTest(changes=changes), self.assertRaises(ValueError):
                    self.publish(**changes)
        self.assertEqual(self.api.calls, [])
        self.branch_check.assert_not_called()
        command.assert_not_called()

    def test_missing_or_failed_rerun_certification_never_mutates(self):
        for response in (RuntimeError("GitHub API GET run failed (HTTP 404)"),
                         RuntimeError("GitHub API GET run failed (HTTP 403)"),
                         ci_run(conclusion="failure", run_attempt=3), ci_run(status="in_progress")):
            with self.subTest(response=response):
                self.api = FakeAPI()
                self.api.responses["actions/runs/1234"] = response
                with patch.object(github_release.subprocess, "run") as command:
                    with self.assertRaises((RuntimeError, ValueError)):
                        self.publish()
                    command.assert_not_called()
                self.assertEqual(self.api.mutations, [])

    def test_wrong_workflow_or_changed_certification_identity_never_mutates(self):
        for changes in ({"workflow_id": 99}, {"run_attempt": 3}, {"id": 5678},
                        {"html_url": "https://github.com/other/run/1234"}, {"head_sha": "0" * 40}):
            with self.subTest(changes=changes):
                self.api = FakeAPI()
                self.api.responses["actions/runs/1234"] = ci_run(**changes)
                with patch.object(github_release.subprocess, "run") as command:
                    with self.assertRaises(ValueError):
                        self.publish()
                    command.assert_not_called()
                self.assertEqual(self.api.mutations, [])

    def test_existing_version_never_tags_or_calls_gh(self):
        for kind in ("tag", "draft", "release"):
            with self.subTest(kind=kind):
                self.api = FakeAPI()
                if kind == "tag":
                    self.api.responses[f"git/ref/tags/v{VERSION}"] = {"object": {"sha": REVISION}}
                else:
                    self.api.responses["releases?per_page=100&page=1"] = [
                        {"tag_name": f"v{VERSION}", "draft": kind == "draft"}]
                with patch.object(github_release.subprocess, "run") as command:
                    with self.assertRaises(ValueError):
                        self.publish()
                    command.assert_not_called()
                self.assertEqual(self.api.mutations, [])

    def test_tag_verification_failure_stops_before_creating_release(self):
        for object_value in ({"type": "commit", "sha": "0" * 40}, {"type": "tag", "sha": REVISION}):
            with self.subTest(object=object_value):
                self.api = FakeAPI()
                self.api.created_object = object_value
                with patch.object(github_release.subprocess, "run") as command:
                    with self.assertRaises(ValueError):
                        self.publish()
                    command.assert_not_called()
                self.assertEqual(len(self.api.mutations), 1)

    def test_failed_gh_creation_is_not_retried_or_cleaned_up(self):
        failure = subprocess.CalledProcessError(1, ["gh", "release", "create"])
        with patch.object(github_release.subprocess, "run", side_effect=failure) as command:
            with self.assertRaises(subprocess.CalledProcessError):
                self.publish()
        command.assert_called_once()
        self.assertEqual(command.call_args.args[0][1:3], ["release", "create"])
        self.assertEqual(self.api.mutations, [("git/refs", {"ref": f"refs/tags/v{VERSION}", "sha": REVISION})])

    def test_prepare_missing_or_unreadable_ci_never_packages_or_mutates(self):
        path = f"actions/workflows/ci.yml/runs?head_sha={REVISION}&per_page=100&page=1"
        for response in ({"workflow_runs": []}, RuntimeError("GitHub API failed (HTTP 500)")):
            with self.subTest(response=response):
                self.api = FakeAPI()
                self.api.responses[path] = response
                with patch("package_release.package_release") as package:
                    with self.assertRaises((ValueError, RuntimeError)):
                        github_release.prepare(self.repository, self.output, VERSION, REVISION, self.api)
                    package.assert_not_called()
                self.assertEqual(self.api.mutations, [])


if __name__ == "__main__":
    unittest.main()
