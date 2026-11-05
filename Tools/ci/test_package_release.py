# File: Tools/ci/test_package_release.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Check actual release archives against immutable Git trees without Swift or network."""

import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import package_release


class ReleasePackageTests(unittest.TestCase):
    """Require complete SwiftPM source, exact evidence identity and immutable assets."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name) / "repository with spaces"
        self.repository.mkdir()
        self.output = Path(self.temporary.name) / "release output"
        self.tracked = {
            "Package.swift": "// root package\n",
            "Package.resolved": '{"pins": []}\n',
            "Sources/DiscordKit/DiscordKit.swift": "// library\n",
            "Tests/Fixtures/sample.json": "{}\n",
            "Packages/DiscordDSLMacros/Package.swift": '// path: "../.."\n',
            "Packages/DiscordDSLMacros/Package.resolved": '{"pins": []}\n',
            "Packages/DiscordDSLExtensions/Package.swift": '// path: "../.."\n',
            "LICENSE": "License terms\n",
            "NOTICE": "DiscordKit\nCreated by Carson Rau.\nCopyright (c) 2026 Aurum Studios.\n",
            "AUTHORS.md": "Carson Rau\n",
            "COPYRIGHT": "Copyright (c) 2026 Aurum Studios.\n",
            "Licenses/dependency.txt": "Dependency terms\n",
            "THIRD_PARTY_NOTICES.md": "Attribution\n",
            ".air/private-plan.md": "Private task data\n",
            ".build/local-cache": "Local build cache\n",
            ".swiftpm/workspace-state.json": "Local workspace data\n",
            "Packages/DiscordDSLMacros/.build/local-cache": "Nested build cache\n",
            "Packages/DiscordDSLExtensions/.swiftpm/configuration.json": "Nested SwiftPM data\n",
        }
        for relative, content in self.tracked.items():
            path = self.repository / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.run_git("init", "--quiet")
        self.run_git("add", ".")
        self.commit("selected source")
        self.revision = self.run_git("rev-parse", "HEAD").decode().strip()
        self.version = "1.2.345"
        self.ci_run = {
            "id": 1234,
            "run_attempt": 2,
            "html_url": "https://github.com/example/DiscordKit/actions/runs/1234",
            "head_sha": self.revision,
            "unrelated": "Never copy arbitrary fields into release provenance",
        }

    def run_git(self, *arguments):
        return subprocess.check_output(["git", "-C", str(self.repository), *arguments])

    def commit(self, message):
        self.run_git("-c", "user.name=CI test", "-c", "user.email=ci@example.invalid",
                     "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", message)

    def package(self, **changes):
        arguments = {"repository": self.repository, "output": self.output,
                     "version": self.version, "revision": self.revision, "ci_run": self.ci_run}
        arguments.update(changes)
        return package_release.package_release(**arguments)

    def test_archive_preserves_selected_source_layout_and_attribution(self):
        """A later, dirty checkout cannot change the selected source or its checksum."""
        source = self.repository / "Sources/DiscordKit/DiscordKit.swift"
        source.write_text("// subsequent commit\n")
        self.run_git("add", ".")
        self.commit("later source")
        source.write_text("// dirty local source\n")
        (self.repository / "untracked.swift").write_text("// local file\n")
        archive, checksum, manifest = self.package()
        self.assertEqual(archive.name, "DiscordKit-1.2.345-source.tar.gz")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.assertEqual(checksum.read_text(), f"{digest}  {archive.name}\n")
        metadata = json.loads(manifest.read_text())
        self.assertEqual(metadata, {
            "schemaVersion": 1, "format": "swiftpm-source", "version": self.version,
            "tag": "v1.2.345", "revision": self.revision, "archive": archive.name,
            "sha256": digest,
            "ciRun": {key: self.ci_run[key] for key in ("id", "run_attempt", "html_url", "head_sha")},
        })
        with tarfile.open(archive) as bundle:
            members = bundle.getmembers()
            self.assertFalse(any(part in (".air", ".build", ".swiftpm")
                                 for member in members for part in Path(member.name).parts))
            files = {member.name: bundle.extractfile(member).read().decode()
                     for member in members if member.isfile()}
        expected = {f"DiscordKit-{self.version}/{path}": content
                    for path, content in self.tracked.items()
                    if not any(part in (".air", ".build", ".swiftpm") for part in Path(path).parts)}
        self.assertEqual(files, expected)

    def test_archive_bytes_are_reproducible(self):
        """Identical selected trees and versions produce identical compressed bytes."""
        first = self.package()[0].read_bytes()
        other_output = Path(self.temporary.name) / "second output"
        second = self.package(output=other_output)[0].read_bytes()
        self.assertEqual(first, second)

    def test_local_state_symlinks_are_excluded(self):
        """Tracked links with local-state names cannot enter a distribution."""
        for relative in ("Linked/.build", "Linked/.swiftpm", "Linked/.air"):
            link = self.repository / relative
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to("../Package.swift")
        self.run_git("add", ".")
        self.commit("tracked state links")
        revision = self.run_git("rev-parse", "HEAD").decode().strip()
        archive, _, _ = self.package(revision=revision, ci_run={**self.ci_run, "head_sha": revision})
        with tarfile.open(archive) as bundle:
            self.assertFalse(any(part in (".air", ".build", ".swiftpm")
                                 for member in bundle.getmembers() for part in Path(member.name).parts))

    def test_existing_release_assets_are_never_replaced(self):
        """Any existing asset blocks packaging without changing its bytes."""
        for suffix in (".tar.gz", ".tar.gz.sha256", ".json"):
            with self.subTest(suffix=suffix):
                self.output.mkdir(exist_ok=True)
                existing = self.output / f"DiscordKit-{self.version}-source{suffix}"
                existing.write_bytes(b"original asset")
                with self.assertRaises(FileExistsError):
                    self.package()
                self.assertEqual(list(self.output.iterdir()), [existing])
                self.assertEqual(existing.read_bytes(), b"original asset")
                existing.unlink()

    def test_repeat_packaging_is_rejected(self):
        """Rerunning the same version cannot replace completed outputs."""
        assets = self.package()
        originals = {path: path.read_bytes() for path in assets}
        with self.assertRaises(FileExistsError):
            self.package()
        self.assertEqual({path: path.read_bytes() for path in assets}, originals)

    def test_concurrent_existing_asset_rolls_back_only_new_outputs(self):
        """A race after validation preserves the concurrent file and removes partial assets."""
        link = package_release.os.link

        def race(source, destination):
            if destination.suffix == ".json":
                destination.write_text("concurrent asset")
            link(source, destination)

        with patch("package_release.os.link", side_effect=race):
            with self.assertRaises(FileExistsError):
                self.package()
        files = list(self.output.iterdir())
        self.assertEqual([path.name for path in files], [f"DiscordKit-{self.version}-source.json"])
        self.assertEqual(files[0].read_text(), "concurrent asset")

    def test_invalid_version_and_revision_do_not_create_output(self):
        """Malformed release identifiers never become filenames or Git arguments."""
        for version in ("v1.2.3", "1.2", "1.2.3.4", "1.02.3", "-1.2.3", "1.2.3;touch bad"):
            with self.subTest(version=version):
                with self.assertRaises(ValueError):
                    self.package(version=version)
        for revision in ("HEAD", self.revision[:12], "--all", "a" * 39, "g" * 40):
            with self.subTest(revision=revision):
                with self.assertRaises(ValueError):
                    self.package(revision=revision)
        self.assertFalse(self.output.exists())

    def test_non_commit_object_is_rejected(self):
        """An annotated tag object is not an exact commit identifier."""
        self.run_git("-c", "user.name=CI test", "-c", "user.email=ci@example.invalid",
                     "tag", "-a", "fixture", "-m", "tag")
        tag_object = self.run_git("rev-parse", "fixture").decode().strip()
        with self.assertRaisesRegex(ValueError, "Git commit"):
            self.package(revision=tag_object)
        self.assertFalse(self.output.exists())

    def test_mismatched_or_incomplete_ci_evidence_is_rejected(self):
        """Release metadata cannot attach another revision's CI run."""
        for evidence in ({**self.ci_run, "head_sha": "0" * 40}, {"head_sha": self.revision}, None):
            with self.subTest(evidence=evidence):
                with self.assertRaisesRegex(ValueError, "CI evidence"):
                    self.package(ci_run=evidence)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
