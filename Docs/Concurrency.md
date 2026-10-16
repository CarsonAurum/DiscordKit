# Concurrency and ownership

Status: adopted implementation policy, updated 2026-10-15. Part 1 implements
Sendable values, pull-body ownership and deadline contexts with deterministic
test support. Part 2 adds actor/event-loop-owned adapters and fenced shard leases;
see [transport ownership](Transport.md). Protocol actors, scheduling queues and event broadcasts described
below remain planned for their respective runtime phases.

## Target settings and isolation

Require Swift 6.4 or newer and preserve `ApproachableConcurrency` on every Swift
library and test target. Set `.defaultIsolation(nil)` explicitly for these
targets, so ordinary declarations are nonisolated by default. This is the SwiftPM
spelling for the nonisolated default; it does not disable isolation explicitly
declared on actors or inferred from other language rules. Reserve `@MainActor`
for platform UI adapters and UI-owned operations. See
[SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md).

Default isolation is distinct from async execution. Under the relevant
approachable-concurrency behavior, a nonisolated async function can inherit its
caller's actor. Do not assume `async` means background execution. Use explicit
isolation and `@concurrent` only when an operation intentionally requires an
executor transition, and test public calls from actor-isolated consumers,
including `MainActor`. See
[SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md).

Immutable models and transferable payloads use compiler-checked `Sendable`
conformance. Avoid unchecked sendability and unsafe isolation escapes. Keep
bounded, inexpensive calculations synchronous. CPU-heavy codecs/crypto must have
a documented execution strategy and measured limits; blocking system calls do
not belong on cooperative async executors.

## Runtime ownership

Actors own shared mutable protocol state, including connection generations,
session/resume state, rate-limit buckets, response acknowledgment state and cache
projections. An actor serializes access but is reentrant at suspension points.
Reserve a transition before suspension and revalidate generations/state after
each relevant `await`, so old socket work cannot mutate a replacement session.

Use structured task lifetimes: a run operation owns its child tasks, streams and
transports. Prefer task groups and `async let` for related concurrent work. Any
unstructured task needs a documented owner that cancels and awaits its completion.
Detached tasks are not a general mechanism for fixing isolation diagnostics.

Cancellation is cooperative and must propagate through adapters, queued work,
stream iteration and child tasks. A cancelled waiter must leave the queue;
continuations finish exactly once. Closing or cancellation must release owned
connections and buffers exactly once, including partial startup and thrown-error
paths. Define idempotent stop behavior and whether close drains or discards work.

## Streams, deadlines and ordering

Event subscriptions are independent bounded broadcasts, not multiple consumers
competing for a single iterator. Define capacity and overflow behavior per
subscription, and report when a consumer must resynchronize. Preserve documented
per-shard dispatch order without promising a global cross-shard total order.
One slow handler must not block heartbeats or another subscription.

Separate control/deadline work from user handlers. Interaction acknowledgment
reserves one initial response before suspension. Rate-limit admission uses an
injected clock and shared coordination; cancellation removes pending reservations
where valid. Backpressure, retry, timeout and overflow policies are explicit API
choices, rather than unbounded task creation or implicit sleeps.

Cache freshness, duplicate events and fetch/event races require explicit state
rules. A value being `Sendable` does not make a snapshot authoritative. Runtime
availability and background lifecycle restrictions remain platform capabilities.

## Aggregate ownership and admission

Partition runtime ownership by authentication identity, resource and shard.
Avoid a global actor in unrelated request/event hot paths. Per-partition limits
must compose with process-wide queue/byte/task/connection/cache/metadata budgets;
bounded individual clients alone do not bound a multi-account deployment.
Admission and retries use those same budgets and a documented fairness policy.
Coalesced reads have bounded independent waiters; canceling one cannot cancel
work still owned by another. Shared reservations and shard leases require atomic
ownership generations and explicit coordinator-outage behavior. Recheck ownership
after suspension and stop new sends when authority is lost.

## Verification

The [scalability requirements](Scalability.md) define deterministic overload,
cross-worker admission, lease-failover and request-reduction gates. Keep local
performance/soak measurements separate from virtual-time correctness tests;
qualify aggregate budgets and control latency from the first runtime milestones.

Use deterministic Swift Testing suites with injected clocks and scripted
transports. Cover success, errors, cancellation before and during work, deadlines,
parallel callers, repeated start/stop, reentrancy, stale generations, ordering,
overflow and exactly-once resource release as each component is implemented.
Assert queue/resource counters and observable state, rather than relying on
wall-clock sleeps. Test consumers on `MainActor` as well as nonisolated callers.

The [Swift language concurrency guide](https://docs.swift.org/latest/documentation/the-swift-programming-language/concurrency/)
is the language reference; each implementation still needs precise local contract
documentation. No protocol concurrency qualification is claimed by this policy.
