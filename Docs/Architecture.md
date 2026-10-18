# Architecture and API conventions

Phase 14's [release tooling](ReleaseTooling.md) independently audits the actual
manifest/import DAG and consumer isolation. SwiftSyntax is confined to the separate
development package; public runtime products select no documentation tooling.
The [release report](Release/2026-10-18.md) distinguishes compiled products from
unverified platform capabilities and preserves the existing adoption boundaries.

Status: adopted design, updated 2026-10-18. `DiscordBits`, `DiscordCore` and
`DiscordTransport` implement the Part 1 foundations; `DiscordKit` exposes common
Core aliases. Part 2 adds independently injected Foundation/NIO adapters, Unix IPC
and Apple lifecycle ownership. Part 3 adds [HTTP execution](HTTP.md), partial Models
and the required [minimal Gateway lifecycle](Gateway.md). Discovery in Gateway
depends on HTTP while the HTTP product remains independent. Part 4 adds separate
[reviewed generation tooling](Generation.md), with committed outputs and no consumer
build-time generator or network access. Part 5A adds the independently adopted
[message/poll REST catalog](RESTCatalog.md), handwritten semantic request/response
contracts, uploads and bounded operation helpers within Models/HTTP. Part 5B adds
[channel/thread contracts](Channels.md) in the same independent products, including
type-aware edits, membership/archive workflows and forum/media creation. Part 5C adds
[guild administration](Guilds.md), typed member/role/ban/settings contracts, explicit
partial bulk outcomes and finite lazy traversal in those same independent products.
Part 5D adds [audit logs and Auto Moderation](Moderation.md), typed audit changes,
validated rule requests and bounded directional audit traversal without adding targets.
Part 5E adds [emoji, stickers and soundboard](Expressions.md), complete written
resource-owned contracts, bounded media and opt-in snapshot reconciliation in Models/HTTP.
Part 5F adds [invites, templates, scheduled events and stages](DiscoveryEvents.md),
with bounded CSV jobs, recurrence/status contracts, finite user traversal and snapshot
reconciliation in the same independent products. Part 5G adds
[applications/users, linked roles and commands](ApplicationsUsers.md), typed profile and
configuration contracts, finite guild traversal and explicit registration reconciliation
without adding dependencies or command-routing targets. Part 5H adds
[webhook/interaction/voice REST contracts](WebhooksInteractionsVoice.md) with typed
path-token scopes. Part 5I adds [monetization contracts](Monetization.md), complete
written SKU/Entitlement/Subscription fields, premium interaction data and finite
traversal in Models/HTTP. Subscription lifecycle state is separate from entitlement
decisions; broader Commerce products remain planned. Part 5J adds
[lobbies and application identity profiles](SocialGame.md), bounded member bulk
workflows and full-replacement profile statistics in the same products. Part 6 adds
[typed Gateway dispatches and commands](Gateway.md), bounded request correlation
and independent opcode admission in Models/Gateway. Gateway continues to depend on
HTTP only for discovery and never imports cache, user handler implementations or concrete transports.
Part 7 adds [consumer composition and optional state](Client.md): independent Cache
and Client products, bounded broadcast/ordered handler infrastructure in Gateway,
explicit scoped cache bridging and typed service access. The umbrella now composes
Client; REST-only consumers retain the independent HTTP graph.
Part 8 adds [signed ingress, response ownership and command workflows](Interactions.md)
in independent Interactions/Commands products. HTTP applications adopt neither Gateway
nor Client/Cache. Interactions selects Swift Crypto for signed requests and digests;
HTTP itself keeps its existing dependency graph. Webhook-event admission requires an
injected durable commit authority; display-only preview values remain in Models.
Part 9 adds [OAuth](OAuth.md), [public game-account services and entitlement helpers](Phase9ServiceContracts.md)
in independently adopted OAuth/GameServices/Commerce products. OAuth uses Swift Crypto
for S256; the HTTP graph remains independent of OAuth and Crypto. Browser UI and
secure transactional storage are injected. Native SDK-only and missing Commerce
wire contracts remain blocked.
Part 10 adds independently adopted [local RPC](RPC.md) and
[Certified Devices](CertifiedDevices.md) products. RPC uses injected Transport
IPC/WebSocket contracts and Core values; CertifiedDevices depends on RPC/Core/Transport.
Neither product selects HTTP, Gateway, OAuth, Client, Cache or a concrete adapter.
Local authorization is explicit and separate from bot credentials. Desktop-host
access, deprecated WebSocket availability and platform adapters remain qualified
separately from portable protocol code.
Part 11 adds [Activities](Activities.md) over Core/Transport contracts and an owned
minimal browser bridge. Applications inject a Swift/browser binding and an authorized
Discord Activity host. The portable product selects no HTTP, Gateway, RPC, OAuth,
Client or Cache. Backend auth and entitlement verification are composed explicitly.
See [transport contracts](Transport.md). The complete
graph below remains the intended architecture, beyond
the current manifest. Introduce further targets and products with implementations
and tests. See [foundation contracts](Foundation.md) for current scope and limits.

Part 12's initial [media/voice release](Voice.md) adds Media, VoiceCodecs,
VoiceCrypto and pure Voice protocol components. ApplePlatform additionally adopts
Media for native capture/playback and supported explicit device routing; Media selects no Apple frameworks.
VoiceCodecs owns ordinary SILK/CELT/hybrid arithmetic, synthesis and loss recovery;
its unified decoder starts no tasks or I/O and retains fixed output channels while
coded channels and modes change. Native Opus is used only by opt-in development
comparisons, never by product or ordinary test linkage. Encoder analysis limits and
the remaining native adapter gates are recorded in the voice capability inventory.
Voice uses Core/Models/Transport plus those media products; existing Gateway dispatch models supply narrow join
inputs without a Gateway runtime dependency. VoiceCrypto uses Crypto/CryptoExtras.
Phase 12B adds independently adopted [MLS](MLS.md): owned MLS 1.0/ciphersuite-2
wire, credentials, key establishment, ratchet trees, secret trees and the restricted
group-handshake profile required by DAVE v1. MLS selects only Swift Crypto and
starts no tasks or I/O. Phase 12C adds independently adopted [DAVE](DAVE.md):
authenticated Voice signaling/MLS coordination, sender ratchets, encoded-frame
transforms and bounded ephemeral identity verification. DAVE selects Voice, MLS,
VoiceCrypto, Core/Transport and existing Crypto/CryptoExtras. Voice and VoiceCrypto
remain independent of MLS/DAVE, preserving adoption without a dependency cycle.
Phase 12D adds [supervised voice sessions](VoiceSessions.md) with an injected
main-Gateway opcode-4 sender; Voice imports no Gateway or client facade.
The DAVE adapter implements Voice's injected E2EE interface, preserving DAVE -> Voice.
HTTP/Gateway/Client/Kit remain independent of voice,
MLS and DAVE. Independent crypto review, complete-client/live interoperability,
platform/device and ten-minute duplex qualification remain open.

Phase 13 adds independently adopted [Social composition](Social.md) over narrow
HTTP/RPC/Activity provider contracts, explicit consent/host admission, bounded scoped
relationship observations and local PCM controls. It imports Core/Models/Transport,
HTTP/OAuth/GameServices/Commerce, RPC/Activities and Media; no existing product depends
upward on Social. Social does not select Gateway/Client/Cache, Voice/MLS/DAVE or concrete
adapters. Applications compose qualified voice separately rather than making Social
account capabilities imply SDK-only lobby-call signaling. OAuth additionally owns the
published confidential backend device flow with explicit bounded polling.

Phase 15A adds independently adopted [shared authoring declarations](DSL.md) in
`DiscordDSL`. Its only direct dependencies are Core and Models; existing products
have no upward DSL dependency. Synchronous module composition produces a finite,
immutable description with stable explicit identities, source diagnostics and
configurable structural admission limits. It owns no tasks, transport, command
registration or event execution. Part 15B adds independently selected
[typed command authoring](CommandDSL.md) in `DiscordCommandDSL`, depending on
DSL/Core/Models/Commands/Interactions. It compiles finite argument schemas and manual
slash handlers to existing command definitions/routes; `makeRouter` explicitly creates
the existing bounded router. Response ownership stays with Interactions. Neither
existing products nor the shared DSL acquire upward dependencies. Part 15C's separate
[macro package](MacroDSL.md) consumes these runtime products; only its host plugin
selects SwiftSyntax 604.0.0. Part 15D adds typed immediate/deferred response adapters
and a signed HTTP `CommandApplication` over the existing application/router, adding
direct HTTP/Transport imports. Initial response admission remains independent and
command synchronization is explicit. Constructors and ordinary run register nothing;
the host injects and owns concrete ingress. Existing runtime graphs remain macro free.
Part 15E adds typed content interpolation to the Core/Models-only shared DSL,
with pure message/component builders and thin immediate/deferred response adapters
in CommandDSL. Existing payload validation owns layout, field presence and aggregate
limits; explicit mention allowlists accompany rendered text. The builders own no
transport, registration or handler lifetime. Policies, broader command families and
Gateway hosts remain later
[implementation milestones](DSLImplementationRoadmap.md).

## Product boundaries

Expose a convenient `DiscordKit` composition root while allowing REST, HTTP
interactions, Gateway, OAuth2 and voice to be adopted separately. Product
separation carries these boundaries; mutually exclusive SwiftPM traits do not.

Arrow direction means "depends on." Names are intended target names, except
`VoiceProduct`, which denotes the separately exposed optional voice composition.
Platform adapters are selected and injected at a composition root; protocol
modules do not choose a concrete networking backend.

```mermaid
flowchart TD
    DiscordCore --> DiscordBits
    DiscordModels --> DiscordCore
    DiscordDSL --> DiscordCore
    DiscordDSL --> DiscordModels
    DiscordCommandDSL --> DiscordDSL
    DiscordCommandDSL --> DiscordCore
    DiscordCommandDSL --> DiscordModels
    DiscordCommandDSL --> DiscordCommands
    DiscordCommandDSL --> DiscordInteractions
    DiscordCommandDSL --> DiscordHTTP
    DiscordCommandDSL --> DiscordTransport
    DiscordTransport --> DiscordCore
    DiscordHTTP --> DiscordModels
    DiscordHTTP --> DiscordTransport
    DiscordGateway --> DiscordHTTP
    DiscordGateway --> DiscordModels
    DiscordGateway --> DiscordTransport
    DiscordFoundationTransport --> DiscordTransport
    DiscordNIOTransport --> DiscordTransport
    DiscordCache --> DiscordModels
    DiscordInteractions --> DiscordHTTP
    DiscordInteractions --> SwiftCrypto[Swift Crypto]
    DiscordCommands --> DiscordInteractions
    DiscordOAuth --> DiscordHTTP
    DiscordOAuth --> SwiftCrypto
    DiscordGameServices --> DiscordOAuth
    DiscordGameServices --> DiscordHTTP
    DiscordClient --> DiscordGateway
    DiscordClient --> DiscordHTTP
    DiscordClient --> DiscordCache
    DiscordClient --> DiscordInteractions
    DiscordVoice --> DiscordGateway
    DiscordVoice --> DiscordVoiceCrypto
    DiscordVoice --> DiscordVoiceCodecs
    DiscordVoice --> DiscordTransport
    DiscordDAVE --> DiscordVoice
    DiscordDAVE --> DiscordMLS
    DiscordDAVE --> DiscordVoiceCrypto
    DiscordDAVE --> DiscordCore
    DiscordDAVE --> DiscordTransport
    DiscordDAVE --> SwiftCrypto
    DiscordMLS --> SwiftCrypto
    DiscordKit --> DiscordClient
    DiscordKit --> DiscordCommands
    DiscordKit --> DiscordOAuth
    DiscordKit --> DiscordGameServices
    DiscordKit --> DiscordCommerce
    VoiceProduct[Optional voice product] --> DiscordVoice
    DiscordRPC --> DiscordTransport
    DiscordRPC --> DiscordCore
    DiscordCertifiedDevices --> DiscordRPC
    DiscordCertifiedDevices --> DiscordTransport
    DiscordCertifiedDevices --> DiscordCore
    DiscordActivities --> DiscordTransport
    DiscordActivities --> DiscordCore
    DiscordSocial --> DiscordCore
    DiscordSocial --> DiscordModels
    DiscordSocial --> DiscordTransport
    DiscordSocial --> DiscordHTTP
    DiscordSocial --> DiscordOAuth
    DiscordSocial --> DiscordGameServices
    DiscordSocial --> DiscordCommerce
    DiscordSocial --> DiscordRPC
    DiscordSocial --> DiscordActivities
    DiscordSocial --> DiscordMedia
    DiscordCommerce --> DiscordHTTP
```

Owned adapters may depend on approved Apple networking packages or platform
facilities. Their concrete dependency graph must be recorded and qualified before
advertising support. Development generators, documentation audits, fixtures and
test support are separate from public runtime products.
The Client → Interactions edge remains planned; current Gateway consumers explicitly
normalize trusted interaction dispatches into the same context and response actor.

## Responsibilities and invariants

| Layer | Responsibility and boundary |
| --- | --- |
| Bits/Core | Portable value semantics, identifiers, field presence, errors, credentials, redaction and capability descriptions. No live networking. |
| DSL | Synchronous structural module composition, bounded source diagnostics and a deterministic immutable declaration description. Core/Models only; no runtime, compiler-plugin or concrete-adapter ownership. |
| Models | Immutable, `Sendable` Discord payloads and forward-compatible variants. No client, socket or transport references. |
| Transport | Narrow HTTP, WebSocket, datagram, IPC, ingress, stream and lifecycle contracts. Own no Discord endpoint policy. |
| HTTP | Typed service descriptors, authentication policy, codecs, bounded bodies, rate limits, retries and pagination. No Gateway requirement. |
| Gateway | Protocol state, discovery, shards, heartbeats, typed catalog, bounded requests/admission, independent bounded broadcast and handler execution. Does not import cache or user handlers. |
| Cache | Optional scoped projections, explicit coalesced refresh/freshness, sparse state, uncertainty and pure arbitrary-width permission resolution. Imports no Gateway/HTTP/Client. |
| Interactions | Signed bounded HTTP ingress, shared HTTP/Gateway response ownership, independent initial admission and durable webhook-event admission hooks. Imports neither Gateway nor concrete adapters. |
| Commands | Complete typed definitions, bounded exact routing and explicit canonical registration reconciliation. Imports neither Gateway nor Client. |
| OAuth | Fixed-origin authorization/token contracts, injected browser UI and secure storage, bounded per-grant refresh, expiry and revocation lineage. No Gateway/Client/Cache dependency. |
| GameServices/Commerce | Public account and publisher wire contracts, snapshot conveniences and backend entitlement authorization. Native SDK and unpublished storefront/fulfillment protocols remain blocked. |
| RPC | Bounded local IPC/WebSocket framing, handshake, nonce correlation, typed commands/events and explicit session/subscription ownership. Injected transport; no remote Gateway or automatic OAuth exchange. |
| CertifiedDevices | Prioritized full-array device publication through injected local HTTP or RPC, with native device identifiers supplied by the host. No native audio-device discovery or media capture. |
| Client/Kit | Supervised discovery/shard/ingestion composition, configuration, optional cache bridge, event access, diagnostics and typed services. |
| Voice | Optional voice/media protocols; narrow Gateway control contracts rather than dependence on the facade. Crypto, MLS and codec work stays isolated. |
| MLS | Independently adopted bounded MLS 1.0/ciphersuite-2 values, key establishment and DAVE-profile group handshakes. No transport, device, media or Gateway ownership; application authentication and delivery are injected. |
| DAVE | Independently adopted Voice/MLS transition coordination, exact-session media readiness, sender ratchets, codec-aware frame protection and ephemeral verification. Authenticated controls, membership, trust and clocks are injected; no socket/device or supervised network ownership. |
| Activities | Bounded host messaging, typed command/event catalog and reference-counted subscriptions over an injected Activity binding. Owned browser bridge validates source/origin; no iframe host is manufactured. |
| Social | Distinct host, authentication and access contracts; missing wire definitions remain explicit blockers. |

Put a shared protocol in the lowest module that already knows its parameter types.
Do not create an upward dependency just to access a facade convenience. The voice
Gateway edge represents narrow control protocols, not ownership of a bot client.
Portable types may compile on hosts where an operation cannot run; report that
capability separately from protocol implementation status.

## Consumer contract

DiscordKit is designed for bot deployments serving hundreds through millions of
accounts, including deployments with many bot identities. User count, credential
count, guilds, shards and simultaneous connections are distinct capacity axes.
The [scalability requirements](Scalability.md) define request efficiency, identity
isolation, aggregate resource budgets and evidence required for capacity claims.
These are design requirements; current foundations establish no runtime capacity.

REST services use async request methods directly and require no Gateway session.
Bot users configure credentials, intents, handlers and policy, then await a
supervised run operation. The library owns discovery, heartbeats, reconnect/resume,
rate-limit scheduling, serialization and sockets.

HTTP-only applications validate and respond to interactions without loading
Gateway or voice. Command builders expose all supported typed fields and permit
direct typed request construction. The same response actor accepts trusted Gateway
snapshots and uses a dedicated HTTP callback queue. Defer, expiry and ambiguous
submission remain explicit; no handler, command synchronization or listener starts
at construction. Planned voice consumers will join, exchange frames and leave;
the module will own heartbeats, discovery, encryption and media counters.

Expose status, errors and diagnostic hooks without making callers maintain
protocol internals. Diagnostics must redact credentials in headers, paths,
bodies, signed URLs, errors, descriptions, logs, metrics, traces and fixtures.

## Public API conventions

- Use Swift naming and deliberate public access. Prefer immutable `Sendable`
  values, actors for shared mutable runtime state, `async throws` for fallible
  I/O and `AsyncSequence` for asynchronous event subscriptions.
- Keep local computation synchronous. Preserve omitted, explicit null and value
  states in PATCH-style payloads. Preserve unknown fields/variants when the
  documented compatibility contract requires it; never silently narrow large IDs.
- Typed authentication distinguishes bot, bearer, interaction, webhook and
  credential-free operations. Services cannot send API credentials to arbitrary
  origins or CDN requests. Portal setup is documented separately from API calls.
- Specify protocol versions explicitly. Current REST and Gateway integrations use
  [REST v10](https://docs.discord.com/developers/reference#api-versioning),
  [Gateway v10](https://docs.discord.com/developers/events/gateway), interaction
  payload version 1 and webhook-event envelope version 1. The planned voice baseline
  is [Voice Gateway v8](https://docs.discord.com/developers/topics/voice-connections),
  subject to official re-verification before implementation.
  Local RPC and Certified Devices explicitly use RPC version 1 and JSON; IPC
  framing and the deprecated approved-participant WebSocket transport are distinct.
- Model permissions, intents, access prerequisites, pagination and retry policy
  per operation. Preserve cancellation and expose an indeterminate mutation
  outcome instead of automatically replaying an ambiguous non-idempotent request.
- Bound subscriptions, queues, frames, bodies and media buffers. Define overflow,
  ordering, close behavior, ownership and cleanup in each public contract.
- Keep raw-route escape hatches within the same authentication, redaction,
  scheduling and origin protections. Raw access does not count as typed parity.
- Every explicitly declared method and test has accurate comprehensive Swift
  documentation and meaningful applicable tests at the time it is introduced.

Rate/cache/coalescing policy belongs above send-once transports. HTTP response
reuse must work without Gateway or the entity-cache product. Shared coordination
is injectable with in-process defaults; shard ownership, Identify admission and
rate reservations cannot silently become independent during coordinator failure.
Start the sharded lifecycle alongside the first HTTP slice, before completing
the endpoint catalog. Measure each runtime milestone against versioned load and
resource budgets in the scalability requirements.

The [concurrency policy](Concurrency.md) supplies execution/ownership rules; the
[parity inventory](Parity/README.md) supplies operation-level evidence. Neither a
diagram nor a public method signature proves supported behavior.
