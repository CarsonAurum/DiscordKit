#!/usr/bin/env python3
"""Record bounded offline Gateway lifecycle/control evidence; never contact Discord."""
import argparse
import json
from pathlib import Path

from record_baseline import PACKAGE, capture, environment


def validate_gateway(report, burst):
    """Reject lost work, multiplied startup allowance, missing Resume and retained ownership."""
    shards = report["selectedShards"]
    if (report["deliveredDispatches"] != report["targetDispatches"]
            or report["identifies"] != shards or report["resumes"] != shards * 2
            or report["reconnects"] != shards * 2
            or report["completedMemberRequests"] != shards * 3
            or report["completedSoundboardRequests"] != shards * 3
            or report["completedChannelInfoRequests"] != shards * 3
            or report["typedResponseEvents"] != shards * 12
            or report["applicationCommandWrites"] != shards * 15
            or report["startupStormAdmitted"] != shards
            or report["startupStormOffered"] != shards * (10 if burst else 2)
            or report["peakOwnedConnections"] > shards
            or report["ownedConnectionsAfterShutdown"] or report["leasesAfterShutdown"]
            or report["pendingRequestsAfterShutdown"] or report["applicationWritesAfterShutdown"]
            or report["configuredMaximumPendingRequests"] != shards * 4
            or report["configuredMaximumResponseEventsPerRequest"] != 8
            or report["configuredMaximumResponseBytes"] != shards * 65_536
            or report["configuredMaximumRequestKeys"] != shards * 32
            or report["sampledPeakQueuedEvents"] > 32
            or report["configuredMaximumQueuedEvents"] != shards * 32
            or report["configuredMaximumQueuedBytes"] != shards * 65_536
            or report["heartbeats"] <= 0 or report["heartbeatACKs"] <= 0
            or report["controlDelay"]["sampleCount"] <= 0
            or report["controlDelay"]["sampleCount"] > shards * 3
            or report["eventLag"]["sampleCount"] != min(4_096, report["targetDispatches"])):
        raise RuntimeError("Gateway script violated bounded work, control, startup or cleanup invariants")


def main():
    """Run every logical population serially and preserve exact release process measurements."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, default=PACKAGE / ".build/release/DiscordKitLoadTests")
    parser.add_argument("--output-dir", type=Path, default=PACKAGE / "Baselines")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    context = environment()
    context["peer"] = "offline credit-limited Gateway JSON script; zero sockets and no real credentials"
    context["measurementScope"] = ("bounded 1/4/16 local Gateway sessions, 1/2/4 synthetic bot identities; "
        "startup storm, two Resumes per shard, typed request rounds, yielding event drains, requested heartbeat delay, CPU/RSS; "
        "no network, real Discord quota, fleet, soak or capacity qualification")
    for accounts in (100, 10000, 1000000):
        for burst in (False, True):
            profile = f"accounts-{accounts}"
            command = [str(args.executable), "--profile", profile, "--scenario", "gateway"]
            if burst:
                command.append("--burst")
            report = json.loads(capture(command))
            validate_gateway(report, burst)
            suffix = "burst" if burst else "normal"
            destination = args.output_dir / f"gateway-{profile}-{suffix}.json"
            destination.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
            print(f"Gateway {profile} {suffix}: {report['deliveredDispatches']} dispatches, "
                  f"{report['selectedShards']} sessions, {report['resumes']} resumes, "
                  f"control p99 {report['controlDelay']['p99Milliseconds']:.3f} ms", flush=True)
    (args.output_dir / "gateway-environment.json").write_text(json.dumps(context, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
