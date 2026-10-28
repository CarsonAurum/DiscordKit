<!--
File: README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# DiscordKit

DiscordKit is a modular, Swift-native library for Discord applications and bots,
created by **Carson Rau** at [Aurum Studios](https://aurum-studios.com).
Copyright (c) 2026 Aurum Studios. See [AUTHORS](AUTHORS.md) and
[COPYRIGHT](COPYRIGHT). Original DiscordKit material is all rights reserved;
see [LICENSE](LICENSE) for terms and licensing inquiries.

Build a REST backend, a supervised Gateway bot, a signed HTTP command application,
an OAuth integration or an embedded Activity using independently adoptable products.
Typed identifiers, presence-aware models, bounded resources and injected transports
make asynchronous work explicit: constructing a client starts no connection,
background task or command registration. Your application owns startup,
cancellation and awaited shutdown.

The optional Swift authoring libraries provide result builders, typed commands,
message and component builders, policies, reusable modules and supervised bot
applications. The separate macro package reduces declaration boilerplate while
keeping compiler plugins out of runtime products.

## Getting started

Use **Swift 6.4 or newer**. Start with the [setup guide](Docs/Setup.md), choose an
[independent example](Sources/DiscordKit/DiscordKit.docc/ExampleCookbook.md), and
select only the products your application needs. See [modular authoring](Docs/DSLAdoption.md)
for commands and bots, or [migration](Docs/Migration.md) for existing integrations.

REST and Gateway use API **v10**. Optional protocol products support Voice **v8**,
RPC **v1**, MLS **1.0** with ciphersuite **2**, and DAVE **v1**. These protocol
versions are independent of the package version.

## Build and test

Run from the repository root:

```sh
swift build
swift test
```

The package uses `ApproachableConcurrency` and an explicit nonisolated default.
Tests use deterministic clocks, injected transports and local peers; ordinary
tests need no Discord credentials. See the [concurrency policy](Docs/Concurrency.md)
and [contribution guide](CONTRIBUTING.md) for ownership and validation requirements.

## Documentation

The DocC catalogs include product guides, tutorials, an example cookbook and public
API references. Start with the [documentation contents](Sources/DiscordKit/DiscordKit.docc/TableOfContents.md)
or [getting started](Sources/DiscordKit/DiscordKit.docc/GettingStarted.md).

Build the independent archives and merged library navigator locally:

```sh
swift package dump-symbol-graph --minimum-access-level public
python3 Tools/ci/curate_docc.py --check
python3 Tools/ci/documentation_examples.py
python3 Tools/ci/build_docc.py
```

Open `.build/documentation/DiscordKitLibrary.doccarchive` in Xcode. The
[documentation build guide](Sources/DiscordKit/DiscordKit.docc/BuildingDocumentation.md)
explains validation and hosting.

## Available products

- `DiscordLogging`: scoped SwiftLog diagnostics, component thresholds and operation context.
- `DiscordLogHandlers`: explicitly selected file, Apple unified-log and callback outputs.
- `DiscordBits`: arbitrary-width unsigned bitsets with decimal-string encoding.
- `DiscordCore`: tagged snowflakes, bounded lossless JSON, absent/null/value fields,
  timestamps, open raw values, redacted credentials, errors and capability reporting.
- `DiscordTransport`: injectable HTTP, WebSocket, datagram, IPC and HTTP-ingress
  protocols, bounded pull bodies and monotonic deadline contexts.
- `DiscordKit`: foundational aliases plus consumer client, interaction and command aliases.
- `DiscordFoundationTransport`: Apple Foundation HTTP and WebSocket adapters.
- `DiscordNIOTransport`: owned bounded HTTP, WebSocket, UDP and ingress adapters.
- `DiscordUnixPlatform`: bounded Unix-domain IPC byte streams.
- `DiscordApplePlatform`: app-driven lifecycle/capability checks and explicit bounded
  native Apple audio capture/playback ownership.
- `DiscordModels`: presence-aware resource and request values for the implemented catalogs,
  typed components and premium interaction data, partial related-resource projections and exact unknown fields.
- `DiscordHTTP`: typed descriptors, codecs, coordinated admission, safe retries, pagination,
  scoped coalescing, opt-in bounded response caching, and message/poll, channel/thread, guild,
  moderation, expression, discovery/event, application/user/command, webhook/interaction/voice,
  monetization and social/game backend REST catalogs.
- `DiscordInteractions`: signed bounded ingress, transport-neutral response ownership,
  optional early defer and independent durable webhook-event admission.
- `DiscordCommands`: complete typed command definitions, bounded exact routing and
  explicit canonical registration reconciliation.
- `DiscordDSL`: synchronous module/result-builder composition, bounded structural
  diagnostics, immutable descriptions and safe typed message content/mentions;
  depends on Core/Models and the shared logging foundation.
- `DiscordCommandDSL`: typed argument schemas/decoding, immediate/deferred/manual slash
  handlers, message/component builders, existing command lowering and signed HTTP
  application composition with explicit synchronization.
- `DiscordBotDSL`: typed Gateway selectors and protocol handlers, finite event compilation,
  bounded event groups, shared services, trusted Gateway interactions and explicit
  supervised bot application lifetime over existing Client/CommandDSL owners.
- `DiscordOAuth`: state/issuer-bound authorization, S256 PKCE, installation URLs,
  form-encoded token operations, injected browser presentation and bounded refresh ownership.
- `DiscordGameServices`: documented provisional/merge/unmerge/publisher backend operations
  and explicit profile/stat/lobby conveniences.
- `DiscordCommerce`: authoritative entitlement verification/consumption and injected Activity
  purchase orchestration; early-access storefront/fulfillment schemas remain blocked.
- `DiscordRPC`: local RPC v1 framing, session ownership, typed commands/events and bounded
  nonce correlation through injected IPC or deprecated approved-participant WebSocket transports.
- `DiscordCertifiedDevices`: validated prioritized full-array device publication through
  injected local HTTP or RPC; host applications supply native device identifiers.
- `DiscordActivities`: transport-neutral Activity sessions, typed command/event values,
  bounded subscription ownership and an owned dependency-free browser bridge.
- `DiscordSocial`: explicit user/host capability coordination, typed owned providers,
  bounded relationship synchronization and local PCM controls; no native SDK runtime.
- `DiscordGateway`: discovery, supervised shards, heartbeat/reconnect/resume, leases,
  startup/opcode budgets, typed dispatch decoding, correlated requests, bounded broadcast
  subscriptions and independently supervised ordered handlers.
- `DiscordCache`: optional scoped bounded entity projections, explicit refresh coalescing,
  sparse merging, stale-fetch fences and arbitrary-width permission resolution.
- `DiscordClient`: task-free configuration, supervised discovery/shards/ingestion, typed
  service access, diagnostics and idempotent awaited shutdown.
- `DiscordMedia`, `DiscordVoiceCodecs`, `DiscordVoiceCrypto`, `DiscordVoice`: independent
  bounded media/codec/transport-crypto and pure voice protocol components.
- `DiscordMLS`: independent MLS 1.0/ciphersuite-2 credentials, key establishment,
  ratchet trees, epoch exporters and the restricted group-handshake profile required by DAVE v1.
- `DiscordDAVE`: independent Voice/MLS transition ownership, sender ratchets,
  Opus/video frame transforms, bounded replay/verification and ephemeral human verification.

See [HTTP execution](Docs/HTTP.md), the [REST-only example](Examples/RESTOnly/README.md),
[interaction contracts](Docs/Interactions.md), the [HTTP application example](Examples/HTTPApp/README.md),
[local RPC contracts](Docs/RPC.md), the [RPC consumer example](Examples/RPCApp/README.md),
[Activity host contracts](Docs/Activities.md), the [Activity consumer example](Examples/ActivityHost/README.md),
[Gateway lifecycle and event catalog](Docs/Gateway.md),
[the bot consumer example](Examples/GatewayBot/README.md), and
[transport ownership, budgets and qualification limits](Docs/Transport.md).
See [MLS ownership, authentication and interoperability limits](Docs/MLS.md) and
[DAVE session/media ownership and qualification limits](Docs/DAVE.md) for the
separately adopted products. Their construction starts no tasks, sockets or device work.
The independent [local load harness](Tools/DiscordKitLoadTests/README.md) records
bounded cohort measurements; broad platform and qualification gates remain open.

Concrete NIO/Unix adapters use approved Apple NIO/TLS dependencies; portable and
Foundation products do not link those packages. Interactions independently adopts
Swift Crypto for Ed25519 verification and delivery digests; HTTP alone does not.
Development-only deterministic
clocks, barriers, scripts and resource tracking are excluded from library products.
Apple deployment baselines are macOS 13, iOS/tvOS 16, watchOS 9 and visionOS 1;
other-platform runtime qualification remains recorded separately.

## Compatibility and limits

Apple deployment baselines are macOS 13, iOS/tvOS 16, watchOS 9 and visionOS 1.
Compilation and runtime qualification are recorded separately in the
[platform guide](Docs/PlatformSupport.md). A Swift target alone does not establish
socket access, background execution, audio capture or the presence of a Discord host.

HTTP, Gateway, interactions and command workflows are implemented with explicit
partial child-resource projections. Local desktop RPC and Activities require an
authorized Discord host and application-owned platform integration. Public game
and Commerce operations are limited to documented contracts; native-only SDK
features and unpublished wire schemas remain unavailable.

Optional media, codec, MLS and DAVE products include bounded processing and supervised
voice sessions. Independent cryptographic review, complete-client and live Discord
interoperability, physical-device and minimum-OS qualification, and production
capacity remain open. Local tests, vectors, synthetic peers and loopback measurements
do not establish those qualifications. Read [voice](Docs/Voice.md),
[MLS](Docs/MLS.md), [DAVE](Docs/DAVE.md) and [voice sessions](Docs/VoiceSessions.md)
before adopting these products.

Applications register with the Discord Developer Portal and supply their own
credentials, shared admission authorities and deployment configuration. See
Discord's [getting started guide](https://docs.discord.com/developers/quick-start/getting-started).

## Project guides

- [Architecture and product boundaries](Docs/Architecture.md)
- [Typed REST operations](Docs/RESTCatalog.md)
- [Gateway and supervised clients](Docs/Client.md)
- [Signed interactions and commands](Docs/Interactions.md)
- [Modular commands and bots](Docs/DSLAdoption.md)
- [OAuth and token ownership](Docs/OAuth.md)
- [Game services and Commerce contracts](Docs/ServiceContracts.md)
- [Integrated diagnostics](Docs/Logging.md)
- [Dependencies and third-party notices](Docs/Dependencies.md)
- [Platform support](Docs/PlatformSupport.md)
- [Scalability and measurements](Docs/Scalability.md)
- [Reviewed source generation](Docs/Generation.md)
- [Release checks](Docs/ReleaseTooling.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)
