# Own concurrency and resource lifetimes

Assign one supervisor to started work and await cleanup when that work ends.

## Overview

### Construction and startup

Configuration values and client constructors are inert. Starting a client, binding a listener, joining a voice session or explicitly connecting an adapter creates the corresponding work. Keep that start inside an application-owned task or structured task group so termination and errors have a known observer.

A client can hold a transport supplied by another owner. Sharing an adapter does not transfer cleanup responsibility to every consumer. Use a single composition root to decide when all users are finished and close the shared resource once.

### Cancellation and deadlines

Pass monotonic deadlines through execution contexts. Cancellation is cooperative: cancel tasks, allow the operation to release pending admission and await its completion. A canceled or timed-out mutation can still have reached the server. Consult its typed outcome before deciding how to recover.

```swift
let task = Task { try await client.run() }
// Application lifecycle eventually requests termination.
await client.shutdown()
task.cancel()
_ = try? await task.value
```

This is a lifecycle sketch: `client` is a configured DiscordClient supplied by the composition root. The complete example in <doc:SuperviseABot> also supervises event consumption and closes its injected adapters. Choose the owning actor for application UI; Sendable contracts do not imply every operation belongs on MainActor.

### Bounds and backpressure

Set count and byte bounds on pending requests, bodies, subscriptions, handlers, cache entries and media buffers. A finite per-client queue does not establish a finite aggregate limit when clients are multiplied. Share aggregate authorities and define overload rejection or resynchronization behavior before increasing concurrency.

Keep heartbeats and control messages independent of handlers and cache I/O. Subscribe before producing events; consume them in order, treat overflow/gaps as a freshness change, and issue an explicitly bounded refresh. Do not mix the shard's raw single-consumer delivery APIs or assume that observing a duplicate event means a mutation should be repeated.

### Shutdown sequence

1. Stop admitting application work and ask supervisors to stop.
2. Cancel dependent tasks and await their outcomes.
3. Close subscriptions, response owners and local state holders.
4. Close each transport, coordinator and platform resource through its designated owner.

The exact sequencing depends on the product. Use each product's lifecycle guide and method contract for idempotence, cancellation, whether pending work fails or drains, and what remains usable after close. A synchronous `defer` cannot await asynchronous cleanup; the examples use explicit success/error paths or a supervisor cleanup closure.
