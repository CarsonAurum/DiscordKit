# Phase 15E: message/component builders and typed interpolation

Recorded, verified and local support date: **2026-10-18**. The **0.15.0 candidate**
remains unpublished. Local commit is **unknown** until this implementation commit is
created. Upstream announcement/effective dates are **unknown** for this additive
Swift authoring milestone: it introduces no new Discord wire operation. REST/Gateway
v10, Voice v8, RPC v1, MLS 1.0 and DAVE v1 remain unchanged.

Previously, typed handlers returned validated direct message/create-edit models and
applications manually coordinated text, mentions, embeds and component trees. The
shared Core/Models-only `DiscordDSL` now captures finite `MessageContent` templates;
`DiscordCommandDSL` supplies message/component builders. Ordinary interpolated strings are escaped and
mention-neutralized; trusted literals and explicit raw segments preserve markup.
Typed user/role mentions add only their IDs to explicit bounded notification
allowlists; channel references add no notification category. Default broad parsing
and reply-author notification are disabled. Discord still applies one allowlist to
the complete message: a trusted literal/raw occurrence of a typed allowed ID can
notify that same ID. Permissions and actual notification delivery remain server-owned.

Typed text/embeds and the component layouts already supported by Models lower to
existing validated payloads. Illegal legacy/V2 combinations, empty output and
message/component/embed/mention limits fail before transmission. Raw model adoption
and explicit absent/null/value remain available. `MessageResponse` and
`DeferredMessageResponse` add thin builder initializers without changing the unique
initial-response owner, acknowledgement timing or edit-original completion. The
independent DSLCommands consumer exercises an ephemeral builder-authored response
in its synthetic signed offline exchange. See [message builders](../../MessageBuilders.md),
[response contracts](../../CommandResponses.md) and [migration](../../Migration.md).

No existing API is removed. Existing products keep independent adoption, the shared
DSL keeps its Core/Models-only graph, and the runtime selects no compiler plugin or
SwiftSyntax. Construction/rendering/lowering starts no task, network request,
registration, upload, handler or device work. Broader command families, policies,
Gateway hosts and full Phase 15 certification remain
[later milestones](../../DSLImplementationRoadmap.md).

The official [message reference](https://docs.discord.com/developers/resources/message),
[component reference](https://docs.discord.com/developers/components/reference),
[interaction reference](https://docs.discord.com/developers/interactions/receiving-and-responding),
[API reference](https://docs.discord.com/developers/reference),
[change log](https://docs.discord.com/developers/change-log),
[Swift interpolation contract](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0228-fix-expressiblebystringinterpolation.md)
and [result builders](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0289-result-builders.md)
were reviewed for the affected authoring and lowering contracts. The current component
reference admits **40 total Components V2 components**; dated earlier change-log
entries preserve superseded limits and are not the current contract.
[Exact source hashes](../../Release/sources/2026-10-18-phase15e.json) identify the
reviewed inputs. Existing discovery classifications and historical evidence remain
unchanged. Local payload parity, Unicode fixtures and synthetic signed HTTP do not
establish live Discord rendering, notification delivery, platform behavior,
production/fleet capacity or independent security review.
