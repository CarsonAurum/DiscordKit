# Webhooks, interaction responses and voice control

Phase 5H implements **28 current written REST operations** in API **v10**:
15 Webhook, eight Interaction response/message and five Voice operations. Current
[Webhook](https://docs.discord.com/developers/resources/webhook),
[Interaction](https://docs.discord.com/developers/interactions/receiving-and-responding),
[Voice](https://docs.discord.com/developers/resources/voice),
[reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log) contracts were verified
**2026-10-16**. Current fingerprints are independent of historical discovery pins.
No dependencies or runtime products are added. HTTP ingress/signature verification,
interaction routing and durable acknowledgement are Phase 8; voice networking,
media and devices are separate work. Phase 5J adds [lobbies and identity profiles](SocialGame.md).

## Webhook ownership and execution

WebhookEndpoints implements channel/guild listing; create, get, modify and delete;
the distinct token-authorized get/modify/delete variants; native, Slack-compatible
and GitHub-compatible execution; and message get/edit/delete. Management operations
use bot authorization and the documented MANAGE_WEBHOOKS/ownership requirements.
Audit headers are exposed only where documented. Token-authorized modification
cannot move the webhook to a different channel. Webhook stores its typed secret
and URL behind explicit unsafe inspectors and redacts ordinary diagnostics.
Follower source guild/channel projections and related user coverage remain explicit.

Native execution distinguishes an unconfirmed empty 204 from a confirmed 200 Message.
With wait=false Discord can discard an unsaved message without returning an error;
that result never proves persistence. Compatibility routes use their own explicit
preview acknowledgement contracts: Slack returns nullable string JSON and GitHub
returns empty 204, with the written default wait=true. They do not invent native
Message responses. Supported GitHub events and Slack exclusions follow the current
written reference and official preview; arbitrary external URLs gain no authority.

Validated native payloads cover content, embeds, mentions, attachments, polls,
components, flags, username/avatar overrides, thread creation/tags and applied query
options. Forum/media execution needs an existing thread or a new thread name;
conflicting targets fail locally. Component ownership is explicit: incoming
webhooks cannot send interactive components, and require with_components to use
noninteractive components. Application-owned webhooks retain documented access.
Native webhook execution with Components V2 rejects file uploads, following the
written Execute Webhook restriction. Initial webhook-message migration to V2
conservatively requires explicit null content, embeds, attachments and poll resets;
already-V2 messages may upload component files with a complete retained-and-new
attachment array. Replayable bounded multipart reuses MessageUpload: sources open
only after admission, each attempt owns its stream, cancellation closes active
sources, and future files are never prefetched. Local hard caps can be stricter
than Discord's current 20 MiB default or context-specific upload allowance.

## Token scopes and shared admission

Create a dedicated RESTClient with Credential.webhook(id, token) or
Credential.interaction(token). A token descriptor requires the exact matching
credential before cache lookup, coalescing, rate admission or transport. It never
adds Authorization. Raw path/query/response evidence remains explicitly sensitive;
ordinary endpoint/client/model/error formatting redacts it. Normalized rate routes
and major-resource IDs contain no token. Rotating credentials requires a new read
scope, as for bot and bearer clients.

Share each token's opaque RateLimitIdentity and RateLimitCoordinator across every
client/worker using it. Distinct token scopes retain separate learned buckets and
private cached responses. Webhook token requests also require an explicit egress
UUID: share it across clients using the same outbound IP. Their global budget and
global 429 restrictions apply across those token identities, while unrelated egress
and authenticated bot-global scopes remain independent. IP invalid-response
protection composes separately. Distributed stores must implement the additional
usesEgressGlobalLimit admission contract; a separate process-local coordinator does
not establish fleet ordering or durability. Interaction response operations are
explicitly exempt from the bot/IP global limit but retain route/resource limits,
bounded queues, retries, cancellation and egress invalid-response protection.

## Interaction responses and snapshots

InteractionEndpoints covers initial callbacks (empty 204 and with_response=true
200 metadata), original get/edit/delete and follow-up create/get/edit/delete.
The callback result has distinct typed interaction metadata and optional produced
message/Activity resource. It is not the incoming Interaction shape. Follow-up
creation always returns a Message; original/follow-up edits preserve documented attachment
replacement and server access checks. InteractionMessageCreate/Edit permit only
documented flags. Poll creation when editing an original deferred response requires
explicit deferred-response context. No generic mutation merging or ambiguous replay
is introduced.

InteractionResponse models PONG, immediate/deferred message, immediate/deferred
update, autocomplete, modal, deprecated premium-required and launch-Activity callback
kinds. Known source-interaction compatibility is validated when supplied; callers
remain responsible for application flags, install context, prior acknowledgement,
entitlement decisions and server eligibility. Preview-only callback type 13 remains
an unknown response code rather than an invented supported outgoing operation.
Modal definitions validate supported nested components and bounded custom IDs,
labels, choices, defaults and file inputs. Incoming submitted components retain
exact values and unknown component variants without applying outgoing requirements.

Interaction snapshots retain command/options, component/modal input, resolved
resources, installation owners, context, permissions and attachment limits, with
unknown JSON/enum values and absent/null/value states preserved. Related members,
roles, channels, messages and entitlements are explicit partial projections; there
is no hidden hydration. Known non-PING interactions require current contextual metadata. Minimal PING
and future kinds preserve context omission where applicable. These decoding contracts do not
verify signatures or establish authority from retained permission strings.

The initial acknowledgement must reach Discord within **three seconds**; continuation
tokens last **15 minutes**. Callers own trusted receipt times and supply finite
execution deadlines. REST factories do not start timers or claim to enforce token
age without that information. Expiry cannot recall an already submitted mutation.
Original and follow-up deletion includes ephemeral messages. Message visibility,
follow-up count restrictions, channel permissions, application eligibility and token
expiry remain server checks.

## Voice REST control

VoiceEndpoints lists global regions and gets/patches current-user or named-user
voice states. VoiceRegion reuses the complete GuildVoiceRegion contract; existing
GuildEndpoints.voiceRegions remains the separate guild-specific read. VoiceState
preserves all 13 current written fields, including nullable channel disconnection
and request-to-speak timestamps, exact session IDs and optional member/stream data.
Unknown fields survive within complete-document parser bounds.

CurrentUserVoiceStateModify and UserVoiceStateModify expose distinct permitted
fields. Clearing a request timestamp remains different from omission; named-user
edits cannot set it. Stage membership, CONNECT/MUTE_MEMBERS/REQUEST_TO_SPEAK,
server time and allowed state transitions are server requirements. No undocumented
audit reason is accepted. These operations neither join a channel nor open a
Gateway/voice session or acquire audio devices. Successful mutations invalidate
relevant credential-scoped voice/guild/channel/member snapshots.

## Validation and qualification

All operations share the [HTTP pipeline](HTTP.md): finite admission, retries,
ordered unsafe writes, strict success/status/schema decoding, bounded response and
upload bytes, cancellation/deadline cleanup and sanitized errors. Eligible read
coalescing is explicit and completed caching is opt-in; successful mutations
invalidate family tags. Deterministic Swift Testing suites exercise each operation,
request and model, failures, malformed JSON, permission/auth errors, 429 retry,
unknown mutation outcomes, scoped reuse, uploads and concurrent cleanup.

The [execution record](../.air/plans/phase-5h-execution.plan.md) records actual
commands and results. Verification is local macOS arm64/Swift 6.4, with synthetic
credentials and peers. Live Discord, other hosts/devices, minimum OS, distributed
coordination and sustained capacity remain separate qualification gates. See the
[chronological support record](Parity/changes/2026-10-16-webhooks-interactions-voice.md)
for previous/current behavior, known upstream dates and migration.
