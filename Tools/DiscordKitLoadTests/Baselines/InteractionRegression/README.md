<!--
File: Tools/DiscordKitLoadTests/Baselines/InteractionRegression/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Interaction regression measurements

Recorded on macOS arm64 with Swift 6.4 on 2026-10-17, using the
source basis `aa4325a` and the exact source fingerprints in the environment records. These reports exercise the existing HTTP policy and
cache/broadcast harnesses. They do not measure signed ingress, command routing,
webhook durable admission, live Discord, remote storage, other hosts or fleet
capacity. Profile account counts represent logical served populations; actual
identity, concurrency and cache-scope counts are recorded separately in each report.

The six HTTP runs cover all three profiles in normal and tenfold burst mode.
Normal profiles completed without refusals and met their configured local p99
and memory gates. Burst refusals are deliberate bounded admission. Every run
exercised request reuse and explicit 429 retries, with zero active/queued requests,
flights and cache entries after shutdown. The largest normal profile completed
20,000 requests and avoided 11,980 exchanges. Artificial latency and synthetic
quota settings are recorded in the reports and are not Discord capacity figures.

The six finite cache and six finite soak runs cover the same three populations in
normal and burst mode. Each scope has twenty fixed keys, a sixteen-entry/65,536-byte
cap, one active refresh and eight admitted refresh callers. Every eight completed
coalesced reads use one loader. Overflow callers are refused, slow subscribers
resynchronize, and all owned cache/hub counters return to zero. Finite soak means
512 recovery rounds; it does not imply a minimum wall duration.

The separate `soak-accounts-1000000-1800s-burst.json` report records the required
thirty-minute fixed-working-set run with actual process RSS and separate accounted
cache-byte checkpoints. Its environment record supplies duration, checkpoint and
cleanup validation, source/executable/report hashes and memory observations.

Reproduction from the repository root, after building the release executable:

```sh
python3 Tools/DiscordKitLoadTests/scripts/record_baseline.py --scenario http --output-dir Tools/DiscordKitLoadTests/Baselines/InteractionRegression
python3 Tools/DiscordKitLoadTests/scripts/record_cache_baseline.py --output-dir Tools/DiscordKitLoadTests/Baselines/InteractionRegression
Tools/DiscordKitLoadTests/.build/release/DiscordKitLoadTests --scenario soak --profile accounts-1000000 --burst --duration-seconds 1800
```

Repository validation and the sustained run overlapped. Per-process memory remains
measured, while CPU/wall timing is local regression evidence rather than an
isolated service-level benchmark. No production capacity claim follows.
