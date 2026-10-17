# Emoji, stickers and soundboard REST catalog

Phase 5E implements all **25 operations** in the current official
[Emoji](https://docs.discord.com/developers/resources/emoji),
[Sticker](https://docs.discord.com/developers/resources/sticker) and
[Soundboard](https://docs.discord.com/developers/resources/soundboard) references:
ten Emoji, eight Sticker and seven Soundboard operations. Contracts were verified
**2026-10-16** against REST **v10**, the
[Permissions reference](https://docs.discord.com/developers/topics/permissions),
[API reference](https://docs.discord.com/developers/reference),
[official OpenAPI](https://github.com/discord/discord-api-spec) and
[change log](https://docs.discord.com/developers/change-log). Current hashes are
recorded separately from original discovery pins. No product or dependency was added.
Phase 5F adds [invites, templates, scheduled events and stages](DiscoveryEvents.md).
Phase 5J adds [lobbies and identity profiles](SocialGame.md); expression Gateway event catalogs remain pending.
Phase 5G adds [applications, users, linked roles and commands](ApplicationsUsers.md).

Import `DiscordModels` and `DiscordHTTP` and inject the existing bounded HTTP
pipeline with shared credential-scoped rate/reuse authorities. REST adoption
requires no Gateway or voice connection. Playing a sound still requires the
caller's existing eligible voice state; this catalog does not establish a voice
session or implement voice media transport. Descriptors perform no network request,
permission lookup, role hydration, boost lookup or entitlement discovery at construction.

## Operations and authorization

| Surface | Operations | Requirements and response contracts |
| --- | --- | --- |
| Guild emoji | list/get/create/modify/delete | Bot authorization; create requires CREATE_GUILD_EXPRESSIONS; editing/deleting own emoji permits CREATE_GUILD_EXPRESSIONS or MANAGE_GUILD_EXPRESSIONS, other emoji requires MANAGE_GUILD_EXPRESSIONS |
| Application emoji | list/get/create/modify/delete | Bot token for the owning application; list returns an `items` envelope; app emoji do not require USE_EXTERNAL_EMOJIS for use |
| Global stickers | get sticker, list packs, get pack | Pack listing permits anonymous or bot authorization; single sticker and pack reads require bot authorization under the current preview; pack list retains its `sticker_packs` envelope |
| Guild stickers | list/get/create/modify/delete | Bot authorization; creation and own/other editing permissions follow the guild expression split; create uses `multipart/form-data` |
| Soundboard reads | list defaults, list guild, get guild sound | Bot authorization; defaults return an array; guild listing retains the `items` envelope |
| Guild soundboard writes | create/modify/delete | CREATE_GUILD_EXPRESSIONS for creation; own edits/deletion permit CREATE_GUILD_EXPRESSIONS or MANAGE_GUILD_EXPRESSIONS; other sounds require MANAGE_GUILD_EXPRESSIONS |
| Soundboard play | send sound to channel | SPEAK and USE_SOUNDBOARD; USE_EXTERNAL_SOUNDS plus source guild ID for another guild's sound; caller must be connected without deaf/self_deaf/mute/suppress |

Creation requires HTTP **201**, ordinary reads/edits **200**, and deletion/play
**204** with an empty body. Guild administrative writes accept the bounded,
percent-encoded `X-Audit-Log-Reason` header; application emoji writes and play do not
invent audit headers. List/get responses include uploader data only under the
permissions described in the upstream resource reference. Permissions and ownership
are server decisions; a retained uploader or availability field is not authorization.

Emoji routes have unusual per-guild quotas and can return 429 even when quota
headers appear to allow a request. The injected coordinator honors actual 429s and
finite retry budgets. Guild and channel major partitions follow existing rate
policy; application emoji share the application route scope without inventing a
new Discord major parameter. Sharding does not increase these quotas. Mutations
retain unsafe replay semantics: explicit rejected-429 handling is bounded, while
ambiguous submission and unsafe server failures are not silently replayed.

## Models and compatibility

`Emoji` retains required nullable ID/name fields, including Unicode emoji with null
IDs and deleted custom emoji with null names. Roles, uploader, colon requirement,
managed, animated and availability flags preserve optional presence. Application
and guild list shapes remain distinct. Names and IDs are never normalized, and
large snowflakes retain exact decimal strings. Premium emoji cannot mix subscription
and ordinary roles, cannot change premium classification after creation and have a
separate limit of 25. Application emoji have an upstream 2,000-item maximum. The
library does not fetch role integration tags or infer remaining capacity.

`Sticker`, `MessageStickerItem` and `StickerPack` expose all written resource-owned fields,
including standard/guild type, PNG/APNG/Lottie/GIF format, nullable sticker
description, pack SKU, cover and banner IDs, sort order and boost availability.
Unknown integral type/format values remain readable. Pack descriptions and sticker
format types follow the written nonnull contract; preview nulls are deliberately
rejected. Pack membership and returned order are preserved without fetching stickers
or SKUs separately. Message-specific sticker items remain the small renderable
projection required by the Message contract.

`SoundboardSound` retains required nullable custom/unicode emoji fields, finite
volume, exact sound ID, optional guild/uploader and availability. Default sound IDs
such as `1` remain valid. Model payloads preserve exact unknown JSON subtrees using
finite byte/depth/node bounds and sanitized diagnostics. Referenced User projections
remain explicitly partial. REST models do not implement their corresponding Gateway
events or establish premium access in another guild.

The [ambiguity register](Parity/ambiguities.json) records written/preview conflicts
for emoji presence, sticker nullability, create/edit fields and Soundboard size units.
Written contracts control outgoing schema and response presence except for explicitly
retained nullable Soundboard source-guild preview compatibility. Providing null does
not satisfy the written cross-guild source requirement. Preview supplements publish
emoji-name, role-array and sound-emoji-name bounds and precise success statuses.

## Validated media and requests

Emoji uploads accept JPEG, PNG, GIF, WebP and AVIF image data and cap decoded bytes
at **256 KiB**. Create requests validate 2–32 Unicode scalar names; guild roles are
a nonnull, distinct ID array of at most 1,521 entries, including empty. Guild edits
preserve omitted/null/value role states. Application create/edit exposes only its
own fields; rename accepts an omitted name under explicit preview compatibility,
rejects null, and retains the String initializer as a convenience. The 128×128 image requirement, image correctness, premium role
classification and slot availability remain caller/server checks. Data-URI validation
performs bounded synchronous decoding and canonical syntax checks and never transcodes media.

Sticker creation sends separate `name`, `description`, `tags` and `file` form parts,
with no invented `payload_json` wrapper. Names allow 2–30 Unicode scalars,
descriptions empty or 2–100, and tags at most 200 including empty. PNG/APNG/GIF/Lottie
uploads cap file bytes at **512 KiB** and bound aggregate multipart framing. Edits
preserve absent fields, accept null description, and require 2–100 scalars for a
present description. Lottie upload eligibility requires VERIFIED or PARTNERED guild
features; 320×320 dimensions and five-second animation limits remain caller/server
checks. A byte limit does not validate an animation or decode its media.

Soundboard creation accepts MP3/Ogg data URIs, 2–32 scalar names, finite volume in
0–1 or explicit null, and nullable emoji fields. The fields remain independent; 1–32 scalar Unicode emoji-name bounds validate text,
while selector compatibility remains a server check. Modification preserves omitted/null/value states and never replaces
sound bytes. The written `512kb` file-size prose lacks an exact byte unit, so the
library conservatively caps decoded sound bytes at **512,000**. The upstream
**5.2-second** duration and correct media encoding remain caller/server checks.
Audio bytes are not decoded or transcoded locally. Upload/request diagnostics conceal
payloads; explicit raw access transfers logging responsibility to callers.

## Request reduction and ownership

Eligible reads coalesce only within the injected authentication identity and require
positive opt-in TTLs for completed caching. Public pack reads use anonymous scope.
Successful writes invalidate the relevant expression and guild/audit visibility
snapshots and fence stale in-flight completions through the common pipeline.
Cross-client visibility requires sharing authorities; external actions can remain
unseen until TTL expiry. Play never invalidates asset metadata and is never cached.

Opt-in `EmojiOperations`, `StickerOperations` and `SoundboardOperations` compare only
requested fields against caller-supplied snapshots and return no descriptor for an
exact no-op. Changed requests retain normal admission and mutation ordering. Helpers
perform no hidden reads, batch writes or per-asset hydration; stale equality cannot
prove current server state or permission. Lists have no documented cursor pagination,
so the library does not invent continuation or prefetching.

Media bodies reuse bounded transport ownership, replay factories and cleanup. Sticker
multipart materializes bounded immutable bytes and creates fresh read cursors per
attempt; cursors stop at declared bounds and close on success, failure or cancellation. Rate admission accounts for the complete request
body rather than file bytes alone. Explicit rejected-429 retries use fresh sources;
indeterminate unsafe writes retain their uncertainty.

## Validation scope

Deterministic Swift Testing fixtures exercise all 25 descriptors through injected
HTTP execution, versioned paths, statuses, auth/error handling, request boundaries,
unknown variants, large and default IDs, presence/nullability and malformed payloads.
Coverage includes multipart framing/cleanup, credential isolation, scoped read reuse,
invalidation, finite retries, unsafe submission outcomes, cancellation and snapshot
no-op/changed request counts. No tests require Discord credentials or live requests.

Root build/tests, the independent REST example, offline generation/parity checks and
local HTTP policy scenarios are the completion checks for this slice. Their execution
results are recorded in the [Phase 5E execution plan](../.air/plans/phase-5e-execution.plan.md).
Other hosts/devices, live API conformance, durable coordination and long-soak
qualification remain separate [platform gates](PlatformSupport.md). Upstream dates
and local support history remain distinct in the
[Phase 5E change record](Parity/changes/2026-10-16-expressions.md).

Phase 5H adds [webhooks, interaction responses and voice control](WebhooksInteractionsVoice.md).
