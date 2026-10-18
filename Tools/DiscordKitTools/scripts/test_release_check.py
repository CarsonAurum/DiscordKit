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

    def test_evidence_paths_reject_escape_and_absolute(self):
        """Absolute, missing, traversal and symlink-escaped files never count as evidence."""
        for value in ("../evidence.txt", "/etc/passwd", "missing"):
            with self.subTest(path=value), self.assertRaises(ValueError):
                audit.local_file(self.root, value)
        (self.root / "escape").symlink_to(Path(self.root.anchor) / "etc/passwd")
        with self.assertRaises(ValueError):
            audit.local_file(self.root, "escape")

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
