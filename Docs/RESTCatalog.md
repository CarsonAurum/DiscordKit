# Typed REST catalog: messages and polls

Verified 2026-10-16 against the official [message](https://docs.discord.com/developers/resources/message),
[poll](https://docs.discord.com/developers/resources/poll),
[component](https://docs.discord.com/developers/components/reference),
[API reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log). All descriptors explicitly
use API v10. This is Phase 5A, the first independent REST catalog work package;
5B adds [channels and threads](Channels.md), 5C adds [guild administration](Guilds.md),
and 5D adds [audit logs and Auto Moderation](Moderation.md); 5E–5J remain pending.
Models and descriptors are committed handwritten semantic
contracts linked through the reviewed inventory. Consumer builds fetch nothing.

## Adoption

Import `DiscordHTTP` and `DiscordModels`, inject a transport and shared rate authority
into `RESTClient`, then execute a `MessageEndpoints` or `PollEndpoints` descriptor.
A REST-only consumer needs no Gateway connection. Credentials stay on the fixed
Discord API origin; attachment/CDN URLs in responses grant no permission to forward
API credentials. Models redact ordinary descriptions/debug output/reflection;
explicit field access and raw JSON remain caller-controlled sensitive data.

```swift
let request = try MessageCreate(
    content: .value("Hello"),
    allowedMentions: .value(MessageAllowedMentions(parse: []))
)
let message = try await client.execute(
    MessageEndpoints.create(channelID: channelID, request: request)
)
let page = try await client.execute(MessageEndpoints.history(channelID: channelID))
```

Every operation passes through the existing [HTTP pipeline](HTTP.md): opaque
credential identity, shared credential-global/route/resource admission, finite
queues/bytes, deadlines and retries. Channel IDs are major rate parameters; guild
search does not invent a guild major bucket. Shards never increase REST quotas.
Mutation descriptors conservatively disallow ambiguous replay, including nonce
creation, PUT and DELETE operations. Rejected 429s remain subject to the common
bounded retry policy. An uncertain send requires reconciliation by the caller.

## Operations

All operations use a bot token. Ordinary OAuth2 bearer scopes do not authorize
message operations. Discord enforces channel visibility and permissions. Guild
reads require VIEW_CHANNEL, message reads require READ_MESSAGE_HISTORY, and voice
channel reads additionally require CONNECT. Missing history permission can return
an empty history/pins list. MESSAGE_CONTENT restrictions can redact content,
embeds, attachments and components, omit polls, and prevent guild search.

| Operation | Public descriptor | Additional behavior or permission |
| --- | --- | --- |
| GET channel messages | `MessageEndpoints.history` | Exclusive before/after/around cursor; 1–100, newest first |
| GET guild message search | `MessageEndpoints.search` | READ_MESSAGE_HISTORY and MESSAGE_CONTENT; 200/results or 202/indexing |
| GET channel message | `MessageEndpoints.get` | Exact decimal-string identifiers |
| POST channel message | `MessageEndpoints.create` | SEND_MESSAGES; TTS also SEND_TTS_MESSAGES; replies need history |
| POST crosspost | `MessageEndpoints.crosspost` | SEND_MESSAGES; other authors also MANAGE_MESSAGES |
| PUT own reaction | `MessageEndpoints.createReaction` | READ_MESSAGE_HISTORY; new emoji also ADD_REACTIONS |
| DELETE own reaction | `MessageEndpoints.deleteOwnReaction` | Current bot's reaction |
| DELETE user reaction | `MessageEndpoints.deleteUserReaction` | MANAGE_MESSAGES |
| GET reaction users | `MessageEndpoints.reactions` | Normal/burst variants; after-user cursor, 1–100 |
| DELETE all reactions | `MessageEndpoints.deleteAllReactions` | MANAGE_MESSAGES |
| DELETE emoji reactions | `MessageEndpoints.deleteEmojiReactions` | MANAGE_MESSAGES |
| PATCH message | `MessageEndpoints.edit` | Author fields; other authors may change allowed flags with MANAGE_MESSAGES |
| DELETE message | `MessageEndpoints.delete` | Other authors require MANAGE_MESSAGES; audit reason |
| POST bulk delete | `MessageEndpoints.bulkDelete` | Guild channels, MANAGE_MESSAGES; 2–100 unique messages younger than two weeks; audit reason |
| GET current pins | `MessageEndpoints.pins` | 1–50; exact pinned-at cursor and explicit has_more |
| PUT current pin | `MessageEndpoints.pin` | PIN_MESSAGES; audit reason |
| DELETE current pin | `MessageEndpoints.unpin` | PIN_MESSAGES; audit reason |
| GET deprecated pins | `MessageEndpoints.legacyPins` | First 50, no pagination; deprecated annotation |
| PUT deprecated pin | `MessageEndpoints.legacyPin` | Deprecated route; use current pin descriptor |
| DELETE deprecated pin | `MessageEndpoints.legacyUnpin` | Deprecated route; use current unpin descriptor |
| GET answer voters | `PollEndpoints.voters` | Positive answer ID, after-user cursor, 1–100 |
| POST expire poll | `PollEndpoints.end` | Poll must belong to the authenticated author; finalized results can lag expiry |

Reaction emoji are supplied as Unicode or an unescaped custom `name:id`. Route
encoding occurs once. The list operation supports both normal and burst reactions;
the create endpoint does not invent a bot super-reaction operation.

## Payloads and uploads

`Message`, its nested message-owned values, polls and components preserve exact
unknown JSON. Required nullable fields differ from optional omitted fields.
Unknown integral variants and flag bits survive decoding. References distinguish
an unfetched referenced message, an explicitly deleted one and a present one;
forwarded snapshots remain immutable copies. Content redaction is retained as
returned and never treated as permission proof. Other-family projections (User,
Application, Channel, Sticker and interaction-resolved resources) keep their named
partial coverage until the corresponding REST batches. Raw nested fields do not
count as full typed parity for those families.

`MessageCreate` covers every current create field. `MessageEdit` preserves
absent/null/value fields, includes retained/new attachment metadata and validates
previous flag information when supplied. Voice-message validation requires one
audio upload with duration and sampled waveform; editing a known voice message
is rejected. Forward requests require the source channel and message IDs. Poll
requests validate text/answer/duration/emoji constraints separately from response
schemas. Components V2 use the correct flag and reject incompatible traditional
content fields. Modal-only component types are decoded for forward access but
are rejected by message-request validation; interaction/modal lifecycle is Phase 8.

`MessageUploadFile` owns materialized bytes or a fresh bounded producer factory.
`MessageUploadLimits` distinguishes the current default **20 MiB per-file** cap
from the message endpoint's **25 MiB complete-request** cap, including multipart
headers, payload JSON and delimiters. A configured local cap is not evidence that
a guild/user has a higher upstream allowance. Each request reserves its complete
conservative byte bound; a retry gets a fresh producer. Consumption, failure and
cancellation close active producers. Factories are never opened merely to validate
metadata. Attachment omission retains existing attachments; an explicit API v10
attachment array lists every retained and new file. Edits with new uploads require
that complete explicit list; an empty array removes files.

## Request reduction and continuation

Safe history/message/pins/reaction/voter reads opt into in-flight coalescing by
default. Completed caching requires an explicit positive TTL. Local channel writes
invalidate channel read tags; unobserved external changes can remain stale until
expiry. Search never caches an indexing response. Private results remain within
the injected authentication scope. No automatic member hydration or per-item
resource fetch is introduced.

`MessageOperations` supplies finite, lazy page sequences. Stopping consumption
starts no next request. Pins use `has_more` and the last exact `pinned_at` timestamp;
reaction/voter/history traversal continues until an empty page rather than assuming
a short page is terminal. Repeated/nonprogressing cursors fail safely. Search uses
requested offsets and its total/indexing state; short result arrays do not terminate
pagination. Its 9,975 maximum offset is an explicit window limit, not an implicit
claim that all guild messages have been searched. Indexing polling observes server
`retry_after`, finite attempts, cancellation and the caller's injected clock/deadline.

Bulk deletion is explicit opt-in through `BulkMessageDeletePlan`; it validates the
whole finite input first and splits legal chunks without a singleton tail. It sends
sequentially, preserves input order/correlation, and stops on failure. The failure
retains completed, attempted and unattempted IDs plus the underlying error; an
ambiguous attempted chunk is not presented as successfully deleted. There is no
implicit batching or per-item fallback after a failed bulk request.

## Evidence and limits

Tests use Swift Testing, exact large-ID fixtures, injected clocks and finite local
scripts. They cover request construction, presence/type/length/count boundaries,
unknown values, auth/API/transport failures, pagination/indexing request counts,
upload cleanup, byte admission and partial/uncertain bulk outcomes. No tests use
credentials or live Discord traffic. Local load smoke checks exercise the existing
HTTP policy; they do not establish additional deployment capacity. Non-macOS,
physical-device, minimum-OS, network replacement and long-soak gates remain in
[platform support](PlatformSupport.md) and [transport contracts](Transport.md).
