# ``DiscordBotDSL``

Compose finite typed Gateway event modules over existing bounded subscriptions and dispatchers.

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

See the repository's Gateway event modules guide and independent DSLEvents offline
consumer. Supervised client/interaction hosts, live Discord, platform qualification
and DSL handler capacity remain separate milestones.
