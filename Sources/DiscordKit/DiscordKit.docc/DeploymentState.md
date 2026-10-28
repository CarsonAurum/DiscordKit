[//]: # "File: Sources/DiscordKit/DiscordKit.docc/DeploymentState.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Deploy with explicit lifecycle and freshness

Bound work and identify when local observations require resynchronization.

Create the application and choose install scopes/permissions in the
[Developer Portal](https://discord.com/developers/applications).
Obtain privileged intent or surface-specific approval before requesting restricted
data. The [setup guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Setup.md)
walks through each consumer and its authorities. Keep backend credentials out of
public mobile/browser artifacts and diagnostic labels.

Constructors start no tasks. A composition root owns run/connect/join, cancellation
and awaited close/stop/leave. Share credential/resource authorities across clients;
process-local bounds do not become a distributed budget. Control/heartbeat admission
must stay independent of handler and cache work. Slow HTTP handlers defer within
the initial response deadline and use explicit finite continuation ownership.

Caches contain partial observations. Respect authentication/guild/consent scope,
missing versus null fields, freshness limits and invalidation. Subscribe before
starting producers; bound count and bytes and respond to overflow/resync signals.
A gap requires a bounded refresh, rather than assuming cache completeness or
permission authority. Retain partial results and unknown mutation outcomes.

Cross-compilation does not qualify background execution, a physical device or a
live Discord host. The [platform matrix](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/PlatformSupport.md)
keeps these gates separate. Capacity claims carry workload, hardware, revision,
throughput, latency percentiles, CPU/RSS, request savings, saturation/recovery and
the fixed-working-set 30-minute soak evidence. Logical users are not socket counts.
