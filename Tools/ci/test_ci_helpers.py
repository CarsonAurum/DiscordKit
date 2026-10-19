"""Deterministic planning tests for CI commands; no compiler or network needed."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build_docc
import documentation_examples
import compile_apple
import live_rest_smoke
import qualify_android
import review_upstream


class CIHelpersTests(unittest.TestCase):
    """Exercise exact scope, missing-evidence rejection and shell-free arguments."""

    def test_graph_selection_requires_primary_and_excludes_other_modules(self):
        """One module receives its own extensions only; an empty directory fails."""
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with self.assertRaises(ValueError):
                build_docc.module_graphs(directory, "DiscordCore")
            for name in ["DiscordCore.symbols.json", "DiscordCore@Swift.symbols.json", "DiscordKit.symbols.json"]:
                (directory / name).write_text('{"module":{"name":"DiscordCore"}}')
            self.assertEqual([path.name for path in build_docc.module_graphs(directory, "DiscordCore")],
                             ["DiscordCore.symbols.json", "DiscordCore@Swift.symbols.json"])
            (directory / "DiscordCore.symbols.json").write_text('{"module":{"name":"Other"}}')
            with self.assertRaises(ValueError):
                build_docc.module_graphs(directory, "DiscordCore")

    def test_docc_catalog_is_optional_and_diagnostics_are_strict(self):
        """Symbol-only modules and the guide module retain identical strict flags."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            catalog = repository / "Sources/DiscordKit/DiscordKit.docc"
            catalog.mkdir(parents=True)
            for module in ["DiscordCore", "DiscordKit"]:
                command = build_docc.conversion_command("docc", repository, Path("output"), module, Path("graphs"))
                self.assertIn("--warnings-as-errors", command)
                self.assertIn("--analyze", command)
                self.assertIn("--experimental-documentation-coverage", command)
                self.assertEqual(str(catalog) in command, module == "DiscordKit")

    def test_manifest_scope_excludes_executables_and_deduplicates_targets(self):
        """Actual library product targets define public archives, rather than directory guesses."""
        result = type("Result", (), {"stdout": '{"products":[{"type":{"library":["automatic"]},"targets":["A"]},'
                                    '{"type":{"library":["automatic"]},"targets":["A","B"]},'
                                    '{"type":{"executable":null},"targets":["Tool"]}]}'})()
        with patch("build_docc.subprocess.run", return_value=result) as run:
            self.assertEqual(build_docc.public_modules(Path("a repository")), ["A", "B"])
            self.assertTrue(run.call_args.kwargs["check"])

    def test_separate_macro_package_public_module_and_catalog_scope(self):
        """Only the authoring library is documented; its compiler plugin and tests remain outside public graphs."""
        result = type("Result", (), {"stdout": json.dumps({"products": [
            {"name": "DiscordDSLMacros", "type": {"library": ["automatic"]}, "targets": ["DiscordDSLMacros"]}],
            "targets": [{"name": "DiscordDSLMacrosPlugin", "type": "macro"},
                        {"name": "DiscordDSLMacrosTests", "type": "test"}]})})()
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "Packages/DiscordDSLMacros"
            catalog = package / "Sources/DiscordDSLMacros/DiscordDSLMacros.docc"
            catalog.mkdir(parents=True)
            with patch("build_docc.subprocess.run", return_value=result) as run:
                self.assertEqual(build_docc.public_modules(package), ["DiscordDSLMacros"])
                self.assertIn(str(package), run.call_args.args[0])
            command = build_docc.conversion_command("docc", package, Path("out"),
                "DiscordDSLMacros", Path("graphs"))
            self.assertIn(str(catalog), command)
            self.assertNotIn("DiscordDSLMacrosPlugin", command)

    def test_docc_dependencies_and_merge_preserve_paths_and_all_archives(self):
        """Cross-module resolution and global navigation use argument arrays."""
        archives = [Path("output with spaces/A.doccarchive"), Path("output/B.doccarchive")]
        command = build_docc.conversion_command("docc", Path("repo"), Path("out"),
                                               "DiscordKit", Path("graphs"), archives)
        self.assertIn("--enable-experimental-external-link-support", command)
        self.assertEqual(command[-4:], ["--dependency", str(archives[0]), "--dependency", str(archives[1])])
        merged = build_docc.merge_command("docc", archives, Path("combined archive"))
        self.assertEqual(merged[:4], ["docc", "merge", *map(str, archives)])
        self.assertEqual(merged[merged.index("--output-path") + 1], "combined archive")
        umbrella = Path("output/DiscordKit.doccarchive")
        merged = build_docc.merge_command("docc", [*archives, umbrella], Path("combined archive"))
        self.assertEqual(merged[2:5], [str(umbrella), *map(str, archives)])

    def test_tutorial_listings_preserve_executable_code_and_regular_comments(self):
        """Historical doc-comment labels are omitted; executable literals stay intact."""
        original = '/// Phase 12 overview\n  /// Detail\nlet value = "Part 9 literal"\n// retained\n'
        self.assertEqual(documentation_examples.displayed_source(original),
                         '/// overview\n  /// Detail\nlet value = "Part 9 literal"\n// retained\n')

    def test_tutorial_snapshot_check_is_nonwriting_and_reports_all_stale_files(self):
        """Missing, changed and matching listings are distinguished deterministically."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            expected = {"a.swift": "let a = 1\n", "b.swift": "let b = 2\n"}
            with patch("documentation_examples.snapshots", return_value=expected):
                self.assertEqual(documentation_examples.synchronize(repository), ["a.swift", "b.swift"])
                self.assertEqual(list(repository.iterdir()), [])
                self.assertEqual(documentation_examples.synchronize(repository, write=True), ["a.swift", "b.swift"])
                self.assertEqual(documentation_examples.synchronize(repository), [])
                resource = repository / "Sources/DiscordKit/DiscordKit.docc/Resources/Examples/a.swift"
                resource.write_text("let a = 3\n")
                self.assertEqual(documentation_examples.synchronize(repository), ["a.swift"])
                self.assertEqual(resource.read_text(), "let a = 3\n")

    def test_tutorial_sources_require_every_named_example(self):
        """An absent origin is an error rather than a silently dropped tutorial."""
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(OSError):
                documentation_examples.snapshots(Path(temporary))

    def test_dsl_tutorials_include_independent_hosts_and_external_dependencies(self):
        """Tutorial code is sourced from independently compiled consumers and libraries.

        Removing an external dependency source must fail snapshot generation,
        rather than leave a plausible but stale actor-injection tutorial.
        """
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            for example in documentation_examples.EXAMPLES:
                base = repository / "Examples" / example
                source = base / "Sources" / example / f"{example}.swift"
                source.parent.mkdir(parents=True)
                source.write_text(f"// compiled {example}\n")
                (base / "Package.swift").write_text(f"// package {example}\n")
            for example, source in documentation_examples.SUPPORT:
                path = repository / "Examples" / example / "Sources" / source
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f"// support {path.name}\n")
            for source in documentation_examples.PACKAGE_SUPPORT:
                path = repository / source
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("actor TutorialDependency {}\n")
            snapshots = documentation_examples.snapshots(repository)
            for example in ("DSLCommands", "DSLEvents", "DSLBot"):
                self.assertEqual(snapshots[f"{example}.swift.txt"], f"// compiled {example}\n")
                self.assertIn(f"{example}-Package.swift.txt", snapshots)
            self.assertEqual(snapshots["ExtensionCommands.swift.txt"], "actor TutorialDependency {}\n")
            (repository / documentation_examples.PACKAGE_SUPPORT[0]).unlink()
            with self.assertRaises(OSError):
                documentation_examples.snapshots(repository)

    def test_tutorial_comment_rewrite_preserves_line_boundaries(self):
        """A label at a comment's end must not absorb the next executable line."""
        self.assertEqual(documentation_examples.displayed_source('/// Phase 12\nlet value = 1\n'),
                         '/// \nlet value = 1\n')

    def test_obsolete_swift_snapshots_fail_check_and_are_removed_only_on_write(self):
        """Retired listings cannot remain current; unrelated resource kinds survive."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            resources = repository / "Sources/DiscordKit/DiscordKit.docc/Resources/Examples"
            resources.mkdir(parents=True)
            stale = resources / "Retired.swift.txt"
            stale.write_text("old listing")
            guide = resources / "README.md"
            guide.write_text("Authored resource guidance")
            with patch("documentation_examples.snapshots", return_value={}):
                self.assertEqual(documentation_examples.synchronize(repository), [stale.name])
                self.assertEqual(stale.read_text(), "old listing")
                self.assertEqual(documentation_examples.synchronize(repository, write=True), [stale.name])
                self.assertFalse(stale.exists())
                self.assertEqual(documentation_examples.synchronize(repository), [])
                self.assertEqual(guide.read_text(), "Authored resource guidance")

    def test_failed_conversion_discards_previous_and_partial_archives(self):
        """A conversion failure cannot leave an older successful page or merge behind."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "output"
            output.mkdir()
            for name in ["A.doccarchive", "DiscordKitLibrary.doccarchive"]:
                archive = output / name
                archive.mkdir()
                (archive / "old-page.json").write_text("previous success")
            (output / "build-report.json").write_text('{"mergeStatus":"succeeded"}')

            def failed_conversion(command, **options):
                """Simulate DocC writing partial output before rejecting the catalog."""
                archive = Path(command[command.index("--output-dir") + 1])
                archive.mkdir()
                (archive / "partial.json").write_text("incomplete")
                return subprocess.CompletedProcess(command, 1)

            arguments = ["build_docc.py", "--repository", str(root), "--output", str(output), "--docc", "docc"]
            with patch("sys.argv", arguments), patch("build_docc.public_modules", return_value=["A"]), \
                 patch("build_docc.module_graphs", return_value=[]), \
                 patch("build_docc.subprocess.run", side_effect=failed_conversion):
                with self.assertRaisesRegex(SystemExit, "conversion failed"):
                    build_docc.main()
            report = json.loads((output / "build-report.json").read_text())
            self.assertEqual(report["failedModules"], ["A"])
            self.assertEqual(report["archiveCount"], 0)
            self.assertEqual(report["mergeStatus"], "skipped")
            self.assertIsNone(report["mergedArchive"])
            self.assertFalse((output / "A.doccarchive").exists())
            self.assertFalse((output / "DiscordKitLibrary.doccarchive").exists())

    def test_failed_merge_updates_report_and_discards_partial_merged_output(self):
        """Independent archives remain valid while the failed merged result is absent."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "output"
            output.mkdir()
            merged = output / "DiscordKitLibrary.doccarchive"
            merged.mkdir()
            (merged / "old-page.json").write_text("previous success")
            (output / "build-report.json").write_text('{"mergeStatus":"succeeded"}')

            def convert_then_fail_merge(command, **options):
                """Write a valid independent archive, then fail after partial merge output."""
                if command[1] == "merge":
                    merged.mkdir()
                    (merged / "partial.json").write_text("incomplete")
                    raise subprocess.CalledProcessError(1, command)
                archive = Path(command[command.index("--output-dir") + 1])
                archive.mkdir()
                (archive / "current-page.json").write_text("current conversion")
                return subprocess.CompletedProcess(command, 0)

            arguments = ["build_docc.py", "--repository", str(root), "--output", str(output), "--docc", "docc"]
            with patch("sys.argv", arguments), patch("build_docc.public_modules", return_value=["A"]), \
                 patch("build_docc.module_graphs", return_value=[]), \
                 patch("build_docc.subprocess.run", side_effect=convert_then_fail_merge):
                with self.assertRaises(subprocess.CalledProcessError):
                    build_docc.main()
            report = json.loads((output / "build-report.json").read_text())
            self.assertEqual(report["failedModules"], [])
            self.assertEqual(report["archiveCount"], 1)
            self.assertEqual(report["mergeStatus"], "failed")
            self.assertIsNone(report["mergedArchive"])
            self.assertFalse(merged.exists())
            self.assertTrue((output / "A.doccarchive/current-page.json").is_file())

    def test_apple_device_simulator_targets_and_concurrency(self):
        """Every device/simulator minimum is explicit and source paths remain one argument."""
        self.assertEqual(len(compile_apple.DESTINATIONS), 9)
        self.assertEqual(compile_apple.MODULES, ["Logging", "DiscordLogging", "DiscordLogHandlers", "DiscordBits",
                                               "DiscordCore", "DiscordTransport", "DiscordMedia", "DiscordApplePlatform"])
        command = compile_apple.compiler_command("DiscordBits", [Path("source with spaces.swift")],
                                                "arm64-apple-ios16.0-simulator", "SDK path", Path("out"), Path("cache"))
        self.assertIn("ApproachableConcurrency", command)
        self.assertIn("nonisolated", command)
        self.assertIn("SDK path", command)
        self.assertEqual(command[-1], "source with spaces.swift")
        self.assertNotIn("-emit-executable", command)
        upstream = compile_apple.compiler_command("Logging", [Path("logging.swift")],
                                                 "arm64-apple-ios16.0", "SDK", Path("out"), Path("cache"))
        self.assertNotIn("ApproachableConcurrency", upstream)
        self.assertIn("-require-explicit-sendable", upstream)
        self.assertEqual(upstream[upstream.index("-package-name") + 1], "swift_log")
        self.assertEqual(command[command.index("-package-name") + 1], "discordkit")
        for feature in compile_apple.LOGGING_FEATURES:
            self.assertIn(feature, upstream)

    def test_apple_resolver_preserves_explicit_paths_and_host_options(self):
        """Resolution is shell-free, and offline callers can supply existing scratch contents."""
        command = compile_apple.resolution_command(Path("repository with spaces"), Path("scratch with spaces"),
                                                   Path("cache with spaces"), disable_sandbox=True)
        self.assertEqual(command, ["swift", "package", "--package-path", "repository with spaces",
                                   "--scratch-path", "scratch with spaces", "--cache-path", "cache with spaces",
                                   "--disable-sandbox", "resolve"])
        minimal = compile_apple.resolution_command(Path("repo"), Path("scratch"))
        self.assertNotIn("--cache-path", minimal)
        self.assertNotIn("--disable-sandbox", minimal)

    def test_apple_logging_requires_resolved_source_and_matching_checkout(self):
        """Missing, stale or escaping checkouts cannot claim compilation of the pinned dependency."""
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            scratch = repository / "scratch"
            scratch.mkdir()
            pin = {"identity": "swift-log", "kind": "remoteSourceControl",
                   "location": "https://github.com/apple/swift-log.git",
                   "state": {"revision": "a" * 40, "version": "1.16.1"}}
            dependency = {"packageRef": {"identity": "swift-log", "location": pin["location"]},
                          "state": {"name": "sourceControlCheckout", "checkoutState": pin["state"]},
                          "subpath": "swift-log"}
            (repository / "Package.resolved").write_text(json.dumps({"pins": [pin]}))

            def save_workspace():
                """Retain the current simulated SwiftPM checkout state for validation."""
                (scratch / "workspace-state.json").write_text(json.dumps({"object": {"dependencies": [dependency]}}))

            save_workspace()
            with self.assertRaisesRegex(ValueError, "Missing resolved"):
                compile_apple.resolved_logging(repository, scratch)
            checkout = scratch / "checkouts/swift-log"
            (checkout / "Sources/Logging").mkdir(parents=True)
            (checkout / "Sources/Logging/Logger.swift").write_text("public struct Logger {}\n")
            with patch("compile_apple.subprocess.check_output", return_value="a" * 40 + "\n"):
                self.assertEqual(compile_apple.resolved_logging(repository, scratch), (checkout.resolve(), pin))
            with patch("compile_apple.subprocess.check_output", return_value="b" * 40 + "\n"):
                with self.assertRaisesRegex(ValueError, "HEAD does not match"):
                    compile_apple.resolved_logging(repository, scratch)
            dependency["state"]["checkoutState"] = {"revision": "b" * 40, "version": "1.16.1"}
            save_workspace()
            with self.assertRaisesRegex(ValueError, "does not match"):
                compile_apple.resolved_logging(repository, scratch)
            dependency["state"]["checkoutState"] = pin["state"]
            dependency["subpath"] = "../../outside"
            save_workspace()
            with self.assertRaisesRegex(ValueError, "Missing resolved"):
                compile_apple.resolved_logging(repository, scratch)

    def test_upstream_requires_exact_pins_and_keeps_surfaces_separate(self):
        """Missing, ambiguous and non-Git revisions cannot silently select a comparison base."""
        sources = [{"authority": key, "revision": "a" * 40} for key in review_upstream.REPOSITORIES]
        self.assertEqual(set(review_upstream.pinned_revisions(sources)), set(review_upstream.REPOSITORIES))
        for invalid in [[], sources[:1], [*sources, {"authority": "written_docs", "revision": "b" * 40}],
                        [{"authority": key, "revision": "main"} for key in review_upstream.REPOSITORIES]]:
            with self.assertRaises(ValueError):
                review_upstream.pinned_revisions(invalid)

    def test_android_always_selects_a_device_and_retains_fixed_remote_scope(self):
        """No operation can target whichever adb device happens to be attached."""
        with self.assertRaises(ValueError):
            qualify_android.adb_command(" ", "shell", "getprop")
        self.assertEqual(qualify_android.adb_command("emulator-5554", "shell", "getprop"),
                         ["adb", "-s", "emulator-5554", "shell", "getprop"])
        self.assertEqual(qualify_android.TRIPLE, "aarch64-unknown-linux-android28")
        self.assertTrue(qualify_android.REMOTE.startswith("/data/local/tmp/"))

    def test_android_refuses_mismatched_toolchains_ndk_and_device_architecture(self):
        """Misconfigured infrastructure cannot qualify an unbuilt ABI or incompatible SDK."""
        valid = ["Swift version 6.4.1", "swift-6.4.1-RELEASE_android", "Pkg.Revision = 30.0.1\n", "arm64-v8a\n"]
        qualify_android.validate_prerequisites(*valid)
        for position, invalid in [(0, "Swift version 6.4.0"), (0, "Swift version 6.3.1"),
                                  (1, "main"), (2, "Pkg.Revision = 29.0.0"), (3, "x86_64")]:
            arguments = valid.copy()
            arguments[position] = invalid
            with self.assertRaises(ValueError):
                qualify_android.validate_prerequisites(*arguments)

    def test_live_smoke_requires_success_line_and_exact_test_application(self):
        """Example failures exit normally, but cannot be interpreted as successful qualification."""
        self.assertEqual(live_rest_smoke.confirmed_identifiers("Fetched bot 7 and application 42.\n", "42"),
                         {"botID": "7", "applicationID": "42"})
        for output, expected in [("REST request failed; inspect the typed error in your own application.", "42"),
                                 ("REST configuration is invalid.", "42"),
                                 ("Fetched bot 7 and application 43.", "42"),
                                 ("Fetched bot 7 and application 42.\nextra output", "42"),
                                 ("Fetched bot 7 and application 0.", "0"),
                                 ("Fetched bot 7 and application 42.", None)]:
            with self.assertRaises(ValueError):
                live_rest_smoke.confirmed_identifiers(output, expected)


if __name__ == "__main__":
    unittest.main()
