# Part 15G policy and middleware authoring

Verified on 2026-10-18 for the unpublished 0.15.0 candidate. Upstream announcement
and effective dates are unknown: this is local composition over existing API v10
contracts, with no newly implemented endpoint, field, intent or permission.

Previously, command applications injected checks directly into handlers. Part 15G
adds pure bounded `InvocationPolicy`/`InvocationMiddleware` values, named/operator
parity, guild/context observations, injected authorization, shared finite concurrency
and explicit denial/error translation. Complete typed input preparation now precedes
execution interception across every command family, including before explicit deferral.
`CommandRoute` gains additive preparation/wrapping APIs without a DSL dependency.

Registration/default permission settings, cache observations and current application
authorization remain distinct. Existing response owners enforce one initial response,
compatible callback kinds, original deadlines and uncertainty. No retries, local HTTP
quota replacement, implicit registration, hidden queue or keyed policy store is added.
Error translation preserves partial effects and never sends a fallback after delivery.

Existing handlers and direct routes remain valid. Apply `CommandPolicies` explicitly
to a compiled catalog or exact route subset; reuse an injected concurrency authority
for an aggregate bound. A raw route needing validation before wrappers must adopt
`CommandRoute.init(key:prepare:)`. See the [policy guide](../../CommandPolicies.md).

Reviewed official [API reference](https://docs.discord.com/developers/reference),
[command permissions](https://docs.discord.com/developers/interactions/application-commands),
[interaction contexts and response ownership](https://docs.discord.com/developers/interactions/receiving-and-responding)
and [change log](https://docs.discord.com/developers/change-log) retain the existing
contracts. Source review metadata is recorded in the
[source review](../../Release/sources/2026-10-18-phase15g.json).

Local deterministic tests and signed offline examples do not establish live service,
other-platform or capacity qualification. Parts 15H-15L remain separate.
