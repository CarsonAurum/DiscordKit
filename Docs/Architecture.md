# Architecture and API conventions

Status: adopted design, baseline dated 2026-10-15. The runtime still contains only
the `DiscordKit` scaffold. The graph below is the intended architecture, not the
current manifest or an assertion that its modules exist. Introduce targets and
public products incrementally with real implementations and tests.

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
    DiscordTransport --> DiscordCore
    DiscordHTTP --> DiscordModels
    DiscordHTTP --> DiscordTransport
    DiscordGateway --> DiscordModels
    DiscordGateway --> DiscordTransport
    DiscordFoundationTransport --> DiscordTransport
    DiscordNIOTransport --> DiscordTransport
    DiscordCache --> DiscordModels
    DiscordInteractions --> DiscordHTTP
    DiscordCommands --> DiscordInteractions
    DiscordOAuth --> DiscordHTTP
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
    DiscordVoiceCrypto --> DiscordMLS
    DiscordKit --> DiscordClient
    DiscordKit --> DiscordCommands
    VoiceProduct[Optional voice product] --> DiscordVoice
    DiscordRPC --> DiscordTransport
    DiscordCertifiedDevices --> DiscordRPC
    DiscordActivities --> DiscordTransport
    DiscordSocial --> DiscordOAuth
    DiscordSocial --> DiscordRPC
    DiscordSocial --> DiscordVoice
    DiscordCommerce --> DiscordHTTP
```

Owned adapters may depend on approved Apple networking packages or platform
facilities. Their concrete dependency graph must be recorded and qualified before
advertising support. Development generators, documentation audits, fixtures and
test support are separate from public runtime products.

## Responsibilities and invariants

| Layer | Responsibility and boundary |
| --- | --- |
| Bits/Core | Portable value semantics, identifiers, field presence, errors, credentials, redaction and capability descriptions. No live networking. |
| Models | Immutable, `Sendable` Discord payloads and forward-compatible variants. No client, socket or transport references. |
| Transport | Narrow HTTP, WebSocket, datagram, IPC, ingress, stream and lifecycle contracts. Own no Discord endpoint policy. |
| HTTP | Typed service descriptors, authentication policy, codecs, bounded bodies, rate limits, retries and pagination. No Gateway requirement. |
| Gateway | Protocol state, discovery, shards, heartbeats and ordered event production. Does not import cache. |
| Cache | Optional projections of model/event data with explicit freshness, partial state and uncertainty. |
| Interactions/Commands | HTTP-only signature/response lifecycle and complete typed command construction/routing. Commands does not import Client. |
| Client/Kit | Supervised composition, consumer-facing configuration, handlers and service access. |
| Voice | Optional voice/media protocols; narrow Gateway control contracts rather than dependence on the facade. Crypto, MLS and codec work stays isolated. |
| RPC/Activities/Social/Commerce | Distinct local, host, authentication and access contracts; missing wire definitions remain explicit blockers. |

Put a shared protocol in the lowest module that already knows its parameter types.
Do not create an upward dependency just to access a facade convenience. The voice
Gateway edge represents narrow control protocols, not ownership of a bot client.
Portable types may compile on hosts where an operation cannot run; report that
capability separately from protocol implementation status.

## Consumer contract

REST services use async request methods directly and require no Gateway session.
Bot users configure credentials, intents, handlers and policy, then await a
supervised run operation. The library owns discovery, heartbeats, reconnect/resume,
rate-limit scheduling, serialization and sockets.

HTTP-only applications validate and respond to interactions without loading
Gateway or voice. Command builders expose all supported typed fields and permit
direct typed request construction. Voice consumers join, exchange frames and
leave; the module owns heartbeats, discovery, encryption and media counters.

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
- Specify protocol versions explicitly. The baseline intends
  [REST v10](https://docs.discord.com/developers/reference#api-versioning),
  [Gateway v10](https://docs.discord.com/developers/events/gateway) and
  [Voice Gateway v8](https://docs.discord.com/developers/topics/voice-connections),
  subject to official re-verification before each implementation; these values
  are not current runtime integrations.
- Model permissions, intents, access prerequisites, pagination and retry policy
  per operation. Preserve cancellation and expose an indeterminate mutation
  outcome instead of automatically replaying an ambiguous non-idempotent request.
- Bound subscriptions, queues, frames, bodies and media buffers. Define overflow,
  ordering, close behavior, ownership and cleanup in each public contract.
- Keep raw-route escape hatches within the same authentication, redaction,
  scheduling and origin protections. Raw access does not count as typed parity.
- Every explicitly declared method and test has accurate comprehensive Swift
  documentation and meaningful applicable tests at the time it is introduced.

The [concurrency policy](Concurrency.md) supplies execution/ownership rules; the
[parity inventory](Parity/README.md) supplies operation-level evidence. Neither a
diagram nor a public method signature proves supported behavior.
