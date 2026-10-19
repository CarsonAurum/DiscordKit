# Part 15H typed Gateway event modules

Verified on 2026-10-18 for the unpublished 0.15.0 candidate. Upstream announcement
and effective dates are unknown: this is authoring over existing Gateway v10
contracts, with no new event name, intent, permission or model projection.

Previously consumers wrote direct hub subscriptions and dispatch closures. Part 15H
adds independently adopted `DiscordBotDSL` with typed protocol handlers, open selectors,
exact declaration/registration validation and explicit required-intent admission.
Modules flatten into one default subscription; named independent groups are explicit
and finitely bounded. Existing dispatchers retain complete-shard ordering, shared
admission, overflow and callback ownership. Constructors and compilation start no work.

Known malformed payloads fail before callbacks in decoded groups. Unknown names
retain raw values; entirely raw groups keep an explicit decoder bypass. Failures and
cancellation close subscriptions and join cooperative work through `run`, preserving
partial side effects without replay. Existing direct consumers remain valid.

Adopt [the event guide](../../GatewayEventModules.md) and
[independent offline example](../../../Examples/DSLEvents/README.md) explicitly;
continue to inject services and select/provision intents at the host. Current
[Gateway intents](https://docs.discord.com/developers/events/gateway) and
[event payloads](https://docs.discord.com/developers/events/gateway-events) were
reviewed in the [source record](../../Release/sources/2026-10-18-phase15h.json).

Synthetic event execution and the existing cache/broadcast soak do not establish
live Discord, full model parity, supervised bot-host lifetime, other platforms or
DSL handler capacity. Parts 15I-15L and external qualification remain separate.
