#!/usr/bin/env python3
# File: Tools/DiscordKitLoadTests/scripts/record_baseline.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

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


def environment(scenario="transport"):
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
    if scenario == "http":
        values["peer"] = "offline finite HTTP policy script; zero credentials and sockets; artificial 1 ms exchange latency"
        values["measurementScope"] = "HTTP policy owners in one process; sampled queue/cache/metadata caps, request savings and CPU/RSS; no Discord quota or fleet/soak qualification"
    return values


def validate_http(report, burst):
    """Enforce local HTTP policy gates without converting the results into Discord capacity claims."""
    if (report["failedRequests"] or report["cancelledRequests"] or report["activeAfterShutdown"]
            or report["queuedAfterShutdown"] or report["flightsAfterShutdown"] or report["cacheEntriesAfterShutdown"]
            or not report["sampledResourceBudgetsMet"] or not report["rssBudgetMet"]):
        raise RuntimeError("HTTP policy workload exceeded resource, failure or cleanup gates")
    if report["avoidedExchanges"] <= 0 or report["retryResponses"] <= 0 or report["minimumIdentitySuccesses"] <= 0:
        raise RuntimeError("HTTP policy workload did not exercise reuse, retries or every identity")
    if not burst and (report["refusedRequests"] or not report["targetP99Met"]):
        raise RuntimeError("HTTP normal-workload targets were not met")


def main():
    """Run every applicable profile serially and write reviewable JSON evidence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, default=PACKAGE / ".build/release/DiscordKitLoadTests")
    parser.add_argument("--output-dir", type=Path, default=PACKAGE / "Baselines")
    parser.add_argument("--scenario", choices=("transport", "http"), default="transport")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    context = environment(args.scenario)
    for accounts in (100, 10000, 1000000):
        for burst in (False, True):
            profile = f"accounts-{accounts}"
            command = [str(args.executable), "--profile", profile, "--scenario", args.scenario]
            if args.scenario == "transport":
                command.extend(["--settle-seconds", "1"])
            if burst:
                command.append("--burst")
            report = json.loads(capture(command))
            suffix = "burst" if burst else "normal"
            if args.scenario == "http":
                validate_http(report, burst)
                destination = args.output_dir / f"http-{profile}-{suffix}.json"
                destination.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
                print(f"HTTP {profile} {suffix}: {report['successfulRequests']} successes, "
                      f"{report['refusedRequests']} refusals, {report['avoidedExchanges']} avoided exchanges", flush=True)
                continue
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
            destination = args.output_dir / f"{profile}-{suffix}.json"
            destination.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
            print(f"{profile} {suffix}: {measurement['admittedSuccesses']} successes, "
                  f"{measurement['capacityRefusals']} refusals, "
                  f"{measurement['successesPerSecond']:.1f} successful exchanges/s", flush=True)
    environment_name = "http-environment.json" if args.scenario == "http" else "environment.json"
    (args.output_dir / environment_name).write_text(json.dumps(context, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
