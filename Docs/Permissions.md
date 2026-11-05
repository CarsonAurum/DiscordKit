<!--
File: Docs/Permissions.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Computed permission REST reads

DiscordKit implements the four API **v10** permission retrieval endpoints added
to the official Guild and Channel references on **2026-10-31**, verified
**2026-11-05**. Previously callers could fetch role and overwrite metadata or use
the separate cache permission resolver. They can now request Discord's computed
result directly without assembling those resources or fetching each member.
The addition is source compatible and changes no existing permission calculation.

| Descriptor | Official route and calculation |
| --- | --- |
| `GuildEndpoints.memberPermissions` | [Get Guild Member Permissions](https://docs.discord.com/developers/resources/guild#get-guild-member-permissions): `/guilds/{guild.id}/permissions/member/{user.id}` combines the member's roles and `@everyone` |
| `GuildEndpoints.rolePermissions` | [Get Guild Role Permissions](https://docs.discord.com/developers/resources/guild#get-guild-role-permissions): `/guilds/{guild.id}/permissions/role/{role.id}` combines the specified role and `@everyone`; excludes other roles and member-specific restrictions |
| `ChannelEndpoints.memberPermissions` | [Get Channel Member Permissions](https://docs.discord.com/developers/resources/channel#get-channel-member-permissions): `/channels/{channel.id}/permissions/member/{user.id}` applies role and member-specific overwrites |
| `ChannelEndpoints.rolePermissions` | [Get Channel Role Permissions](https://docs.discord.com/developers/resources/channel#get-channel-role-permissions): `/channels/{channel.id}/permissions/role/{role.id}` applies the specified role's and `@everyone`'s overwrites; excludes other roles and member-specific overwrites |

All four descriptors use bot authentication, accept exactly HTTP 200 and return
`ComputedPermissions`. Its required `permissions` string retains arbitrary-width
ASCII decimal digits, including future permission bits and leading zeroes. Unknown
response fields and exact numeric spellings remain available through `rawFields`
and `jsonValue()`. Missing/null/mistyped permissions and invalid decimal syntax
fail with sanitized schema errors. Byte, depth and node limits cover the complete
response, including unknown subtrees. Ordinary descriptions and reflection redact
payload values.

```swift
let member = try await client.execute(
    GuildEndpoints.memberPermissions(guildID: guildID, userID: userID)
)
let unmaskedRole = try await client.execute(
    ChannelEndpoints.rolePermissions(channelID: channelID, roleID: roleID, implicit: false)
)
```

Channel reads require `VIEW_CHANNEL` and additionally `CONNECT` for voice/stage
channels. Threads use their parent's overwrites. The optional `implicit` argument
defaults to nil, omitting the query and retaining Discord's default **true**.
Explicit true/false requests masking or an unmasked calculation respectively.
Masking follows Discord's [implicit permission rules](https://docs.discord.com/developers/topics/permissions#implicit-permissions)
when the target lacks `VIEW_CHANNEL` or voice/stage `CONNECT`. Discord skips this
masking for bot member targets, including when true is requested. Guild reads
have no masking query; their reference documents no additional intent or
permission requirement. Discord decides current eligibility for every request.

These operations use the existing [HTTP pipeline](HTTP.md), including shared
credential-global admission, exact guild/channel major partitions, bounded safe
retries, cancellation and deadlines. No pagination, background work, local
permission calculation or follow-up hydration occurs. Equivalent in-flight reads
coalesce by default, and completed caching requires an explicit positive TTL.
The credential scope, target and masking query separate reuse identities. Resource
catalog tags participate in existing local mutation invalidation; external changes
can leave an explicitly cached result stale until expiry.

Results describe the requested calculation at the server's response time. A role
result does not include every permission a member could receive. Neither a result
nor a cached snapshot establishes authorization for a later operation. Missing
targets, forbidden access, API failures and malformed responses retain normal
typed HTTP error behavior. Local scripted tests exercise requests, bounded models,
successes, failures and finite rate retries; no live Discord qualification is claimed.

Review evidence is pinned to
[discord-api-docs revision da52492](https://github.com/discord/discord-api-docs/tree/da52492ced82d375981c46618cc3e182daada9a2),
compared with the prior reviewed revision
[3714862](https://github.com/discord/discord-api-docs/tree/37148620d2324292b76047541d5f8331f81ea77a).
The official changelog announces these endpoints on **2026-10-30**; a separate
effective date is unknown.
