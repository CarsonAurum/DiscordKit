#!/usr/bin/env python3
"""Cross-build and run only the offline CommandsApp on an explicitly selected Android.

Requires a matching open-source Swift toolchain/SDK, NDK r30 and adb-connected API28+
device/emulator. This does not qualify networking, audio, JNI or an Android app.
"""

import argparse
import json
import os
import re
import subprocess
from pathlib import Path

TRIPLE = "aarch64-unknown-linux-android28"
REMOTE = "/data/local/tmp/discordkit-phase14-commands"


def adb_command(serial, *arguments):
    """Build shell-free adb arguments with an explicit device selector for every operation."""
    if not serial.strip():
        raise ValueError("An explicit adb serial is required")
    return ["adb", "-s", serial, *arguments]


def validate_prerequisites(swift_version, sdk_identifier, ndk_properties, abi):
    """Require matching Swift6.4+ release/SDK, NDK30, and the compiled arm64 ABI."""
    version = re.search(r"Swift version (\d+\.\d+(?:\.\d+)?)", swift_version)
    sdk = re.fullmatch(r"swift-(\d+\.\d+\.\d+)-RELEASE_android", sdk_identifier)
    if version is None or sdk is None:
        raise ValueError("Expected matching open-source Swift release and Android SDK identifier")
    host_version = tuple(map(int, version[1].split(".")))
    host_version += (0,) * (3 - len(host_version))
    if host_version < (6, 4, 0) or host_version != tuple(map(int, sdk[1].split("."))):
        raise ValueError("Swift host and Android SDK must match exactly and require Swift6.4+")
    if not re.search(r"^Pkg\.Revision\s*=\s*30\.", ndk_properties, re.MULTILINE):
        raise ValueError("The Android SDK requires NDK r30")
    if abi.strip() != "arm64-v8a":
        raise ValueError("This job compiles arm64 and requires an arm64 Android host")


def main():
    """Require the selected API level, cross-build, run offline validation and retain scope."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-sdk", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--ndk", type=Path, default=os.environ.get("ANDROID_NDK_HOME"))
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, default=Path(".build/android-qualification.json"))
    arguments = parser.parse_args()
    if arguments.ndk is None:
        parser.error("--ndk or ANDROID_NDK_HOME must point to matching NDK r30")
    libraries = sorted(arguments.ndk.glob("toolchains/llvm/prebuilt/*/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"))
    if len(libraries) != 1:
        parser.error("Expected exactly one aarch64 NDK libc++_shared.so")
    level = int(subprocess.check_output(adb_command(arguments.serial, "shell", "getprop", "ro.build.version.sdk"), text=True).strip())
    if level < 28:
        parser.error("The explicitly selected Android host must be API28 or newer")
    abi = subprocess.check_output(adb_command(arguments.serial, "shell", "getprop", "ro.product.cpu.abi"), text=True)
    validate_prerequisites(subprocess.check_output(["swift", "--version"], text=True), arguments.swift_sdk,
                           (arguments.ndk / "source.properties").read_text(), abi)
    package = arguments.repository.resolve() / "Examples/CommandsApp"
    base = ["swift", "build", "--package-path", str(package), "--swift-sdk", arguments.swift_sdk,
            "--triple", TRIPLE, "--static-swift-stdlib"]
    subprocess.run(base, check=True)
    binary = Path(subprocess.check_output([*base, "--show-bin-path"], text=True).strip()) / "CommandsApp"
    subprocess.run(adb_command(arguments.serial, "shell", "mkdir", "-p", REMOTE), check=True)
    try:
        subprocess.run(adb_command(arguments.serial, "push", str(binary), f"{REMOTE}/CommandsApp"), check=True)
        subprocess.run(adb_command(arguments.serial, "push", str(libraries[0]), f"{REMOTE}/libc++_shared.so"), check=True)
        subprocess.run(adb_command(arguments.serial, "shell", "chmod", "700", f"{REMOTE}/CommandsApp"), check=True)
        subprocess.run(adb_command(arguments.serial, "shell", "env", f"LD_LIBRARY_PATH={REMOTE}", f"{REMOTE}/CommandsApp"), check=True)
    finally:
        subprocess.run(adb_command(arguments.serial, "shell", "rm", "-rf", REMOTE), check=True)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps({
        "swiftSDK": arguments.swift_sdk, "triple": TRIPLE, "apiLevel": level,
        "scope": "Offline CommandsApp command/component composition only; no network/device/JNI/app qualification",
        "crossBuild": "passed", "runtime": "passed",
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
