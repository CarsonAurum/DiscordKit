# Social, Activity and Commerce protocol feasibility

Verified on **2026-10-15**. This report classifies potential owned providers for roadmap Part 0. No Social, Activity or Commerce implementation is added or certified by these records.

## Per-method inventory

The authoritative method-by-method map is [method-contracts.json](method-contracts.json). It contains **718 individually identified operation records** and **302 separately identified definitions**. The **73 source records** retain full source-content SHA-256, definition anchors, verified dates, optional pinned revisions, and source membership. Every operation has an implementation status separate from its contract classification; all remain **unsupported**. A full contract mapping means that an available provider has public protocol evidence, not that DiscordKit implements it or that a native SDK binary has been replicated.

| Surface | Operation records | Discovery scope |
| --- | ---: | --- |
| Social | 649 | Every method declaration in 33 published classes, including value/handle methods, overloads and static helpers, plus 29 namespace functions |
| Activity | 39 | Four written lifecycle methods, exported commands and compatibility alias, initialization and exported local utilities |
| Activity events | 15 | Thirteen written events and two additional pinned-source events |
| Commerce | 15 | Eight published SKU/entitlement/subscription REST operations and seven named early-access capability gaps |

| Candidate provider | Records | Meaning |
| --- | ---: | --- |
| Local computation | 590 | Owned values, callback registration, cache queries, formatting, media controls and platform adapters; remote data sources remain separately gated |
| Browser protocol | 50 | OAuth browser flow and Activity host frame messaging |
| HTTP | 28 | Explicit published endpoints or carefully marked partial server equivalents |
| RPC | 6 | A documented desktop-client provider or a partial candidate with a remaining SDK-equivalence gap |
| Missing upstream contract | 44 | No complete permitted provider established from the reviewed official sources |

There are **89 named blockers**. This exceeds the 44 missing-primary-provider rows because partial providers, source-only exports and locally callable methods with an unestablished remote data source also need evidence. No Social method is assigned bot Gateway support solely because its name resembles a bot operation. Native SDK session events and bot Gateway events have different authorization and lifecycle contracts.

The 302 additional definitions include 198 enum variants, 71 callback aliases and 33 static values. In particular, Social connection/call states and error variants remain visible instead of disappearing inside broad SDK-family labels. Unknown upstream announcement/effective dates are not inferred from the local verified date or repository commit.

## Social owned providers

The [Social Client reference](https://discord.com/developers/docs/social-sdk/classdiscordpp_1_1Client.html) supplies method definitions, not universal public network schemas. The map treats constructors, value accessors, conversions and registration helpers as local implementation work. A getter over cached relationships or users still needs a qualified source for that cache; callback registration does not establish a remote event stream. C++ copy/move/deleted ownership operations are classified so the source catalog is complete; this is not a promise to expose C++ ownership or native-runtime compatibility in Swift.

| Public candidate | Exact methods or family | Required qualification / remaining boundary |
| --- | --- | --- |
| OAuth2 HTTP/browser | Authorize, FetchCurrentUser, GetToken, RefreshToken, RevokeToken | Correct user identity/scopes, state/PKCE, redirect handling, refresh/revocation semantics and token redaction |
| Documented device authorization | GetTokenFromDevice | Device-flow application prerequisites; public/confidential client rules, bounded polling, cancellation and errors |
| Lobby HTTP | CreateOrJoinLobby variants, LeaveLobby, link/unlink channel, SendLobbyMessage variants, GetLobbyMessagesWithLimit | Bearer SDK scopes, membership/linking rights, metadata replacement and limit semantics |
| User HTTP | GetUserGuilds | User `guilds` authorization and pagination; a bot-owned guild list is not equivalent |
| Desktop RPC | GetVoiceSettings and UpdateRichPresence; partial GetGuildChannels / connected-user / join-request-reply candidates | Running Discord desktop host, approved scopes and exact RPC schemas; remote Social-session equivalence remains separate |
| Platform/local media | Device selection, volume, mute/deafen, VAD, AEC/noise suppression, callback delivery, audio routing | Owned/native adapters and platform permission/session behavior; functioning Social call signaling still needs a contract |

The underlying public routes are described by the [OAuth2 reference](https://docs.discord.com/developers/topics/oauth2), [Lobby resource](https://docs.discord.com/developers/resources/lobby), [User resource](https://docs.discord.com/developers/resources/user), [device authorization guide](https://docs.discord.com/developers/discord-social-sdk/development-guides/account-linking-on-consoles) and [RPC reference](https://docs.discord.com/developers/topics/rpc). Every mapped row names the concrete route or command. Providers must enforce the applicable access contract rather than moving a token between unrelated authorization surfaces.

SDK user DM creation/history/mutation and metadata, relationship mutations, remote presence/invites, remote user updates, Social socket Connect/Disconnect and lobby-call signaling retain per-method blockers. Required evidence includes URL/command/opcode, credential type and scopes, payload/error schemas, event ordering, initial snapshots/resume, rate limiting and host support. There is no inferred private endpoint implementation. The SDK's [native setup](https://docs.discord.com/developers/discord-social-sdk/getting-started/using-c%2B%2B) uses a distributed Discord runtime; wrapping that runtime does not satisfy this repository's dependency policy.

Krisp-specific `SetNoiseCancellation` remains distinct from owned noise suppression. Launch-command/Steam registration requires documented per-platform Discord registration semantics or approved host evidence. A generic process-launch helper cannot certify that integration.

## Public-client versus backend authentication

Some SDK calls have a public backend equivalent without establishing the SDK public-client wire contract. [External credentials exchange](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/external-credentials-exchange) documents a confidential server request; the [public-client guide](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/public-client) primarily exposes `GetProvisionalToken` through the runtime. The map records this equivalence as partial and requires the missing public-client request/authentication schema.

The same boundary applies to [publisher child-token exchange](https://docs.discord.com/developers/discord-social-sdk/development-guides/publisher-level-account-linking), [provisional merges](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/merging-accounts), and [unmerging](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/unmerging-accounts). A server request requiring an application secret is suitable for an owned backend provider; it cannot be silently copied into a public Swift app. Parent/child tokens, provisional/full tokens, audience, expiry and revocation lineage require distinct models and tests.

## Activity browser bridge

The [written Embedded App reference](https://docs.discord.com/developers/developer-tools/embedded-app-sdk) defines the supported lifecycle/commands/events and their platform/scope restrictions. The map also inspects the official exported commands and schemas at [revision 14264ecc](https://github.com/discord/embedded-app-sdk/tree/14264eccbf9e68d5d58c1aadbc7579e003e0dce6/src). Source-only Quest commands, proxy-ticket refresh, user/invite/share helpers and additional events remain explicitly partial where written availability/scopes are absent.

The [official bridge implementation](https://github.com/discord/embedded-app-sdk/blob/14264eccbf9e68d5d58c1aadbc7579e003e0dce6/src/Discord.ts) is evidence for iframe `postMessage` framing, version-1 handshake, per-command nonces, dispatch/error routing and subscription reference counts. DiscordKit must author its own JavaScript bridge without the npm runtime graph. A native Swift object, a local web page or a successful mock cannot establish a Discord-hosted Activity session. Browser bindings or a WebKit adapter must use the actual Discord iframe host and its permitted origins.

Host-specific restrictions remain method-specific: for example, hardware-acceleration prompting differs from commands supported on mobile hosts, guild/DM channel reads require their own scopes, and relationships access is gated. `getInstanceConnectedParticipants` is a compatibility alias, not an additional backend operation. Permission checks, price formatting and URL remapping are owned local utilities; their source dependencies are not imported. No Activity host conformance test ran in Part 0.

## Commerce contracts

The public [SKU](https://docs.discord.com/developers/resources/sku), [Entitlement](https://docs.discord.com/developers/resources/entitlement) and [Subscription](https://docs.discord.com/developers/resources/subscription) resource operations have explicit HTTP mappings. Activity purchase/entitlement commands remain Activity browser operations in the inventory. Entitlement ownership verification and consumption must follow the relevant resource contract; a subscription flag alone is not authorization.

[Social Commerce](https://docs.discord.com/developers/social-commerce/overview) advertises an early-access Game Shop with catalog/pricing/storefront, gifting/wishlists and fulfillment. The reviewed public overview does not publish all corresponding route or webhook schemas. The map gives each capability a separate named missing-contract row and records required evidence: authenticated request/response fields, supported variants, signed event payloads, retry/order/idempotency, account linking, fulfillment acknowledgment, reversals and failure recovery. It invents no endpoint names, event types or protocol versions. Ordinary entitlement consumption is not proof of Game Shop fulfillment parity.

## Evidence still needed

The [ambiguity register](../Parity/ambiguities.json) records the Identity Profile success-response contradiction, conflicting RPC/Certified Device port upper bound, preview-spec precedence, missing SDK protocols, server/public-client equivalence, source-only Activity availability, RPC presence clearing and DAVE document/wire-version distinction. It states interim policies and explicit resolution requirements.

Public API mapping is feasible without the Discord native runtime. Entire-platform parity remains blocked by unresolved upstream contracts/access and unqualified host behavior. Complete public-provider implementation, deterministic fixtures, approved host/runtime conformance and platform-specific capability reporting in the later roadmap parts before changing any operation's unsupported status.
