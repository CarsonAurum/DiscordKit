<!--
File: Docs/RPC.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Local desktop RPC

DiscordKit provides independently adopted `DiscordRPC` and `DiscordCertifiedDevices`
products, verified against the official [RPC reference](https://docs.discord.com/developers/topics/rpc)
and [change log](https://docs.discord.com/developers/change-log) on **2026-10-17**.
RPC uses version **1**, independently of REST/Gateway v10. RPC has no HTTP,
Gateway, Client, Cache, OAuth or concrete adapter dependency. Construction opens
no socket, user prompt or background task. The [RPCApp example](../Examples/RPCApp/README.md)
checks the independent consumer graph.

## Connection and ownership

`RPCIPCConnector` performs bounded sequential candidate discovery using an
injected `RPCIPCOpening`. Unix chooses the first nonempty prefix in
`XDG_RUNTIME_DIR`, `TMPDIR`, `TMP`, `TEMP`, then `/tmp`, preserving the documented
precedence. Windows candidate names use `\\?\pipe\discord-ipc-{n}`. The default
0..<10 candidate budget is local policy: upstream publishes no maximum index.
The maximum caller-selected candidate count is 100. Native Unix applications
can inject the existing `UnixIPCTransport` from DiscordUnixPlatform. Windows
named-pipe I/O requires a separately qualified injected implementation; no owned
Windows named-pipe adapter or desktop support is qualified by these tests.

`RPCIPCConnection` owns a byte stream, encodes the 8-byte little-endian header
and decodes split/coalesced frames. Opcode 0 sends `{v:1,client_id:...}`;
opcode 1 carries bounded lossless JSON, 2 closes, and 3/4 exchange opaque
ping/pong bytes. Unknown opcodes, oversized lengths and truncated EOF fail closed.
At most one incomplete frame and one bounded read batch are retained. Ordinary
WebSockets use JSON messages without IPC headers; the WebSocket adapter owns
RFC 6455 fragmentation/control traffic.

`RPCClient` explicitly connects, validates the READY envelope/version and starts one reader plus
a demand-driven single writer. The application must await `close` before dropping
ownership. Close cancels/awaits startup, reader and writer work and closes the
transport even when cancellation happens during native open or READY. Repeated
close is safe. A fresh explicit connect/reconnect creates a fenced generation;
old replies/errors cannot cross it. Authentication/subscriptions are explicitly
restored by the application. No request is automatically replayed.

READY admission checks DISPATCH/READY, absent-or-null nonce, object data and the
exact v1 integer marker. Nested config/user data remains raw; consumers requiring
the typed configuration/user schema can separately use `RPCReady(value:)`.

Defaults bound pending requests to 128 and 4 MiB, queued events to 128 and 4 MiB,
and each JSON payload to 1 MiB. Frame/node/depth limits apply before JSON schema
inspection. A single queued control slot prioritizes pong work without creating
unbounded tasks. An application adopting multiple sessions must bound the
aggregate number of sessions/providers. No capacity/fleet claim follows from
these local caps.

Requests correlate by nonce and command; SUBSCRIBE/UNSUBSCRIBE also validate the
documented `data.evt` echo. Unknown late/duplicate nonces are ignored; mismatched
matched replies terminate the session. Cancellation/expiry removes only that
caller's continuation/unsent queue entry. An admitted native write remains
session-owned until completion or close, and mutations may already have executed.
Reconcile ambiguous outcomes before retrying. Server error messages are discarded
from diagnostics; only numeric error codes such as 4006 are exposed.

`nextEvent` permits one waiting consumer, delivers dispatches in wire order and
preserves unknown names/data. User processing does not block the sole reader.
Count/byte overflow terminates the session and resolves waiters rather than
silently dropping events. There are no handlers, automatic subscription reference
counts or unbounded broadcasts. Use explicit typed subscribe/unsubscribe requests.

## Catalog, authorization and compatibility

The catalog includes all **18 documented client commands** and **25 documented
event names**. Typed requests cover AUTHORIZE/AUTHENTICATE, guild/channel reads,
voice settings/selections, presence/invites, subscriptions and certified devices.
Only a raw local OAuth access token is accepted by the authentication builder;
bot and Authorization-header credential forms are rejected. AUTHORIZE returns a
code to exchange through a separately adopted OAuth/backend flow. Tester lists,
approval and requested/rejected scopes remain server-authoritative. Advisory
scope metadata does not establish access or Social SDK session equivalence.

Known projections retain complete `rawFields`, exact numeric lexemes and omitted/
null/value distinctions. Nested resource projections are partial; remote HTTP and
Gateway shapes are not assumed equivalent. Unpublished activity/invite response
schemas stay lossless `unmodeled` values. Diagnostics/reflection redact access
tokens, authorization codes, user/event bodies, partial decoder buffers and activity
secrets. Explicit raw payload access remains sensitive.

`SELECT_VOICE_CHANNEL(force:true)` requires explicit caller attestation of user
approval. SET_ACTIVITY accepts documented types 0/2/3/5 and an activity object;
null/omitted clearing has no established public contract. RPC voice shortcut
examples contain arrays despite the table's object label; array behavior is an
explicit local compatibility policy. Decimal voice pings follow official examples
and preserve `JSONNumber`, despite the table's integer label. The historical
GET_GUILD members array and guild online count remain deprecated. Conflicting
`relationships_read`/`relationships.read` scope spellings do not establish approval.

## WebSocket access and qualification

`RPCWebSocketConnector` explicitly selects one `127.0.0.1` port in **6463...6472**
with `v=1`, `encoding=json`, a registered client ID and a validated registered
HTTP(S) Origin. It never scans, follows a remote fallback or adds bot credentials.
This upstream transport is **deprecated** and limited to old approved private-beta
participants. Certified Devices publishes **6463...6473**; its dedicated connector
keeps that separate range. The [ambiguity register](Parity/ambiguities.json) retains
the unresolved endpoint discrepancy. No clarification or approved host evidence
has established one common range.

Deterministic peers cover framing, correlation, subscriptions, cancellation,
deadlines, failure/reconnect, bounds and cleanup. A real local Unix socket peer
also exercises the production Unix adapter and RPC stack. These results qualify
local behavior on this macOS host only. Real Discord desktop smoke tests on
macOS/Linux/Windows, minimum OS versions, approved WebSocket access, rejected
portal scopes and concrete hardware/native device enumeration remain separate
open gates. No remote Gateway or native Social SDK support follows from local RPC.
