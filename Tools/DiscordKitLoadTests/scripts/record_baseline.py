#!/usr/bin/env python3
"""Record serial normal/10x-burst release runs; never contact a remote service."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import os
import signal
import subprocess


PACKAGE = Path(__file__).resolve().parents[1]


def capture(command):
    """Capture a trusted local command; stop its owned process group after five minutes."""
    process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    try:
        output, error = process.communicate(timeout=300)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate()
        raise RuntimeError("local measurement exceeded five-minute process-group budget") from None
    if process.returncode:
        raise subprocess.CalledProcessError(process.returncode, command, output=output, stderr=error)
    return output.strip()


def environment():
    """Record actual toolchain/hardware and the dirty working-tree revision basis."""
    values = {
        "recordedAtUTC": datetime.now(timezone.utc).isoformat(),
        "toolchain": capture(["swift", "--version"]),
        "architecture": platform.machine(),
        "kernel": platform.platform(),
        "sourceCommitBasis": capture(["git", "-C", str(PACKAGE), "rev-parse", "HEAD"]),
        "dirtySource": bool(capture(["git", "-C", str(PACKAGE), "status", "--porcelain"])),
        "buildConfiguration": "release",
        "peer": "Python standard-library ThreadingHTTPServer, IPv4 loopback, HTTP/1.1, fixed1024-byte payload",
        "measurementScope": "client process only; immediate and one-second settled heap/RSS, sampled pool slots, live malloc gauges; no fleet or soak qualification",
    }
    if platform.system() == "Darwin":
        values["hardwareModel"] = capture(["/usr/sbin/sysctl", "-n", "hw.model"])
        values["processor"] = capture(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"])
        values["physicalMemoryBytes"] = int(capture(["/usr/sbin/sysctl", "-n", "hw.memsize"]))
    return values


def main():
    """Run every applicable profile serially and write reviewable JSON evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, default=PACKAGE / ".build/release/DiscordKitLoadTests")
    parser.add_argument("--output-dir", type=Path, default=PACKAGE / "Baselines")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    context = environment()
    for accounts in (100, 10000, 1000000):
        for burst in (False, True):
            profile = f"accounts-{accounts}"
            command = [str(args.executable), "--profile", profile, "--scenario", "transport", "--settle-seconds", "1"]
            if burst:
                command.append("--burst")
            report = json.loads(capture(command))
            measurement = report["measurement"]
            if report["peerConnections"]["peakConnections"] > measurement["configuredMaximumConnections"]:
                raise RuntimeError(f"{profile}: physical peer socket cap exceeded")
            if (measurement["failedRequests"] or report["poolActiveAfterShutdown"] or report["poolIdleAfterShutdown"]
                    or measurement["sampledPeakPoolSlots"] > measurement["configuredMaximumConnections"]):
                raise RuntimeError(f"{profile}: failed requests or invalid pool ownership")
            if (not measurement["peakRSSBudgetMet"] or measurement.get("endHeapBudgetMet") is False
                    or report["settledAfterShutdown"]["peakRSSBytes"] > measurement["maximumPeakRSSBytes"]):
                raise RuntimeError(f"{profile}: exceeded measured memory budgets")
            if not burst and (measurement["capacityRefusals"] or not measurement["latencyTargetMet"]
                              or not measurement["throughputTargetMet"]):
                raise RuntimeError(f"{profile}: normal-workload targets were not met")
            suffix = "burst" if burst else "normal"
            destination = args.output_dir / f"{profile}-{suffix}.json"
            destination.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
            print(f"{profile} {suffix}: {measurement['admittedSuccesses']} successes, "
                  f"{measurement['capacityRefusals']} refusals, "
                  f"{measurement['successesPerSecond']:.1f} successful exchanges/s", flush=True)
    (args.output_dir / "environment.json").write_text(json.dumps(context, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
