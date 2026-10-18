"""Deterministic planning tests for CI commands; no compiler or network needed."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build_docc
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

    def test_apple_device_simulator_targets_and_concurrency(self):
        """Every device/simulator minimum is explicit and source paths remain one argument."""
        self.assertEqual(len(compile_apple.DESTINATIONS), 9)
        self.assertEqual(len(compile_apple.MODULES), 5)
        command = compile_apple.compiler_command("DiscordBits", [Path("source with spaces.swift")],
                                                "arm64-apple-ios16.0-simulator", "SDK path", Path("out"), Path("cache"))
        self.assertIn("ApproachableConcurrency", command)
        self.assertIn("nonisolated", command)
        self.assertIn("SDK path", command)
        self.assertEqual(command[-1], "source with spaces.swift")
        self.assertNotIn("-emit-executable", command)

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
