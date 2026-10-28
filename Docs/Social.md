<!--
File: Docs/Social.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Owned Social composition

DiscordKit provides independently adopted `DiscordSocial`, verified **2026-10-18** against
the [Social reference](https://discord.com/developers/docs/social-sdk/classdiscordpp_1_1Client.html),
[current change log](https://docs.discord.com/developers/change-log),
[RPC reference](https://docs.discord.com/developers/topics/rpc),
[Activity reference](https://docs.discord.com/developers/developer-tools/embedded-app-sdk)
and the account/mobile/Commerce sources pinned in
[current sources](Parity/social-current-sources.json).
HTTP descriptors select REST **v10**, desktop RPC handshakes select **v1** and the
existing owned Activity bridge selects **v1**. The native Social session and
early-access Commerce protocols have no published equivalent version negotiated
by this product. Upstream introduction/effective dates remain unknown unless
the catalog records a dated official announcement. Local implementation is 2026-10-18.

## Client and authority

`SocialClient<C>` coordinates explicit consent and common profile/presence operations
over narrow `SocialProfileProvider` and `SocialPresenceProvider` contracts. Construction
starts no tasks, sockets, native devices, authorization flow or persistence. The
application injects caller-owned clients sharing their clock and appropriate credential/
rate/resource authorities. There is no global actor owning all network I/O and no
automatic fallback from one host to another.

The application first validates an OAuth grant and its application/account association,
then activates a `SocialScope` with exact granted scopes and qualified hosts. These
inputs are assertions from the application, not proof acquired by the coordinator.
Use a fresh consent generation whenever account, visibility or consent changes.
The profile result must match the activated account; a mismatch fails closed.
Bot/backend authority is never used to manufacture consented user functionality.

Providers publish exact scope/host prerequisites. Capability reports describe local
admission and do not establish live host readiness, Discord approval, remote permissions,
current consent or device qualification. Extended typed provider APIs retain their own
requirements and authoritative upstream checks. Server entitlement verification remains
in Commerce; relationship/presence snapshots and purchase hints never authorize access.

`maximumOperations` bounds concurrent common provider calls (default 32). Admission
fails immediately at capacity, without an extra waiter queue. Presence admits one
writer at a time, including across consent replacement; no mutation is replayed.
Every caller owns its operation as structured work, with injected deadlines and
cooperative cancellation. Unknown provider error text is sanitized; safe `DiscordError`
values retain indeterminate mutation outcomes.

Disconnect/close clears the private relationship store and fences late results. Already
submitted mutations can still finish remotely. These methods do not cancel/await caller
tasks, revoke durable OAuth tokens or close shared provider clients: the application
must cancel/await outstanding calls, revoke when appropriate, and close resources it owns.
Close permanently disables this coordinator. Replacing providers requires a new client.

## Implemented public equivalents

| Provider | Owned behavior | Exact boundary |
| --- | --- | --- |
| `SocialHTTPProvider` | Consented current profile; create/join/leave lobby, link/unlink channel, send/history and linked-channel invite | Bearer-only endpoints; `identify` or `sdk.social_layer`; existing bounded REST/rate/retry policy. SDK lobby/network session methods remain distinct. |
| `SocialHTTPApplicationProvider` | All public application identity/profile routes | Bot-only backend authority; user scopes never inferred from this credential. Stats updates replace the entire supplied stats value. |
| `SocialRPCProvider` | Presence, guild channels, read/write desktop voice/device settings, per-user volume/pan/mute, select local text/voice channel, invite/reject join request | Explicit connected/authenticated approved desktop host and RPC scopes. Device settings control Discord's desktop devices, without opening app hardware. |
| `SocialActivityProvider` | Presence/explicit clear, relationships, Activity participants, invite dialog and external-link prompt | Existing exact-source/origin bridge and authorized host; command-specific host/scope checks. Immutable application name must match common presence updates. |
| `OAuthDeviceAuthorizationFlow` in OAuth | Published confidential console device authorization and explicit token polling | Application backend only, approved application configuration, published device grant. No SDK-managed public-client or console runtime integration. |

The complete [SDK method/event catalog](Parity/social-catalog.json) keeps each
method declaration and callback alias visible, including overloads. Public equivalents
are classified separately from exact SDK behavior. A profile REST call does not provide
an SDK live user handle; lobby messaging does not establish SDK DMs or call signaling.
Shared signing/session voice policies remain independently adopted Voice/DAVE concerns.

`SocialPresence` bounds UTF-8 fields and offers common name/details/state. Activity
names are application-derived and cannot be overridden; mismatches fail before I/O.
Full provider-specific presence fields remain available through their existing validated
types. RPC clearing remains an unresolved contract, while Activity null clearing is
explicitly supported by the embedded schema.

## Local observations and audio

`SocialRelationshipStore` owns finite users, relationship counts and UTF-8 string bytes.
Application-normalized observations require exact application/account/consent scope,
provider generation and sequence. Snapshot replacement is atomic; duplicate/older
observations are ignored. Gaps, new-generation events or exhausted capacity invalidate
freshness and require a complete snapshot. No event history or implicit fetch is retained.
Unknown relationship kinds survive without becoming friendships. Presence groups and Unicode-lowercased
username lookup are local display conveniences; they never send friend/block requests.
Presence grouping uses optional trusted observations of online/idle/do-not-disturb,
offline and current-game identity. Missing/unknown presence stays separate. In the
online-elsewhere group, prior players of this scoped application sort first, then IDs.
The private store inside SocialClient follows the same rules. Standalone stores must
be cleared explicitly when their application revokes consent.

`SocialActivityInvite` and `SocialAdditionalContent` provide bounded immutable local
metadata with exact IDs and preserved unknown integer kinds. They own neither native
handles nor invite delivery/redemption, and do not invent an upstream wire schema.
Display data is available only through explicit fields; ordinary diagnostics are redacted.

`SocialAudioControls` is an independent local PCM provider for application-owned route
keys, with a default 16-call cap. Global and per-call mute/deafen and linear input/output
gain compose synchronously; deafen also mutes capture, mute alone preserves playback,
and combined gain clips once. Missing routes fail closed. The provider owns no PCM
queue, device, DSP engine, network session or remote Social lobby call. Devices are
selected through separately qualified native adapters or documented desktop RPC settings.
Echo/noise/AGC, concurrent SDK-only lobby network calls, camera/Go Live and proprietary
Krisp remain subject to the exact recorded protocol/implementation/platform requirements.

`SocialAudioInputMonitor` supplies a separate constant-state local no-input equivalent.
The documented finite `-100...100` dBFS threshold uses `-100` to disable detection.
This provider computes per-block all-channel RMS and emits only changes after an
initial baseline. Discord's native analysis window/hysteresis is unpublished, so
equivalent native timing is not claimed. Empty buffers do not change state, callback
registration replaces the single observer, and close releases it. The application
routes microphone PCM explicitly; there is no device-health probe or native capture.

## Mobile, Commerce and qualification

The official native SDK supports current mobile integrations; this portable product
does not infer their transport from legacy desktop IPC. The catalog records iOS/Android
authorization, PKCE/redirect, installed-client presence prerequisites, native audio,
lifecycle/permissions and platform qualification gates separately. Console host/runtime
and access requirements remain separate from the public backend device flow.

The [Social Commerce overview](https://docs.discord.com/developers/social-commerce/overview)
still exposes early access rather than complete public catalog/storefront/pricing/gift/
wishlist/fulfillment wire schemas. Those named rows remain blocked. Existing ordinary
premium entitlements do not satisfy Commerce-specific purchase/fulfillment contracts.
No forms are submitted, credentials requested or live purchases made by this work.

Local tests exercise owned protocol clients against scripted peers, explicit
consent/host failures, account replacement, cancellation/deadline cleanup, bounded
state overflow/resync and PCM policy. They establish no authorized Discord/mobile/
console session, production purchase, physical device or sustained/fleet capacity.
Required native SDK and unpublished Commerce contracts remain unavailable.

Build/run the credential-free [independent Social example](../Examples/SocialApp/README.md).
Its graph excludes Gateway, Client, Cache, Voice/MLS/DAVE and concrete adapters. Existing
HTTP, RPC, Activities, Media and Voice remain independently adoptable and never depend
upward on Social. Consumers migrate by explicitly selecting providers; existing products
and their authorization/ownership contracts remain unchanged.
