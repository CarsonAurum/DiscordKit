# File: Tools/DiscordKitTools/scripts/test_harvest_inventory.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Deterministic extractor regression tests; only standard-library unittest is required."""

import json
import tempfile
import unittest
from pathlib import Path

from harvest_inventory import (
    catalog_source, clean, digest, entry, markdown_entries, pointer_component,
    protocol_version, spec_entries, write_catalog,
)


class DiscoveryTests(unittest.TestCase):
    """Check discovery boundaries without network requests or full upstream fixtures."""

    def test_identity_and_presentation(self):
        """IDs depend on source/kind/location, never unstable labels or arbitrary iteration."""
        self.assertEqual(clean("[id?](/link) `?string`"), "id? ?string")
        self.assertEqual(len(digest(b"")), 64)
        a = entry("source", "field", "name", "L1", "Object")
        self.assertEqual(a["id"], entry("source", "field", "renamed", "L1", "Object")["id"])
        self.assertNotEqual(a["id"], entry("other", "field", "name", "L1", "Object")["id"])
        self.assertEqual(a["status"], "unsupported")
        self.assertEqual(a["review"], "discovered")

    def test_markdown_structure_and_fences(self):
        """Retain optional/nullable fields, skip illustrative tables, discover real routes."""
        document = '''## Object
| Field | Type | Description |
| --- | --- | --- |
| id? | ?string | Optional and nullable |
```markdown
## fake
| Field | Type |
| --- | --- |
| fake | string |
```
## Get Object
<Route method="GET">/objects/[\\{id\\}](/resource)</Route>
'''
        rows = markdown_entries("developers/resources/objects", document)
        self.assertEqual([r["name"] for r in rows if r["kind"] == "field"], ["id?"])
        self.assertEqual([r["name"] for r in rows if r["kind"] == "endpoint"], ["GET /objects/{id}"])
        self.assertEqual(rows[2]["definition"], {"column": "Type", "value": "?string"})
        self.assertFalse(any(r["name"] == "fake" for r in rows))

    def test_special_reference_tables(self):
        """Opcode, close-code, permissions and intent rows retain their individual kind."""
        for source, title, header, expected in [
            ("developers/topics/opcodes-and-status-codes", "Gateway Opcodes", "Code | Name", "opcode"),
            ("developers/topics/opcodes-and-status-codes", "Voice Close Event Codes", "Code | Description", "close_code"),
            ("developers/topics/permissions", "Permissions", "Permission | Bit", "permission"),
            ("developers/topics/permissions", "Bitwise Permission Flags", "Permission | Value", "permission"),
            ("developers/events/gateway", "Intents", "Intent | Value", "intent"),
            ("developers/topics/rpc", "RPC Events", "Name | Description", "event"),
            ("developers/developer-tools/embedded-app-sdk", "SDK Events", "Name | Description", "event"),
            ("developers/events/gateway-events", "Receive Events", "Name | Description", "event"),
            ("developers/topics/rpc", "Commands and Events\n### Relationship Types", "Name | Value", "enum_value"),
            ("developers/topics/rpc", "Commands and Events\n### RPC Commands", "Name | Description", "sdk_method"),
            ("developers/reference", "CDN Endpoints", "Type | Path", "endpoint"),
            ("unknown", "Unknown", "Thing | Description", "table_row"),
        ]:
            with self.subTest(expected=expected):
                rows = markdown_entries(source, f"## {title}\n| {header} |\n| --- | --- |\n| 0 | value |\n")
                self.assertEqual(rows[-1]["kind"], expected)

    def test_guide_and_intent_code_blocks(self):
        """Guide-only endpoints and normative plain-text intents survive code-fence filtering."""
        rows = markdown_entries("developers/events/gateway", "## List of Intents\n```\nGUILDS (1 << 0)\nGUILD_MEMBERS (1 << 1) **\n```\n")
        intents = [r for r in rows if r["kind"] == "intent"]
        self.assertEqual([r["definition"]["bit"] for r in intents], [0, 1])
        rows = markdown_entries("guide", "```python\nrequests.post('https://discord.com/api/v10/partner-sdk/token/bot')\n```\n```http\nPOST /partner-sdk/token\n```\n")
        self.assertEqual(len([r for r in rows if r["kind"] == "endpoint"]), 2)

    def test_regression_guide_templates_unversioned_oauth_and_gateway_headings(self):
        """Retain variable-prefix backend paths, OAuth URLs, indented changelog and event headings."""
        guide = "```python\nrequests.post(f'{API_ENDPOINT}/partner-sdk/child-token')\nrequests.post('%s/partner-sdk/provisional-accounts/unmerge' % API_ENDPOINT)\n```\nPOST https://discord.com/api/oauth2/token/rpc\n"
        rows = markdown_entries("guide", guide)
        self.assertEqual(len([r for r in rows if r["kind"] == "endpoint"]), 3)
        rows = markdown_entries("developers/events/gateway-events", "## Send Events\n#### Identify\n## Receive Events\n#### Ready\n")
        self.assertEqual([r["name"] for r in rows if r["kind"] == "event"], ["Identify", "Ready"])
        rows = markdown_entries("developers/change-log", "  ## New feature\n")
        self.assertEqual(rows[-1]["name"], "New feature")

    def test_nested_inline_spec(self):
        """Discover nested array/union properties and huge enum values without float conversion."""
        maximum = 2**64 - 1
        document = {"paths": {"/things/{id}": {"get": {"operationId": "get_thing"}, "parameters": []}}, "components": {"schemas": {"Thing": {"properties": {"nested": {"items": {"anyOf": [{"properties": {"value": {"enum": [maximum, "unknown", None]}}}]}}}}}}}
        rows = spec_entries("spec", document)
        self.assertEqual([r["name"] for r in rows if r["kind"] == "endpoint"], ["GET /things/{id}"])
        self.assertEqual([r["name"] for r in rows if r["kind"] == "field"], ["nested", "value"])
        self.assertIn(str(maximum), [r["name"] for r in rows if r["kind"] == "enum_value"])
        self.assertTrue(any("~1things~1{id}" in r["locator"] for r in rows))
        self.assertEqual(pointer_component("a~/b"), "a~0~1b")

    def test_catalog_is_reproducible(self):
        """A minimal complete local snapshot produces byte-identical catalogs on repeated runs."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "developers").mkdir()
            (root / "snippets").mkdir()
            (root / "specs").mkdir()
            (root / "developers" / "example.mdx").write_text("## Example\n")
            (root / "snippets" / "error.mdx").write_text("## Error\n")
            for name in ("openapi.json", "openapi_preview.json"):
                (root / "specs" / name).write_text('{}')
            (root / "index.txt").write_text("- [Example](https://docs.discord.com/developers/example.md)\n")
            count = write_catalog(root, root, root / "index.txt", root / "out")
            before = (root / "out" / "inventory-v1.json").read_bytes()
            self.assertEqual(count, (7, 5))
            self.assertEqual(write_catalog(root, root, root / "index.txt", root / "out"), count)
            self.assertEqual(before, (root / "out" / "inventory-v1.json").read_bytes())
            catalog = json.loads((root / "out" / "sources-2026-10-15.json").read_bytes())
            self.assertEqual(catalog["sources"][1]["announcementDate"], "unknown")
            self.assertIn("github.com", catalog["sources"][1]["url"])

    def test_contract_map_owns_every_overload(self):
        """Shared SDK anchors keep unique signature IDs and per-source discovery membership."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "specs").mkdir()
            for name in ("openapi.json", "openapi_preview.json"):
                (root / "specs" / name).write_text('{}')
            (root / "index").write_text("- [Example](https://docs.discord.com/example.md)\n")
            methods = {"sources": [{"id": "sdk", "url": "https://discord.com/sdk", "sha256": "a" * 64, "revision": None}], "methods": []}
            for identifier, transport, blocker in [("overload1", "local computation", None), ("overload2", "missing contract", {"id": "gap"})]:
                methods["methods"].append({"id": identifier, "sourceID": "sdk", "symbol": "same()", "surface": "Social", "definitionURL": "https://discord.com/sdk#same", "mapping": {"transport": transport}, "blocker": blocker})
            (root / "methods").write_text(json.dumps(methods))
            self.assertEqual(write_catalog(root, root, root / "index", root / "out", root / "methods"), (5, 4))
            rows = json.loads((root / "out" / "inventory-v1.json").read_text())["entries"][-2:]
            self.assertNotEqual(rows[0]["id"], rows[1]["id"])
            self.assertEqual([r["condition"] for r in rows], ["not_applicable", "undocumented_protocol"])
            methods["definitions"] = [{"id": "sdk.enum.1", "sourceID": "sdk", "surface": "Social", "symbol": "Status::New", "kind": "enum_value", "definitionURL": "https://discord.com/sdk#enum", "signatureSHA256": "b" * 64, "rawValue": "18446744073709551615"}]
            (root / "methods").write_text(json.dumps(methods))
            self.assertEqual(write_catalog(root, root, root / "index", root / "out", root / "methods"), (6, 4))
            last = json.loads((root / "out" / "inventory-v1.json").read_text())["entries"][-1]
            self.assertEqual(last["kind"], "enum_value")
            self.assertEqual(last["definition"]["rawValue"], "18446744073709551615")

    def test_source_provenance(self):
        """Source metadata retains the exact content hash and marks upstream dates unknown."""
        source = catalog_source("id", "https://example.com", "revision", b"abc", "written_docs", "10", [{"id": "entry"}])
        self.assertEqual(source["sha256"], digest(b"abc"))
        self.assertEqual(source["entryIDs"], ["entry"])
        self.assertEqual(source["effectiveDate"], "unknown")

    def test_protocol_surfaces_are_independent(self):
        """REST, Gateway and voice versions never imply a local RPC, SDK or OAuth version."""
        for source, expected in [
            ("developers/topics/voice-connections", "8"),
            ("developers/topics/rpc", "unversioned"),
            ("developers/topics/certified-devices", "unversioned"),
            ("developers/topics/oauth2", "unversioned"),
            ("developers/developer-tools/embedded-app-sdk", "unversioned"),
            ("developers/discord-social-sdk/development-guides/example", "unversioned"),
            ("developers/events/gateway", "10"),
            ("developers/resources/user", "10"),
            ("developers/intro", "not_applicable"),
        ]:
            with self.subTest(source=source):
                self.assertEqual(protocol_version(source), expected)


if __name__ == "__main__":
    unittest.main()
