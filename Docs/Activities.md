<!--
File: Docs/Activities.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Activities and the owned browser bridge

DiscordKit provides an independently adopted `DiscordActivities` product and a minimal
owned JavaScript bridge. Contracts were verified against the official
[Embedded App SDK reference](https://docs.discord.com/developers/developer-tools/embedded-app-sdk),
[Activity lifecycle](https://docs.discord.com/developers/activities/how-activities-work),
[networking guide](https://docs.discord.com/developers/activities/development-guides/networking)
and [change log](https://docs.discord.com/developers/change-log) on **2026-10-17**.
The official SDK **2.5.0** source revision
[`14264eccbf9e68d5d58c1aadbc7579e003e0dce6`](https://github.com/discord/embedded-app-sdk/tree/14264eccbf9e68d5d58c1aadbc7579e003e0dce6)
was verified as the current official `main` HEAD on 2026-10-17; its commit timestamp
is 2026-05-05. It is protocol/schema evidence, not a runtime dependency. Current
[source fingerprints](Parity/activities-current-sources.json) preserve the original
discovery inventory's membership and historical source hashes.

## Adoption and host ownership

An Activity is a web application inside an authorized Discord iframe/mobile
host. Native WebKit, a host-provided browser or a separately qualified Swift/browser
binding can adapt the Activity transport. They cannot create a Discord host in an
ordinary standalone app. The portable Swift product depends only on Core/Transport;
it selects no HTTP, Gateway, RPC, OAuth, Cache or Client. Construction starts no
network requests, listeners or background tasks. Applications explicitly start and
close the session and retain ownership of their injected platform binding.

The owned bridge lives in [Browser/DiscordActivityBridge](../Browser/DiscordActivityBridge/README.md).
It uses browser APIs and JavaScript built-ins, with no npm runtime dependencies.
The [ActivityHost example](../Examples/ActivityHost/README.md) shows independent
composition and compiles without authenticated calls or purchases. Browser-Wasm,
native WebKit/JNI adapters and approved Discord embedding are separate qualification
work; a simulated peer is not evidence of host availability.

## Protocol and resource ownership

The host messaging protocol uses numeric opcodes **0 HANDSHAKE**, **1 FRAME**,
**2 CLOSE** and **3 HELLO**. Handshake uses **v1**, JSON encoding, the registered
application/client ID and host frame ID; this version is independent of REST and
Gateway v10. READY establishes the connected generation before ordinary commands.
Host parameters include required frame/instance IDs and desktop/mobile platform,
with optional guild/channel/location/custom/referrer/mobile-version values. These
values are untrusted client context and do not authorize backend access.

The browser bridge validates the precise expected message source and configured
trusted origin before inspecting frames. Deployment policy must provide the
expected authorized Discord origin; broad wildcard or opaque-origin acceptance
is not a default. The main Discord window can be the parent or the parent's opener
for popouts. Origin validation does not replace source-window identity. HELLO is a
legacy compatibility opcode; both the pinned SDK and the owned bridge ignore it.
READY, command replies and dispatches are distinct.

Requests correlate both nonce and command. Late/duplicate replies cannot satisfy
another caller. Close/failure rejects outstanding startup, request and subscription
waiters and releases listeners, timers, queues and pending storage. Cancellation
and deadlines affect individual operations; a command already transmitted may
have taken effect, so reconcile mutation outcomes before retrying. No automatic
purchase, authorization or mutation replay is permitted.

Pending operations, frame bytes and event storage have explicit finite limits.
User processing does not run inside transport message admission. Overflow and
malformed matched protocol frames produce explicit failures rather than unbounded
work. Callers owning multiple clients/bindings must also bound aggregate resources.
No fleet capacity or browser memory claim follows from synthetic tests.

Subscriptions share upstream admission by event plus canonical argument identity.
Two local consumers of the same event/arguments make one upstream subscription;
release of the final consumer sends the matching unsubscribe. Different channel
arguments retain distinct identities. READY is session lifecycle, while ERROR can
represent a correlated command failure. Unknown event names and unknown fields remain explicit forward-compatible values.
A reply with a mismatched or unknown command cannot satisfy an existing request;
unknown late nonces are ignored. The outgoing typed command enum covers the pinned
exported catalog. Unknown data does not silently become a known event or grant permission.

## Catalog and availability

The current reference documents **21 command methods**, four lifecycle methods
and **13 event names including ERROR**. The pinned official SDK additionally
exports **seven command methods** and two events, plus the deprecated participant
method alias. SUBSCRIBE/UNSUBSCRIBE are wire commands owned by the session.
The [machine-readable catalog](Parity/activity-catalog.json) names each codec,
documentation path and access/host status. Catalog presence, codec coverage, nested
projection completeness and real host
availability are separate dimensions. Lossless raw JSON for a nested child does
not claim a complete typed schema for that child.

The catalog records host support as **Web / iOS / Android**, independently from
Swift deployment platforms. Most documented commands support all three. Exceptions:

| Commands | Web | iOS | Android | Scope |
| --- | --- | --- | --- | --- |
| encourageHardwareAcceleration, openShareMomentDialog, setConfig, startPurchase | Yes | No | No | None |
| setOrientationLockState | No | Yes | Yes | None |
| getChannel | Yes | Yes | Yes | guilds; GDM also needs approved dm_channels.read |
| getChannelPermissions | Yes | Yes | Yes | guilds.members.read |
| getRelationships | Yes | Yes | Yes | relationships.read and accepted Social SDK terms |
| setActivity | Yes | Yes | Yes | rpc.activities.write |
| userSettingsGetLocale | Yes | Yes | Yes | identify |
| Other reference command methods | Yes | Yes | Yes | None |

The [2026-01-21 change-log entry](https://docs.discord.com/developers/change-log#relationshipsread-scope)
says Activities need accepted Social SDK terms for `relationships.read` and no
longer need separate Discord approval. This newer clarification takes precedence
over the reference's older submit-for-access wording. Scope metadata remains
advisory; the host enforces the granted scopes and user authorization.

Event scopes are `rpc.voice.read` for VOICE_STATE_UPDATE/SPEAKING_START/SPEAKING_STOP,
`identify` for CURRENT_USER_UPDATE, both `identify` and `guilds.members.read` for
CURRENT_GUILD_MEMBER_UPDATE, and `relationships.read` plus Social SDK terms for
RELATIONSHIP_UPDATE. READY, ERROR, layout/orientation/thermal and participant
updates list no required scope. Event reference sections do not publish a complete
per-host matrix. ENTITLEMENT_CREATE is still marked **not available during Developer
Preview** in the reference; implementing its published codec does not guarantee
delivery. Source-only ACTIVITY_JOIN and QUEST_ENROLLMENT_STATUS_UPDATE retain
unknown host/scope/access status.

The seven source-exported methods absent from the reference are `getUser`,
`inviteUserEmbedded`, `shareInteraction`, `getQuest`, `getQuestEnrollmentStatus`,
`questStartTimer` and `requestProxyTicketRefresh`. Their official published source
schemas permit exact codec implementation; their platform, scope, approval and
production availability remain unspecified. They are not counted as approved
ordinary application capabilities. No undocumented wire behavior is inferred from
method names.

## Compatibility and unknown data

Discord announced `getInstanceConnectedParticipants`' rename to
`getActivityInstanceConnectedParticipants` on **2026-10-06**. The old name remains
an alias in the pinned source; removal is announced for a future major version
with unknown effective date. Prefer the new name. The source also removes
`grid_lock_state` on the documented invalid-payload compatibility fallback for
older orientation hosts; this is a specific bounded fallback, not a generic retry.
`openExternalLink` preserves `opened:null` for Discord clients before December
2024 that did not report the result. Missing, null and concrete values remain
separate where the schema permits them. Snowflakes and permission values must
retain exact decimal representation rather than JavaScript floating-point rounding.

Rich-presence, nested message/channel/user, Quest and entitlement values can carry
sensitive user data, activity secrets and tokens. Diagnostic descriptions must
redact these values. Explicit raw fields remain sensitive application data. Do not
trust client-supplied identity, purchase or entitlement data as backend authority.

## Network mappings and server composition

Activity requests use Discord's configured proxy and Developer Portal URL mappings.
Absolute application resources use the registered application's
`https://{clientId}.discordsays.com` origin. Mapping helpers perform explicit bounded
URL transformation and preserve allowed path/query data; they do not configure the
portal, bypass CSP or create an unrestricted network tunnel. HTTP(S)/WebSocket
mapping behavior must remain scheme/host/path-boundary aware. WebRTC and
WebTransport remain unavailable in the current networking reference.

The owned `ActivityURLMapper`, `createActivityFetch` and
`createActivityWebSocket` helpers are explicit and do not patch browser globals.
They do not claim drop-in equivalence to the SDK global `patchUrlMappings` utility.
Mapping helpers and injected browser networking are distinct from a native Swift
network adapter.

Authorization returns a code to the application's backend. Compose
[DiscordOAuth](OAuth.md) for server-side code exchange/token ownership, then send
only the user access token needed to authenticate the Activity.
`OAuthEndpoints.activityAuthorizationCode` uses the documented confidential backend
form for a code returned by Activity AUTHORIZE: grant type, code and client
authentication, plus a verifier when PKCE was requested. It omits a redirect URI
because this iframe grant does not redirect through the ordinary browser OAuth
callback. Ordinary redirect-bound OAuth continues to use its own stricter API. Never embed a
client secret or server token storage in iframe/mobile code. Signed HTTP launch
interactions and command definitions continue through [interaction and command owners](Interactions.md);
Activity startup does not require a remote Gateway session.

A purchase response or ENTITLEMENT_CREATE event is client context. Use
[DiscordCommerce's server entitlement verification](ServiceContracts.md)
with the expected application, user/SKU and validity/consumption policy before
granting durable value. Subscription status alone is not authorization. The
injected Activity purchase operation remains separate from authoritative backend
verification. No real-money purchase is performed by the example or local tests.

## Validation boundary

Swift Testing exercises synthetic protocol frames; Node's built-in test runner
exercises a simulated message host without external test/runtime packages. These
checks cover local origin/source rejection, handshake/READY, correlation,
subscriptions, cancellation, bounded storage and teardown. They establish only the
executed local contracts. Approved Discord **Web, iOS and Android** host tests for
handshake, auth, participants and purchase/entitlement workflows remain **not run**.
Native UI adapters, actual Swift/browser-Wasm builds, minimum OS/browser versions,
mobile suspension/recovery and real proxy behavior remain separate gates. These
requirements prevent a whole-platform qualification claim while the implemented
local protocol slice is independently adoptable.
