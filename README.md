# DiscordKit

DiscordKit is the foundation of a modular, Swift-native Discord application and
bot library. Parts 1–3 provide portable values, owned network adapters, a bounded
HTTP execution pipeline and a minimal sharded Gateway lifecycle. The typed REST
slice retrieves the current user/application and Gateway discovery, and adds
[message and poll operations](Docs/RESTCatalog.md) in Phase 5A,
[channels and threads](Docs/Channels.md) in Phase 5B,
[guild administration](Docs/Guilds.md) in Phase 5C,
[audit logs and Auto Moderation](Docs/Moderation.md) in Phase 5D,
[emoji, stickers and soundboard](Docs/Expressions.md) in Phase 5E,
[invites, templates, scheduled events and stages](Docs/DiscoveryEvents.md) in Phase 5F, and
[applications, users, linked roles and commands](Docs/ApplicationsUsers.md) in Phase 5G, and
[webhooks, interaction responses and voice control](Docs/WebhooksInteractionsVoice.md) in Phase 5H, and
[SKUs, entitlements and subscriptions](Docs/Monetization.md) in Phase 5I, and
[lobbies and application identity profiles](Docs/SocialGame.md) in Phase 5J. Phase 6 adds
[typed Gateway dispatches, commands and bounded requests](Docs/Gateway.md). Phase 7 adds
[the consumer client, bounded broadcast/handlers, entity state and permission resolution](Docs/Client.md).
Phase 8 adds [signed HTTP ingress, interaction response ownership, command routing
and explicit reconciliation, webhook-event admission and display-only link previews](Docs/Interactions.md).
Phase 9 adds [OAuth2, installation and token ownership](Docs/OAuth.md),
[public game-account services](Docs/Phase9ServiceContracts.md), server entitlement
verification and explicit Activity purchase orchestration. Phase 10 adds
[local desktop RPC v1](Docs/RPC.md) and [Certified Devices](Docs/CertifiedDevices.md)
with bounded injected IPC/WebSocket sessions and prioritized device publication.
Phase 11 adds the independent [Activity client and owned browser bridge](Docs/Activities.md)
with typed catalogs, bounded correlation/subscriptions and injected host integration.
Approved Discord browser/mobile smoke qualification remains open. Phase 12 starts
with independent [portable media and voice protocol components](Docs/Voice.md):
bounded PCM/DSP, Opus framing/entropy, mono/stereo SILK/CELT/hybrid coding, ordinary packet decoding with explicit loss/FEC recovery, transport AEAD, RTP and pure voice control reducers. The Apple adapter
owns audio I/O and supported explicit device routing;
native device qualification and Windows/Android implementations remain open.
Encoding analysis and platform qualification remain bounded. Phase 12B adds
independent [MLS 1.0/ciphersuite-2 key establishment and DAVE-profile group handshakes](Docs/MLS.md).
Phase 12C adds independently adopted [DAVE signaling, encoded-frame protection
and human verification](Docs/DAVE.md). Independent crypto review and complete-client/live
interoperability remain open. [Phase 12D](Docs/VoiceSessions.md) adds supervised per-guild
voice sessions, bounded PCM/Opus pipelines and an independently composed DAVE adapter;
Phase 13 adds an independently adopted [owned Social client](Docs/Social.md), typed
HTTP/RPC/Activity providers, bounded local state/audio controls and explicit device
authorization. Native Social protocols and schema-blocked Commerce remain visible blockers.

Phase 14 adds [release certification](Docs/Release/README.md), DocC adoption guides,
an owned declaration-documentation audit, product/import isolation and API/semver
checks, cross-platform CI and weekly upstream maintenance. The
[0.14.0 candidate report](Docs/Release/2026-10-18.md) records exact local evidence
and all excluded platform/live/hardware claims. Start with [setup](Docs/Setup.md),
[migration](Docs/Migration.md) and the offline
[commands/components consumer](Examples/CommandsApp/README.md).

Phase 15A adds an independently adopted [Swift module authoring foundation](Docs/DSL.md).
`DiscordDSL` composes finite declarations into deterministic descriptions with explicit
module identities, source diagnostics and structural bounds. Construction and compilation
start no tasks or I/O. Part 15B adds independently adopted
[typed command authoring](Docs/CommandDSL.md): typed argument schemas/decoding, manual
slash handlers and explicit lowering to existing command definitions/routes. Part 15C
adds a separate [macro authoring package](Docs/MacroDSL.md) with compiled parity and
external diagnostic fixtures. Part 15D adds [typed response ownership and signed HTTP
command applications](Docs/CommandResponses.md), with explicit command synchronization
and an [independent offline consumer](Examples/DSLCommands/README.md).
Part 15E adds [validated message/component builders](Docs/MessageBuilders.md), safe
text interpolation and explicit mention allowlists over existing Models. Part 15F adds
[command families](Docs/CommandFamilies.md), partial autocomplete, exact component/modal
routes and explicit catalog reconciliation. Part 15G adds [bounded policies and
middleware](Docs/CommandPolicies.md), injected authorization and concurrency admission.
Part 15H adds [typed Gateway event modules](Docs/GatewayEventModules.md), explicit
intent validation and bounded ordered dispatch in the independent `DiscordBotDSL` product.
Part 15I adds [supervised bot applications](Docs/BotApplications.md), shared service
access and trusted Gateway interaction callbacks over HTTP. Explicit `run` owns the
existing client and bounded pipelines; construction and ordinary execution register
nothing. Part 15J adds [external module namespaces and typed dependencies](Docs/ModuleExtensions.md),
with separately adopted extension libraries and independent HTTP/Gateway consumers.
Dependency validation precedes lazy body creation; namespaces preserve original
metadata and wire routes. Part 15K adds [offline DSL measurements](Docs/DSLBenchmarks.md),
with paired direct/DSL workloads, compiler costs and finite regression budgets.
Production capacity and final release review remain separate
[DSL gates](Docs/DSLImplementationRoadmap.md).

Part 4 adds reviewed inventory contracts and deterministic offline generation for
the existing model/endpoint slice. Consumer builds compile committed output; see
[reviewed generation and parity checks](Docs/Generation.md).

The architecture baseline records platform capabilities, dependency policy, a
versioned parity inventory and explicit feasibility blockers. Portable values are
usable today; HTTP/WebSocket/UDP/ingress/Unix adapters are available with explicit
limits and macOS-local qualification. REST and Gateway are independently adoptable;
broader resource projections retain explicit partial coverage. A planned
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

## Documentation

The DocC catalogs cover all 28 public products, with task guides, nine tutorials,
an example cookbook and organized pages for every public type. Start with the
[documentation contents](Sources/DiscordKit/DiscordKit.docc/TableOfContents.md)
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
explains navigation generation, synchronized tutorial code, validation and hosting.

## Available products

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
  moderation, expression, discovery/event, application/user/command, webhook/interaction/voice
  monetization and social/game backend REST catalogs.
- `DiscordInteractions`: signed bounded ingress, transport-neutral response ownership,
  optional early defer and independent durable webhook-event admission.
- `DiscordCommands`: complete typed command definitions, bounded exact routing and
  explicit canonical registration reconciliation.
- `DiscordDSL`: synchronous module/result-builder composition, bounded structural
  diagnostics, immutable descriptions and safe typed message content/mentions;
  Core/Models dependencies only.
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
bounded cohort measurements; broad platform and Phase 2 qualification gates remain open.

Concrete NIO/Unix adapters use approved Apple NIO/TLS dependencies; portable and
Foundation products do not link those packages. Interactions independently adopts
Swift Crypto for Ed25519 verification and delivery digests; HTTP alone does not.
Development-only deterministic
clocks, barriers, scripts and resource tracking are excluded from library products.
Apple deployment baselines are macOS 13, iOS/tvOS 16, watchOS 9 and visionOS 1;
other-platform runtime qualification remains recorded separately.

## Consumer experience

- REST services work without a Gateway connection or voice dependencies.
- Bot clients supervise heartbeats, reconnect/resume, rate limits and socket
  ownership through an async run operation.
- HTTP interactions work without loading Gateway or voice.
- Local RPC and Certified Devices retain independent products; applications supply
  local user authorization, host integration and platform qualification separately.
- Activities require an authorized Discord iframe/mobile host and an injected Swift/browser
  binding; backend OAuth and entitlement verification retain independent ownership.
- Commands and routers provide conveniences over complete typed requests.
- Optional voice products expose bounded streaming media, framing/entropy/crypto
  primitives, control reducers and supervised per-guild join/frame/leave sessions
  with injected Gateway, secure signaling and network/device authorities.
- MLS can be adopted separately for authenticated group key establishment; callers
  supply trusted participant identity/key associations and authenticated delivery.
- DAVE composes MLS and Voice over injected authenticated controls and clocks;
  exact-session readiness and frame transforms do not create a running connection.
- Platform and access restrictions produce explicit capability information.

HTTP execution, the consumer client, sharded Gateway lifecycle, HTTP interactions and
command workflows are implemented with explicit partial child-resource projections.
Feature products are introduced
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
- [Signed ingress, interactions, commands and webhook events](Docs/Interactions.md)
- [OAuth2, installations and token ownership](Docs/OAuth.md)
- [Public account/game contracts and Commerce blockers](Docs/Phase9ServiceContracts.md)
- [Local RPC v1 and host qualification](Docs/RPC.md)
- [Certified Devices and prioritized publication](Docs/CertifiedDevices.md)
- [Activities, browser bridge and host qualification](Docs/Activities.md)
- [Sharded Gateway lifecycle and event catalog](Docs/Gateway.md)
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
