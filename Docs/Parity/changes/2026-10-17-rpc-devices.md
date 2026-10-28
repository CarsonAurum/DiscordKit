<!--
File: Docs/Parity/changes/2026-10-17-rpc-devices.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Local desktop RPC and Certified Devices

Verified **2026-10-17**. These products use **RPC v1**, with
JSON command/event envelopes. IPC's little-endian framing is independent of REST
v10 and remote Gateway v10. Current [source fingerprints](../rpc-device-current-sources.json)
are separate from the unchanged original discovery membership/revisions/hashes.
No release or commit identifier is known at the time of this record.

The [official change log](https://docs.discord.com/developers/change-log) announces
the IPC documentation on **2026-04-03**; that date establishes documentation
availability, not the introduction or effective date of the protocol. It records
the additional SET_ACTIVITY types on **2024-07-25** and deprecated RPC guild
member/online counts on **2018-06-11**. The original protocol/device introduction,
WebSocket deprecation announcement/effective dates and other upstream dates remain
unknown. No local implementation date is used as an upstream introduction date.

Previously the repository supplied Unix IPC byte streams and generic HTTP/WebSocket
transports without local Discord framing, correlation, typed RPC payloads or device
publication. Independent RPC and CertifiedDevices products now use injected
Core/Transport contracts. Importing them selects no HTTP execution, remote Gateway,
Client, Cache, OAuth, Commands, Interactions or concrete adapter. The independent
RPCApp example builds without connecting to Discord. Construction starts no tasks
or I/O; applications explicitly own connection and publisher lifetimes.

IPC implements bounded split/coalesced frame decoding, opcodes 0 through 4,
versioned handshake and READY validation. Discovery preserves the published Unix
environment-prefix precedence and Windows named-pipe namespace. Candidate counts
are an explicit bounded local policy; the documentation does not establish a
maximum IPC suffix. Native stream opening is injected. The existing Unix adapter
is available to native callers; an owned Windows named-pipe I/O implementation
and Windows runtime evidence remain absent.
The macOS-local simulated peer also exercises the production Unix byte stream
through RPCIPCConnector/RPCClient: handshake, READY, typed request, opaque control
payload, cancellation and namespace/queue cleanup. That peer is not Discord desktop.

Sessions bound pending request counts/bytes and event counts/bytes, use one reader
and one demand-driven writer, and correlate both command and nonce. Startup,
request and event consumption have independent cancellation/deadline handling.
Explicit reconnect creates a fresh generation; requests, authentication and
subscriptions are not automatically replayed or restored. Reconcile mutations
after cancellation or loss because transmission may already have taken effect.
Queue overflow and malformed protocol input fail closed. Callers await close to
release owned session work and transport resources.

Typed requests cover the 18 documented request commands and distinguish DISPATCH
as an incoming envelope. The event catalog covers the 25 documented names with
forward-compatible raw values and bounded JSON preservation. RPC-specific
projections retain explicit partial related-resource/Activity coverage rather
than assuming HTTP or Gateway payload equivalence. Local authorization is
explicit: AUTHORIZE, caller-owned token exchange, then AUTHENTICATE. Bot tokens
and a remote Gateway connection do not supply local RPC authority. Tester lists,
scope approval, RPC-specific permissions and host availability remain required.
The documented GET_GUILD members array and GUILD_STATUS online count retain their
deprecated empty/zero meaning. SET_ACTIVITY uses a nonnull activity object and the
documented types 0, 2, 3 and 5; presence clearing remains unsupported because its
public argument semantics are not established.
The RPC relationship-event prose spells its scope `relationships_read`, whereas
the linked current OAuth table publishes `relationships.read` with Social SDK
access prerequisites. Advisory metadata uses the current table spelling; runtime
never substitutes scopes or infers approval from it. The discrepancy remains open.
Two further local compatibility policies preserve the official examples without
claiming upstream resolution: voice-mode `shortcut` uses an array of key combos
despite singular-object table prose, and voice-connection telemetry preserves
exact JSON numbers so the published 13.37 millisecond example remains valid
despite integer-only table prose. The ambiguity register records both policies.

The official reference marks WebSocket RPC **deprecated**, restricted to old
private-beta participants, and prefers IPC. The explicit WebSocket connector uses
loopback, RPC v1/JSON and a caller-configured allowed origin. RPC's reference range
**6463...6472** remains separate from Certified Devices' HTTP/WebSocket range
**6463...6473**. Both are recorded as written. The [ambiguity register](../ambiguities.json)
retains the range and clear-presence blockers: no upstream correction or approved
desktop-host conformance has resolved them.

Certified device publication validates device types, vendor/model metadata,
native identifiers and input-only audio processing flags. Each update sends the
entire current highest-priority-first array, including an empty replacement;
there is no implicit merge, hardware watcher or background polling. Device IDs
remain host supplied: Windows native endpoint-instance identifiers and macOS device names are
documented separately. A fixed loopback HTTP publisher validates the 200 response,
command/nonce and null acknowledgement; an RPC wrapper uses the same validated
device array. A separate Certified Devices WebSocket connector retains its own
inclusive 6473 endpoint policy and origin/JSON/frame checks. Local count/body limits are resource policy rather than invented
Discord quotas. The HTTP publisher rejects overlapping updates; RPC publication
uses the client's bounded request admission and allows concurrent calls. Neither
publisher retries ambiguous mutations. The borrowed HTTP pool and injected RPC session retain caller ownership.

Migration is additive: import the desired product, inject a local transport and
explicitly authenticate/subscribe/publish. Share existing adapter ownership where
appropriate and await owned cleanup. Raw JSON access and portable Windows path
construction do not count as missing protocol or adapter support. See [RPC](../../RPC.md),
[Certified Devices](../../CertifiedDevices.md) and the
[technical guide](../../RPC.md).

Deterministic peers and macOS-local compilation do not establish real Discord
desktop behavior, certified-hardware behavior, deprecated private-beta access,
Linux/Windows/minimum-OS runtime support or fleet capacity. Real
desktop completion gate remains open on macOS, Linux and Windows. Native SDK-only
Social features, Activity host APIs and undocumented protocols remain separate work.
