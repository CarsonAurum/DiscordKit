# File: Tools/ci/test_documentation_site.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Check the complete static-export pipeline without a compiler or network."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_documentation_site as site


class DocumentationSiteTests(unittest.TestCase):
    """Exercise package scope, static routes and safe failure behavior."""

    def fake_toolchain(self, commands):
        """Materialize the artifacts emitted by the existing converter and DocC."""
        def execute(command, repository):
            command = list(map(str, command))
            commands.append(command)
            if "build_docc.py" in Path(command[1]).name:
                output = Path(command[command.index("--output") + 1])
                package = Path(command[command.index("--repository") + 1])
                modules = ["DiscordKit", "DiscordCore"] if package == repository else [package.name]
                output.mkdir()
                for module in [*modules, "DiscordKitLibrary"]:
                    (output / f"{module}.doccarchive").mkdir()
                (output / "build-report.json").write_text(json.dumps({
                    "modules": modules, "failedModules": [], "mergeStatus": "succeeded"}))
            elif command[1] == "merge":
                Path(command[command.index("--output-path") + 1]).mkdir()
            elif "transform-for-static-hosting" in command:
                output = Path(command[command.index("--output-path") + 1])
                page = output / "documentation/discordkit/index.html"
                page.parent.mkdir(parents=True)
                page.write_text("symbol page")
                (output / "documentation/index.html").write_text("library landing")
                (output / "index.html").write_text("DocC application")
        return execute

    def test_all_packages_are_checked_and_individual_archives_share_one_static_site(self):
        """Authoring modules share the library navigator and all deep routes survive."""
        with tempfile.TemporaryDirectory(prefix="documentation test ") as temporary:
            repository = Path(temporary)
            output = repository / ".build/site export"
            for relative in site.PACKAGES:
                graphs = repository / relative / ".build/out/symbolgraph"
                graphs.mkdir(parents=True)
                (graphs / "Stale.symbols.json").write_text("old graph")
                (graphs / "keep.txt").write_text("unrelated generated evidence")
            commands = []
            with patch.object(site, "run", side_effect=self.fake_toolchain(commands)):
                site.build_site(repository, output, "docc tool", "/DiscordKit")
            dumps = [command for command in commands if "dump-symbol-graph" in command]
            self.assertEqual(len(dumps), 3)
            self.assertTrue(all("--force-resolved-versions" in command for command in dumps))
            checks = [command for command in commands if Path(command[1]).name == "curate_docc.py"]
            self.assertEqual(len(checks), 3)
            self.assertTrue(all("--check" in command and "--write" not in command for command in checks))
            examples = [command for command in commands if Path(command[1]).name == "documentation_examples.py"]
            self.assertEqual(len(examples), 1)
            self.assertEqual(Path(examples[0][-1]), repository.resolve())
            merge = next(command for command in commands if command[1] == "merge")
            merged_inputs = merge[2:merge.index("--output-path")]
            self.assertEqual([Path(path).name for path in merged_inputs], [
                "DiscordKit.doccarchive", "DiscordCore.doccarchive", "DiscordDSLMacros.doccarchive",
                "DiscordDSLExtensions.doccarchive"])
            transform = commands[-1]
            self.assertEqual(transform[-2:], ["--hosting-base-path", "/DiscordKit"])
            self.assertEqual((output / "documentation/discordkit/index.html").read_text(), "symbol page")
            self.assertEqual((output / "documentation/index.html").read_text(), "library landing")
            self.assertIn('href="documentation/"', (output / "index.html").read_text())
            self.assertTrue((output / ".nojekyll").is_file())
            self.assertEqual((output / site.MARKER).read_text(), site.MARKER_CONTENT)
            for relative in site.PACKAGES:
                graphs = repository / relative / ".build/out/symbolgraph"
                self.assertFalse((graphs / "Stale.symbols.json").exists())
                self.assertTrue((graphs / "keep.txt").is_file())
            self.assertEqual(sorted(path.name for path in output.parent.iterdir()), ["out", "site export"])

    def test_failed_rebuild_leaves_no_previous_site_or_partial_export(self):
        """A failing command cannot make an earlier successful tree look current."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            output = repository / ".build/site"
            output.mkdir(parents=True)
            (output / site.MARKER).write_text(site.MARKER_CONTENT)
            (output / "index.html").write_text("stale successful site")
            commands = []
            fake = self.fake_toolchain(commands)

            def fail_transform(command, root):
                if "transform-for-static-hosting" in command:
                    raise subprocess.CalledProcessError(1, command)
                fake(command, root)

            with patch.object(site, "run", side_effect=fail_transform):
                with self.assertRaises(subprocess.CalledProcessError):
                    site.build_site(repository, output, "docc", "/")
            self.assertFalse(output.exists())
            self.assertEqual(list(output.parent.iterdir()), [])

    def test_unowned_outputs_and_symlinks_are_preserved(self):
        """An output typo cannot delete source files or follow a symbolic link."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            existing = repository / "existing"
            existing.mkdir()
            (existing / "index.html").write_text("authored page")
            linked = repository / "linked"
            linked.symlink_to(existing, target_is_directory=True)
            with patch.object(site, "run") as run:
                for output in [existing, linked]:
                    with self.assertRaises(ValueError):
                        site.build_site(repository, output, "docc", "/DiscordKit")
                run.assert_not_called()
            self.assertEqual((existing / "index.html").read_text(), "authored page")
            self.assertTrue(linked.is_symlink())

    def test_missing_static_landing_is_not_published(self):
        """Successful subprocess status alone is insufficient for a usable export."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            output = repository / "site"
            fake = self.fake_toolchain([])

            def omit_landing(command, root):
                fake(command, root)
                if "transform-for-static-hosting" in command:
                    transformed = Path(command[command.index("--output-path") + 1])
                    (transformed / "documentation/index.html").unlink()

            with patch.object(site, "run", side_effect=omit_landing):
                with self.assertRaisesRegex(ValueError, "landing page"):
                    site.build_site(repository, output, "docc", "/DiscordKit")
            self.assertFalse(output.exists())

    def test_empty_base_path_hosts_at_domain_root(self):
        """Domain-root deployments pass DocC's empty base path through unchanged."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            output = repository / "site"
            commands = []
            with patch.object(site, "run", side_effect=self.fake_toolchain(commands)):
                site.build_site(repository, output, "docc", "")
            self.assertEqual(commands[-1][-2:], ["--hosting-base-path", ""])
            self.assertIn('href="documentation/"', (output / "index.html").read_text())


if __name__ == "__main__":
    unittest.main()
