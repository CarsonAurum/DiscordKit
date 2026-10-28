# File: Tools/DiscordKitTools/scripts/test_verify_social_catalog.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Regression tests for exhaustive Social declaration and blocker traceability."""

import copy
import json
from pathlib import Path
import tempfile
import unittest

from verify_social_catalog import load_and_validate, validate_catalog, validate_evidence


class SocialCatalogTests(unittest.TestCase):
    """Use isolated evidence files to reject omitted declarations and inflated claims."""

    def setUp(self):
        """Create an isolated checkout-shaped evidence root and three stable declarations.

        The fixture includes one overload-like Social method ID, one event callback
        alias and one Commerce capability. No network or production test execution
        is involved; temporary files are removed by unittest cleanup.
        """
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        (self.root / "Source.swift").write_text("public struct Owned {}\n")
        (self.root / "Tests.swift").write_text("import Testing\n@Test func owned() {}\n")
        self.baseline = {"methods": [], "definitions": []}
        rows = []
        for key, surface, kind in [
            ("social.method.signature", "Social", "method"),
            ("social.callback.signature", "Social", "callback_type"),
            ("commerce.capability.signature", "Commerce", "method"),
        ]:
            original = {
                "id": key, "surface": surface, "kind": kind, "symbol": key,
                "definitionURL": "https://discord.com/example#" + key,
                "signatureSHA256": "0" * 64,
            }
            self.baseline["definitions" if kind == "callback_type" else "methods"].append(original)
            rows.append({
                **original, "status": "partial", "sdkParity": False,
                "prerequisites": ["Consented user"], "authorizationBoundary": "User bearer",
                "platforms": {"iOS": "unqualified", "android": "unqualified"},
                "limitation": "Synthetic equivalent only", "blockerIDs": ["wire"],
                "ownedEquivalent": {
                    "scope": "Owned behavior", "limitations": "No native SDK parity",
                    "implementations": [{"path": "Source.swift", "symbol": "Owned"}],
                    "tests": ["Tests.swift"],
                },
            })
        self.catalog = {
            "schemaVersion": 1, "entirePlatformParity": False, "qualification": "offline_local_only",
            "entries": rows, "blockers": [{
                "id": "wire", "kind": "upstream_contract", "reason": "No published wire schema",
                "requiredEvidence": "Official schema and permitted user authentication",
            }],
        }

    def test_complete_catalog_and_local_loader(self):
        """A complete local catalog reports stable counts and loads without regeneration."""
        report = validate_catalog(self.catalog, self.baseline, self.root)
        self.assertEqual(report, {
            "entries": 3, "baselineDeclarations": 3, "blockers": 1, "statuses": {"partial": 3},
        })
        (self.root / "Docs/Parity").mkdir(parents=True)
        (self.root / "Docs/Feasibility").mkdir(parents=True)
        (self.root / "Docs/Parity/social-catalog.json").write_text(json.dumps(self.catalog))
        (self.root / "Docs/Feasibility/method-contracts.json").write_text(json.dumps(self.baseline))
        self.assertEqual(load_and_validate(self.root), report)

    def test_all_declaration_kinds_are_required(self):
        """Methods, callback aliases and Commerce gaps cannot disappear from a release."""
        for index in range(3):
            with self.subTest(index=index):
                catalog = copy.deepcopy(self.catalog)
                del catalog["entries"][index]
                with self.assertRaisesRegex(ValueError, "Missing original"):
                    validate_catalog(catalog, self.baseline, self.root)

    def test_declaration_identity_cannot_be_rewritten(self):
        """Stable signatures, public source anchors and symbols retain baseline identity."""
        for field in ["symbol", "definitionURL", "signatureSHA256"]:
            with self.subTest(field=field):
                catalog = copy.deepcopy(self.catalog)
                catalog["entries"][0][field] = "changed"
                with self.assertRaises(ValueError):
                    validate_catalog(catalog, self.baseline, self.root)

    def test_support_and_qualification_cannot_expand(self):
        """Synthetic tests and public equivalents cannot become SDK or live qualification."""
        changes = [
            (None, "schemaVersion", 2), (None, "entirePlatformParity", True),
            (None, "qualification", "live_discord"),
            (0, "status", "supported"), (0, "sdkParity", True),
        ]
        for index, field, value in changes:
            with self.subTest(field=field):
                catalog = copy.deepcopy(self.catalog)
                target = catalog if index is None else catalog["entries"][index]
                target[field] = value
                with self.assertRaises(ValueError):
                    validate_catalog(catalog, self.baseline, self.root)

    def test_duplicates_and_unknown_records_are_rejected(self):
        """Overloads stay uniquely identified and invented SDK declarations are rejected."""
        catalog = copy.deepcopy(self.catalog)
        catalog["entries"].append(copy.deepcopy(catalog["entries"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            validate_catalog(catalog, self.baseline, self.root)
        catalog["entries"][-1]["id"] = "social.invented"
        with self.assertRaisesRegex(ValueError, "Unknown non-mobile"):
            validate_catalog(catalog, self.baseline, self.root)

    def test_missing_boundaries_and_evidence_are_rejected(self):
        """An equivalent needs declared authorization, platform and implementation limits."""
        for field in ["prerequisites", "authorizationBoundary", "platforms", "limitation", "ownedEquivalent", "blockerIDs"]:
            with self.subTest(field=field):
                catalog = copy.deepcopy(self.catalog)
                del catalog["entries"][0][field]
                with self.assertRaises(ValueError):
                    validate_catalog(catalog, self.baseline, self.root)

    def test_partial_evidence_is_local_concrete_and_swift_testing(self):
        """Missing declarations, tests, and non-Swift-Testing evidence do not count."""
        equivalent = copy.deepcopy(self.catalog["entries"][0]["ownedEquivalent"])
        equivalent["implementations"][0]["symbol"] = "MissingType"
        with self.assertRaisesRegex(ValueError, "symbol"):
            validate_evidence(equivalent, self.root)
        equivalent["implementations"][0]["symbol"] = "Owned"
        equivalent["tests"] = ["missing.swift"]
        with self.assertRaisesRegex(ValueError, "test path"):
            validate_evidence(equivalent, self.root)
        equivalent["tests"] = ["Source.swift"]
        with self.assertRaisesRegex(ValueError, "Swift Testing"):
            validate_evidence(equivalent, self.root)

    def test_evidence_cannot_escape_repository(self):
        """Absolute, parent-relative and symlink escapes cannot provide local evidence."""
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / "Outside.swift"
            external.write_text("public struct Owned {}\n")
            (self.root / "Escape.swift").symlink_to(external)
            for path in [str(external), "../absent.swift", "Escape.swift"]:
                with self.subTest(path=path):
                    equivalent = copy.deepcopy(self.catalog["entries"][0]["ownedEquivalent"])
                    equivalent["implementations"][0]["path"] = path
                    with self.assertRaisesRegex(ValueError, "implementation path"):
                        validate_evidence(equivalent, self.root)

    def test_named_blockers_are_complete_and_referenced(self):
        """Every incomplete row resolves to exactly described upstream or local evidence."""
        for mutation in ["unknown", "missing", "duplicate", "unused", "kind", "reason", "requiredEvidence"]:
            with self.subTest(mutation=mutation):
                catalog = copy.deepcopy(self.catalog)
                if mutation == "unknown":
                    catalog["entries"][0]["blockerIDs"] = ["absent"]
                elif mutation == "missing":
                    catalog["entries"][0]["blockerIDs"] = []
                elif mutation in {"duplicate", "unused"}:
                    blocker = copy.deepcopy(catalog["blockers"][0])
                    if mutation == "unused":
                        blocker["id"] = "unused"
                    catalog["blockers"].append(blocker)
                else:
                    catalog["blockers"][0][mutation] = "invalid" if mutation == "kind" else ""
                with self.assertRaises(ValueError):
                    validate_catalog(catalog, self.baseline, self.root)

    def test_blocked_and_native_language_rows_do_not_require_fake_implementations(self):
        """Unimplemented wire operations stay blocked; C++ ownership stays explicit."""
        catalog = copy.deepcopy(self.catalog)
        catalog["entries"][0]["status"] = "blocked"
        del catalog["entries"][0]["ownedEquivalent"]
        catalog["entries"][1]["status"] = "language_specific"
        catalog["entries"][1]["blockerIDs"] = []
        del catalog["entries"][1]["ownedEquivalent"]
        self.assertEqual(validate_catalog(catalog, self.baseline, self.root)["statuses"], {
            "blocked": 1, "language_specific": 1, "partial": 1,
        })

    def test_mobile_capabilities_preserve_distinct_platform_prerequisites(self):
        """Additional current mobile capabilities must distinguish iOS from Android."""
        mobile = copy.deepcopy(self.catalog["entries"][0])
        mobile.update({"id": "mobile.deep_link", "kind": "mobile_capability"})
        self.catalog["entries"].append(mobile)
        self.assertEqual(validate_catalog(self.catalog, self.baseline, self.root)["entries"], 4)
        del mobile["platforms"]["android"]
        with self.assertRaisesRegex(ValueError, "Mobile platform"):
            validate_catalog(self.catalog, self.baseline, self.root)

    def test_repository_release_catalog(self):
        """The committed release map covers every historical declaration and real evidence."""
        repository = Path(__file__).resolve().parents[3]
        report = load_and_validate(repository)
        self.assertGreaterEqual(report["baselineDeclarations"], 735)
        self.assertGreater(report["entries"], report["baselineDeclarations"])
        self.assertGreater(report["blockers"], 0)


if __name__ == "__main__":
    unittest.main()
