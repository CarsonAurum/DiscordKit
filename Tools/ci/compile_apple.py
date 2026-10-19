#!/usr/bin/env python3
"""Compile selected logging/foundation/Apple modules at device and simulator minima.

Uses installed Xcode SDKs without signing, running devices, linking NIO or
claiming a complete package cross-build. Missing SDKs fail instead of passing.
"""

import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

MODULES = ["Logging", "DiscordLogging", "DiscordLogHandlers", "DiscordBits", "DiscordCore",
           "DiscordTransport", "DiscordMedia", "DiscordApplePlatform"]
LOGGING_FEATURES = ["ExistentialAny", "MemberImportVisibility", "InternalImportsByDefault",
                    "NonisolatedNonsendingByDefault"]
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
    settings = ["-enable-upcoming-feature", "ApproachableConcurrency"]
    if module == "Logging":
        # Match the resolved SwiftLog 1.16.1 target rather than the root's settings.
        settings = [argument for feature in LOGGING_FEATURES for argument in ["-enable-upcoming-feature", feature]]
        settings += ["-Xfrontend", "-require-explicit-sendable"]
    package = "swift_log" if module == "Logging" else "discordkit"
    return ["xcrun", "swiftc", "-target", target, "-sdk", sdk, "-swift-version", "6", *settings,
            "-package-name", package,
            "-default-isolation", "nonisolated", "-module-cache-path", str(cache),
            "-I", str(output), "-parse-as-library", "-emit-module", "-module-name", module,
            "-emit-module-path", str(output / f"{module}.swiftmodule"), *map(str, sources)]


def resolution_command(repository, scratch, cache=None, disable_sandbox=False):
    """Resolve the root graph with explicit SwiftPM paths and inherited environment."""
    command = ["swift", "package", "--package-path", str(repository), "--scratch-path", str(scratch)]
    if cache is not None:
        command += ["--cache-path", str(cache)]
    if disable_sandbox:
        command.append("--disable-sandbox")
    return [*command, "resolve"]


def resolved_logging(repository, scratch):
    """Require the SwiftLog checkout and source to match the root's resolved revision."""
    pins = json.loads((repository / "Package.resolved").read_text())["pins"]
    pins = [pin for pin in pins if pin["identity"] == "swift-log"]
    if len(pins) != 1 or pins[0].get("kind") != "remoteSourceControl":
        raise ValueError("Expected one resolved SwiftLog source-control pin")
    pin = pins[0]
    state = json.loads((scratch / "workspace-state.json").read_text())["object"]["dependencies"]
    dependencies = [dependency for dependency in state if dependency["packageRef"]["identity"] == "swift-log"]
    if len(dependencies) != 1:
        raise ValueError("Expected one resolved SwiftLog checkout")
    dependency = dependencies[0]
    if dependency["state"].get("name") != "sourceControlCheckout" or \
            dependency["state"].get("checkoutState") != pin["state"] or \
            dependency["packageRef"]["location"] != pin["location"]:
        raise ValueError("SwiftLog checkout does not match Package.resolved")
    checkouts = (scratch / "checkouts").resolve()
    checkout = (checkouts / dependency["subpath"]).resolve()
    if not checkout.is_relative_to(checkouts) or not (checkout / "Sources/Logging").is_dir():
        raise ValueError("Missing resolved SwiftLog Logging source")
    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if revision != pin["state"].get("revision"):
        raise ValueError("SwiftLog checkout HEAD does not match Package.resolved")
    return checkout, pin


def main():
    """Emit every requested module in dependency order and retain exact source hashes."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--sdk", choices=DESTINATIONS, action="append")
    parser.add_argument("--output", type=Path, default=Path(".build/apple-compile.json"))
    parser.add_argument("--scratch-path", type=Path, help="SwiftPM build/checkouts directory; defaults to repository/.build")
    parser.add_argument("--cache-path", type=Path, help="Optional SwiftPM dependency cache directory")
    parser.add_argument("--disable-sandbox", action="store_true", help="Disable SwiftPM manifest sandboxing on managed hosts")
    parser.add_argument("--skip-resolve", action="store_true", help="Use an existing verified checkout without network resolution")
    arguments = parser.parse_args()
    repository = arguments.repository.resolve()
    swiftpm_scratch = arguments.scratch_path.resolve() if arguments.scratch_path else repository / ".build"
    if not arguments.skip_resolve:
        subprocess.run(resolution_command(repository, swiftpm_scratch, arguments.cache_path,
                                          arguments.disable_sandbox), check=True)
    logging_checkout, pin = resolved_logging(repository, swiftpm_scratch)
    report = {"scope": "Selected-module device/simulator compile only; no runtime or full-package qualification",
              "modules": MODULES, "platforms": [], "sourceSHA256": {}, "dependencySourceSHA256": {},
              "loggingDependency": pin}
    report["swiftVersion"] = subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="discordkit-apple-compile-") as scratch:
        for name in arguments.sdk or DESTINATIONS:
            sdk = subprocess.check_output(["xcrun", "--sdk", name, "--show-sdk-path"], text=True).strip()
            output = Path(scratch) / name
            output.mkdir()
            for module in MODULES:
                source_root = logging_checkout if module == "Logging" else repository
                sources = sorted((source_root / "Sources" / module).rglob("*.swift"))
                if not sources:
                    raise ValueError(f"Empty source module: {module}")
                for source in sources:
                    hashes = report["dependencySourceSHA256"] if module == "Logging" else report["sourceSHA256"]
                    hashes[str(source.relative_to(source_root))] = hashlib.sha256(source.read_bytes()).hexdigest()
                subprocess.run(compiler_command(module, sources, DESTINATIONS[name], sdk,
                                                output, Path(scratch) / "cache"), check=True)
            report["platforms"].append({"sdk": name, "target": DESTINATIONS[name], "modules": len(MODULES)})
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Compiled {len(MODULES) * len(report['platforms'])} selected Apple module emissions")


if __name__ == "__main__":
    main()
