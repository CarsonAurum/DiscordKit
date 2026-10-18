#!/usr/bin/env python3
"""Normalize public Swift symbol graphs and conservatively enforce source semver.

The baseline is scoped to the compiler target that emitted its graphs. Conditional
APIs on other targets require separate snapshots; a macOS snapshot is not an ABI,
Linux, Windows, device, or Android compatibility qualification.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re

from release_check import local_file, read_json, require


def semantic_version(value):
    """Parse stable major.minor.patch versions; prerelease/build metadata is deliberately unsupported."""
    require(isinstance(value, str) and re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", value), "Expected stable semantic version")
    return tuple(int(part) for part in value.split("."))


def fingerprint(symbol):
    """Hash source-significant declarations, constraints, availability and callable signatures.

    Documentation, source paths, line offsets, generated timestamps and compiler
    prose are excluded. Spelling/defaults, access, availability, generic/extension
    constraints and parameter signatures remain compatibility-significant.
    """
    keys = ["kind", "accessLevel", "pathComponents", "declarationFragments", "functionSignature", "swiftGenerics", "swiftExtension", "availability", "isVirtual"]
    canonical = {key: symbol[key] for key in keys if key in symbol}
    # Display names can change independently; fragments' precise IDs encode type identity.
    return hashlib.sha256(json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def snapshot(directory, expected_modules, version):
    """Read all graph shards for the exact expected product modules into a deterministic baseline.

    Graph fragments from dependencies are ignored; every owned product module
    must occur. Conflicting duplicate symbols or mixed compiler target triples
    fail instead of silently dropping a shard. Public and open symbols only are
    admitted. Relationships retain conformance/requirement/member changes.
    """
    semantic_version(version)
    modules = {}
    platforms = set()
    for path in sorted(directory.glob("*.symbols.json")):
        graph = read_json(path)
        name = graph.get("module", {}).get("name")
        if name not in expected_modules:
            continue
        platform = graph["module"].get("platform", {})
        # Minimum OS deployment version is source policy, but SDK patch versions are not.
        platforms.add(json.dumps(platform, sort_keys=True))
        module = modules.setdefault(name, {"symbols": {}, "relationships": []})
        for symbol in graph.get("symbols", []):
            if symbol.get("accessLevel") not in {"public", "open"}:
                continue
            identifier = symbol["identifier"]["precise"]
            record = {"signatureSHA256": fingerprint(symbol), "kind": symbol["kind"]["identifier"], "path": symbol.get("pathComponents", [])}
            if identifier in module["symbols"]:
                require(module["symbols"][identifier] == record, f"Conflicting symbol shard: {identifier}")
            module["symbols"][identifier] = record
        for relationship in graph.get("relationships", []):
            qualifiers = {key: value for key, value in relationship.items() if key not in {"source", "kind", "target", "targetFallback"}}
            module["relationships"].append([relationship["source"], relationship["kind"], relationship["target"], json.dumps(qualifiers, sort_keys=True, separators=(",", ":"))])
    require(set(modules) == set(expected_modules), "Symbol graph module coverage differs from product policy")
    require(len(platforms) == 1, "Mixed or missing symbol graph platform scope")
    for module in modules.values():
        module["symbols"] = dict(sorted(module["symbols"].items()))
        module["relationships"] = sorted(set(tuple(value) for value in module["relationships"]))
        require(module["symbols"], "Empty public module graph")
    return {"schemaVersion": 1, "version": version, "platform": json.loads(next(iter(platforms))), "qualification": "source_api_snapshot_only", "modules": dict(sorted(modules.items()))}


def snapshot_modules(policy, authoring_package=None):
    """Select exact reviewed public runtime or downstream authoring modules.

    A separate authoring snapshot contains only library product roots; compiler
    plugins and tests remain outside the public source-API contract. Unknown
    packages and invalid policy roots fail rather than silently narrowing scope.
    Omitting the package retains the existing complete runtime target policy.
    """
    if authoring_package is None:
        return set(policy["targets"])
    require(authoring_package in policy.get("authoringPackages", {}), "Unknown authoring package API scope")
    package = policy["authoringPackages"][authoring_package]
    modules = {name for roots in package["products"].values() for name in roots}
    require(modules and all(package["targetTypes"].get(name) == "regular" for name in modules),
            "Authoring API products must select regular library modules")
    return modules


def validate_snapshot(value):
    """Validate normalized snapshot shape, including exact symbol hashes and duplicate edges."""
    require(value.get("schemaVersion") == 1 and value.get("qualification") == "source_api_snapshot_only", "Unsupported API snapshot")
    semantic_version(value.get("version"))
    require(isinstance(value.get("platform"), dict) and value["platform"], "Missing API platform scope")
    require(isinstance(value.get("modules"), dict) and value["modules"], "Missing API modules")
    for module in value["modules"].values():
        require(module.get("symbols"), "Missing public symbols")
        for identifier, symbol in module["symbols"].items():
            require(isinstance(identifier, str) and identifier, "Invalid public symbol identifier")
            require(re.fullmatch(r"[0-9a-f]{64}", symbol.get("signatureSHA256", "")), "Invalid API fingerprint")
            require(isinstance(symbol.get("kind"), str) and symbol["kind"], "Missing API symbol kind")
        edges = module.get("relationships", [])
        require(all(isinstance(edge, (list, tuple)) and len(edge) in {3, 4} and all(isinstance(part, str) for part in edge) for edge in edges), "Malformed API relationship")
        require(len(edges) == len({tuple(edge) for edge in edges}), "Duplicate API relationship")


def write_snapshot(path, value):
    """Write deterministic valid JSON with one compact symbol/relationship per reviewable line.

    The normalized data remains ordinary JSON, but avoids both megabytes of
    pretty-print array whitespace and one enormous line that obscures API diffs.
    Only the explicitly requested output path is replaced.
    """
    validate_snapshot(value)
    encode = lambda item: json.dumps(item, sort_keys=True, separators=(",", ":"))
    lines = ["{"]
    for key in ("schemaVersion", "version", "platform", "qualification"):
        lines.append(f'  {encode(key)}:{encode(value[key])},')
    lines.append('  "modules":{')
    modules = sorted(value["modules"])
    for index, name in enumerate(modules):
        module = value["modules"][name]
        lines.append(f'    {encode(name)}:{{"relationships":[')
        edges = sorted(module["relationships"])
        lines.extend(f"      {encode(edge)}{',' if position + 1 < len(edges) else ''}" for position, edge in enumerate(edges))
        lines.append('    ],"symbols":{')
        symbols = sorted(module["symbols"])
        lines.extend(f"      {encode(identifier)}:{encode(module['symbols'][identifier])}{',' if position + 1 < len(symbols) else ''}" for position, identifier in enumerate(symbols))
        lines.append(f"    }}}}{',' if index + 1 < len(modules) else ''}")
    lines.extend(["  }", "}", ""])
    path.write_text("\n".join(lines))


def compare(baseline, candidate, proposed):
    """Classify source changes and reject insufficient or decreasing semantic versions.

    Removal/signature/constraint/availability/relationship removal is breaking.
    New required protocol members and enum cases are breaking to conformers or
    exhaustive switches. Other additions require a minor increment. Breaking
    changes require a major increment at 1.x+, or a minor increment before 1.0.
    Unchanged snapshots permit the same candidate version for release validation.
    This conservative check cannot prove behavioral or binary compatibility.
    """
    validate_snapshot(baseline)
    validate_snapshot(candidate)
    previous, next_version = semantic_version(baseline["version"]), semantic_version(proposed)
    require(candidate["version"] == proposed, "Candidate snapshot version differs from proposed release")
    require(next_version >= previous, "Semantic version decreases")
    require(candidate["platform"] == baseline["platform"], "API snapshots have different platform scopes")
    changes = {"removed": [], "changed": [], "added": [], "removedRelationships": [], "addedRelationships": [], "removedModules": [], "addedModules": []}
    old_modules, new_modules = baseline["modules"], candidate["modules"]
    changes["removedModules"] = sorted(set(old_modules) - set(new_modules))
    changes["addedModules"] = sorted(set(new_modules) - set(old_modules))
    required_additions = []
    for name in sorted(set(old_modules) | set(new_modules)):
        old = old_modules.get(name, {"symbols": {}, "relationships": []})
        new = new_modules.get(name, {"symbols": {}, "relationships": []})
        before, after = old["symbols"], new["symbols"]
        removed, added = set(before) - set(after), set(after) - set(before)
        changes["removed"].extend(f"{name}:{key}" for key in sorted(removed))
        changes["added"].extend(f"{name}:{key}" for key in sorted(added))
        changes["changed"].extend(f"{name}:{key}" for key in sorted(set(before) & set(after)) if before[key] != after[key])
        old_edges, new_edges = {tuple(edge) for edge in old["relationships"]}, {tuple(edge) for edge in new["relationships"]}
        changes["removedRelationships"].extend([name, *edge] for edge in sorted(old_edges - new_edges))
        changes["addedRelationships"].extend([name, *edge] for edge in sorted(new_edges - old_edges))
        required_additions.extend(key for key in added if after[key]["kind"] == "swift.enum.case")
        required_additions.extend(edge[0] for edge in new_edges - old_edges if edge[1] == "requirementOf")
    breaking = bool(changes["removed"] or changes["changed"] or changes["removedRelationships"] or changes["removedModules"] or required_additions)
    additive = any(changes.values())
    required = "major" if breaking else "minor" if additive else "none"
    if breaking:
        require(next_version[0] > previous[0] or (previous[0] == 0 and next_version[1] > previous[1]), "Breaking source API requires major version (minor before 1.0)")
    elif additive:
        require(next_version[:2] > previous[:2], "Additive source API requires minor version")
    return {"baselineVersion": baseline["version"], "candidateVersion": proposed, "requiredIncrement": required, "changes": changes}


def main():
    """Snapshot compiler output or compare two exact local baselines; never invoke networking."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["snapshot", "check"])
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--symbolgraphs", type=Path)
    parser.add_argument("--authoring-package", help="Snapshot one separate package from the root release policy")
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--candidate", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "snapshot":
            require(args.symbolgraphs and args.output, "snapshot requires --symbolgraphs and --output")
            policy = read_json(local_file(args.repository.resolve(), "Tools/DiscordKitTools/release-policy.json"))
            result = snapshot(args.symbolgraphs, snapshot_modules(policy, args.authoring_package), args.version)
            write_snapshot(args.output, result)
            print(json.dumps({"modules": len(result["modules"]), "symbols": sum(len(module["symbols"]) for module in result["modules"].values()), "version": args.version}, sort_keys=True))
        else:
            require(args.baseline and args.candidate, "check requires --baseline and --candidate")
            print(json.dumps(compare(read_json(args.baseline), read_json(args.candidate), args.version), sort_keys=True))
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, f"API audit failed: {error}\n")


if __name__ == "__main__":
    main()
