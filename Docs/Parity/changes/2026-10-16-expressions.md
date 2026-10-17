# Emoji, stickers and soundboard: Phase 5E

Local implementation and verification: **2026-10-16**. REST API version: **10**.
Local release/commit: unknown until committed/released. No dependency changes.

Previously these resource operations were unsupported, with explicitly partial
emoji/sticker projections used by messages, polls and guilds. This change exposes
all **25** current written-reference operations: ten Emoji, eight Sticker and seven
Soundboard. New complete written resource-owned contracts preserve Unicode/deleted/
animated emoji, guild/application ownership, premium and availability state,
sticker packs and formats, and default/guild sound metadata. User projections and
corresponding Gateway events remain partial or pending; batches 5F–5J are separate.

Upstream chronology, distinct from local support:

- **2017-09-10:** Guild Emoji endpoints announced; earlier effective dates unknown.
- **2018-01-30:** Get Guild Emoji uploader data announced; current conditional
  uploader visibility follows the latest resource reference.
- **2020-11-13:** Stickers documented on Message. This does not establish the
  introduction date of the current Sticker CRUD or pack operations.
- **2023-12-15:** Clarification documents the July 2023 expression-permission split
  for users/roles and notes it was then unavailable to bot developers. An exact
  July introduction day is unknown.
- **2024-07-18:** Application-owned emoji announced, including bot-token API
  management and up to 2,000 emoji per application.
- **2024-09-20:** Soundboard API announced, including retrieval, modification,
  sending sounds and receiving associated events. This does not establish a
  separate introduction day for every currently documented endpoint.
- **2025-11-20:** CREATE_GUILD_EXPRESSIONS announced for bot developers, with
  creation permission changes effective **2026-02-23**; **2025-11-24** repeats that
  MANAGE_GUILD_EXPRESSIONS alone would no longer permit custom emoji/sticker creation.
  Current Soundboard creation follows the same permission in its resource reference.
- Separate effective dates and other field/endpoint introduction dates are unknown.

Official [Emoji](https://docs.discord.com/developers/resources/emoji),
[Sticker](https://docs.discord.com/developers/resources/sticker),
[Soundboard](https://docs.discord.com/developers/resources/soundboard),
[Permissions](https://docs.discord.com/developers/topics/permissions),
[API reference](https://docs.discord.com/developers/reference),
[change log](https://docs.discord.com/developers/change-log) and
[official OpenAPI](https://github.com/discord/discord-api-spec/tree/ed014089afa986f2b532ae081c456a85de074d0c)
were verified 2026-10-16. GitHub's API confirmed that revision as current main.
Hashes in the expression current-source record remain separate from original
discovery membership pins. Full source content is not vendored.

Compatibility policies remain explicit in the ambiguity register. Written Emoji
presence accepts Unicode/deleted forms; written Sticker format and pack-description
contracts remain nonnull despite preview nullability. Outgoing Sticker description
and tag limits follow written semantics. Application rename accepts an omitted name
under explicit preview compatibility and rejects null; the String initializer remains
a convenience overload. Nullable Soundboard source-guild preview
compatibility does not satisfy the cross-guild source requirement. The Soundboard
`512kb` wording is conservatively interpreted as 512,000 decoded bytes pending
clarification. File size validation does not claim codec, dimension or duration
validation, or entitlement/role verification.

Migration: import Models/HTTP and opt into EmojiEndpoints, StickerEndpoints or
SoundboardEndpoints and their explicit snapshot reconciliation helpers. Keep shared
credential-scoped rate/reuse authorities and the current expression permission split.
Creation uses 201, reads/edits 200, and delete/play 204 empty responses. Sticker create
uses direct multipart fields; Emoji/Soundboard use bounded data URIs. No public API
is removed or renamed. Local fixture validation cannot qualify live Discord, other
platforms or long-soak behavior. See [expression contracts](../../Expressions.md)
and the execution plan for detailed behavior and validation evidence.
