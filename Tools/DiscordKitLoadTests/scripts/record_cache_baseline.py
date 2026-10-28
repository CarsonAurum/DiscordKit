#!/usr/bin/env python3
# File: Tools/DiscordKitLoadTests/scripts/record_cache_baseline.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Record finite local cache/broadcast recovery evidence without credentials or sockets."""
import argparse
import hashlib
import json
import math
from pathlib import Path

from record_baseline import PACKAGE, capture, environment


def validate_cache(report, burst):
    """Reject missing recovery, changed request reduction, exceeded budgets or retained ownership."""
    rounds = report["completedRounds"]
    scopes = report["selectedScopes"]
    units = rounds * scopes
    samples = report.get("checkpoints", [])
    duration = report.get("configuredDurationSeconds")
    if (rounds <= 0 or scopes not in (1, 2, 4) or not 1 <= report["configuredRounds"] <= 1_000_000
            or rounds < report["configuredRounds"]
            or (report.get("configuredDurationSeconds") is None and rounds != report["configuredRounds"])
            or (duration is not None and (not 1 <= duration <= 3_600 or report["durationSeconds"] < duration))
            or report["workingSetKeysPerScope"] != 20
            or report["offeredRefreshCalls"] != (64 if burst else 16) * units
            or report["completedRefreshCalls"] != 8 * units or report["actualLoaderCalls"] != units
            or report["capacityRefusals"] != (56 if burst else 8) * units
            or report["coalescedReads"] != 7 * units or report["evictions"] != 4 * units
            or report["expirations"] != 16 * units or report["recoveryReads"] != units
            or report["healthyBroadcastDeliveries"] != 3 * rounds
            or report["slowSubscriberResynchronizations"] != rounds
            or report["maximumEntries"] != 16 * scopes or report["peakEntries"] != 16 * scopes
            or report["maximumAccountedBytes"] != 65_536 * scopes
            or not 0 < report["peakAccountedBytes"] <= report["maximumAccountedBytes"]
            or report["peakRefreshes"] != 1 or report["peakWaiters"] != 8
            or report["peakBufferedEvents"] != 2
            or not math.isfinite(report["durationSeconds"]) or report["durationSeconds"] <= 0
            or report["afterShutdown"]["peakRSSBytes"] <= 0
            or not 2 <= len(samples) <= 121
            or samples[0]["completedRounds"] != 0 or samples[0]["elapsedSeconds"] != 0
            or samples[-1]["completedRounds"] != rounds or samples[-1]["entries"] != 0
            or samples[-1]["accountedBytes"] != 0
            or samples[-1]["elapsedSeconds"] != report["durationSeconds"]
            or any(not 0 <= sample["entries"] <= report["maximumEntries"]
                   or not 0 <= sample["accountedBytes"] <= report["maximumAccountedBytes"]
                   or not 0 <= sample["completedRounds"] <= rounds
                   or not math.isfinite(sample["elapsedSeconds"]) or sample["elapsedSeconds"] < 0
                   or sample["process"]["peakRSSBytes"] <= 0 for sample in samples)
            or any(right["elapsedSeconds"] < left["elapsedSeconds"]
                   or right["completedRounds"] < left["completedRounds"] for left, right in zip(samples, samples[1:]))
            or any(report[field] for field in (
                "entriesAfterShutdown", "refreshesAfterShutdown", "waitersAfterShutdown",
                "subscriptionsAfterShutdown", "bufferedEventsAfterShutdown"))):
        raise RuntimeError("cache workload violated bounded recovery, reduction or cleanup invariants")


def main():
    """Record all three logical populations serially in cache/soak normal/burst modes."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, default=PACKAGE / ".build/release/DiscordKitLoadTests")
    parser.add_argument("--output-dir", type=Path, default=PACKAGE / "Baselines")
    parser.add_argument("--cache-rounds", type=int, default=8)
    parser.add_argument("--soak-rounds", type=int, default=512)
    args = parser.parse_args()
    if not all(1 <= count <= 1_000_000 for count in (args.cache_rounds, args.soak_rounds)):
        parser.error("round counts must be in 1...1000000")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    context = environment()
    context["peer"] = "offline fixed-key cache/broadcast scripts; no credentials or sockets"
    context["measurementScope"] = ("one shared cache; 1/2/4 scopes and 20 fixed keys per scope; "
        "exact finite refresh, eviction, TTL, invalidation and subscriber recovery rounds; "
        "separate accounted bytes and actual process RSS; no fleet or 30-minute qualification inferred")
    context["cacheRounds"] = args.cache_rounds
    context["soakRounds"] = args.soak_rounds
    context["executableSHA256"] = hashlib.sha256(args.executable.read_bytes()).hexdigest()
    measured_sources = ["Sources/DiscordCache/CacheValues.swift", "Sources/DiscordCache/EntityCache.swift",
                        "Sources/DiscordCache/EventReducer.swift", "Sources/DiscordGateway/EventHub.swift",
                        "Sources/DiscordGateway/EventHandlers.swift",
                        "Tools/DiscordKitLoadTests/Sources/DiscordKitLoadTests/CacheLoadRunner.swift"]
    context["sourceSHA256"] = {path: hashlib.sha256((PACKAGE.parents[1] / path).read_bytes()).hexdigest()
                               for path in measured_sources}
    for scenario, rounds in (("cache", args.cache_rounds), ("soak", args.soak_rounds)):
        for accounts in (100, 10_000, 1_000_000):
            for burst in (False, True):
                profile = f"accounts-{accounts}"
                command = [str(args.executable), "--scenario", scenario, "--profile", profile, "--rounds", str(rounds)]
                if burst:
                    command.append("--burst")
                report = json.loads(capture(command))
                validate_cache(report, burst)
                suffix = "burst" if burst else "normal"
                destination = args.output_dir / f"{scenario}-{profile}-{suffix}.json"
                destination.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
                print(f"{scenario} {profile} {suffix}: {rounds} rounds in {report['durationSeconds']:.3f}s, "
                      f"{report['actualLoaderCalls']} loaders for {report['completedRefreshCalls']} completed reads, "
                      f"{report['capacityRefusals']} refused", flush=True)
    (args.output_dir / "cache-environment.json").write_text(json.dumps(context, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
