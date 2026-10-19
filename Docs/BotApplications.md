# Supervised bot applications

Part 15I extends the independently selected `DiscordBotDSL` product with an explicit
application host, shared typed REST access and trusted Gateway interaction delivery.
It composes the existing `DiscordClient`, event dispatcher, command router and
interaction response owner. It introduces no second Gateway runtime or automatic
command registration. The independent [DSLBot consumer](../Examples/DSLBot/README.md)
builds and exercises this composition offline.

## Construct the host explicitly

`BotApplication` is a Sendable, `@main`-compatible protocol. Its
`static makeRuntime() async throws -> BotRuntime` requirement constructs the host;
the default entry point awaits that factory and the runtime's `run()`. Credential
loading, environment reads, concrete adapter selection, clocks and dependency
construction belong in the factory. The library supplies no global service locator
or implicit process configuration.

Construct the existing `DiscordClient` with its explicit bot identity/token, intents,
services, discovery/connector, lease store and authorities. Compile event modules
with the same selected intents. Construct command catalogs and their bounded router
separately when interactions are enabled. Services and actors remain ordinary
initializer dependencies; module count does not create extra credential, startup,
lease, REST, event or handler authorities. Reuse shared authorities across related
clients and inject externally coordinated authorities when multiple workers share
a credential.

`BotRuntime` is a nongeneric actor. Its generic initializer retains an existing
`DiscordClient<C, L>`, immutable `CompiledEvents`, explicit handler configuration,
an optional shared handler authority and an optional `GatewayInteractionAdapter<C>`.
Its throwing initializer checks the event plan's required intents against the
actual client's selected intents, so a mismatched compilation selection fails
before any subscription or I/O.
Constructing these values starts no tasks, subscriptions, sockets, command
registration or handler execution. An omitted interaction adapter means event-only
hosting. Explicit command synchronization continues through the compiled catalog's
existing reconciliation APIs; construction and ordinary `run` never synchronize.

The selected BotDSL graph now includes DSL, CommandDSL, Client, Commands,
Interactions, Gateway, Models, Core, HTTP and Transport. Client's optional cache
product remains in its dependency closure, but the runtime constructs no cache
implicitly. Shared DSL retains Core/Models-only adoption; CommandDSL retains
independent HTTP adoption. Existing products gain no dependency on BotDSL. Concrete
adapters, compiler plugins, voice, Social and OAuth remain application choices.
Part 15J adds [explicit external module installation and typed dependency validation](ModuleExtensions.md).
Pass the same services and aggregate authorities into each reusable module; validated
dependency values retain those references without creating another owner.
Application-owned Voice, Social or OAuth interfaces may be injected explicitly,
without adding those products to BotDSL's runtime graph. The independent DSLBot
consumer adopts an external event extension through its own package selection.

## Own startup and terminal cleanup

`run()` admits every event and trusted interaction subscription before calling
`client.run()`, so initial events cannot race subscription setup. The runtime
supervises one client and the declared pipelines. The client remains the exclusive
consumer of raw shard queues; modules consume bounded broadcast subscriptions.
Event declaration order, complete-shard serialization, independent-group semantics
and overflow remain those of the [event module owner](GatewayEventModules.md).

`run()` is single-use. On normal completion, setup failure, child failure, explicit
stop or cancellation, the runtime cancels subscriptions, requests client shutdown
and awaits the client and cooperative pipeline children. Partially admitted setup
is rolled back. No retry, mutation replay or compensating side effect occurs.
User builders and callbacks must terminate cooperatively; cancellation cannot
preempt arbitrary Swift work or undo already completed effects.

`requestStop()` requests terminal cleanup without joining the caller's handler.
Use it from an event or command handler. `shutdown()` waits for terminal cleanup
and preserves the terminal failure; it is suitable for external owners. Repeated
shutdown calls share cleanup, and a cancelled cleanup waiter does not abandon that
cleanup. A handler must not await a shutdown that joins its own work. Stopping
before `run()` performs no discovery or shard leasing; construct a new runtime and
client to run again.

Noncancellation failures, including client cleanup and lease-release failures,
remain observable even when another child first cancels. Always await `run()` or
the joining shutdown owner before a worker handoff. Shared REST transports and
other injected dependencies close only under the existing client's explicit owner
cleanup contract; this runtime does not infer ownership of shared resources.
`phase` reports the runtime's idle/start/run/stop/terminal observation, rather than
per-shard readiness. A single terminal error is rethrown unchanged. Multiple child
failures use `BotRuntimeFailures`, retaining the first observed error plus at most
two additional errors. Ordinary formatting/reflection redacts dependency text;
explicit error access remains available for deliberate application handling.

## Keep interaction provenance at ingestion

The Gateway interaction adapter receives only the package-internal stream populated
by the existing client's shard-ingestion boundary. Ordinary `GatewayEventHub.publish`
is useful for synthetic event consumers, but cannot authenticate an interaction or
reach this trusted stream. There is no public initializer that marks an arbitrary
raw envelope as authenticated. A caller-supplied transport still defines the host's
trust boundary; synthetic test peers do not prove Discord provenance.

The bridge handles Gateway `INTERACTION_CREATE` input, verifies the configured
application identity, normalizes the existing partial Models and creates the same
transport-neutral `InteractionContext` and `InteractionResponder` used by command
execution. Malformed, unsupported or wrong-application input fails before handlers.
The adapter adds no model projections, REST hydration, current authorization or
durable delivery guarantee. Optional policies retain their explicit injected
authorization requirements.

Construct `GatewayInteractionAdapter` with the expected application ID, compiled
command catalog, `BotServiceAdapter`, shared clock and initial acknowledgement
admission authority. Its `guildID` selects the explicit registration scope, rather
than filtering incoming interactions. Public `synchronize(deadline:)` is the only
registration operation; preparation, serving and cancellation belong to the runtime.
The adapter defaults to a private queue of 256 events/8 MiB, existing dispatcher
bounds of four tasks and 128 retained events, 64 concurrent router handlers and
1 MiB of registration definitions. These are admission defaults, not measured
deployment capacity. Share aggregate handler authority where needed.

Gateway receipt changes how an interaction arrives; response callbacks still use
the existing HTTP endpoints. Initial-response admission remains separate from
ordinary REST traffic. Immediate, deferred and manual command adapters retain one
initial response, complete input preparation before acknowledgement, receipt-relative
deadlines/token expiry and uncertainty after an ambiguous send. The package records
socket receipt age before fencing/parsing; queueing and dispatch do not restart the
three-second acknowledgement or fifteen-minute continuation lifetimes. Deferred completion
continues through edit-original. Construction and serving never register commands.

The trusted stream and dispatcher have explicit finite queue/count/byte/admission
bounds. Handler work never moves onto the Gateway heartbeat/control path. Overflow
or a child error terminates the supervised owner; reconnecting does not silently
replay handler effects. Applications retain responsibility for explicit recovery.

## Reuse typed REST services

`BotServiceAdapter` takes the shared bot `ServiceContext`, clock and two explicit
factories for each interaction's initial HTTP client and continuation service
context. Factories run only after trusted input admission, off client ingestion.
The initial client must use exact interaction-token credentials and an admission
queue independent of ordinary REST. Continuations use the matching token and shared
invalidation authority. The adapter retains no token-indexed registry and owns no
transport cleanup.

It delegates typed endpoint execution through the existing
`ServiceContext.execute`, retaining authentication, shared REST admission, retry
rules and conservative entity invalidation around writes, including failed or
indeterminate writes. Inject the Sendable `BotServiceProviding` protocol when common
handlers should be independent of a concrete clock. Its generic
`execute(_:timeout:)` accepts nil for ordinary REST bounds or a positive relative
timeout no greater than one day. Invalid durations fail before endpoint execution;
valid durations set a deadline in the adapter's clock domain. This avoids mixing `Clock.Instant`
domains in shared handler dependencies. No schema reconstruction, implicit hydration,
background refresh, registration or new rate authority is added by the adapter.

## Validation and qualification boundaries

Root Swift Testing suites exercise startup/subscription order, inert construction,
stop-before-run, startup cancellation, repeated shutdown, cancelled cleanup waiters,
handler-requested stop, child failure, failed lease release and released owned
counters. Bridge tests cover trusted admission, public-publication isolation,
malformed/wrong-application inputs and existing HTTP response ownership. Service
tests cover typed reads/writes, relative deadlines and invalidation/error behavior.
The independently compiled DSLBot consumer supplies offline host composition.

Run root build/tests, callable documentation, graph/import isolation, scoped API
and DocC checks; build/test/run DSLBot offline and affected command/event consumers.
Gateway/cache changes retain the existing local cache/broadcast profiles and
fixed-working-set 30-minute soak requirement. Those measurements cover their named
harness and do not establish DSL handler capacity. Part 15J's independent extension
package/consumer checks cover public external adoption. Part 15K adds separate
[direct/DSL handler measurements and soak evidence](DSLBenchmarks.md). Part 15L
adds complete [adoption guidance](DSLAdoption.md) and scoped
[release-candidate records](Release/README.md); local measurements do not establish
production capacity.
Local synthetic peers do not qualify live Discord, other platforms, hardware,
independent crypto review or production capacity.
