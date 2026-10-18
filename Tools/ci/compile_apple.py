#!/usr/bin/env python3
"""Compile five owned foundation/Apple modules at device and simulator minima.

Uses installed Xcode SDKs without signing, running devices, linking NIO or
claiming a complete package cross-build. Missing SDKs fail instead of passing.
"""

import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

MODULES = ["DiscordBits", "DiscordCore", "DiscordTransport", "DiscordMedia", "DiscordApplePlatform"]
DESTINATIONS = {
    "macosx": "arm64-apple-macos13.0",
    "iphoneos": "arm64-apple-ios16.0",
    "iphonesimulator": "arm64-apple-ios16.0-simulator",
    "appletvos": "arm64-apple-tvos16.0",
    "appletvsimulator": "arm64-apple-tvos16.0-simulator",
    "watchos": "arm64_32-apple-watchos9.0",
    "watchsimulator": "arm64-apple-watchos9.0-simulator",
    "xros": "arm64-apple-xros1.0",
    "xrsimulator": "arm64-apple-xros1.0-simulator",
}


def compiler_command(module, sources, target, sdk, output, cache):
    """Build an exact argument array preserving package concurrency and isolation."""
    return ["xcrun", "swiftc", "-target", target, "-sdk", sdk,
            "-swift-version", "6", "-enable-upcoming-feature", "ApproachableConcurrency",
            "-default-isolation", "nonisolated", "-module-cache-path", str(cache),
            "-I", str(output), "-parse-as-library", "-emit-module", "-module-name", module,
            "-emit-module-path", str(output / f"{module}.swiftmodule"), *map(str, sources)]


def main():
    """Emit every requested module in dependency order and retain exact source hashes."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--sdk", choices=DESTINATIONS, action="append")
    parser.add_argument("--output", type=Path, default=Path(".build/apple-compile.json"))
    arguments = parser.parse_args()
    repository = arguments.repository.resolve()
    report = {"scope": "Selected-module device/simulator compile only; no runtime or full-package qualification",
              "modules": MODULES, "platforms": [], "sourceSHA256": {}}
    report["swiftVersion"] = subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="discordkit-apple-compile-") as scratch:
        for name in arguments.sdk or DESTINATIONS:
            sdk = subprocess.check_output(["xcrun", "--sdk", name, "--show-sdk-path"], text=True).strip()
            output = Path(scratch) / name
            output.mkdir()
            for module in MODULES:
                sources = sorted((repository / "Sources" / module).rglob("*.swift"))
                if not sources:
                    raise ValueError(f"Empty source module: {module}")
                for source in sources:
                    report["sourceSHA256"][str(source.relative_to(repository))] = hashlib.sha256(source.read_bytes()).hexdigest()
                subprocess.run(compiler_command(module, sources, DESTINATIONS[name], sdk,
                                                output, Path(scratch) / "cache"), check=True)
            report["platforms"].append({"sdk": name, "target": DESTINATIONS[name], "modules": len(MODULES)})
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Compiled {len(MODULES) * len(report['platforms'])} selected Apple module emissions")


if __name__ == "__main__":
    main()
