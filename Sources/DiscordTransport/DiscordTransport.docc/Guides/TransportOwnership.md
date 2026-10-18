# Owning transport operations and bodies

Make resource transfer, cancellation and cleanup explicit at every asynchronous boundary.

## Overview

### Bind work to a clock and deadline

``TransportContext`` carries an injected clock and optional inclusive deadline. Pass the same clock domain through admission, transport and body consumption. `check` observes cancellation and expiry; `run` races cooperative work against its deadline and joins owned work. An adapter must cooperate with cancellation so that a bounded API does not leave an unbounded child task behind.

```swift
import DiscordTransport

let clock = ContinuousClock()
let context = TransportContext(clock: clock,
    deadline: clock.now.advanced(by: .seconds(10)))
try context.check()
```

Constructing a context performs no network work. Use virtual clocks in deterministic tests rather than sleeping for real deadlines.

### Consume or close transferred bodies

``BodyStream`` is a single-consumer pull sequence of bounded `Data` chunks. It does not prefetch into an internal unbounded queue. A request body belongs to its producer until the adapter's contract transfers ownership; a returned response body must be consumed to EOF or explicitly closed by its recipient.

```swift
import DiscordTransport

/// Counts one transferred body's bytes and releases it on success and failure.
/// - Parameter body: Caller-owned, single-consumer response body.
/// - Returns: Total consumed bytes; this example retains no payload chunks.
/// - Throws: The source's read failures or cancellation.
func countBytes(in body: BodyStream) async throws -> Int {
    do {
        var count = 0
        for try await chunk in body { count += chunk.count }
        await body.close()
        return count
    } catch {
        await body.close()
        throw error
    }
}
```

Add an application total-byte cap when counting untrusted arbitrary peers; each chunk being bounded does not by itself limit the complete stream. Concurrent iteration fails instead of queuing additional readers. Explicit close discards a late in-flight result and is idempotent; EOF, errors and cancellation also initiate cleanup. Cleanup must unblock a suspended source read.

### Keep ownership distinct from shared dependencies

``TransportResource`` defines asynchronous close. Close sockets, datagram endpoints, IPC connections and ingress responders when their owner ends. Await close instead of launching detached cleanup. A higher-level client may share its transport with other clients and must not implicitly close it unless the application assigned that complete lifetime to the client.

A transport sends once. It does not perform Discord retries, infer permission scopes or migrate an uncertain request after network replacement. A failure after submission can leave a mutation's outcome unknown. REST or application policy determines whether reconciliation or replay is appropriate.

### Related reading

- <doc:ImplementingAdapters>
- [Owned adapter behavior](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Transport.md)
