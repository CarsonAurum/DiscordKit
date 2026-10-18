# Delivering events to consumers and handlers

Choose single-consumer ingestion or bounded broadcast without blocking protocol control work.

## Overview

### Decode only what each consumer needs

``GatewayEvent`` retains shard identity, socket generation, opcode, name, sequence and lossless data under envelope bounds. `decodeDispatch` returns a typed known/unknown dispatch for opcode zero while preserving raw observations. Malformed known payloads can fail decoding without destroying the original event or changing session state.

Raw shard `nextEvents` is a single-consumer ingestion boundary. Do not mix it with `drainEvents`, and do not give it to several independent features expecting broadcast. DiscordClient owns this boundary when it composes shards.

### Give each consumer an independent finite queue

``GatewayEventHub`` provides subscriptions. Subscribe before the supervised run if initial events matter. Defaults cap each subscription at 128 events/one MiB and the hub at 64 subscribers, 4,096 retained copies and 16 MiB. Sharing ``GatewayEventHubAuthority`` bounds aggregate ownership across hubs.

Default overflow terminates only the slow subscription with a resynchronization-required error. Explicit drop-newest/drop-oldest policies are lossy alternatives. Queue accounting ends when an event transfers to its consumer, so a consumer that retains an unlimited array still has unlimited application memory.

Always cancel a subscription when abandoning iteration. A cancelled suspended `next` removes its queue; overlapping iteration on one subscription fails. `finish` closes admission and awaits racing registrations. No implicit durable replay, global ordering, completeness or exactly-once delivery is promised.

### Run handlers in a structured owner

``GatewayEventHandlerDispatcher`` runs callbacks serially per complete shard identity while allowing different shards to overlap. Its default bounds are four concurrent callbacks and 128 retained events/four MiB across active/pending work. A shared ``GatewayHandlerAuthority`` bounds aggregate callbacks and permit waiters across dispatchers.

Handlers run outside publication and control tasks. A slow handler backpressures its own bounded subscription, while other subscribers and heartbeats remain independent. A hot shard can fill finite lookahead; do not assume fairness creates infinite buffering. Callback errors propagate to the dispatcher owner, and already completed side effects are not rolled back.

### Resynchronize explicitly

After overflow, identify what state the consumer needs, fetch authoritative current data through an eligible REST path, reconcile it and establish a new subscription. Retain a deliberate freshness policy; a new subscription does not recover lost events automatically. Preserve per-shard order without inventing a global sequence across shards or socket generations.

Test multiple independent subscribers, queue overflow, shutdown racing subscription, abandoned iterators, duplicate events, reconnect generations, handler failure, cancellation and per-shard ordering. Use barriers and virtual clocks instead of timing-dependent sleeps.
