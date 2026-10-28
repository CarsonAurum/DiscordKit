<!--
File: Docs/Parity/changes/2026-10-17-activities.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Activities and owned browser protocol

Verified **2026-10-17**. The iframe host protocol uses numeric
HANDSHAKE/FRAME/CLOSE/HELLO opcodes and **v1** JSON handshake, independently of REST
and Gateway v10. Official SDK **2.5.0** source at revision
[`14264eccbf9e68d5d58c1aadbc7579e003e0dce6`](https://github.com/discord/embedded-app-sdk/tree/14264eccbf9e68d5d58c1aadbc7579e003e0dce6)
provides protocol/schema evidence without adding its npm runtime/dependency graph.
The [current source fingerprints](../activities-current-sources.json) are separate
from the unchanged historical discovery membership/revision hashes. Previously the repository provided backend OAuth/token ownership, signed launch
interactions and an injected Activity purchase authority without an owned iframe
messaging implementation. The independent Activities product now provides
transport-neutral session ownership, typed command/event values, bounded
correlation and subscriptions over an injected browser/platform binding. An owned
JavaScript bridge performs browser postMessage admission and teardown with no
external runtime package. Construction starts no I/O. Callers explicitly start,
retain and close sessions and inject authorized host bindings.

The [catalog](../activity-catalog.json) records the 21 reference command methods,
seven additional official-source exports, participant migration alias,
SUBSCRIBE/UNSUBSCRIBE controls, four lifecycle methods, 14 source dispatch names
and special ERROR. Each row separates codec/projection coverage from scopes,
Web/iOS/Android availability and host qualification. Source-only Quest, proxy,
user/invite/share operations remain explicitly unknown for host/scope/access
rather than contributing approved ordinary application coverage. Nested raw
resource fields remain partial projections; a known command enum is not complete
schema parity.

The browser bridge validates exact sending host and explicit trusted origin,
required host parameters and bounded frame/queue state. Handshake/READY,
nonce-plus-command replies, failure/close and cleanup are deterministic local
protocol behavior. Subscription reference counts use event plus canonical
arguments, making one upstream subscription for duplicate local consumers.
Independent cancellation/deadlines remove caller ownership; an already transmitted
mutation may still execute. No authorization/purchase mutation is replayed
implicitly. Explicit URL mapping helpers preserve Discord proxy and portal/CSP
requirements; unsupported WebRTC/WebTransport do not become supported network
transports through the bridge.

The [change log](https://docs.discord.com/developers/change-log) announced the
participant-method rename on **2026-10-06**. Prefer
`getActivityInstanceConnectedParticipants`; `getInstanceConnectedParticipants`
remains an alias until a future major release with unknown effective date. It
announced Activity `relationships.read` availability on **2026-01-21**, requiring
accepted Social SDK terms and removing separate Discord approval. That dated
clarification takes precedence over stale submit-for-access reference wording.
Original protocol/command/event introduction dates, the source-only rollout dates
and the orientation compatibility transition date remain unknown. Local support
dates are never used as upstream introduction dates.

Compatibility retains older hosts' `openExternalLink` `opened:null` and the pinned
source's explicit invalid-payload orientation fallback without `grid_lock_state`.
The reference still marks ENTITLEMENT_CREATE unavailable during Developer Preview;
its source codec does not establish actual event delivery. Web-only commands and
mobile-only orientation remain explicit catalog restrictions. Diagnostics redact
credentials, authorization codes, host context and raw user/purchase payloads.

The ActivityHost consumer composes backend OAuth exchange and
server-authoritative entitlement verification without storing client secrets in
iframe/mobile code. Client purchase responses/events are advisory context; durable
grants require backend entitlement checks. No live authenticated calls or real
purchases are part of local validation.

Migration is additive: adopt Activities, inject the owned browser/platform binding,
start and await READY, authorize/exchange server-side, authenticate and subscribe.
Explicitly release subscriptions and await close. Existing HTTP/Gateway/RPC
adoption is unchanged. See the [guide](../../Activities.md) and
[technical guide](../../Activities.md).

Swift synthetic protocol suites and Node built-in simulated-host suites establish
executed local contracts only. Approved Discord **Web, iOS and Android** tests for
handshake/auth/participants and purchase/entitlement workflows remain **not run**.
Swift/browser-Wasm, native WebKit/JNI adapters, proxy runtime policy, minimum
OS/browser versions and mobile suspension/recovery remain separate gates. No
standalone web view creates a Discord Activity host. These gates prevent a
whole-platform Activity qualification or fleet-capacity claim.
