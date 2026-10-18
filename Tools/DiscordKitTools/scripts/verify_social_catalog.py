#!/usr/bin/env python3
"""Validate Phase 13 Social mappings offline without expanding SDK support claims.

The historical method catalog remains the declaration-membership authority. This
audit checks every Social declaration and callback and all Commerce capabilities,
including overloads, against the release catalog. It verifies local symbol/test
evidence and named prerequisites, but never certifies live Discord, native SDK,
device, mobile, or entire-platform interoperability.
"""

import argparse
import collections
import json
from pathlib import Path


def require(condition, message):
    """Raise a sanitized catalog error when a deterministic invariant is false.

    Arguments are a boolean condition and a non-secret diagnostic string. A false
    condition raises ValueError; success returns None without I/O or mutation.
    """
    if not condition:
        raise ValueError(message)


def validate_evidence(equivalent, repository):
    """Check an owned equivalent's concrete local declarations and Swift tests.

    equivalent is a catalog evidence object; repository is a resolved local root.
    Paths must be root-relative, remain inside that root after symlink resolution,
    and point at existing files. Symbols must occur in the cited production source
    and tests must use Swift Testing. This is traceability rather than proof of
    branch coverage. Missing or unsafe evidence raises ValueError; no file is
    changed and no code, network request, or test process is executed.
    """
    require(equivalent.get("scope") and equivalent.get("limitations"), "Missing equivalent boundary")
    require(equivalent.get("implementations") and equivalent.get("tests"), "Missing equivalent evidence")
    for implementation in equivalent["implementations"]:
        path = (repository / implementation["path"]).resolve()
        require(path.is_relative_to(repository) and path.is_file(), "Missing or unsafe implementation path")
        require(implementation.get("symbol") in path.read_text(), "Missing implementation symbol")
    for reference in equivalent["tests"]:
        path = (repository / reference).resolve()
        require(path.is_relative_to(repository) and path.is_file(), "Missing or unsafe test path")
        text = path.read_text()
        require("import Testing" in text and "@Test" in text, "Equivalent requires Swift Testing evidence")


def validate_catalog(catalog, baseline, repository):
    """Validate exhaustive membership, bounded claims, and local evidence links.

    catalog and baseline are decoded JSON objects; repository is a Path to the
    checkout. Every original Social method, Social callback alias and Commerce
    capability must occur exactly once, retaining its stable ID, symbol and source
    URL. Added mobile records have their own namespace. Every incomplete row names
    a blocker with required evidence, while partial equivalents cite real owned
    declarations/tests and explicitly disclaim full SDK parity. C++ ownership and
    native SDK formatting/version helpers may be classified language_specific.
    The return value counts rows, blockers and statuses. Malformed or unsupported
    claims raise ValueError; all reads are local and deterministic.
    """
    repository = repository.resolve()
    require(catalog.get("schemaVersion") == 1, "Unsupported Social catalog schema")
    require(catalog.get("entirePlatformParity") is False, "Entire-platform parity is not established")
    require(catalog.get("qualification") == "offline_local_only", "Unexpected qualification claim")
    original = {
        item["id"]: item for item in baseline["methods"]
        if item["surface"] in {"Social", "Commerce"}
    }
    original.update({
        item["id"]: item for item in baseline["definitions"]
        if item["surface"] == "Social" and item["kind"] == "callback_type"
    })
    entries = catalog.get("entries", [])
    ids = [item["id"] for item in entries]
    require(len(ids) == len(set(ids)), "Duplicate Social catalog ID")
    require(set(original).issubset(ids), "Missing original method or callback")
    require(all(key in original or key.startswith("mobile.") for key in ids), "Unknown non-mobile declaration")
    blockers = catalog.get("blockers", [])
    blocker_ids = [item["id"] for item in blockers]
    require(len(blocker_ids) == len(set(blocker_ids)), "Duplicate blocker ID")
    blockers_by_id = {item["id"]: item for item in blockers}
    allowed_blocker_kinds = {
        "upstream_contract", "platform_qualification", "access_approval",
        "owned_projection", "native_runtime", "upstream_ambiguity",
    }
    for blocker in blockers:
        require(blocker.get("kind") in allowed_blocker_kinds, "Unknown blocker kind")
        require(blocker.get("requiredEvidence") and blocker.get("reason"), "Incomplete named blocker")
    for entry in entries:
        require(entry.get("status") in {"partial", "blocked", "language_specific"}, "Unsupported SDK parity claim")
        require(entry.get("sdkParity") is False, "A local equivalent cannot establish SDK parity")
        require(entry.get("prerequisites") and entry.get("authorizationBoundary"), "Missing prerequisite or authorization boundary")
        require(entry.get("platforms") and entry.get("limitation"), "Missing platform or semantic boundary")
        if entry["id"] in original:
            old = original[entry["id"]]
            require(entry.get("symbol") == old["symbol"], "Changed historical declaration symbol")
            require(entry.get("definitionURL") == old["definitionURL"], "Changed declaration source")
            require(entry.get("signatureSHA256") == old["signatureSHA256"], "Changed declaration identity")
        else:
            require(entry.get("kind") == "mobile_capability", "Invalid added mobile row")
            require(set(entry["platforms"]) >= {"iOS", "android"}, "Mobile platform distinction is missing")
        if entry["status"] == "partial":
            validate_evidence(entry.get("ownedEquivalent", {}), repository)
        if entry["status"] != "language_specific":
            require(entry.get("blockerIDs"), "Incomplete SDK row needs a named prerequisite")
        require(all(key in blockers_by_id for key in entry.get("blockerIDs", [])), "Unknown blocker reference")
    used = {key for entry in entries for key in entry.get("blockerIDs", [])}
    require(used == set(blockers_by_id), "Unreferenced blocker")
    return {
        "entries": len(entries), "baselineDeclarations": len(original),
        "blockers": len(blockers), "statuses": dict(sorted(collections.Counter(
            entry["status"] for entry in entries
        ).items())),
    }


def load_and_validate(repository):
    """Read the release and historical catalogs from one local checkout and audit.

    repository is a Path; file/JSON errors and validation ValueError propagate to
    the caller. Returns validate_catalog's deterministic count object. Reading
    does not regenerate data, fetch sources, or alter historical discovery records.
    """
    return validate_catalog(
        json.loads((repository / "Docs/Parity/phase13-social-catalog.json").read_text()),
        json.loads((repository / "Docs/Feasibility/method-contracts.json").read_text()),
        repository,
    )


def main():
    """Parse a repository root, print validated counts, and return normally on success.

    The optional --repository argument defaults to this script's checkout root.
    argparse exits for invalid arguments and file/validation errors propagate with
    a nonzero process status. This development command performs only local reads.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    print(json.dumps(load_and_validate(args.repository), sort_keys=True))


if __name__ == "__main__":
    main()
