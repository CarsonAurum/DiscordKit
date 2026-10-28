#!/usr/bin/env python3
# File: Tools/DiscordKitTools/scripts/release_check.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Fail-closed, offline release traceability, module isolation and maintenance checks.

These audits inspect declared evidence. They never turn local measurements into
live interoperability, independent review, or untested platform qualification.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlparse


def require(condition, message):
    """Raise ValueError with a non-secret diagnostic when an invariant is false."""
    if not condition:
        raise ValueError(message)


def read_json(path):
    """Decode one UTF-8 JSON file, rejecting duplicate object keys rather than overwriting."""
    def unique(pairs):
        """Build an object from parser pairs; duplicate keys invalidate evidence."""
        result = {}
        for key, value in pairs:
            require(key not in result, f"Duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(Path(path).read_text(), object_pairs_hook=unique)


def local_file(repository, relative):
    """Resolve an existing repository-relative file, rejecting traversal and symlink escape."""
    require(isinstance(relative, str) and relative and not Path(relative).is_absolute() and ".." not in Path(relative).parts, "Expected relative evidence path without traversal")
    root = repository.resolve()
    path = (root / relative).resolve()
    require(path.is_relative_to(root) and path.is_file(), f"Missing or unsafe file: {relative}")
    return path


def evidence_file(repository, evidence):
    """Verify a root-relative evidence object's exact SHA-256 and return its path."""
    path = local_file(repository, evidence.get("path"))
    digest = evidence.get("sha256", "")
    require(re.fullmatch(r"[0-9a-f]{64}", digest) is not None, "Invalid evidence SHA-256")
    require(hashlib.sha256(path.read_bytes()).hexdigest() == digest, f"Stale evidence hash: {evidence['path']}")
    return path


def iso_date(value):
    """Parse an exact Gregorian YYYY-MM-DD value, rejecting compact or alternate forms."""
    require(isinstance(value, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value), "Invalid ISO date")
    return dt.date.fromisoformat(value)


def swift_imports(source):
    """Collect imported module identifiers using a conservative Swift lexical scan.

    Comments, strings (including recursively nested interpolation) and regex
    literals are skipped as complete tokens. Every conditional compilation
    branch remains in scope. Backticked and Unicode module identifiers retain
    their spelling. Malformed comments/literals fail rather than dropping text.
    This checks imports, not full Swift syntax or compiler-selected conditions.
    """
    length = len(source)
    import_kinds = {"typealias", "struct", "class", "enum", "protocol", "let", "var", "func"}
    regex_context = {None, "=", "(", "[", "{", ",", ":", ";", "!", "?", "&", "|", "+", "-", "*", "%", "^", "~", "<", ">", "return", "throw", "case", "in"}

    def identifier_start(character):
        """Recognize ASCII/Unicode Swift identifier candidates without hiding unknown modules."""
        return character == "_" or character.isalpha() or ord(character) >= 128

    def comment_end(index):
        """Skip line comments or balanced nested block comments, preserving lexical ownership."""
        if source.startswith("//", index):
            end = source.find("\n", index)
            return length if end < 0 else end
        end, depth = index + 2, 1
        while end < length and depth:
            if source.startswith("/*", end):
                depth += 1
                end += 2
            elif source.startswith("*/", end):
                depth -= 1
                end += 2
            else:
                end += 1
        require(depth == 0, "Unterminated Swift comment")
        return end

    def string_end(index, hashes, quotes):
        """Skip a complete ordinary/raw string and recursively consume interpolation expressions."""
        end = index + len(hashes) + len(quotes)
        closing, escape = quotes + hashes, "\\" + hashes
        while end < length:
            if source.startswith(closing, end):
                return end + len(closing)
            if source.startswith(escape, end):
                end += len(escape)
                if end < length and source[end] == "(":
                    end, _ = tokens(end + 1, interpolation=True)
                else:
                    end += 1
            else:
                require(quotes == '"""' or source[end] not in "\r\n", "Unterminated Swift string")
                end += 1
        raise ValueError("Unterminated Swift string")

    def regex_end(index, hashes):
        """Skip slash-delimited regex text, escaped delimiters, classes and interpolation."""
        end, bracket_depth = index + len(hashes) + 1, 0
        closing, escape = "/" + hashes, "\\" + hashes
        while end < length:
            if source.startswith(escape, end):
                end += len(escape)
                if end < length and source[end] == "(":
                    end, _ = tokens(end + 1, interpolation=True)
                else:
                    end += 1
            elif not bracket_depth and source.startswith(closing, end):
                return end + len(closing)
            else:
                if source[end] == "[":
                    bracket_depth += 1
                elif source[end] == "]" and bracket_depth:
                    bracket_depth -= 1
                end += 1
        raise ValueError("Unterminated Swift regex literal")

    def tokens(index, interpolation=False):
        """Tokenize code until EOF or the matching interpolation close, recursively masking literals."""
        result, depth, previous = [], 0, None
        while index < length:
            character = source[index]
            if character.isspace():
                index += 1
                continue
            if source.startswith(("//", "/*"), index):
                index = comment_end(index)
                continue
            string = re.match(r'(\#*)("""|")', source[index:])
            extended_regex = re.match(r'(\#+)/', source[index:])
            if string:
                index = string_end(index, *string.groups())
                token = "<literal>"
            elif extended_regex:
                index = regex_end(index, extended_regex.group(1))
                token = "<literal>"
            elif (character == "/" and previous in regex_context and index + 1 < length
                  and not source[index + 1].isspace() and source[index + 1] != "="):
                index = regex_end(index, "")
                token = "<literal>"
            elif character == "`":
                end = source.find("`", index + 1)
                require(end > index + 1, "Unterminated or empty Swift escaped identifier")
                token = source[index:end + 1]
                index = end + 1
            elif identifier_start(character):
                end = index + 1
                while end < length and (identifier_start(source[end]) or source[end].isdigit()):
                    end += 1
                token, index = source[index:end], end
            else:
                if interpolation and character == ")":
                    if depth == 0:
                        return index + 1, result
                    depth -= 1
                elif interpolation and character == "(":
                    depth += 1
                token, index = character, index + 1
            result.append(token)
            previous = token
        require(not interpolation, "Unterminated Swift string interpolation")
        return index, result

    _, lexical = tokens(0)
    imports = set()
    for index, token in enumerate(lexical):
        if token != "import":
            continue
        position = index + 1
        if position < len(lexical) and lexical[position] in import_kinds:
            position += 1
        require(position < len(lexical), "Malformed Swift import")
        module = lexical[position]
        if module.startswith("`") and module.endswith("`"):
            module = module[1:-1]
        require(module and identifier_start(module[0]), "Malformed Swift import")
        imports.add(module)
    return imports


def manifest_dependencies(target):
    """Normalize SwiftPM dump-package target references and external product references."""
    result = []
    for dependency in target.get("dependencies", []):
        require(len(dependency) == 1, "Unexpected target dependency encoding")
        kind, values = next(iter(dependency.items()))
        require(kind in {"byName", "target", "product"}, "Unsupported dependency kind")
        require(isinstance(values, list) and values and isinstance(values[0], str), "Malformed dependency")
        result.append(values[0] if kind != "product" else f"{values[1]}/{values[0]}")
    require(len(result) == len(set(result)), "Duplicate target dependency")
    return sorted(result)


def closure(graph, roots):
    """Return reachable modules including roots; reject cycles and dangling local dependencies."""
    complete, active = set(), set()
    def visit(name):
        """Depth-first visit one local or package/product node and detect cycles."""
        if name in complete:
            return
        require(name not in active, f"Dependency cycle at {name}")
        active.add(name)
        if "/" not in name:
            require(name in graph, f"Unknown local target: {name}")
            for dependency in graph[name]:
                visit(dependency)
        active.remove(name)
        complete.add(name)
    for root in roots:
        visit(root)
    return complete


def dump_manifest(repository):
    """Evaluate the actual SwiftPM manifest with isolated writable caches and no network fetch.

    SwiftPM manifest evaluation executes repository code, as ordinary builds do.
    The development-only --disable-sandbox option accommodates managed macOS hosts;
    this command neither resolves packages nor builds targets.
    """
    with tempfile.TemporaryDirectory(prefix="discordkit-release-") as temporary:
        environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(Path(temporary) / "clang"))
        result = subprocess.run([
            "swift", "package", "--package-path", str(repository), "--disable-sandbox",
            "--cache-path", str(Path(temporary) / "cache"), "dump-package",
        ], check=True, text=True, capture_output=True, env=environment)
        return json.loads(result.stdout)


def validate_graph(repository, manifest, policy, resolved):
    """Audit exact product DAG, reviewed Apple pins and actual imports for shipped targets.

    Manifest edges are checked even when unused by source. Imports are checked in
    every branch against direct dependencies and narrowly allowed system modules.
    Product reachability enforces independent adoption and excludes test support.
    A changed boundary requires an explicit review of the committed policy.
    """
    require(policy.get("schemaVersion") == 1, "Unsupported release policy")
    targets = {target["name"]: target for target in manifest["targets"]}
    require(len(targets) == len(manifest["targets"]), "Duplicate manifest target")
    graph = {name: manifest_dependencies(target) for name, target in targets.items()}
    products = {product["name"]: sorted(product["targets"]) for product in manifest["products"]}
    require(len(products) == len(manifest["products"]), "Duplicate product")
    require(products == policy["products"], "Product roots differ from reviewed policy")
    expected = policy["targets"]
    shipped = set().union(*(closure(graph, roots) for roots in products.values()))
    authoring_targets = {name for package in policy.get("authoringPackages", {}).values()
                         for name in package["targets"]}
    require(not shipped.intersection(authoring_targets)
            and not any(name.lower().startswith("swift-syntax/") for name in shipped),
            "Runtime products must not depend on authoring macros or SwiftSyntax")
    local_shipped = {name for name in shipped if "/" not in name}
    require(local_shipped == set(expected), "Shipped target membership changed")
    imports_count = files_count = 0
    for name in sorted(expected):
        target = targets[name]
        require(target.get("type") == "regular", "Non-library target in product graph")
        require(graph[name] == expected[name], f"Dependency policy mismatch: {name}")
        relative = target.get("path", f"Sources/{name}")
        require(relative == policy.get("targetPaths", {}).get(name, f"Sources/{name}"), f"Target source path changed: {name}")
        path = (repository / relative).resolve()
        require(path.is_relative_to(repository.resolve()) and path.is_dir(), f"Unsafe target path: {name}")
        allowed = {value.split("/")[-1] for value in graph[name]}
        allowed.update(policy["systemImports"])
        allowed.update(policy.get("targetSystemImports", {}).get(name, []))
        excluded = [(path / value).resolve() for value in target.get("exclude", [])]
        for source in path.rglob("*.swift"):
            if any(source.resolve() == value or value in source.resolve().parents for value in excluded):
                continue
            require(source.resolve().is_relative_to(repository.resolve()), "Source symlink escapes repository")
            imports = swift_imports(source.read_text())
            require(not imports - allowed, f"Undeclared import in {source.name}: {', '.join(sorted(imports - allowed))}")
            files_count += 1
            imports_count += len(imports)
    direct_requirements = {}
    for item in manifest.get("dependencies", []):
        require(set(item) == {"sourceControl"}, "Only reviewed source-control dependencies are allowed")
        for source in item["sourceControl"]:
            require(source["identity"] in policy["externalPackages"], "Unreviewed package identity")
            direct_requirements[source["identity"]] = source.get("requirement")
            remote = source["location"].get("remote", [])
            require(len(remote) == 1 and remote[0]["urlString"] == policy["externalPackages"][source["identity"]], "Package URL mismatch")
    if "directRequirements" in policy:
        require(direct_requirements == policy["directRequirements"], "Direct package requirements changed")
    pins = resolved.get("pins", [])
    identities = [pin["identity"] for pin in pins]
    require(len(identities) == len(set(identities)), "Duplicate resolved pin")
    require(set(identities) == set(policy["externalPackages"]), "Resolved package membership changed")
    for pin in pins:
        require(pin.get("kind") == "remoteSourceControl", "Unreviewed resolved package kind")
        require(pin["location"] == policy["externalPackages"][pin["identity"]], "Resolved package URL mismatch")
        require(re.fullmatch(r"[0-9a-f]{40}", pin.get("state", {}).get("revision", "")), "Missing resolved revision")
    for name, forbidden in policy["isolation"].items():
        reached = closure(graph, products[name])
        require(not reached.intersection(forbidden), f"Independent product isolation violation: {name}")
    return {"products": len(products), "targets": len(expected), "sourceFiles": files_count, "imports": imports_count, "resolvedPackages": len(pins)}


def validate_consumer(repository, relative, manifest, policy):
    """Audit one independent example's actual imports, selected products and reachable root DAG.

    Only non-test consumer targets form the delivered example graph. Their exact
    dependency roots are reviewed, all source compile branches are inspected, and
    their selected root product closures must avoid explicitly excluded products.
    Consumers default to this checkout alone. Explicit per-consumer policy may
    additionally select an already audited local authoring package and reviewed
    external products, with exact package paths, URLs and version requirements.
    Authoring-selected runtime closures also participate in isolation checks.
    Reviewed targetSystemImports admit platform measurement modules only in the
    named consumer target; every inactive branch remains inspected. Only Darwin,
    Glibc and the already reviewed global system modules are accepted. Unknown target
    keys and malformed import allowlists fail before source import admission.
    """
    require(relative in policy.get("consumers", {}), "Unknown example consumer")
    expected = policy["consumers"][relative]
    local_packages = {"discordkit": repository.resolve()}
    authoring_packages = {}
    for identity, path in expected.get("authoringPackages", {}).items():
        require(path in policy.get("authoringPackages", {}), "Consumer selects unaudited authoring package")
        package_root = (repository / path).resolve()
        require(package_root.is_relative_to(repository.resolve()) and package_root.is_dir(), "Unsafe consumer authoring package path")
        require(identity.lower() not in local_packages, "Duplicate consumer package identity")
        local_packages[identity.lower()] = package_root
        authoring_packages[identity.lower()] = policy["authoringPackages"][path]
    paths, requirements = [], {}
    for dependency in manifest.get("dependencies", []):
        require(len(dependency) == 1, "Ambiguous consumer package dependency")
        if "fileSystem" in dependency:
            paths.extend(Path(item["path"]).resolve() for item in dependency["fileSystem"])
        else:
            require(set(dependency) == {"sourceControl"}, "Unsupported consumer package dependency")
            for item in dependency["sourceControl"]:
                identity = item["identity"]
                require(identity not in requirements, "Duplicate consumer external package")
                require(identity in expected.get("externalProducts", {}) and identity in policy["externalPackages"], "Unreviewed consumer external package")
                remote = item["location"].get("remote", [])
                require(len(remote) == 1 and remote[0]["urlString"] == policy["externalPackages"][identity], "Consumer package URL mismatch")
                requirements[identity] = item.get("requirement")
    require(len(paths) == len(local_packages) and set(paths) == set(local_packages.values()), "Consumer package does not reference this checkout and exact reviewed local packages")
    require(requirements == expected.get("directRequirements", {}), "Consumer package requirements changed")
    targets = {target["name"]: target for target in manifest["targets"] if target.get("type") != "test"}
    graph = {name: manifest_dependencies(target) for name, target in targets.items()}
    require(graph == expected["targets"], f"Consumer dependency roots changed: {relative}")
    system_imports = expected.get("targetSystemImports", {})
    require(isinstance(system_imports, dict) and not set(system_imports) - set(targets),
            "Consumer system imports name an unknown target")
    permitted_system_imports = set(policy["systemImports"]) | {"Darwin", "Glibc"}
    require(all(isinstance(values, list) and all(isinstance(value, str) and value in permitted_system_imports for value in values)
                for values in system_imports.values()), "Malformed consumer system imports")
    root_products = set()
    source_files = 0
    for name, target in targets.items():
        for dependency in graph[name]:
            if "/" in dependency:
                package, product = dependency.split("/", 1)
                if package.lower() == "discordkit":
                    require(product in policy["products"], "Consumer selects unknown root product")
                    root_products.add(product)
                elif package.lower() in authoring_packages:
                    authoring = authoring_packages[package.lower()]
                    require(product in authoring["products"], "Consumer selects unknown authoring product")
                    reached = closure(authoring["targets"], authoring["products"][product])
                    root_products.update(value.split("/", 1)[1] for value in reached if value.lower().startswith("discordkit/"))
                else:
                    require(package in requirements and product in expected.get("externalProducts", {}).get(package, []), "Consumer selects unknown external product")
            else:
                require(dependency in targets, "Consumer has unknown local target")
        relative_source = target.get("path", f"Sources/{name}")
        require(relative_source == f"Sources/{name}", "Consumer source path changed")
        source_root = (repository / relative / relative_source).resolve()
        require(source_root.is_relative_to(repository.resolve()) and source_root.is_dir(), "Missing consumer sources")
        allowed = {value.split("/")[-1] for value in graph[name]} | set(policy["systemImports"])
        allowed.update(system_imports.get(name, []))
        for source in source_root.rglob("*.swift"):
            require(source.resolve().is_relative_to(source_root), "Consumer source symlink escapes target")
            imports = swift_imports(source.read_text())
            require(not imports - allowed, f"Undeclared consumer import in {source.name}: {', '.join(sorted(imports - allowed))}")
            source_files += 1
    closure(graph, graph)
    selected = set().union(*(closure(policy["targets"], policy["products"][product]) for product in root_products))
    require(not selected.intersection(expected["forbidden"]), f"Consumer isolation violation: {relative}")
    return {"targets": len(targets), "sourceFiles": source_files, "selectedProducts": sorted(root_products), "reachableTargets": sorted(name for name in selected if "/" not in name)}


def validate_authoring_package(repository, relative, manifest, policy, resolved):
    """Audit the downstream compiler package, including plugin/tests and exact host-tool pins.

    The only filesystem package must be this runtime checkout. Other direct
    packages require reviewed URLs and exact manifest requirements. Every target,
    including tests, has reviewed direct imports, type and source location; the
    compiler plugin cannot select runtime products. The resolved package set is
    the root's reviewed closure plus the explicitly pinned authoring dependencies.
    This is graph/source evidence, not compiler or platform qualification.
    """
    require(relative in policy.get("authoringPackages", {}), "Unknown authoring package")
    expected = policy["authoringPackages"][relative]
    package_root = (repository / relative).resolve()
    require(package_root.is_relative_to(repository.resolve()) and package_root.is_dir(), "Unsafe authoring package path")
    targets = {target["name"]: target for target in manifest["targets"]}
    require(len(targets) == len(manifest["targets"]), "Duplicate authoring target")
    graph = {name: manifest_dependencies(target) for name, target in targets.items()}
    require(graph == expected["targets"], "Authoring target dependencies changed")
    products = {product["name"]: sorted(product["targets"]) for product in manifest["products"]}
    require(len(products) == len(manifest["products"]) and products == expected["products"], "Authoring products changed")
    require(all("library" in product["type"] for product in manifest["products"]), "Authoring product must be a library")
    paths = []
    requirements = {}
    for dependency in manifest.get("dependencies", []):
        require(len(dependency) == 1, "Ambiguous authoring package dependency")
        if "fileSystem" in dependency:
            paths.extend(Path(item["path"]).resolve() for item in dependency["fileSystem"])
        else:
            require(set(dependency) == {"sourceControl"}, "Unsupported authoring package dependency")
            for item in dependency["sourceControl"]:
                identity = item["identity"]
                require(identity not in requirements, "Duplicate authoring package identity")
                require(identity in expected["externalPackages"], "Unreviewed authoring package identity")
                remote = item["location"].get("remote", [])
                require(len(remote) == 1 and remote[0]["urlString"] == expected["externalPackages"][identity], "Authoring package URL mismatch")
                requirements[identity] = item.get("requirement")
    require(paths == [repository.resolve()], "Authoring package must reference only this runtime checkout")
    require(requirements == expected["directRequirements"], "Authoring package requirements changed")
    pins = resolved.get("pins", [])
    packages = dict(policy["externalPackages"], **expected["externalPackages"])
    identities = [pin["identity"] for pin in pins]
    require(len(identities) == len(set(identities)) and set(identities) == set(packages), "Authoring resolved package membership changed")
    for pin in pins:
        require(pin.get("kind") == "remoteSourceControl" and pin.get("location") == packages[pin["identity"]], "Authoring resolved package URL or kind changed")
        require(re.fullmatch(r"[0-9a-f]{40}", pin.get("state", {}).get("revision", "")), "Missing authoring resolved revision")
        if pin["identity"] in expected["directRequirements"]:
            require(expected["directRequirements"][pin["identity"]] == {"exact": [pin.get("state", {}).get("version")]}, "Authoring resolved version differs from exact requirement")
    selected = set()
    source_files = 0
    for name, target in targets.items():
        require(target.get("type") == expected["targetTypes"][name], "Authoring target type changed")
        relative_source = target.get("path", f"Sources/{name}")
        require(relative_source == expected["targetPaths"][name], "Authoring target source path changed")
        source_root = (package_root / relative_source).resolve()
        require(source_root.is_relative_to(package_root) and source_root.is_dir(), "Unsafe authoring source path")
        for dependency in graph[name]:
            if "/" in dependency:
                identity, product = dependency.split("/", 1)
                if identity.lower() == "discordkit":
                    require(target.get("type") != "macro", "Compiler plugin must not depend on runtime products")
                    require(product in policy["products"], "Unknown authoring runtime product")
                    selected.update(closure(policy["targets"], policy["products"][product]))
                else:
                    require(identity in expected["externalPackages"], "Unknown authoring external product")
        allowed = {value.split("/")[-1] for value in graph[name]}
        allowed.update(policy["systemImports"])
        allowed.update(expected.get("targetSystemImports", {}).get(name, []))
        for source in source_root.rglob("*.swift"):
            require(source.resolve().is_relative_to(source_root), "Authoring source symlink escapes target")
            imports = swift_imports(source.read_text())
            require(not imports - allowed, f"Undeclared authoring import in {source.name}: {', '.join(sorted(imports - allowed))}")
            source_files += 1
    closure(graph, graph)
    require(not selected.intersection(expected["forbiddenRuntimeTargets"]), "Authoring runtime selection violates isolation")
    return {"products": len(products), "targets": len(targets), "sourceFiles": source_files,
            "resolvedPackages": len(pins), "runtimeTargets": sorted(name for name in selected if "/" not in name)}


def validate_report(repository, report, policy):
    """Check report completeness, exact evidence hashes and exclusions for unavailable gates.

    Passed evidence is traceability, not independent attestation. Every claim must
    depend solely on passed gates; unavailable gates name claims that stay absent.
    Failed gates and missing required checks always reject the release record.
    """
    require(report.get("schemaVersion") == 1, "Unsupported release report")
    require(re.fullmatch(r"\d+\.\d+\.\d+", report.get("releaseVersion", "")), "Invalid release version")
    verified = iso_date(report.get("verifiedOn"))
    require(report.get("protocols") == policy["protocols"], "Protocol-version report mismatch")
    checks = report.get("checks", [])
    require(isinstance(checks, list) and all(isinstance(check, dict) for check in checks), "Malformed release checks")
    ids = [check["id"] for check in checks]
    require(len(ids) == len(set(ids)), "Duplicate release check")
    require(set(ids) == set(policy["requiredCheckIDs"]), "Missing or unknown release checks")
    global_exclusions = report.get("globalExclusions", [])
    require(isinstance(global_exclusions, list) and all(isinstance(value, str) and value.strip() for value in global_exclusions), "Malformed global exclusions")
    by_id, excluded = {}, set(global_exclusions)
    for check in checks:
        status = check.get("status")
        require(status in {"passed", "unverified"}, f"Failed or invalid release gate: {check['id']}")
        require(isinstance(check.get("scope"), str) and check["scope"].strip(), "Missing evidence scope")
        references = check.get("evidence", [])
        excluded_ids = check.get("excludedClaims", [])
        require(isinstance(references, list) and all(isinstance(value, dict) for value in references), "Malformed gate evidence")
        require(isinstance(excluded_ids, list) and all(isinstance(value, str) and value.strip() for value in excluded_ids), "Malformed excluded claims")
        if status == "passed":
            require(check.get("evidence"), f"Passed gate requires evidence: {check['id']}")
        else:
            require(check.get("reason") and check.get("excludedClaims"), "Unverified gate needs reason and excluded claims")
            require(check["id"] in check["excludedClaims"], "Unverified gate must exclude its canonical qualification ID")
        for evidence in check.get("evidence", []):
            evidence_file(repository, evidence)
        excluded.update(check.get("excludedClaims", []))
        by_id[check["id"]] = check
    claims = report.get("claims", [])
    require(isinstance(claims, list) and all(isinstance(claim, dict) for claim in claims), "Malformed support claims")
    claim_ids = [claim["id"] for claim in claims]
    require(len(claim_ids) == len(set(claim_ids)), "Duplicate support claim")
    require(not set(claim_ids).intersection(excluded), "Unverified qualification appears in support claims")
    for claim in claims:
        require(claim.get("description") and claim.get("checkIDs"), "Support claim lacks scope or gate references")
        require(isinstance(claim["checkIDs"], list) and all(isinstance(value, str) and value for value in claim["checkIDs"]), "Malformed claim gate references")
        require(all(value in by_id and by_id[value]["status"] == "passed" for value in claim["checkIDs"]), "Claim depends on unavailable gate")
    return {"releaseVersion": report["releaseVersion"], "verifiedOn": str(verified), "passed": sum(check["status"] == "passed" for check in checks), "unverified": sum(check["status"] == "unverified" for check in checks), "claims": len(claims), "excludedClaims": sorted(excluded)}


def official_url(value):
    """Accept HTTPS Discord documentation/spec sources without credentials or lookalike hosts."""
    url = urlparse(value)
    return (url.scheme == "https" and not url.username and not url.password and not url.port
            and ((url.hostname == "docs.discord.com" and url.path.startswith("/developers/"))
                 or (url.hostname == "discord.com" and url.path.startswith("/developers/"))
                 or (url.hostname == "github.com" and url.path.startswith("/discord/"))))


def validate_maintenance(repository, record, as_of, policy=None):
    """Check weekly review freshness and dated transition fixtures without activating future behavior.

    as_of is an explicit date for deterministic historical reproduction; normal
    CLI use selects today's date. Source snapshot hashes bind locally reviewed
    evidence metadata, not independently fetched upstream bytes. The HTTP channel
    transition is required and must have before/on-boundary fixture cases.
    """
    require(record.get("schemaVersion") == 1, "Unsupported maintenance record")
    reviewed, due = iso_date(record.get("reviewedOn")), iso_date(record.get("nextReviewDue"))
    require(reviewed <= as_of <= due <= reviewed + dt.timedelta(days=7), "Weekly upstream review is overdue or future-dated")
    require(record.get("unclassifiedEntries") == [], "Unclassified upstream changes remain")
    history = read_json(local_file(repository, record.get("historyPath")))
    require(isinstance(history, (dict, list)) and bool(history), "Missing append-only parity history")
    if policy and policy.get("historyPrefix"):
        entries = history.get("entries", [])
        prefix = policy["historyPrefix"]
        require(len(entries) >= len(prefix), "Historical parity entries were removed")
        for entry, expected in zip(entries, prefix):
            digest = hashlib.sha256(json.dumps(entry, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            require(entry.get("id") == expected["id"] and digest == expected["sha256"], "Append-only parity history prefix changed")
    sources = record.get("officialSources", [])
    require(sources, "Missing official source review")
    for source in sources:
        require(official_url(source["url"]), "Unapproved upstream source")
        require(iso_date(source["verifiedOn"]) == reviewed, "Stale source verification date")
        evidence_file(repository, {"path": source["snapshotPath"], "sha256": source["sha256"]})
    transitions = record.get("transitions", [])
    ids = [item["id"] for item in transitions]
    require(len(ids) == len(set(ids)) and "channel-obfuscation-http" in ids, "Missing or duplicate required transition")
    for transition in transitions:
        announced, effective = iso_date(transition["announcedOn"]), iso_date(transition["effectiveOn"])
        require(announced <= reviewed and announced <= effective, "Invalid announcement/effective ordering")
        require(transition.get("status") == ("future_effective" if as_of < effective else "effective"), "Future transition has incorrect current status")
        require(transition.get("currentBehavior") and transition.get("futureBehavior"), "Missing behavior migration boundary")
        require(transition.get("sourceURLs") and all(official_url(url) for url in transition["sourceURLs"]), "Missing official transition source")
        path = evidence_file(repository, {"path": transition["fixturePath"], "sha256": transition["fixtureSHA256"]})
        fixture = read_json(path)
        require(fixture.get("schemaVersion") == 1 and fixture.get("transitionID") == transition["id"] and fixture.get("effectiveOn") == str(effective), "Fixture transition mismatch")
        cases = fixture.get("cases", [])
        case_ids = [case["id"] for case in cases]
        require(cases and len(case_ids) == len(set(case_ids)), "Missing or duplicate transition case")
        days = set()
        for case in cases:
            day = iso_date(case["date"])
            days.add(day)
            require(case.get("expectedPhase") == ("current" if day < effective else "effective"), "Transition fixture activates future behavior early")
        require({effective - dt.timedelta(days=1), effective}.issubset(days), "Missing before/on effective-date fixture")
        if transition["id"] == "channel-obfuscation-http":
            require(str(effective) == "2026-11-16", "Unexpected channel-obfuscation effective date")
    return {"reviewedOn": str(reviewed), "nextReviewDue": str(due), "sources": len(sources), "transitions": len(transitions), "asOf": str(as_of)}


def main():
    """Run one local nonwriting audit; invalid JSON/evidence or failed checks exit nonzero."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["graph", "report", "maintenance"])
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--policy", default="Tools/DiscordKitTools/release-policy.json")
    parser.add_argument("--report", default="Docs/Release/publication-report.json")
    parser.add_argument("--record", default="Docs/Release/maintenance.json")
    parser.add_argument("--as-of", type=iso_date, default=dt.date.today())
    args = parser.parse_args()
    repository = args.repository.resolve()
    policy = read_json(local_file(repository, args.policy))
    try:
        if args.command == "graph":
            result = validate_graph(repository, dump_manifest(repository), policy, read_json(repository / "Package.resolved"))
            result["consumers"] = {relative: validate_consumer(repository, relative, dump_manifest(repository / relative), policy) for relative in sorted(policy.get("consumers", {}))}
            if policy.get("authoringPackages"):
                result["authoringPackages"] = {relative: validate_authoring_package(
                    repository, relative, dump_manifest(repository / relative), policy,
                    read_json(local_file(repository, relative + "/Package.resolved")))
                    for relative in sorted(policy["authoringPackages"])}
        elif args.command == "report":
            result = validate_report(repository, read_json(local_file(repository, args.report)), policy)
        else:
            result = validate_maintenance(repository, read_json(local_file(repository, args.record)), args.as_of, policy)
        print(json.dumps(result, sort_keys=True))
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release audit failed: {error}\n")


if __name__ == "__main__":
    main()
