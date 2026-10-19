"""Exercise release boundary failures with deterministic isolated local repositories."""

import copy
import datetime as dt
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import release_check as audit


class ReleaseChecks(unittest.TestCase):
    """Check policy, evidence hashes, claim exclusions and future-date admission independently."""

    def setUp(self):
        """Create two owned modules, one Apple pin and minimal hash-bound release evidence."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name, text in {"A": "import B\nimport Foundation", "B": "import Foundation"}.items():
            path = self.root / "Sources" / name / f"{name}.swift"
            path.parent.mkdir(parents=True)
            path.write_text(text)
        self.manifest = {"targets": [
            {"name": "A", "type": "regular", "dependencies": [{"byName": ["B", None]}]},
            {"name": "B", "type": "regular", "dependencies": []},
        ], "products": [{"name": "A", "targets": ["A"]}, {"name": "B", "targets": ["B"]}], "dependencies": []}
        self.policy = {"schemaVersion": 1, "products": {"A": ["A"], "B": ["B"]}, "targets": {"A": ["B"], "B": []}, "systemImports": ["Foundation"], "externalPackages": {"swift-crypto": "https://github.com/apple/swift-crypto.git"}, "isolation": {"B": ["A"]}, "requiredCheckIDs": ["build", "live"], "protocols": {"REST": "10"}}
        self.resolved = {"pins": [{"identity": "swift-crypto", "kind": "remoteSourceControl", "location": "https://github.com/apple/swift-crypto.git", "state": {"revision": "a" * 40}}]}
        path = self.root / "evidence.txt"
        path.write_text("local build passed; no live qualification\n")
        self.evidence = {"path": "evidence.txt", "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        self.report = {"schemaVersion": 1, "releaseVersion": "0.14.0", "verifiedOn": "2026-10-18", "protocols": {"REST": "10"}, "checks": [
            {"id": "build", "status": "passed", "scope": "local compiler", "evidence": [self.evidence]},
            {"id": "live", "status": "unverified", "scope": "authorized Discord", "reason": "No approved account", "excludedClaims": ["live", "live-discord"]},
        ], "claims": [{"id": "local-build", "description": "local compiler only", "checkIDs": ["build"]}]}

    def graph(self):
        """Run the local graph audit for a test's current manifest/policy state."""
        return audit.validate_graph(self.root, self.manifest, self.policy, self.resolved)

    def test_valid_graph_and_scoped_imports(self):
        """Ordinary reviewed DAG/import/pin membership yields exact bounded counts."""
        self.assertEqual(self.graph(), {"products": 2, "targets": 2, "sourceFiles": 2, "imports": 3, "resolvedPackages": 1})

    def test_actual_import_requires_direct_dependency(self):
        """A transitive umbrella build cannot hide an undeclared direct source import."""
        (self.root / "Sources/B/B.swift").write_text("import A")
        with self.assertRaisesRegex(ValueError, "Undeclared import"):
            self.graph()

    def test_source_policy_checks_inactive_branches(self):
        """A forbidden import under an inactive compile branch is conservatively rejected."""
        (self.root / "Sources/B/B.swift").write_text("#if os(Windows)\nimport Forbidden\n#endif")
        with self.assertRaisesRegex(ValueError, "Forbidden"):
            self.graph()

    def test_manifest_dependency_change_fails(self):
        """Unused added edges fail even when source currently never imports the target."""
        self.manifest["targets"][0]["dependencies"].append({"product": ["Crypto", "swift-crypto", None, None]})
        with self.assertRaisesRegex(ValueError, "policy mismatch"):
            self.graph()

    def test_dependency_cycles_and_unknown_targets(self):
        """Cycles and local dangling nodes reject reachability before policy comparison."""
        for graph in ({"A": ["B"], "B": ["A"]}, {"A": ["missing"]}):
            with self.subTest(graph=graph), self.assertRaises(ValueError):
                audit.closure(graph, ["A"])

    def test_external_pin_changes_fail_closed(self):
        """Identity, URL, remote kind and concrete revision are required on resolved pins."""
        for key, value in (("identity", "third-party"), ("location", "https://github.com/evil/swift-crypto.git"), ("kind", "localSourceControl"), ("state", {"revision": "unknown"})):
            with self.subTest(key=key):
                resolved = copy.deepcopy(self.resolved)
                resolved["pins"][0][key] = value
                with self.assertRaises(ValueError):
                    audit.validate_graph(self.root, self.manifest, self.policy, resolved)

    def test_product_membership_and_forbidden_transitive_dependency(self):
        """Product roots and separately reviewed isolation closures are both enforced."""
        self.policy["isolation"]["A"] = ["B"]
        with self.assertRaisesRegex(ValueError, "isolation"):
            self.graph()
        self.policy["isolation"]["A"] = []
        self.manifest["products"].pop()
        with self.assertRaisesRegex(ValueError, "Product roots"):
            self.graph()

    def test_independent_consumer_selected_graph_and_actual_imports(self):
        """Standalone consumers cannot hide root selection, transitive coupling or undeclared imports."""
        directory = self.root / "Examples/Consumer/Sources/App"
        directory.mkdir(parents=True)
        source = directory / "App.swift"
        source.write_text("import A\nimport Foundation")
        manifest = {"dependencies": [{"fileSystem": [{"path": str(self.root)}]}], "targets": [{"name": "App", "type": "executable", "dependencies": [{"product": ["A", "DiscordKit", None, None]}]}]}
        self.policy["consumers"] = {"Examples/Consumer": {"targets": {"App": ["DiscordKit/A"]}, "forbidden": []}}
        result = audit.validate_consumer(self.root, "Examples/Consumer", manifest, self.policy)
        self.assertEqual(result["reachableTargets"], ["A", "B"])
        self.policy["consumers"]["Examples/Consumer"]["forbidden"] = ["B"]
        with self.assertRaisesRegex(ValueError, "isolation"):
            audit.validate_consumer(self.root, "Examples/Consumer", manifest, self.policy)
        self.policy["consumers"]["Examples/Consumer"]["forbidden"] = []
        source.write_text("import B")
        with self.assertRaisesRegex(ValueError, "Undeclared consumer import"):
            audit.validate_consumer(self.root, "Examples/Consumer", manifest, self.policy)
        source.write_text("import A")
        manifest["dependencies"][0]["fileSystem"][0]["path"] = str(self.root.parent)
        with self.assertRaisesRegex(ValueError, "this checkout"):
            audit.validate_consumer(self.root, "Examples/Consumer", manifest, self.policy)

    def test_consumer_system_imports_remain_scoped_and_validated(self):
        """A reviewed platform gauge import is local to its target and rejects malformed policy."""
        relative = "Tools/Benchmarks"
        for name, source in (("App", "#if os(macOS)\nimport Darwin\n#endif"), ("Other", "import Foundation")):
            path = self.root / relative / "Sources" / name / (name + ".swift")
            path.parent.mkdir(parents=True)
            path.write_text(source)
        manifest = {"dependencies": [{"fileSystem": [{"path": str(self.root)}]}],
                    "targets": [{"name": name, "type": "executable", "dependencies": []} for name in ("App", "Other")]}
        entry = {"targets": {"App": [], "Other": []}, "forbidden": [], "targetSystemImports": {"App": ["Darwin"]}}
        self.policy["consumers"] = {relative: entry}
        self.assertEqual(audit.validate_consumer(self.root, relative, manifest, self.policy)["sourceFiles"], 2)
        other = self.root / relative / "Sources/Other/Other.swift"
        other.write_text("import Darwin")
        with self.assertRaisesRegex(ValueError, "Undeclared consumer import"):
            audit.validate_consumer(self.root, relative, manifest, self.policy)
        other.write_text("import Foundation")
        for value in ({"Missing": ["Darwin"]}, {"App": "Darwin"}, {"App": [None]}, [], {"App": [""]}, {"App": ["B"]}, {"App": ["DiscordClient"]}):
            entry["targetSystemImports"] = value
            with self.subTest(policy=value), self.assertRaisesRegex(ValueError, "system imports"):
                audit.validate_consumer(self.root, relative, manifest, self.policy)
        entry.pop("targetSystemImports")
        with self.assertRaisesRegex(ValueError, "Undeclared consumer import"):
            audit.validate_consumer(self.root, relative, manifest, self.policy)

    def test_evidence_paths_reject_escape_and_absolute(self):
        """Absolute, missing, traversal and symlink-escaped files never count as evidence."""
        for value in ("../evidence.txt", "/etc/passwd", "missing"):
            with self.subTest(path=value), self.assertRaises(ValueError):
                audit.local_file(self.root, value)
        (self.root / "escape").symlink_to(Path(self.root.anchor) / "etc/passwd")
        with self.assertRaises(ValueError):
            audit.local_file(self.root, "escape")

    def consumer_authoring_fixture(self):
        """Create an explicitly reviewed example selecting a local macro product and existing Crypto."""
        relative, _, _ = self.authoring_fixture()
        source = self.root / "Examples/Consumer/Sources/App/App.swift"
        source.parent.mkdir(parents=True)
        source.write_text("import A\nimport Authoring\nimport Crypto")
        manifest = {"dependencies": [
            {"fileSystem": [{"path": str(self.root)}]},
            {"fileSystem": [{"path": str(self.root / relative)}]},
            {"sourceControl": [{"identity": "swift-crypto", "location": {"remote": [{"urlString": self.policy["externalPackages"]["swift-crypto"]}]}, "requirement": {"range": [{"lowerBound": "5.0.1", "upperBound": "6.0.0"}]}}]},
        ], "targets": [{"name": "App", "type": "executable", "dependencies": [
            {"product": ["A", "DiscordKit", None, None]},
            {"product": ["Authoring", "Authoring", None, None]},
            {"product": ["Crypto", "swift-crypto", None, None]},
        ]}]}
        self.policy["consumers"] = {"Examples/Consumer": {
            "targets": {"App": ["Authoring/Authoring", "DiscordKit/A", "swift-crypto/Crypto"]},
            "forbidden": [], "authoringPackages": {"Authoring": relative},
            "externalProducts": {"swift-crypto": ["Crypto"]},
            "directRequirements": {"swift-crypto": {"range": [{"lowerBound": "5.0.1", "upperBound": "6.0.0"}]}},
        }}
        return manifest

    def test_consumer_explicit_authoring_and_crypto_preserve_runtime_isolation(self):
        """Reviewed authoring selection contributes its transitive root runtime to the isolation audit."""
        manifest = self.consumer_authoring_fixture()
        result = audit.validate_consumer(self.root, "Examples/Consumer", manifest, self.policy)
        self.assertEqual(result["selectedProducts"], ["A"])
        self.assertEqual(result["reachableTargets"], ["A", "B"])
        manifest["targets"][0]["dependencies"].pop(0)
        self.policy["consumers"]["Examples/Consumer"]["targets"]["App"].remove("DiscordKit/A")
        (self.root / "Examples/Consumer/Sources/App/App.swift").write_text("import Authoring\nimport Crypto")
        self.policy["consumers"]["Examples/Consumer"]["forbidden"] = ["B"]
        with self.assertRaisesRegex(ValueError, "isolation"):
            audit.validate_consumer(self.root, "Examples/Consumer", manifest, self.policy)

    def test_consumer_additional_packages_require_exact_reviewed_paths_urls_and_versions(self):
        """Missing, duplicate, escaped and unreviewed packages cannot widen the selected example graph."""
        original = self.consumer_authoring_fixture()
        mutations = [
            lambda m: m["dependencies"][1]["fileSystem"][0].update(path=str(self.root.parent)),
            lambda m: m["dependencies"].append(copy.deepcopy(m["dependencies"][0])),
            lambda m: m["dependencies"].pop(),
            lambda m: m["dependencies"][2]["sourceControl"][0].update(identity="unknown"),
            lambda m: m["dependencies"][2]["sourceControl"][0]["location"]["remote"][0].update(urlString="https://example.invalid/fork"),
            lambda m: m["dependencies"][2]["sourceControl"][0].update(requirement={"exact": ["6.0.0"]}),
            lambda m: m["dependencies"].append(copy.deepcopy(m["dependencies"][2])),
            lambda m: m["dependencies"].append({"registry": []}),
        ]
        for mutation in mutations:
            manifest = copy.deepcopy(original)
            mutation(manifest)
            with self.subTest(manifest=manifest), self.assertRaises(ValueError):
                audit.validate_consumer(self.root, "Examples/Consumer", manifest, self.policy)

    def test_consumer_unknown_authoring_or_external_products_fail_closed(self):
        """Policy target roots do not bypass separately reviewed macro/product membership."""
        original = self.consumer_authoring_fixture()
        for index, replacement in ((1, ["OtherMacro", "Authoring", None, None]),
                                   (2, ["CryptoExtras", "swift-crypto", None, None]),
                                   (0, ["A", "UnknownPackage", None, None])):
            manifest = copy.deepcopy(original)
            manifest["targets"][0]["dependencies"][index]["product"] = replacement
            graph = {"App": audit.manifest_dependencies(manifest["targets"][0])}
            self.policy["consumers"]["Examples/Consumer"]["targets"] = graph
            with self.subTest(product=replacement), self.assertRaisesRegex(ValueError, "unknown"):
                audit.validate_consumer(self.root, "Examples/Consumer", manifest, self.policy)
        self.policy["consumers"]["Examples/Consumer"]["authoringPackages"] = {"Authoring": "Packages/Missing"}
        with self.assertRaisesRegex(ValueError, "unaudited"):
            audit.validate_consumer(self.root, "Examples/Consumer", original, self.policy)

    def authoring_fixture(self):
        """Create a separate plugin package whose generated runtime declarations select A only."""
        relative = "Packages/Authoring"
        directory = self.root / relative
        for path, text in {"Sources/Authoring/Authoring.swift": "import A",
                           "Sources/Plugin/Plugin.swift": "import SwiftSyntax",
                           "Tests/Tests.swift": "import Testing\nimport Authoring"}.items():
            source = directory / path
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(text)
        manifest = {"products": [{"name": "Authoring", "targets": ["Authoring"], "type": {"library": ["automatic"]}}],
                    "targets": [
                        {"name": "Authoring", "type": "regular", "dependencies": [{"byName": ["Plugin", None]}, {"product": ["A", "DiscordKit", None, None]}]},
                        {"name": "Plugin", "type": "macro", "dependencies": [{"product": ["SwiftSyntax", "swift-syntax", None, None]}]},
                        {"name": "AuthoringTests", "type": "test", "path": "Tests", "dependencies": [{"byName": ["Authoring", None]}]},
                    ], "dependencies": [
                        {"fileSystem": [{"path": str(self.root)}]},
                        {"sourceControl": [{"identity": "swift-syntax", "location": {"remote": [{"urlString": "https://github.com/swiftlang/swift-syntax.git"}]}, "requirement": {"exact": ["604.0.0"]}}]},
                    ]}
        self.policy["authoringPackages"] = {relative: {
            "products": {"Authoring": ["Authoring"]},
            "targets": {"Authoring": ["DiscordKit/A", "Plugin"], "Plugin": ["swift-syntax/SwiftSyntax"], "AuthoringTests": ["Authoring"]},
            "targetTypes": {"Authoring": "regular", "Plugin": "macro", "AuthoringTests": "test"},
            "targetPaths": {"Authoring": "Sources/Authoring", "Plugin": "Sources/Plugin", "AuthoringTests": "Tests"},
            "targetSystemImports": {"AuthoringTests": ["Testing"]},
            "externalPackages": {"swift-syntax": "https://github.com/swiftlang/swift-syntax.git"},
            "directRequirements": {"swift-syntax": {"exact": ["604.0.0"]}}, "forbiddenRuntimeTargets": [],
        }}
        resolved = copy.deepcopy(self.resolved)
        resolved["pins"].append({"identity": "swift-syntax", "kind": "remoteSourceControl",
                                 "location": "https://github.com/swiftlang/swift-syntax.git",
                                 "state": {"version": "604.0.0", "revision": "b" * 40}})
        return relative, manifest, resolved

    def test_separate_authoring_package_checks_plugin_tests_and_runtime_closure(self):
        """Downstream authoring adds compiler tools while retaining the exact root runtime closure."""
        relative, manifest, resolved = self.authoring_fixture()
        result = audit.validate_authoring_package(self.root, relative, manifest, self.policy, resolved)
        self.assertEqual(result, {"products": 1, "targets": 3, "sourceFiles": 3,
                                  "resolvedPackages": 2, "runtimeTargets": ["A", "B"]})
        self.policy["authoringPackages"][relative]["forbiddenRuntimeTargets"] = ["B"]
        with self.assertRaisesRegex(ValueError, "isolation"):
            audit.validate_authoring_package(self.root, relative, manifest, self.policy, resolved)

    def test_runtime_products_never_select_compiler_dependencies(self):
        """Adding a reviewed-looking SwiftSyntax edge cannot introduce compiler tools into runtime products."""
        self.authoring_fixture()
        self.manifest["targets"][0]["dependencies"].append({"product": ["SwiftSyntax", "swift-syntax", None, None]})
        self.policy["targets"]["A"].append("swift-syntax/SwiftSyntax")
        with self.assertRaisesRegex(ValueError, "Runtime products must not depend"):
            self.graph()

    def test_authoring_direct_package_and_pin_changes_fail_closed(self):
        """Wrong runtime checkout, SwiftSyntax requirement, URL, version and resolved set all reject."""
        relative, manifest, resolved = self.authoring_fixture()
        mutations = [
            lambda m, r: m["dependencies"][0]["fileSystem"][0].update(path=str(self.root.parent)),
            lambda m, r: m["dependencies"][1]["sourceControl"][0].update(requirement={"exact": ["605.0.0"]}),
            lambda m, r: m["dependencies"][1]["sourceControl"][0]["location"]["remote"][0].update(urlString="https://example.invalid/fork"),
            lambda m, r: r["pins"][-1]["state"].update(version="605.0.0"),
            lambda m, r: r["pins"][-1]["state"].update(revision="main"),
            lambda m, r: r["pins"].pop(),
            lambda m, r: r["pins"].append(copy.deepcopy(r["pins"][-1])),
        ]
        for index, change in enumerate(mutations):
            candidate, pins = copy.deepcopy(manifest), copy.deepcopy(resolved)
            change(candidate, pins)
            with self.subTest(index=index), self.assertRaises(ValueError):
                audit.validate_authoring_package(self.root, relative, candidate, self.policy, pins)

    def test_authoring_target_product_and_source_changes_reject(self):
        """Target topology, target kind, published plugin roots and source redirection need explicit review."""
        relative, manifest, resolved = self.authoring_fixture()
        mutations = [
            lambda m: m["targets"][0]["dependencies"].append({"product": ["B", "DiscordKit", None, None]}),
            lambda m: m["targets"][1].update(type="regular"),
            lambda m: m["targets"][2].update(path="../other-tests"),
            lambda m: m["products"][0].update(targets=["Plugin"]),
            lambda m: m["products"][0].update(type={"executable": None}),
        ]
        for index, change in enumerate(mutations):
            candidate = copy.deepcopy(manifest)
            change(candidate)
            with self.subTest(index=index), self.assertRaises(ValueError):
                audit.validate_authoring_package(self.root, relative, candidate, self.policy, resolved)

    def test_authoring_import_scope_includes_inactive_plugin_and_test_code(self):
        """Inactive branches and test targets cannot hide undeclared imports or escaping source links."""
        relative, manifest, resolved = self.authoring_fixture()
        source = self.root / relative / "Tests/Tests.swift"
        source.write_text("#if os(Imaginary)\nimport SwiftSyntax\n#endif")
        with self.assertRaisesRegex(ValueError, "Undeclared authoring import"):
            audit.validate_authoring_package(self.root, relative, manifest, self.policy, resolved)
        source.unlink()
        source.symlink_to(self.root / "Sources/A/A.swift")
        with self.assertRaisesRegex(ValueError, "symlink escapes"):
            audit.validate_authoring_package(self.root, relative, manifest, self.policy, resolved)

    def test_compiler_plugin_cannot_select_runtime_even_if_reviewed_policy_adds_edge(self):
        """A plugin operates on syntax rather than importing runtime implementation products."""
        relative, manifest, resolved = self.authoring_fixture()
        manifest["targets"][1]["dependencies"].append({"product": ["A", "DiscordKit", None, None]})
        self.policy["authoringPackages"][relative]["targets"]["Plugin"] = ["DiscordKit/A", "swift-syntax/SwiftSyntax"]
        with self.assertRaisesRegex(ValueError, "Compiler plugin must not depend"):
            audit.validate_authoring_package(self.root, relative, manifest, self.policy, resolved)

    def test_duplicate_json_keys_and_stale_evidence(self):
        """Ambiguous overwritten evidence and changed bytes reject validation."""
        path = self.root / "duplicate.json"
        path.write_text('{"id": 1, "id": 2}')
        with self.assertRaisesRegex(ValueError, "Duplicate JSON"):
            audit.read_json(path)
        (self.root / "evidence.txt").write_text("changed")
        with self.assertRaisesRegex(ValueError, "Stale evidence"):
            audit.evidence_file(self.root, self.evidence)

    def test_unverified_gates_are_explicitly_excluded(self):
        """An unavailable live gate can pass report validation only with a narrower claim."""
        result = audit.validate_report(self.root, self.report, self.policy)
        self.assertEqual((result["passed"], result["unverified"], result["claims"]), (1, 1, 1))
        self.assertEqual(result["excludedClaims"], ["live", "live-discord"])

    def test_missing_failed_and_duplicate_checks_reject(self):
        """Missing gates, failed checks and duplicate IDs cannot look like a complete release."""
        for mutate in (lambda r: r["checks"].pop(), lambda r: r["checks"][0].update(status="failed"), lambda r: r["checks"].append(r["checks"][0])):
            report = copy.deepcopy(self.report)
            mutate(report)
            with self.assertRaises(ValueError):
                audit.validate_report(self.root, report, self.policy)

    def test_unverified_claims_and_missing_evidence_reject(self):
        """Both a claimed excluded scope and a claim depending on unavailable gates fail."""
        for change in ({"id": "live-discord"}, {"checkIDs": ["live"]}, {"checkIDs": ["unknown"]}):
            report = copy.deepcopy(self.report)
            report["claims"][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                audit.validate_report(self.root, report, self.policy)
        self.report["checks"][0]["evidence"] = []
        with self.assertRaises(ValueError):
            audit.validate_report(self.root, self.report, self.policy)

    def test_exclusion_requires_array_and_canonical_gate_id(self):
        """A substring string or unrelated exclusion label cannot stand in for the unavailable gate."""
        for exclusions in ("live", ["unrelated"]):
            report = copy.deepcopy(self.report)
            report["checks"][1]["excludedClaims"] = exclusions
            with self.subTest(exclusions=exclusions), self.assertRaises(ValueError):
                audit.validate_report(self.root, report, self.policy)

    def test_global_exclusions_cannot_be_claimed_through_passed_local_gate(self):
        """A declared global limitation remains excluded even when a claim cites a passed local gate."""
        self.report["globalExclusions"] = ["production-qualification"]
        self.assertIn("production-qualification", audit.validate_report(self.root, self.report, self.policy)["excludedClaims"])
        self.report["claims"][0]["id"] = "production-qualification"
        with self.assertRaisesRegex(ValueError, "Unverified qualification"):
            audit.validate_report(self.root, self.report, self.policy)

    def maintenance(self):
        """Build exact-date fixtures and source records for current/future boundary checks."""
        (self.root / "history.json").write_text('[{"id":"historical"}]')
        fixture = {"schemaVersion": 1, "transitionID": "channel-obfuscation-http", "effectiveOn": "2026-11-16", "cases": [{"id": "before", "date": "2026-11-15", "expectedPhase": "current"}, {"id": "on", "date": "2026-11-16", "expectedPhase": "effective"}]}
        path = self.root / "fixture.json"
        path.write_text(json.dumps(fixture))
        return {"schemaVersion": 1, "reviewedOn": "2026-10-18", "nextReviewDue": "2026-10-25", "unclassifiedEntries": [], "historyPath": "history.json", "officialSources": [{"url": "https://docs.discord.com/developers/change-log", "verifiedOn": "2026-10-18", "snapshotPath": self.evidence["path"], "sha256": self.evidence["sha256"]}], "transitions": [{"id": "channel-obfuscation-http", "announcedOn": "2026-08-12", "effectiveOn": "2026-11-16", "status": "future_effective", "sourceURLs": ["https://docs.discord.com/developers/change-log"], "fixturePath": "fixture.json", "fixtureSHA256": hashlib.sha256(path.read_bytes()).hexdigest(), "currentBehavior": "channels visible", "futureBehavior": "inaccessible omitted"}]}

    def test_maintenance_current_then_effective_with_fresh_review(self):
        """Future behavior remains separate; fresh on-date review changes its explicit status."""
        record = self.maintenance()
        result = audit.validate_maintenance(self.root, record, dt.date(2026, 10, 18))
        self.assertEqual(result["transitions"], 1)
        record.update(reviewedOn="2026-11-16", nextReviewDue="2026-11-23")
        record["officialSources"][0]["verifiedOn"] = "2026-11-16"
        record["transitions"][0]["status"] = "effective"
        self.assertEqual(audit.validate_maintenance(self.root, record, dt.date(2026, 11, 16))["asOf"], "2026-11-16")

    def test_maintenance_overdue_unclassified_and_early_activation(self):
        """Overdue reviews, unclassified changes and early effective-state claims fail."""
        record = self.maintenance()
        with self.assertRaisesRegex(ValueError, "overdue"):
            audit.validate_maintenance(self.root, record, dt.date(2026, 10, 26))
        record["unclassifiedEntries"] = ["new-upstream-feature"]
        with self.assertRaisesRegex(ValueError, "Unclassified"):
            audit.validate_maintenance(self.root, record, dt.date(2026, 10, 18))
        record["unclassifiedEntries"] = []
        record["transitions"][0]["status"] = "effective"
        with self.assertRaisesRegex(ValueError, "incorrect current status"):
            audit.validate_maintenance(self.root, record, dt.date(2026, 10, 18))

    def test_transition_missing_boundary_and_unsafe_domain(self):
        """Hash-valid but incomplete transition cases and lookalike upstream domains fail."""
        record = self.maintenance()
        path = self.root / "fixture.json"
        fixture = json.loads(path.read_text())
        fixture["cases"].pop()
        path.write_text(json.dumps(fixture))
        record["transitions"][0]["fixtureSHA256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        with self.assertRaisesRegex(ValueError, "before/on"):
            audit.validate_maintenance(self.root, record, dt.date(2026, 10, 18))
        for url in ("http://docs.discord.com/developers/reference", "https://docs.discord.com.evil/developers/reference", "https://github.com/third-party/docs", "https://user@discord.com/developers/reference"):
            with self.subTest(url=url):
                self.assertFalse(audit.official_url(url))

    def test_historical_prefix_cannot_be_rewritten(self):
        """Appending parity entries remains allowed while changing a frozen historical entry fails."""
        record = self.maintenance()
        entry = {"id": "historical"}
        prefix = {"historyPrefix": [{"id": "historical", "sha256": hashlib.sha256(json.dumps(entry, sort_keys=True, separators=(",", ":")).encode()).hexdigest()}]}
        path = self.root / "history.json"
        path.write_text(json.dumps({"entries": [entry, {"id": "new"}]}))
        audit.validate_maintenance(self.root, record, dt.date(2026, 10, 18), prefix)
        path.write_text(json.dumps({"entries": [{"id": "rewritten"}]}))
        with self.assertRaisesRegex(ValueError, "prefix changed"):
            audit.validate_maintenance(self.root, record, dt.date(2026, 10, 18), prefix)


if __name__ == "__main__":
    unittest.main()
