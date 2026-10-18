#!/usr/bin/env python3
"""Fetch read-only official docs/spec diffs for human weekly review, never apply them.

This scheduled evidence collector does not refresh inventory verification dates,
classify parity, regenerate source, create issues or contact Discord API accounts.
"""

import argparse
import datetime
import hashlib
import json
import re
import subprocess
import tempfile
import urllib.request
from pathlib import Path

REPOSITORIES = {
    "written_docs": ("discord-api-docs", "https://github.com/discord/discord-api-docs.git"),
    "preview_spec": ("discord-api-spec", "https://github.com/discord/discord-api-spec.git"),
}
CHANGE_LOG = "https://docs.discord.com/developers/change-log"


def pinned_revisions(sources):
    """Require one exact frozen revision per official repository, without guessing refs."""
    result = {}
    for authority in REPOSITORIES:
        revisions = {source["revision"] for source in sources if source["authority"] == authority}
        if len(revisions) != 1 or not re.fullmatch(r"[0-9a-f]{40}", next(iter(revisions), "")):
            raise ValueError(f"Expected one pinned Git revision for {authority}")
        result[authority] = revisions.pop()
    return result


def collect_diff(url, revision, output, label):
    """Fetch HEAD/base into a temporary repository and retain diff/stat artifacts only."""
    with tempfile.TemporaryDirectory(prefix="discordkit-upstream-") as temporary:
        directory = Path(temporary)
        subprocess.run(["git", "init", "--quiet", str(directory)], check=True)
        command = ["git", "-C", str(directory)]
        subprocess.run([*command, "remote", "add", "origin", url], check=True)
        subprocess.run([*command, "fetch", "--quiet", "--depth=1", "origin", "HEAD"], check=True, timeout=120)
        head = subprocess.check_output([*command, "rev-parse", "FETCH_HEAD"], text=True).strip()
        subprocess.run([*command, "fetch", "--quiet", "--depth=1", "origin", revision], check=True, timeout=120)
        for suffix, arguments in [("patch", ["--binary"]), ("stat", ["--stat"])]:
            with (output / f"{label}.{suffix}").open("wb") as artifact:
                subprocess.run([*command, "diff", *arguments, revision, head], stdout=artifact, check=True)
        return {"repository": url, "pinnedRevision": revision, "currentRevision": head,
                "changed": head != revision, "semanticReview": "required"}


def main():
    """Collect bounded changelog bytes and exact repository diffs without modifying source."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, default=Path(".build/upstream-review"))
    arguments = parser.parse_args()
    sources = json.loads((arguments.repository / "Docs/Parity/sources-2026-10-15.json").read_text())["sources"]
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {"collectedOn": datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
              "scope": "Read-only official source collection; human semantic review and inventory updates still required",
              "sourceChangesApplied": False, "repositories": []}
    for authority, revision in pinned_revisions(sources).items():
        label, url = REPOSITORIES[authority]
        report["repositories"].append(collect_diff(url, revision, output, label))
    request = urllib.request.Request(CHANGE_LOG, headers={"User-Agent": "DiscordKit-upstream-review/0.14"})
    with urllib.request.urlopen(request, timeout=60) as response:
        content = response.read(8 * 1024 * 1024 + 1)
    if len(content) > 8 * 1024 * 1024:
        raise ValueError("Official change log exceeds the 8 MiB collection budget")
    (output / "change-log.html").write_bytes(content)
    report["changeLog"] = {"url": CHANGE_LOG, "sha256": hashlib.sha256(content).hexdigest(), "bytes": len(content)}
    (output / "review.json").write_text(json.dumps(report, indent=2) + "\n")
    (output / "review.md").write_text(
        "# Upstream review collection\n\n" + report["scope"] + "\n\n" +
        "\n".join(f"- {item['repository']}: {item['pinnedRevision']} -> {item['currentRevision']}"
                  for item in report["repositories"]) +
        "\n\nReview the change log and patches; classify every affected inventory row, update tests/docs/history, "
        "and record human review before advancing maintenance dates. Production source was not changed.\n")
    print("Collected official source diffs and change log; human review required")


if __name__ == "__main__":
    main()
