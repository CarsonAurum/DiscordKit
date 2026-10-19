# ``DiscordBotDSL``

Compose finite typed Gateway modules and explicit supervised bot applications over existing owners.

## Overview

`GatewayEventHandler` values compose directly in the shared module builder.
`EventCompilation` checks identities, immutable snapshots, explicit intent requirements
and finite independent-group admission without executing user handlers or starting work.
`CompiledEvents.subscribe` explicitly acquires queues; `GatewayEventPipelines.run`
starts and joins their dispatchers. One default subscription serves every default module.
Handlers run in declaration order per event with complete-shard serialization;
explicit independent groups have no ordering guarantee between them.

Existing Models own typed/unknown dispatch decoding and partial payload semantics.
Raw-only groups deliberately bypass model decoding. Services are initializer injected.
Construction and compilation start no tasks, client, sockets, registration or I/O.
Cancellation and failure release subscriptions and join cooperative callbacks through
`run`; explicit `cancel` may safely be called by a handler without joining itself.

`BotApplication` provides an explicit application factory and a default async entry
point. `BotRuntime` subscribes before starting the existing client, supervises event
and optional interaction pipelines, and closes/joins them on every terminal exit.
Use nonjoining `requestStop` from handlers and joining `shutdown` from external
owners. Terminal cleanup failures remain visible; stopped runtimes are single-use.

The trusted Gateway interaction adapter accepts only the client's package-internal
ingestion stream. Public event-hub publication cannot authenticate interactions.
Command routes retain the existing response owner and HTTP callback transport;
initial-response admission remains independent and synchronization stays explicit.
Fail-fast invocation handling remains the default. Explicit
`GatewayInvocationFailurePolicy.continueInvocations` isolates ordinary handler,
response and stale-command failures without replay or replacement responses.
Malformed/untrusted input, wrong application, continuity loss, owner failures and
cancellation remain terminal. `BotFailureDiagnostic` and synchronous
`BotFailureObserver` callbacks provide closed stages/categories and numeric protocol
evidence without retaining interaction data or arbitrary errors. See
<doc:InvocationRecovery> for recovery boundaries and diagnostic attribution limits.
`BotServiceAdapter` delegates typed REST operations through existing shared services
with relative deadlines and conservative mutation invalidation.

The selected product includes Client and CommandDSL without adding an upward
dependency to existing products. Concrete adapters and compiler plugins remain
application choices. See the repository's bot application/event guides and the
independent DSLBot/DSLEvents offline consumers. Local benchmark and release-candidate
records state their actual scope. Live Discord, platform qualification and
production/fleet capacity retain separate gates.

## Topics

### Adopt the authoring layer

- <doc:HostingModules>

### Complete API reference

- <doc:APIReference>
