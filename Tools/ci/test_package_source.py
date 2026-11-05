# File: Tools/ci/test_package_source.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Exercise real Git archives and SwiftPM layout without a compiler or network."""

import hashlib
import json
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import package_source


class SourcePackageTests(unittest.TestCase):
    """Require exact source, complete package relationships and no local state."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name) / "repository with spaces"
        self.repository.mkdir()
        self.output = self.repository / ".build/packages"
        self.tracked = {
            ".gitignore": ".build/\ncredentials.txt\n",
            "Package.swift": "// root package\n",
            "Package.resolved": '{"pins": []}\n',
            "Sources/DiscordKit/DiscordKit.swift": "// library\n",
            "Tests/Fixtures/sample.json": "{}\n",
            "Packages/DiscordDSLMacros/Package.swift": '// path: "../.."\n',
            "Packages/DiscordDSLMacros/Package.resolved": '{"pins": []}\n',
            "Packages/DiscordDSLExtensions/Package.swift": '// path: "../.."\n',
            "LICENSE": "License terms\n",
            "Licenses/dependency.txt": "Dependency terms\n",
            "THIRD_PARTY_NOTICES.md": "Attribution\n",
            ".air/private-plan.md": "Private task data\n",
        }
        for relative, content in self.tracked.items():
            path = self.repository / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.run_git("init", "--quiet")
        self.run_git("add", ".")
        self.run_git("-c", "user.name=CI test", "-c", "user.email=ci@example.invalid",
                     "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "fixture")
        self.check_output = subprocess.check_output

    def run_git(self, *arguments):
        return subprocess.check_output(["git", "-C", str(self.repository), *arguments])

    def compiler_output(self, command, **kwargs):
        if command == ["swift", "-print-target-info"]:
            return json.dumps({"target": {"triple": "x86_64-unknown-linux-gnu"}})
        if command == ["swift", "--version"]:
            return "Swift version 6.4.1\nTarget: x86_64-unknown-linux-gnu\n"
        return self.check_output(command, **kwargs)

    def test_archive_preserves_source_and_pins_with_revision_and_checksum(self):
        """Extract actual packaged bytes; ignored/untracked/private files stay out."""
        (self.repository / "credentials.txt").write_text("local credential")
        (self.repository / "untracked.swift").write_text("local source")
        with patch("package_source.subprocess.check_output", side_effect=self.compiler_output), \
                patch("package_source.platform.freedesktop_os_release", return_value={"ID": "ubuntu", "VERSION_ID": "24.04"}):
            archive, checksum, manifest = package_source.package_source(self.repository, self.output)
            first = archive.read_bytes()
            package_source.package_source(self.repository, self.output)
        self.assertEqual(first, archive.read_bytes())
        digest = hashlib.sha256(first).hexdigest()
        self.assertEqual(checksum.read_text(), f"{digest}  {archive.name}\n")
        metadata = json.loads(manifest.read_text())
        self.assertEqual(metadata["revision"], self.run_git("rev-parse", "HEAD").decode().strip())
        self.assertEqual(metadata["sha256"], digest)
        self.assertEqual(metadata["targetTriple"], "x86_64-unknown-linux-gnu")
        with tarfile.open(archive) as bundle:
            files = {member.name: bundle.extractfile(member).read().decode()
                     for member in bundle.getmembers() if member.isfile()}
        expected = {f"DiscordKit/{path}": content for path, content in self.tracked.items()
                    if not path.startswith(".air/")}
        self.assertEqual(files, expected)

    def test_dirty_tracked_source_is_rejected(self):
        """Both unstaged and staged changes must never be mislabeled as tested HEAD."""
        (self.repository / "Package.swift").write_text("changed\n")
        for staged in [False, True]:
            if staged:
                self.run_git("add", "Package.swift")
            with self.assertRaisesRegex(ValueError, "clean tracked checkout"):
                package_source.package_source(self.repository, self.output)
        self.assertFalse(self.output.exists())

    def test_non_linux_toolchain_is_rejected(self):
        """A macOS compiler cannot issue Linux build provenance."""
        def output(command, **kwargs):
            if command[0] == "swift":
                return json.dumps({"target": {"triple": "arm64-apple-macosx27.0"}})
            return self.check_output(command, **kwargs)
        with patch("package_source.subprocess.check_output", side_effect=output):
            with self.assertRaisesRegex(ValueError, "native Linux Swift toolchain"):
                package_source.package_source(self.repository, self.output)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
