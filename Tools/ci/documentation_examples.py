#!/usr/bin/env python3
"""Keep DocC tutorial listings synchronized with independently buildable examples.

Development milestone labels are omitted from documentation comments in the
displayed listings. Executable code is byte-for-byte preserved. Run without --write to
reject missing or stale snapshots; no compiler, credentials or network is used.
Build/test the originating example packages separately to validate their code.
"""

import argparse
import re
from pathlib import Path


EXAMPLES = (
    "CommandsApp", "RESTOnly", "GatewayBot", "HTTPApp", "OAuthApp",
    "RPCApp", "ActivityHost", "SocialApp", "VoiceBot",
)
SUPPORT = (
    ("ActivityHost", "ActivityHostSupport/ActivityHostSession.swift"),
    ("ActivityHost", "ActivityBackend/ActivityBackend.swift"),
    ("VoiceBot", "VoiceBot/MLSExample.swift"),
    ("VoiceBot", "VoiceBot/DAVEExample.swift"),
)


def displayed_source(source):
    """Keep documented code while omitting historical labels from doc comments.

    Parameters:
        source: UTF-8 Swift source text, including its original final newline.
    Returns:
        Text for a contextual tutorial listing, never a rewritten implementation.
    """
    return "".join(re.sub(r"\b(?:Phase|Part) [0-9]+[A-Z]?[ \t]?", "", line)
                   if line.lstrip().startswith("///") else line
                   for line in source.splitlines(keepends=True))


def snapshots(repository):
    """Map unique tutorial resource names to expected whole-source listings.

    Missing source files raise OSError so a removed or renamed example cannot
    silently disappear from the tutorial set. No resource files are written.
    """
    sources = {}
    for example in EXAMPLES:
        base = repository / "Examples" / example
        sources[f"{example}-Package.swift.txt"] = (base / "Package.swift").read_text()
        source = base / "Sources" / example / f"{example}.swift"
        sources[f"{example}.swift.txt"] = displayed_source(source.read_text())
    for example, source in SUPPORT:
        path = repository / "Examples" / example / "Sources" / source
        sources[path.name + ".txt"] = displayed_source(path.read_text())
    return sources


def synchronize(repository, write=False):
    """Write requested snapshots or report every missing/stale listing.

    Parameters:
        repository: Repository root containing the independently owned examples.
        write: False checks without mutation; True updates expected resources and
            removes obsolete .swift.txt snapshots from the dedicated generated folder.
    Returns:
        Sorted resource names that differed before this invocation.
    """
    resources = repository / "Sources/DiscordKit/DiscordKit.docc/Resources/Examples"
    expected_sources = snapshots(repository)
    changed = []
    for name, expected in sorted(expected_sources.items()):
        destination = resources / name
        if not destination.is_file() or destination.read_text() != expected:
            changed.append(name)
            if write:
                resources.mkdir(parents=True, exist_ok=True)
                destination.write_text(expected)
    # This dedicated directory contains generated listings. Never delete other
    # resource kinds; retired Swift listings must not silently remain usable.
    for stale in sorted(resources.glob("*.swift.txt")):
        if stale.name not in expected_sources:
            changed.append(stale.name)
            if write:
                stale.unlink()
    return sorted(changed)


def main():
    """Check by default; explicit --write refreshes the committed tutorial code."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--write", action="store_true")
    arguments = parser.parse_args()
    changed = synchronize(arguments.repository.resolve(), arguments.write)
    if changed and not arguments.write:
        parser.exit(1, "Stale DocC example resources: " + ", ".join(changed) + "\n")
    print(f"{'Updated' if arguments.write else 'Verified'} {len(snapshots(arguments.repository.resolve()))} DocC example listings")


if __name__ == "__main__":
    main()
