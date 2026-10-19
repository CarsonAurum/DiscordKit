# Typed Gateway event modules

Part 15H adds the independently adopted `DiscordBotDSL` product. It composes typed
protocol handlers with the shared `BotModule`/`BotBuilder` structure and the existing
bounded Gateway hub/dispatcher. Part 15I broadens the explicitly selected BotDSL
product with [supervised bot applications](BotApplications.md), Client and CommandDSL
composition. Existing shared/command products gain no upward dependency. Event-only
execution still creates no client, cache, command runtime, concrete adapter or macros,
although BotDSL's selected product graph now includes the host dependencies.

## Declare, compile, subscribe, run

A `GatewayEventHandler` declares an associated `Event`, stable globally unique
`handlerID`, `GatewayEventSelector<Event>` and async throwing `handle(_:context:)`.
Services are ordinary initializer-injected actors or Sendable values. The context
retains the exact raw envelope, including complete shard identity, sequence and
socket generation. Neither a synthetic event nor a chosen hub proves authenticity
or current authorization.

Put handler values directly in modules and call `EventCompilation.compile` with
the exact intents the host has explicitly selected. Collection enforces existing
module, depth, declaration, text and structural-node limits; lowering checks the
complete registration snapshot against collected metadata. Custom
`GatewayEventContribution` leaves can expose an existing registration without a
closed central handler switch. Getters/builders must be deterministic, inert and
terminate cooperatively. Separate captures detect inconsistent metadata, not
arbitrary behavioral changes hidden in author closures.

Construction and compilation invoke no selector or handler, create no tasks or
subscriptions, and perform no I/O or registration. After successful compilation,
explicit `subscribe(to:configuration:authority:policy:maximumEvents:maximumBytes:)`
acquires all subscriptions before returning a `GatewayEventPipelines` owner. It
rolls back admitted subscriptions if setup fails or is cancelled. The owner starts
callbacks only in `run()`. Cancel an abandoned owner explicitly.

The independently compiled [DSLEvents consumer](../Examples/DSLEvents/README.md)
contains two external module types, a custom typed selector, exact direct-decoder
payload parity and deterministic cleanup checks. It needs no credentials or sockets.

## Intent validation and model limits

Selector requirements and handler `requiredIntents` are unioned, then checked as
a subset of caller-selected intents before any subscription. Missing bits produce
`EventCompilationDiagnostic` with code `.missingIntents` and the absent bitfield. No bit,
including privileged bits, is enabled implicitly. The caller must pass the same
configuration to its real client; compilation cannot inspect portal approval,
permissions, live session configuration or eventual delivery.

Built-in `.ready`, `.messageCreate`, `.messageUpdate`, `.all` and `.unknown`
selectors delegate to `GatewayEvent.decodeDispatch()`. Message selectors deliberately
cover both guild and DM events and require both `.guildMessages` and
`.directMessages`; use a custom selector with the scope needed by a narrower host.
Content-dependent handlers additionally declare `.messageContent` when applicable.
Discord treats content access separately from event subscription; fields can remain
absent or restricted. Review the official [intent reference](https://docs.discord.com/developers/events/gateway#gateway-intents)
and [event payload reference](https://docs.discord.com/developers/events/gateway-events).

Decoded selectors share one decode per event in their group. Unknown names retain
the exact lossless raw data through `.unknown` or `.all`. Malformed known dispatches
throw the existing decoder error before any handler in a decoded group; they do
not become unknown events. The deliberate `.raw` escape hatch includes control
opcodes and skips model decoding only when every handler in its group is raw.
Mixed raw/typed groups retain strict known-payload validation. Existing partial
Models and unknown fields remain authoritative; this layer adds no model coverage,
implicit hydration, cache mutation, deduplication, replay or response ownership.

## Ordering and finite resources

All handlers whose `eventGroup` is nil share one subscription, regardless of module
count. Matching handlers run sequentially in declaration order for each event.
The existing dispatcher preserves subscription order per complete shard identity
(bot ID, topology generation, shard index/count). Distinct complete shard identities
can progress concurrently. It does not sort sequence numbers or impose global order.

A nonnil stable group ID explicitly opts into an independent subscription. Equal
IDs share one pipeline; different groups have no cross-group ordering guarantee.
Compilation defaults to eight independent groups plus at most one default group;
`maximumIndependentGroups` accepts `0...128`. Empty plans need no subscription.
Handler IDs remain globally unique even across different groups.

Existing dispatcher configuration bounds callbacks and retained event count/bytes
per group. Existing hub configuration bounds queue copies, bytes and subscriptions;
per-subscription overrides remain explicit. Share `GatewayHandlerAuthority` and
`GatewayEventHubAuthority` when multiple groups or clients need aggregate admission.
Groups multiply these explicit finite local budgets. They create no replacement
REST or Gateway rate authority. The default overflow policy fails with a required
resynchronization; opting into dropping events retains the hub's continuity limits.
Publication and Gateway control do not await callbacks.

`run()` is single-use. Decode, selector, callback, overflow and admission failures
propagate and cancel sibling pipelines; no retries or compensating effects occur.
Task cancellation and explicit `cancel()` close subscriptions. `cancel()` is
idempotent and may be called from a handler without awaiting that same handler;
the caller of `run()` must still await it to join all work. User callbacks must
cooperate with cancellation. Cancellation cannot force a nonterminating callback
to finish or undo already completed effects. Hub finish closes queued input under
the hub's existing semantics; already admitted callbacks are joined.

## Qualification boundary

The event compilation and pipeline APIs own event delivery only. They never start
or stop a client, consume raw shard queues, bridge interactions, read credentials
or register commands. Explicitly adopt Part 15I's [bot runtime](BotApplications.md)
for shared services, trusted interaction delivery and supervised client lifetime.
Parts 15J-15L retain full extension adoption, DSL handler measurements,
capacity/soak and final release certification. Local synthetic tests and the existing
cache/broadcast soak do not qualify live Discord, other platforms or DSL capacity.
