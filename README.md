# DiscordKit

DiscordKit is the foundation of a modular, Swift-native Discord application and
bot library. Parts 1–3 provide portable values, owned network adapters, a bounded
HTTP execution pipeline and a minimal sharded Gateway lifecycle. The typed REST
slice retrieves the current user/application and Gateway discovery, and adds
[message and poll operations](Docs/RESTCatalog.md) in Phase 5A and
[channels and threads](Docs/Channels.md) in Phase 5B. Interactions,
OAuth2 flows, voice, RPC, Activities, Social and commerce are not implemented.

Part 4 adds reviewed inventory contracts and deterministic offline generation for
the existing model/endpoint slice. Consumer builds compile committed output; see
[reviewed generation and parity checks](Docs/Generation.md).

The architecture baseline records platform capabilities, dependency policy, a
versioned parity inventory and explicit feasibility blockers. Portable values are
usable today; HTTP/WebSocket/UDP/ingress/Unix adapters are available with explicit
limits and macOS-local qualification. REST and Gateway are independently adoptable;
the full resource/event catalog and consumer facade follow later. A planned
target or an unavailable-capability stub never counts as implemented support.

## Build and test

Use Swift 6.4 or newer. The package preserves `ApproachableConcurrency` and uses
an explicit nonisolated default for library and test declarations. See the
[concurrency policy](Docs/Concurrency.md) for the distinction between default
isolation and the executor on which an async operation runs.

Run from the repository root:

```sh
swift build
swift test
```

The package tests exercise precision, field presence, timestamps, secret redaction,
stream ownership, cancellation and virtual time. Passing these tests does not
establish endpoint parity or qualify untested hosts. See the
[foundation contracts](Docs/Foundation.md) for limits and examples.

## Available foundations

- `DiscordBits`: arbitrary-width unsigned bitsets with decimal-string encoding.
- `DiscordCore`: tagged snowflakes, bounded lossless JSON, absent/null/value fields,
  timestamps, open raw values, redacted credentials, errors and capability reporting.
- `DiscordTransport`: injectable HTTP, WebSocket, datagram, IPC and HTTP-ingress
  protocols, bounded pull bodies and monotonic deadline contexts.
- `DiscordKit`: common foundational type aliases for convenient adoption.
- `DiscordFoundationTransport`: Apple Foundation HTTP and WebSocket adapters.
- `DiscordNIOTransport`: owned bounded HTTP, WebSocket, UDP and ingress adapters.
- `DiscordUnixPlatform`: bounded Unix-domain IPC byte streams.
- `DiscordApplePlatform`: app-driven lifecycle resource ownership and capability checks.
- `DiscordModels`: presence-aware Message/Poll payloads, components, partial related-resource
  projections and exact unknown fields.
- `DiscordHTTP`: typed descriptors, codecs, coordinated admission, safe retries, pagination,
  scoped coalescing, opt-in bounded response caching and the message/poll REST catalog.
- `DiscordGateway`: discovery, supervised shards, heartbeat/reconnect/resume, leases and startup budgets.

See [HTTP execution](Docs/HTTP.md), the [REST-only example](Examples/RESTOnly/README.md),
[minimal Gateway lifecycle](Docs/Gateway.md), and
[transport ownership, budgets and qualification limits](Docs/Transport.md).
The independent [local load harness](Tools/DiscordKitLoadTests/README.md) records
bounded cohort measurements; broad platform and Phase 2 qualification gates remain open.

Concrete NIO/Unix adapters use approved Apple NIO/TLS dependencies; portable and
Foundation products do not link those packages. Development-only deterministic
clocks, barriers, scripts and resource tracking are excluded from library products.
Apple deployment baselines are macOS 13, iOS/tvOS 16, watchOS 9 and visionOS 1;
other-platform runtime qualification remains recorded separately.

## Planned consumer experience

- REST services work without a Gateway connection or voice dependencies.
- Bot clients supervise heartbeats, reconnect/resume, rate limits and socket
  ownership through an async run operation.
- HTTP interactions work without loading Gateway or voice.
- Commands and routers provide conveniences over complete typed requests.
- Optional voice APIs own the media protocol and expose join, frames and leave.
- Platform and access restrictions produce explicit capability information.

The HTTP execution and minimal raw Gateway lifecycle are implemented. The remaining
consumer workflows describe future work. Feature products are introduced
with implementations and tests as their roadmap phases are completed.

Scalability is an early design requirement: deployments serving hundreds through
millions of accounts need coordinated rate admission, bounded caches, equivalent
read coalescing, documented bulk operations and sharding in the first Gateway
slice. Per-identity and aggregate budgets, load profiles and measured release
gates are defined in the [scalability requirements](Docs/Scalability.md). These
include implemented admission, caching and sharding policies; the workload sizes
do not establish deployment capacity.

## Scope and constraints

The roadmap includes backend APIs, Gateway, voice/media, OAuth2, local RPC,
certified devices, Activities, Social capabilities and commerce. It targets all
Swift platforms with capability-specific qualification. A compiler target does
not prove sockets, background execution, audio capture or a Discord host exists
on that platform.

Only approved Apple-origin or official Swift-project package families and their
normal maintained transitive/bundled implementations are permitted. Discord's
distributed native runtime is outside that policy. Missing public wire contracts
remain blockers even when Discord publishes an SDK method signature.

Discord applications are registered in the Developer Portal. DiscordKit will use
documented application and authentication APIs; application creation and bot-token
provisioning are not invented SDK endpoints. See Discord's
[getting started guide](https://docs.discord.com/developers/quick-start/getting-started).

## Project records

- [Architecture and API conventions](Docs/Architecture.md)
- [Portable foundation contracts](Docs/Foundation.md)
- [Owned transport adapters](Docs/Transport.md)
- [HTTP execution and request reuse](Docs/HTTP.md)
- [Minimal sharded Gateway lifecycle](Docs/Gateway.md)
- [Concurrency and ownership](Docs/Concurrency.md)
- [Scalability and request efficiency](Docs/Scalability.md)
- [Dependency policy and candidate releases](Docs/Dependencies.md)
- [Platform support and feasibility](Docs/PlatformSupport.md)
- [Parity inventory and evidence](Docs/Parity/README.md)
- [Reviewed definitions and offline generation](Docs/Generation.md)
- [Contribution requirements](CONTRIBUTING.md)
- [Change history](CHANGELOG.md)

Protocol evidence is dated and versioned separately from library releases.
Current support claims must come from validated inventory records and linked
tests, rather than the size of the roadmap.
