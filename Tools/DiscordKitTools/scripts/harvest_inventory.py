#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/harvest_inventory.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Reproduce the discovery inventory from pinned, local official sources (no network).

This is a discovery extractor, not a schema generator or semantic contract reviewer.
Markdown sections and table rows are retained individually so ambiguous prose is
visible instead of silently discarded. The preview specification remains supplemental.
Only identifying labels, source locations and hashes are retained, not full documents.
"""

import argparse
import hashlib
import json
import re
from pathlib import Path

DATE = "2026-10-15"
DOCS_REVISION = "37148620d2324292b76047541d5f8331f81ea77a"
SPEC_REVISION = "ed014089afa986f2b532ae081c456a85de074d0c"
STATUSES = "unsupported"


def digest(data):
    """Return lowercase SHA-256 for source provenance and stable definition IDs."""
    return hashlib.sha256(data).hexdigest()


def clean(value):
    """Strip presentation markup while retaining wire spelling and optionality markers."""
    value = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", value)
    return re.sub(r"\s+", " ", value.replace("`", "").replace("\\", "")).strip()


def entry(source, kind, name, locator, context, condition="not_applicable"):
    """Create an unsupported discovery record; extraction never grants SDK parity."""
    return {
        "id": "d-" + digest(f"{source}\n{kind}\n{locator}".encode())[:24],
        "kind": kind, "name": clean(name), "sourceID": source,
        "locator": locator, "context": clean(context), "status": STATUSES,
        "condition": condition, "review": "discovered", "evidence": [],
    }


def markdown_entries(source, text):
    """Discover pages, headings, routes, fields, enumerants and other table rows.

    Code fences are skipped to avoid treating illustrative JSON or Markdown as
    normative definitions. Every unrecognized table row is retained as table_row.
    Semantic review must resolve those records before implementation, not infer a
    public protocol solely from a guide's title. Lines are one-based source locators.
    """
    technical = any(part in source for part in (
        "/resources/", "/events/", "/interactions/", "/components/", "/topics/",
    ))
    condition = "public_protocol" if technical else "not_applicable"
    rows = [entry(source, "page", source.rsplit("/", 1)[-1], "L1", "Document", condition)]
    headings = []
    headers = None
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        context = " > ".join(n for _, n in headings) or "Document"
        # Normative intent definitions are published as a plain-text code block.
        intent = re.match(r"^([A-Z_]+)\s+\(1\s*<<\s*(\d+)\)", stripped)
        if source.endswith("/events/gateway") and intent:
            item = entry(source, "intent", intent[1], f"L{number}", context, "public_protocol")
            item["definition"] = {"bit": int(intent[2])}
            rows.append(item)
        # Guides often put the only endpoint contract inside an HTTP/curl/Python example.
        guide_url = re.search(r"https://discord\.com/api/(?:v10/)?(?:oauth2|partner-sdk|applications|users|lobbies|channels|guilds|webhooks)/[^\s'\"`)]+", line)
        template_path = re.search(r"(?:\{API_ENDPOINT\}|%s)(/partner-sdk/[^\s'\"`)]+)", line)
        request = re.match(r"^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+(/\S+)", stripped)
        if guide_url or request or template_path:
            name = request[0] if request else guide_url[0] if guide_url else template_path[1]
            rows.append(entry(source, "endpoint", name, f"L{number}", context, "public_protocol"))
        fence_match = re.match(r"^(`{3,}|~{3,})", stripped)
        if fence_match:
            marker = fence_match.group(1)[0]
            fence = None if fence == marker else marker if fence is None else fence
            continue
        if fence:
            continue
        heading = re.match(r"^(#{1,6})\s+(.+)", stripped)
        if heading:
            depth, name = len(heading[1]), clean(heading[2])
            headings = [(d, n) for d, n in headings if d < depth] + [(depth, name)]
            context = " > ".join(n for _, n in headings)
            kind = "section"
            if source.endswith("/gateway-events") and (depth == 4 or name == "Request Channel Info"):
                kind = "event"
            if source.endswith("/embedded-app-sdk") and depth == 3:
                kind = "event" if "SDK Events" in context else "sdk_method" if "(" in name else "section"
            if source.endswith(("/gateway", "/voice-connections")) and any(word in name.lower() for word in ("connect", "heartbeat", "resum", "identify", "handshak")):
                kind = "protocol_state"
            rows.append(entry(source, kind, name, f"L{number}", context, condition))
            headers = None
        route = re.search(r'<Route\s+method="([A-Z]+)"[^>]*>(.*?)</Route>', line)
        context = " > ".join(n for _, n in headings) or "Document"
        if route:
            rows.append(entry(source, "endpoint", f"{route[1]} {route[2]}", f"L{number}", context, "public_protocol"))
        # Some backend guides publish HTTP request lines instead of Route elements.
        if not stripped.startswith("|"):
            headers = None
            continue
        cells = [clean(x) for x in re.split(r"(?<!\\)\|", stripped.strip("|"))]
        if all(re.fullmatch(r"[: -]+", cell or " ") for cell in cells):
            continue
        if headers is None:
            headers = cells
            continue
        if not cells or not cells[0]:
            continue
        first = headers[0].lower()
        lower_context = context.lower()
        kind = "table_row"
        if first in ("field", "parameter", "param", "property"):
            kind = "field"
        elif "opcode" in lower_context:
            kind = "opcode"
        elif "close" in lower_context and "code" in lower_context:
            kind = "close_code"
        elif source.endswith("/permissions") and (first == "permission" or "bit" in " ".join(headers).lower()):
            kind = "permission"
        elif "intent" in lower_context:
            kind = "intent"
        elif "event" in first or lower_context.endswith(("send events", "receive events", "sdk events", "rpc events")):
            kind = "event"
        elif lower_context.split(" > ")[-1] in ("sdk methods", "sdk commands", "rpc commands"):
            kind = "sdk_method"
        elif lower_context.split(" > ")[-1] == "cdn endpoints":
            kind = "endpoint"
        elif any(x in first for x in ("type", "value", "name", "flag", "code")):
            kind = "enum_value"
        item = entry(source, kind, cells[0], f"L{number}", context, condition)
        # Preserve value/type metadata without copying the descriptive document.
        if len(cells) > 1 and headers[1].lower() not in ("description", "explanation"):
            item["definition"] = {"column": headers[1], "value": cells[1]}
        rows.append(item)
    return rows


def pointer_component(value):
    """Escape one RFC 6901 JSON-pointer token, including path slashes and tildes."""
    return str(value).replace("~", "~0").replace("/", "~1")


def protocol_version(source):
    """Choose a surface version without incorrectly treating local RPC/OAuth as REST.

    Sources combining multiple mechanisms remain unversioned at source level;
    recognizable v10 endpoint URLs and voice-opcode entries override that default.
    RPC's handshake version is a payload field, not a REST API version.
    """
    if source.endswith("/voice-connections"):
        return "8"
    if source.endswith(("/rpc", "/certified-devices", "/oauth2", "/embedded-app-sdk")) or "/discord-social-sdk/" in source or "/social-commerce/" in source:
        return "unversioned"
    if any(part in source for part in ("/resources/", "/events/", "/interactions/", "/topics/", "/components/")):
        return "10"
    return "not_applicable"


def spec_entries(source, document):
    """Discover every operation, named schema, nested property and enum variant.

    Entire stable and preview documents are inventoried separately to preserve
    contradictions; neither overrides written docs. JSON pointers are definitions,
    not a claim that a matching REST implementation exists.
    """
    rows = [entry(source, "page", source, "#", "OpenAPI 3.1 discovery", "not_applicable")]
    for path, methods in document.get("paths", {}).items():
        for method, definition in methods.items():
            if method.lower() in ("get", "post", "put", "patch", "delete", "head", "options", "trace"):
                pointer = f"#/paths/{pointer_component(path)}/{method}"
                item = entry(source, "endpoint", f"{method.upper()} {path}", pointer, definition.get("operationId", path), "public_protocol")
                item["definition"] = {"operationId": definition.get("operationId"), "security": definition.get("security", [])}
                rows.append(item)
    for name in document.get("components", {}).get("schemas", {}):
        rows.append(entry(source, "model", name, "#/components/schemas/" + pointer_component(name), name, "public_protocol"))

    def visit(node, pointer, context):
        """Walk arbitrarily nested schemas, retaining inline properties and numeric lexemes."""
        if isinstance(node, dict):
            for key, value in node.items():
                child = pointer + "/" + pointer_component(key)
                if key == "properties" and isinstance(value, dict):
                    for name, definition in value.items():
                        location = child + "/" + pointer_component(name)
                        item = entry(source, "field", name, location, context, "public_protocol")
                        if isinstance(definition, dict):
                            item["definition"] = {k: definition[k] for k in ("type", "$ref", "format") if k in definition}
                        rows.append(item)
                elif key == "enum" and isinstance(value, list):
                    for index, variant in enumerate(value):
                        rows.append(entry(source, "enum_value", json.dumps(variant, ensure_ascii=False), child + f"/{index}", context, "public_protocol"))
                visit(value, child, child if key == "schemas" else context)
        elif isinstance(node, list):
            for index, value in enumerate(node):
                visit(value, pointer + f"/{index}", context)

    visit(document, "#", "OpenAPI definition")
    return rows


def catalog_source(source_id, url, revision, content, authority, protocol, entries):
    """Capture immutable content provenance and membership without inventing upstream dates."""
    return {
        "id": source_id, "url": url, "revision": revision, "sha256": digest(content),
        "verifiedOn": DATE, "announcementDate": "unknown", "effectiveDate": "unknown",
        "protocolVersion": protocol, "authority": authority,
        "accessPrerequisites": "See linked definition; per-operation auth, approval and scopes require semantic review before implementation.",
        "platformAvailability": "See capability matrix; no DiscordKit runtime capability is qualified by discovery.",
        "entryIDs": [row["id"] for row in entries],
    }


def write_catalog(docs_root, spec_root, index_path, output, method_path=None):
    """Write deterministic UTF-8 catalogs from local snapshots and optional SDK mappings.

    Input revisions must be the constants above. Source Git blob verification is a
    separate acquisition step documented in Parity/README. Existing catalogs are
    overwritten only when explicitly invoking this development command.
    """
    entries, sources = [], []
    paths = sorted((docs_root / "developers").rglob("*.mdx")) + sorted((docs_root / "snippets").rglob("*.mdx"))
    for path in paths:
        relative = path.relative_to(docs_root).as_posix()
        source_id = relative.removesuffix(".mdx")
        content = path.read_bytes()
        rows = markdown_entries(source_id, content.decode())
        protocol = protocol_version(source_id)
        for row in rows:
            row["protocolVersion"] = "8" if source_id.endswith("opcodes-and-status-codes") and row["context"].startswith("Voice") else protocol
            if row["kind"] == "endpoint" and "/api/v10/" in row["name"]:
                row["protocolVersion"] = "10"
            if row["kind"] == "endpoint" and "/api/oauth2/" in row["name"]:
                row["protocolVersion"] = "unversioned"
        url = "https://docs.discord.com/" + source_id if relative.startswith("developers/") else f"https://github.com/discord/discord-api-docs/blob/{DOCS_REVISION}/{relative}"
        sources.append(catalog_source(source_id, url, DOCS_REVISION, content, "written_docs", protocol, rows))
        entries.extend(rows)
    for filename in ("openapi.json", "openapi_preview.json"):
        source_id = "spec/" + filename
        content = (spec_root / "specs" / filename).read_bytes()
        rows = spec_entries(source_id, json.loads(content))
        for row in rows:
            row["protocolVersion"] = "10"
        sources.append(catalog_source(source_id, f"https://github.com/discord/discord-api-spec/blob/{SPEC_REVISION}/specs/{filename}", SPEC_REVISION, content, "preview_spec", "10", rows))
        entries.extend(rows)
    content = index_path.read_bytes()
    rows = []
    for number, line in enumerate(content.decode().splitlines(), 1):
        match = re.match(r"- \[([^]]+)\]\((https://docs.discord.com/[^)]+)\)", line)
        if match:
            rows.append(entry("docs-index", "page", match[1], f"L{number}", match[2]))
    sources.append(catalog_source("docs-index", "https://docs.discord.com/llms.txt", "sha256:" + digest(content), content, "discovery_index", "not_applicable", rows))
    entries.extend(rows)
    if method_path and method_path.exists():
        content = method_path.read_bytes()
        mapping = json.loads(content)
        grouped = {source["id"]: [] for source in mapping["sources"]}
        for method in mapping["methods"]:
            source_id = "contracts/" + method["sourceID"]
            condition = "undocumented_protocol" if method.get("blocker") else "not_applicable" if method["mapping"]["transport"] == "local computation" else "public_protocol"
            row = entry(source_id, "event" if method["surface"] == "ActivityEvent" else "sdk_method", method["symbol"], method["definitionURL"], method["surface"], condition)
            # Overloads can share an anchor; retain the source's unique signature-based key.
            row["id"] = "m-" + digest(method["id"].encode())[:24]
            row["definition"] = {"mappingID": method["id"], "mapping": method["mapping"], "blocker": method.get("blocker")}
            grouped[method["sourceID"]].append(row)
        for definition in mapping.get("definitions", []):
            source_id = "contracts/" + definition["sourceID"]
            kind = {"callback_type": "model", "static_value": "field"}.get(definition["kind"], definition["kind"])
            row = entry(source_id, kind, definition["symbol"], definition["definitionURL"], definition["surface"], "not_applicable")
            row["id"] = "m-" + digest(definition["id"].encode())[:24]
            row["definition"] = {"mappingID": definition["id"], "definitionKind": definition["kind"], "signatureSHA256": definition["signatureSHA256"]}
            if "rawValue" in definition:
                row["definition"]["rawValue"] = definition["rawValue"]
            grouped[definition["sourceID"]].append(row)
        for source in mapping["sources"]:
            rows = grouped[source["id"]]
            if not rows:
                # Context-only sources are provenance in the method map, not empty inventory groups.
                continue
            record = catalog_source("contracts/" + source["id"], source["url"], source.get("revision") or "sha256:" + source["sha256"], b"", "sdk_reference", "unversioned", rows)
            record["sha256"] = source["sha256"]
            sources.append(record)
            entries.extend(rows)
    output.mkdir(parents=True, exist_ok=True)
    inventory = {"schemaVersion": 1, "verifiedOn": DATE, "protocolVersions": {"rest": "10", "gateway": "10", "voice": "8"}, "entries": entries}
    catalog = {"schemaVersion": 1, "verifiedOn": DATE, "sources": sources}
    for name, document in (("inventory-v1.json", inventory), ("sources-2026-10-15.json", catalog)):
        # One record per line keeps reviewed diffs bounded and source inventories searchable.
        key = "entries" if name.startswith("inventory") else "sources"
        header = {k: v for k, v in document.items() if k != key}
        prefix = json.dumps(header, ensure_ascii=False, sort_keys=True)[:-1]
        body = ",\n".join(json.dumps(row, ensure_ascii=False, sort_keys=True) for row in document[key])
        (output / name).write_text(prefix + f', "{key}": [\n' + body + "\n]}\n")
    return len(entries), len(sources)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--docs", type=Path, required=True)
    parser.add_argument("--spec", type=Path, required=True)
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--methods", type=Path)
    args = parser.parse_args()
    print("Discovered entries/sources:", write_catalog(args.docs, args.spec, args.index, args.output, args.methods))
