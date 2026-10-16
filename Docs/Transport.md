# Owned transport adapters

Implementation date: **2026-10-15**, Swift 6.4, macOS arm64. Part 2 adds real
network adapters without implementing any Discord endpoint, Gateway session,
interaction handler, OAuth flow, voice protocol or desktop RPC framing. Protocol
versions and operation statuses in the discovery inventory remain unchanged.

## Adoption and ownership

Choose a concrete adapter and inject it through `DiscordTransport` protocols.
`DiscordKit`, Bits, Core and Transport retain their independent product graphs;
none imports a concrete adapter. Foundation users do not link NIO. The NIO and
Unix products use the audited Apple NIO/TLS graph in `Package.resolved`.

```swift
import DiscordNIOTransport
import DiscordTransport
import Foundation

let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration())
do {
    let clock = ContinuousClock()
    let response = try await transport.execute(
        HTTPRequest(method: "GET", url: URL(string: "https://example.com/")!),
        context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(10)))
    )
    // Consume the bounded body, or explicitly await response.body?.close().
    if let body = response.body {
        do { for try await chunk in body { /* consume chunk */ } }
        catch { await body.close(); throw error }
        await body.close()
    }
} catch {
    await transport.close()
    throw error
}
await transport.close()
```

The example sends no Discord credentials. Endpoint authentication/origin checks,
rate admission, retries and caching are future higher-layer responsibilities.
Transport calls send once. After an ambiguous failure, the caller cannot infer
that a mutation did not reach its peer. Redirect responses are returned without
following them, including same-origin redirects. No adapter transfers credential
headers to a redirected URL. CDN operations must use a credential-free higher-layer
request policy; no generic transport can infer whether arbitrary supplied headers
are appropriate for a destination.

Every resource has an explicit owner. Consume or close response bodies; close
WebSocket/datagram/IPC connections and ingress responders; close adapters after
use. Failure/cancellation closes untransferred resources. Shared cleanup tasks
are retained and awaited; cancelling a caller does not cancel cleanup. A new
adapter instance is the explicit network-replacement boundary. There is no
transparent request replay or socket migration.

## Implemented behavior and budgets

| Adapter | Behavior | Default bounds and limits |
| --- | --- | --- |
| `NIOHTTPTransport` | HTTP/1.1 pool keyed by scheme/host/port, duplicate fields, bounded upload collection, demand-driven response reads, keep-alive reuse after complete framing | 32 active+idle slots, 8 per origin, 8 MiB request/response, 32 KiB headers, 16 KiB chunks; fail-fast admission, no waiter queue |
| `NIOWebSocketTransport` | RFC 6455 upgrade validation, masked client frames, fragmented text/binary assembly, UTF-8 checking, ping/pong, close handling | 32 live+connecting sockets, 1 MiB complete message and aggregate received payload, 8 queued messages, 8 application sends and 8 independent pong writes; one terminal close reply; overflow closes, application writes reserve count/bytes before suspension |
| `NIODatagramTransport` | Numeric IPv4/IPv6 bind/send, preserves empty/binary datagrams and peer boundaries | 65,507-byte application datagram cap, 64 queued datagrams and 1 MiB queued payload; native socket limits also apply; rejects oversized input/overflow and concurrent receives |
| `NIOHTTPIngress` | HTTP/1.1 local listener, one request per connection, exactly-once responder reservation | 128 sockets, 64 complete queued requests, 1 MiB request/response body, 16 KiB headers; bounded whole-body buffering |
| `UnixIPCTransport` | Unix-domain byte streams with ordered writes, bounded reads and explicit close | 1 MiB buffered input and per-write cap; one reader, fail-fast overlapping writes, no Discord RPC framing |
| `FoundationHTTPTransport` | Ephemeral URLSession, bounded upload collection and native byte pulls, no redirects/cookies/cache/credential persistence | 32 admitted operations including owned bodies, 8 MiB request/consumed response, 16 KiB emitted chunks |
| `FoundationWebSocketTransport` | Apple URLSession WebSocket, native complete-message framing and explicit cancellation/close | Shared admission settings, 1 MiB message cap, bounded writer reservations; ordinary watchOS use rejected |

NIO's HTTP response parser bounds headers separately from body bytes. Socket
reads are demand-driven and fixed-size; TLS may emit a larger plaintext record,
so HTTP queues allow at most 64 KiB plus the configured read chunk. Bodies split
that bounded record into the configured emitted chunk size. HTTP uploads are
collected within the configured cap before transmission; these adapters do not
provide streaming uploads. NIO does not implement automatic decompression,
HTTP/2, proxies, cookies, client TLS identities or TLS verification bypasses.

`TLSPolicy` always validates certificate chains and hostnames and requires at least
TLS 1.2. By default NIOSSL uses system trust roots. Explicit PEM trust anchors
replace system roots for private PKI and local fixture tests; they do not disable
hostname verification. Native errors are sanitized rather than retaining URLs,
headers, bodies or certificate paths. DNS uses NIO's resolver; a cancellation
closes the operation-owned channel, but cannot forcibly terminate an OS resolver
call already in progress. This limitation is distinct from socket cleanup.

Foundation owns protocol negotiation, proxy/decompression behavior, private
buffering and pooling; those platform details are not configured as NIO features.
Its public API does not promise an exact internal socket-buffer or connection ceiling: configured
admission/consumed-body limits are application limits. Foundation response
metadata collapses duplicate header fields; duplicate request names are rejected
rather than silently normalized. Choose NIO when exact duplicate fields and
owned socket buffering matter. Foundation has no production Linux WebSocket
qualification in this change.

Ingress does not terminate TLS, negotiate upgrades, accept trailers/Expect,
reuse keep-alive connections or run application handlers on its event loop.
Deploy behind an appropriately configured TLS proxy when public ingress is
needed. Its process-owned NIO singleton outlives listeners: listener close cleans
unaccepted sockets, while accepted exchanges remain independently caller-owned.
The connection budget includes both queued and accepted sockets until close.

## Lifecycle and shard coordination

`AppleLifecycle` takes app-reported lifecycle transitions and an explicit set of
qualified capabilities. It bounds resource registrations, stops admission before
draining invalid resources, and supports explicit foreground restart. It does
not observe UI notifications, request OS permissions, grant background execution,
or implement browser/authentication/audio/video UI. Those adapters belong with
their later feature implementations. watchOS socket restrictions remain explicit;
simulator success cannot override physical-device policy.

`ShardIdentity` implements validated shard topology/routing. `ShardLeaseStore`
defines injectable atomic ownership with inclusive expiry and fencing generations;
`InProcessShardLeaseStore` supplies a bounded actor implementation with an injected
clock, no background timers and fail-closed stale-ticket validation. Renewal
replaces the fence. External fleet stores must persist issuance, reject stale
owners and fail closed on coordinator loss. The process-local actor cannot
coordinate other processes or preserve fencing across its own restart. Separate
topology generations require an orchestrated old-topology drain; keys alone do
not stop overlapping deployments. These contracts do not implement Identify,
Gateway discovery, heartbeat/session lifecycle or distributed infrastructure.

## Qualification and remaining gates

Root Swift Testing suites use local loopback/raw peers, virtual clocks and
barriers, never Discord credentials or live Discord requests. A reusable HTTP
contract runs against both HTTP adapters. Backend suites additionally cover
protocol-specific fields, fragmentation, limits, malformed input, cancellations,
ownership, repeated close and overload. The committed localhost key is public
fixture data, never a production credential.

Exact results and the local transport baseline are recorded in
[platform support](PlatformSupport.md) and the separate
[load harness](../Tools/DiscordKitLoadTests/README.md). Logical served-account
profiles select bounded active cohorts; they do not create one task/socket per
account or qualify millions of simultaneous connections.

Part 2's whole-platform completion gate remains **open**. This host cannot execute
Linux, Windows, Android or physical Apple-device qualification. Windows named
pipes, Android JNI/lifecycle/browser/media integration, native authentication and
media UI adapters, IPv6 beyond local UDP/DNS/network-change/minimum-OS coverage,
cancellation during blocked HTTP/WebSocket writes and connect handshakes,
expired certificate coverage, Foundation-specific TLS rejection and writer-overflow
checks, and long soak/allocation profiling need their own evidence before those capabilities are
advertised. No empty targets or unavailable stubs count toward those gates.

Local UDP tests qualify IPv4 payloads up to 8 KiB and basic IPv6 loopback. This macOS
host reports a 9,216-byte native UDP send ceiling, below the configurable
application maximum; larger sends can fail with a redacted I/O error. Unix tests
also qualify cancellation of a blocked write to a deliberately nonreading peer.
